import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { AppCard } from '../common/components/AppCard';
import { CourseSession, Outline, TranscriptSegment } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

/**
 * P3 课时详情（三栏）：课时列表 | 转写文本 | AI 提纲与操作。
 */
@Component
export struct SessionDetailPage {
  pathStack: NavPathStack = new NavPathStack();
  @State sessions: CourseSession[] = [];
  @State selectedIndex: number = 0;
  @State transcript: TranscriptSegment[] = [];
  @State outlineData: Outline | null = null;
  @State generating: boolean = false;

  aboutToAppear(): void {
    this.loadSessions();
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private currentSession(): CourseSession | null {
    return this.sessions.length === 0 ? null : this.sessions[this.selectedIndex];
  }

  private async loadSessions(): Promise<void> {
    try {
      this.sessions = JSON.parse(
        await Api.get(`/sessions?class_course_id=${GlobalState.courseId()}`)) as CourseSession[];
      if (this.sessions.length === 0) {
        return;
      }
      let idx: number = 0;
      if (GlobalState.currentSessionId >= 0) {
        for (let i = 0; i < this.sessions.length; i++) {
          if (this.sessions[i].id === GlobalState.currentSessionId) {
            idx = i;
            break;
          }
        }
        GlobalState.currentSessionId = -1;
      }
      await this.selectSession(idx);
    } catch (e) {
      this.toast(`加载课时失败：${(e as Error).message}`);
    }
  }

  private async selectSession(index: number): Promise<void> {
    this.selectedIndex = index;
    const s: CourseSession | null = this.currentSession();
    if (s === null) {
      return;
    }
    try {
      this.transcript = JSON.parse(
        await Api.get(`/sessions/${s.id}/transcript`)) as TranscriptSegment[];
    } catch (e) {
      this.transcript = [];
    }
    try {
      this.outlineData = JSON.parse(await Api.get(`/sessions/${s.id}/outline`)) as Outline;
    } catch (e) {
      this.outlineData = null; // 404：尚未生成
    }
  }

  private async generateOutline(): Promise<void> {
    const s: CourseSession | null = this.currentSession();
    if (s === null) {
      return;
    }
    if (this.transcript.length === 0) {
      this.toast('该课时尚无转写文本');
      return;
    }
    this.generating = true;
    try {
      this.outlineData = JSON.parse(await Api.post(`/sessions/${s.id}/outline/generate`)) as Outline;
      this.toast('提纲已生成（草稿）');
    } catch (e) {
      this.toast(`生成失败：${(e as Error).message}`);
    } finally {
      this.generating = false;
    }
  }

  private async review(action: string): Promise<void> {
    const s: CourseSession | null = this.currentSession();
    if (s === null || this.outlineData === null) {
      return;
    }
    interface ReviewBody {
      user_id: number;
      action: string;
    }

    const body: ReviewBody = { user_id: GlobalState.userId(), action: action };
    try {
      this.outlineData = JSON.parse(
        await Api.post(`/sessions/${s.id}/outline/review`, body)) as Outline;
      this.toast(action === 'publish' ? '已发布并写入本课程知识库' : '已退回');
    } catch (e) {
      this.toast(`操作失败：${(e as Error).message}`);
    }
  }

  private statusLabel(): string {
    if (this.outlineData === null) {
      return '未生成';
    }
    const s: string = this.outlineData.status;
    if (s === 'draft') {
      return '草稿';
    }
    if (s === 'pending') {
      return '待审核';
    }
    if (s === 'published') {
      return '已发布';
    }
    return '已退回';
  }

  private statusColor(): string {
    if (this.outlineData === null) {
      return AppTheme.TEXT_TERTIARY;
    }
    const s: string = this.outlineData.status;
    if (s === 'published') {
      return AppTheme.SUCCESS;
    }
    if (s === 'rejected') {
      return AppTheme.DANGER;
    }
    return AppTheme.WARNING;
  }

  build() {
    Row({ space: AppTheme.SPACE_L }) {
      // 左栏：课时列表
      Column({ space: AppTheme.SPACE_M }) {
        Text('课时列表').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_SECONDARY).width('100%')
        List({ space: AppTheme.SPACE_M }) {
          ForEach(this.sessions, (s: CourseSession, index: number) => {
            ListItem() {
              AppCard({
                selected: this.selectedIndex === index,
                clickable: true,
                onCardClick: () => {
                  this.selectSession(index);
                }
              }) {
                Column({ space: AppTheme.SPACE_XS }) {
                  Text(s.title)
                    .fontSize(AppTheme.FONT_BODY)
                    .fontColor(AppTheme.TEXT_PRIMARY)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(s.created_at.substring(0, 10))
                    .fontSize(AppTheme.FONT_CAPTION)
                    .fontColor(AppTheme.TEXT_TERTIARY)
                }
                .alignItems(HorizontalAlign.Start)
              }
            }
          }, (s: CourseSession) => `${s.id}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width(220)
      .height('100%')

      // 中栏：转写文本
      Column({ space: AppTheme.SPACE_M }) {
        Text('转写文本').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_SECONDARY).width('100%')
        Column() {
          AppCard({ fillHeight: true }) {
            Scroll() {
              Column({ space: AppTheme.SPACE_L }) {
                if (this.transcript.length === 0) {
                  Text('暂无转写内容').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_TERTIARY)
                }
                ForEach(this.transcript, (seg: TranscriptSegment) => {
                  Column({ space: AppTheme.SPACE_XS }) {
                    Text(`${Math.floor(seg.start_ms / 60000)}:${
                      ((seg.start_ms % 60000) / 1000).toFixed(0).padStart(2, '0')}`)
                      .fontSize(AppTheme.FONT_CAPTION)
                      .fontColor(AppTheme.PRIMARY)
                    Text(seg.text)
                      .fontSize(AppTheme.FONT_BODY)
                      .fontColor(AppTheme.TEXT_PRIMARY)
                      .lineHeight(22)
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                }, (seg: TranscriptSegment) => `${seg.id}`)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
            .scrollBar(BarState.Auto)
            .align(Alignment.TopStart)
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .layoutWeight(1)
      .height('100%')

      // 右栏：提纲预览 + 操作
      Column({ space: AppTheme.SPACE_M }) {
        Row({ space: AppTheme.SPACE_S }) {
          Text('AI 提纲').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_SECONDARY)
          Text(this.statusLabel())
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor('#FFFFFF')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(AppTheme.RADIUS_TAG)
            .backgroundColor(this.statusColor())
          Blank()
        }
        .width('100%')

        Column() {
          AppCard({ fillHeight: true }) {
            Scroll() {
              Column() {
                Text(this.outlineData === null ?
                  '尚未生成提纲，点击下方「生成提纲」调用 AI 层。' : this.outlineData.markdown)
                  .fontSize(AppTheme.FONT_BODY)
                  .fontColor(this.outlineData === null ? AppTheme.TEXT_TERTIARY : AppTheme.TEXT_PRIMARY)
                  .lineHeight(24)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
            .scrollBar(BarState.Auto)
            .align(Alignment.TopStart)
          }
        }
        .layoutWeight(1)
        .width('100%')

        Row({ space: AppTheme.SPACE_M }) {
          Button(this.generating ? '生成中…' : '生成提纲')
            .layoutWeight(1)
            .enabled(!this.generating)
            .backgroundColor(AppTheme.PRIMARY)
            .borderRadius(AppTheme.RADIUS_BTN)
            .onClick(() => {
              this.generateOutline();
            })
          if (GlobalState.isTeacher() && this.outlineData !== null && this.outlineData.status !== 'published') {
            Button('发布')
              .layoutWeight(1)
              .backgroundColor(AppTheme.SUCCESS)
              .borderRadius(AppTheme.RADIUS_BTN)
              .onClick(() => {
                this.review('publish');
              })
          }
        }
        .width('100%')
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
