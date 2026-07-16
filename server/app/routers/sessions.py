from datetime import datetime

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlmodel import Session, select

from ..db import get_db
from ..models import ClassCourse, CourseSession, Outline, TranscriptSegment, User
from ..services import rag
from ..services.asr import get_asr_provider
from ..services.llm import chat

router = APIRouter(prefix="/sessions", tags=["sessions"])

OUTLINE_SYSTEM = (
    "你是课堂笔记助手。请将课堂转写文本整理为结构化 Markdown 提纲："
    "分章节列出知识点，标注例题与考试重点。只输出 Markdown，不要额外说明。"
)


class CreateSession(BaseModel):
    class_course_id: int
    title: str
    creator_id: int


@router.get("")
def list_sessions(class_course_id: int, db: Session = Depends(get_db)):
    return db.exec(
        select(CourseSession)
        .where(CourseSession.class_course_id == class_course_id)
        .order_by(CourseSession.created_at.desc())
    ).all()


@router.post("")
def create_session(body: CreateSession, db: Session = Depends(get_db)):
    s = CourseSession(**body.model_dump())
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


@router.post("/{session_id}/chunks/{seq}")
async def upload_chunk(session_id: int, seq: int, file: UploadFile = File(...), db: Session = Depends(get_db)):
    """上传音频分片 → 云端 ASR（当前 Mock）→ 返回并保存转写分段"""
    s = db.get(CourseSession, session_id)
    if not s:
        raise HTTPException(404, "课时不存在")
    audio = await file.read()
    result = await get_asr_provider().transcribe_chunk(audio, seq)
    old = db.exec(
        select(TranscriptSegment).where(TranscriptSegment.session_id == session_id, TranscriptSegment.seq == seq)
    ).first()
    if old:
        db.delete(old)
    seg = TranscriptSegment(session_id=session_id, seq=seq, start_ms=result.start_ms, end_ms=result.end_ms, text=result.text)
    s.status = "transcribing"
    db.add(seg)
    db.commit()
    db.refresh(seg)
    return seg


@router.post("/{session_id}/finish")
def finish_session(session_id: int, db: Session = Depends(get_db)):
    s = db.get(CourseSession, session_id)
    if not s:
        raise HTTPException(404, "课时不存在")
    s.status = "done"
    db.commit()
    db.refresh(s)
    return s


@router.get("/{session_id}/transcript")
def get_transcript(session_id: int, db: Session = Depends(get_db)):
    return db.exec(
        select(TranscriptSegment).where(TranscriptSegment.session_id == session_id).order_by(TranscriptSegment.seq)
    ).all()


@router.post("/{session_id}/outline/generate")
async def generate_outline(session_id: int, db: Session = Depends(get_db)):
    s = db.get(CourseSession, session_id)
    if not s:
        raise HTTPException(404, "课时不存在")
    segs = db.exec(
        select(TranscriptSegment).where(TranscriptSegment.session_id == session_id).order_by(TranscriptSegment.seq)
    ).all()
    if not segs:
        raise HTTPException(400, "尚无转写文本")
    text = "\n".join(x.text for x in segs)
    md = await chat(OUTLINE_SYSTEM, text)
    outline = db.exec(select(Outline).where(Outline.session_id == session_id)).first()
    if outline:
        outline.markdown = md
        outline.status = "draft"
        outline.updated_at = datetime.utcnow()
    else:
        outline = Outline(session_id=session_id, class_course_id=s.class_course_id, markdown=md)
        db.add(outline)
    db.commit()
    db.refresh(outline)
    return outline


@router.get("/{session_id}/outline")
def get_outline(session_id: int, db: Session = Depends(get_db)):
    outline = db.exec(select(Outline).where(Outline.session_id == session_id)).first()
    if not outline:
        raise HTTPException(404, "提纲不存在")
    return outline


class PublishBody(BaseModel):
    user_id: int
    action: str = "publish"  # publish | reject


class OutlineUpdate(BaseModel):
    markdown: str


@router.put("/{session_id}/outline")
def update_outline(session_id: int, body: OutlineUpdate, db: Session = Depends(get_db)):
    """教师发布前编辑提纲内容"""
    outline = db.exec(select(Outline).where(Outline.session_id == session_id)).first()
    if not outline:
        raise HTTPException(404, "提纲不存在")
    outline.markdown = body.markdown
    outline.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(outline)
    return outline


@router.post("/{session_id}/outline/review")
def review_outline(session_id: int, body: PublishBody, db: Session = Depends(get_db)):
    """教师审核：发布 → 写入该集合知识库；退回 → rejected"""
    outline = db.exec(select(Outline).where(Outline.session_id == session_id)).first()
    if not outline:
        raise HTTPException(404, "提纲不存在")
    user = db.get(User, body.user_id)
    cc = db.get(ClassCourse, outline.class_course_id)
    if not user or user.role != "teacher" or cc.teacher_id != user.id:
        raise HTTPException(403, "仅本课程教师可审核")
    if body.action == "publish":
        outline.status = "published"
        s = db.get(CourseSession, session_id)
        rag.add_document(outline.class_course_id, f"outline_{outline.id}", outline.markdown, source=f"提纲：{s.title}")
    else:
        outline.status = "rejected"
    outline.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(outline)
    return outline


@router.get("/outlines/pending")
def pending_outlines(class_course_id: int, db: Session = Depends(get_db)):
    """教师审核页：该集合所有草稿/待审提纲"""
    outlines = db.exec(
        select(Outline).where(Outline.class_course_id == class_course_id, Outline.status.in_(["draft", "pending"]))
    ).all()
    result = []
    for o in outlines:
        s = db.get(CourseSession, o.session_id)
        result.append({**o.model_dump(), "session_title": s.title if s else ""})
    return result
