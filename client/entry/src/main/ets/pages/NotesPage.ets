import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppTheme } from '../common/AppTheme';
import { AppCard } from '../common/components/AppCard';
import { HandwritingBoard } from '../common/components/HandwritingBoard';
import { Note } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

/**
 * P5 笔记页：列表（MD/手写、私有/共享、入库状态）| 编辑器（按类型）。
 * 共享 → 服务端 LLM 质量评估 → 通过入本集合知识库（仅 MD）。
 */
@Component
export struct NotesPage {
  pathStack: NavPathStack = new NavPathStack();
  @State notes: Note[] = [];
  @State selectedIndex: number = -1;
  @State editorText: string = '';
  @State noteTitle: string = '';
  @State dirty: boolean = false;
  @State showCreate: boolean = false;
  @State sharing: boolean = false;
  /** 手写画板重建开关：切换笔记时强制重建组件加载新笔迹 */
  @State boardKey: number = 0;

  aboutToAppear(): void {
    this.loadNotes(true);
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private current(): Note | null {
    return this.selectedIndex < 0 || this.selectedIndex >= this.notes.length ?
      null : this.notes[this.selectedIndex];
  }

  private isMine(n: Note): boolean {
    return n.owner_id === GlobalState.userId();
  }

  private async loadNotes(selectFirst: boolean): Promise<void> {
    try {
      this.notes = JSON.parse(await Api.get(
        `/notes?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}`)) as Note[];
      if (selectFirst && this.notes.length > 0) {
        this.selectNote(0);
      }
    } catch (e) {
      this.toast(`加载笔记失败：${(e as Error).message}`);
    }
  }

  private selectNote(index: number): void {
    this.selectedIndex = index;
    const n: Note | null = this.current();
    if (n !== null) {
      this.editorText = n.content;
      this.noteTitle = n.title;
      this.dirty = false;
      this.boardKey += 1;
    }
  }

  private async createNote(kind: string): Promise<void> {
    interface NoteBody {
      class_course_id: number;
      owner_id: number;
      title: string;
      kind: string;
      content: string;
    }

    const body: NoteBody = {
      class_course_id: GlobalState.courseId(),
      owner_id: GlobalState.userId(),
      title: kind === 'md' ? '新 MD 笔记' : '新手写笔记',
      kind: kind,
      content: ''
    };
    try {
      await Api.post('/notes', body);
      this.showCreate = false;
      await this.loadNotes(false);
      // 新笔记通常排在自己名下最后一条
      for (let i = this.notes.length - 1; i >= 0; i--) {
        if (this.isMine(this.notes[i])) {
          this.selectNote(i);
          break;
        }
      }
      this.toast('已创建');
    } catch (e) {
      this.toast(`创建失败：${(e as Error).message}`);
    }
  }

  private async saveNote(): Promise<void> {
    const n: Note | null = this.current();
    if (n === null || !this.isMine(n)) {
      return;
    }
    interface UpdateBody {
      title: string;
      content: string;
    }

    const body: UpdateBody = { title: this.noteTitle, content: this.editorText };
    try {
      await Api.put(`/notes/${n.id}`, body);
      n.title = this.noteTitle;
      n.content = this.editorText;
      this.dirty = false;
      this.toast('已保存');
    } catch (e) {
      this.toast(`保存失败：${(e as Error).message}`);
    }
  }

  private async toggleShare(): Promise<void> {
    const n: Note | null = this.current();
    if (n === null) {
      return;
    }
    this.sharing = true;
    try {
      if (n.visibility === 'private') {
        if (this.dirty) {
          await this.saveNote();
        }
        const updated: Note = JSON.parse(await Api.post(`/notes/${n.id}/share`)) as Note;
        this.notes.splice(this.selectedIndex, 1, updated);
        if (updated.kind === 'md') {
          if (updated.quality_status === 'accepted') {
            this.toast(`已共享，质量评估通过（${(updated.quality_score ?? 0).toFixed(1)} 分），已入知识库`);
          } else {
            this.toast('已共享，质量评估未通过，未入知识库');
          }
        } else {
          this.toast('已共享（手写笔记暂不入知识库）');
        }
      } else {
        const updated: Note = JSON.parse(await Api.post(`/notes/${n.id}/unshare`)) as Note;
        this.notes.splice(this.selectedIndex, 1, updated);
        this.toast('已设为私有');
      }
    } catch (e) {
      this.toast(`操作失败：${(e as Error).message}`);
    } finally {
      this.sharing = false;
    }
  }

  private exportMd(): void {
    const n: Note | null = this.current();
    if (n === null) {
      return;
    }
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, `# ${this.noteTitle}\n\n${this.editorText}`);
    pasteboard.getSystemPasteboard().setData(data);
    this.toast('Markdown 已复制到剪贴板');
  }

  private qualityLabel(n: Note): string {
    if (n.quality_status === 'accepted') {
      return '已入库';
    }
    if (n.quality_status === 'evaluating') {
      return '评估中';
    }
    if (n.quality_status === 'rejected') {
      return '未通过';
    }
    return '';
  }

  // ---------- UI ----------
  @Builder
  tag(text: string, color: string) {
    Text(text)
      .fontSize(10)
      .fontColor('#FFFFFF')
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(AppTheme.RADIUS_TAG)
      .backgroundColor(color)
  }

  @Builder
  leftPane() {
    Column({ space: AppTheme.SPACE_M }) {
      Row() {
        Text('本课程笔记').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_SECONDARY)
        Blank()
        Text('+ 新建')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.PRIMARY)
          .onClick(() => {
            this.showCreate = !this.showCreate;
          })
      }
      .width('100%')

      if (this.showCreate) {
        Row({ space: AppTheme.SPACE_S }) {
          Button('📝 MD 笔记')
            .layoutWeight(1)
            .fontSize(AppTheme.FONT_CAPTION)
            .backgroundColor(AppTheme.PRIMARY)
            .borderRadius(AppTheme.RADIUS_BTN)
            .onClick(() => {
              this.createNote('md');
            })
          Button('✍️ 手写笔记')
            .layoutWeight(1)
            .fontSize(AppTheme.FONT_CAPTION)
            .backgroundColor(AppTheme.WARNING)
            .borderRadius(AppTheme.RADIUS_BTN)
            .onClick(() => {
              this.createNote('handwriting');
            })
        }
        .width('100%')
      }

      List({ space: AppTheme.SPACE_M }) {
        ForEach(this.notes, (n: Note, index: number) => {
          ListItem() {
            AppCard({
              selected: this.selectedIndex === index,
              clickable: true,
              onCardClick: () => {
                this.selectNote(index);
              }
            }) {
              Column({ space: AppTheme.SPACE_S }) {
                Text(n.title)
                  .fontSize(AppTheme.FONT_BODY)
                  .fontColor(AppTheme.TEXT_PRIMARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Row({ space: AppTheme.SPACE_S }) {
                  this.tag(n.kind === 'md' ? 'MD' : '手写', n.kind === 'md' ? AppTheme.PRIMARY : AppTheme.WARNING)
                  this.tag(n.visibility === 'private' ? '私有' : '共享',
                    n.visibility === 'private' ? AppTheme.TEXT_TERTIARY : AppTheme.SUCCESS)
                  if (this.qualityLabel(n) !== '') {
                    this.tag(this.qualityLabel(n),
                      n.quality_status === 'accepted' ? AppTheme.SUCCESS : AppTheme.TEXT_TERTIARY)
                  }
                  if (!this.isMine(n)) {
                    this.tag('同学共享', AppTheme.PRIMARY)
                  }
                }
              }
              .alignItems(HorizontalAlign.Start)
            }
          }
        }, (n: Note) => `${n.id}`)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  rightPane() {
    if (this.current() === null) {
      Column() {
        Text('选择左侧笔记或新建').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_TERTIARY)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Column({ space: AppTheme.SPACE_M }) {
        Row({ space: AppTheme.SPACE_M }) {
          TextInput({ text: this.noteTitle, placeholder: '笔记标题' })
            .fontSize(AppTheme.FONT_SUBTITLE)
            .layoutWeight(1)
            .backgroundColor('transparent')
            .enabled(this.isMine(this.current()!))
            .onChange((v: string) => {
              this.noteTitle = v;
              this.dirty = true;
            })
          if (this.dirty) {
            Text('未保存').fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.WARNING)
          }
          if (this.isMine(this.current()!)) {
            Button('保存')
              .fontSize(AppTheme.FONT_BODY)
              .backgroundColor(AppTheme.PRIMARY)
              .borderRadius(AppTheme.RADIUS_BTN)
              .onClick(() => {
                this.saveNote();
              })
            Button(this.sharing ? '…' :
              (this.current()!.visibility === 'private' ? '共享' : '取消共享'))
              .fontSize(AppTheme.FONT_BODY)
              .enabled(!this.sharing)
              .backgroundColor(this.current()!.visibility === 'private' ? AppTheme.SUCCESS : AppTheme.BG_CARD)
              .fontColor(this.current()!.visibility === 'private' ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
              .borderRadius(AppTheme.RADIUS_BTN)
              .onClick(() => {
                this.toggleShare();
              })
          }
          if (this.current()!.kind === 'md') {
            Button('导出 MD')
              .fontSize(AppTheme.FONT_BODY)
              .backgroundColor(AppTheme.BG_CARD)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .borderRadius(AppTheme.RADIUS_BTN)
              .onClick(() => {
                this.exportMd();
              })
          }
        }
        .width('100%')

        if (this.current()!.kind === 'md') {
          TextArea({ text: this.editorText, placeholder: 'Markdown 内容…' })
            .width('100%')
            .layoutWeight(1)
            .fontSize(AppTheme.FONT_BODY)
            .backgroundColor(AppTheme.BG_CARD)
            .borderRadius(AppTheme.RADIUS_CARD)
            .enabled(this.isMine(this.current()!))
            .onChange((v: string) => {
              this.editorText = v;
              this.dirty = true;
            })
        } else {
          Column() {
            if (this.boardKey >= 0) {
              HandwritingBoard({
                initialJson: this.editorText,
                onStrokesChanged: (json: string) => {
                  this.editorText = json;
                  this.dirty = true;
                }
              })
            }
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
    }
  }

  build() {
    Row({ space: AppTheme.SPACE_L }) {
      Column() {
        this.leftPane()
      }
      .width(280)
      .height('100%')

      Column() {
        this.rightPane()
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .padding(AppTheme.SPACE_L)
    .backgroundColor(AppTheme.BG_PAGE)
    .alignItems(VerticalAlign.Top)
  }
}
