import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppTheme } from '../common/AppTheme';
import { CourseSession, Note } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

/**
 * 课程概览：课程信息 + 统计 + 最近课时。
 */
@Component
export struct OverviewPage {
  @StorageLink('currentTab') currentTab: string = 'overview';
  @State sessions: CourseSession[] = [];
  @State noteCount: number = 0;
  @State sharedCount: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private async load(): Promise<void> {
    try {
      this.sessions = JSON.parse(
        await Api.get(`/sessions?class_course_id=${GlobalState.courseId()}`)) as CourseSession[];
    } catch (e) {
      this.sessions = [];
    }
    try {
      const notes: Note[] = JSON.parse(await Api.get(
        `/notes?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}`)) as Note[];
      this.noteCount = notes.length;
      this.sharedCount = notes.filter((n: Note) => n.visibility === 'shared').length;
    } catch (e) {
      this.noteCount = 0;
      this.sharedCount = 0;
    }
  }

  private copyInvite(): void {
    if (GlobalState.course === null) {
      return;
    }
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, GlobalState.course.invite_code);
    pasteboard.getSystemPasteboard().setData(data);
    this.toast('邀请码已复制');
  }

  @Builder
  statCard(num: string, label: string, accent: string) {
    Column({ space: AppTheme.SPACE_XS }) {
      Text(num)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(accent)
      Text(label)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_TERTIARY)
    }
    .layoutWeight(1)
    .padding(AppTheme.SPACE_L)
    .borderRadius(AppTheme.RADIUS_CARD)
    .backgroundColor(AppTheme.BG_CARD)
    .alignItems(HorizontalAlign.Start)
    .shadow({ radius: 16, color: 'rgba(17,17,17,0.04)', offsetX: 0, offsetY: 4 })
  }

  build() {
    Column({ space: AppTheme.SPACE_XL }) {
      // 头部
      Row({ space: AppTheme.SPACE_M }) {
        Column({ space: AppTheme.SPACE_XS }) {
          Text(GlobalState.course === null ? '' : GlobalState.course.name)
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
          Text(GlobalState.course === null ? '' :
            `${GlobalState.course.class_name} · ${GlobalState.course.teacher_name ?? ''}`)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
        Text(`邀请码 ${GlobalState.course === null ? '' : GlobalState.course.invite_code} ⧉`)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.PRIMARY)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(999)
          .backgroundColor(AppTheme.PRIMARY_LIGHT)
          .onClick(() => {
            this.copyInvite();
          })
      }
      .width('100%')

      // 统计
      Row({ space: AppTheme.SPACE_L }) {
        this.statCard(`${this.sessions.length}`, '课时', AppTheme.INK)
        this.statCard(`${this.noteCount}`, '我的笔记', AppTheme.PRIMARY)
        this.statCard(`${this.sharedCount}`, '共享笔记', AppTheme.SUCCESS)
      }
      .width('100%')

      // 最近课时
      Row() {
        Text('最近课时').fontSize(AppTheme.FONT_SUBTITLE).fontWeight(FontWeight.Medium).fontColor(AppTheme.INK)
        Blank()
        Text('去录音 →')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.PRIMARY)
          .onClick(() => {
            this.currentTab = 'record';
          })
      }
      .width('100%')

      if (this.sessions.length === 0) {
        Column({ space: AppTheme.SPACE_M }) {
          Text('🎙️').fontSize(40)
          Text('还没有课时，去「录音」开始第一节课')
            .fontSize(AppTheme.FONT_BODY)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: AppTheme.SPACE_M }) {
          ForEach(this.sessions, (s: CourseSession) => {
            ListItem() {
              Row({ space: AppTheme.SPACE_M }) {
                Text('📄').fontSize(20)
                Column({ space: 2 }) {
                  Text(s.title)
                    .fontSize(AppTheme.FONT_BODY)
                    .fontColor(AppTheme.TEXT_PRIMARY)
                  Text(s.created_at.substring(0, 10))
                    .fontSize(AppTheme.FONT_CAPTION)
                    .fontColor(AppTheme.TEXT_TERTIARY)
                }
                .alignItems(HorizontalAlign.Start)

                Blank()
                Text(s.status === 'done' ? '已完成' : '转写中')
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(s.status === 'done' ? AppTheme.SUCCESS : AppTheme.WARNING)
                  .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                  .borderRadius(999)
                  .backgroundColor(AppTheme.tagBg(s.status === 'done' ? AppTheme.SUCCESS : AppTheme.WARNING))
              }
              .width('100%')
              .padding(AppTheme.SPACE_L)
              .borderRadius(AppTheme.RADIUS_CARD)
              .backgroundColor(AppTheme.BG_CARD)
              .onClick(() => {
                GlobalState.currentSessionId = s.id;
                this.currentTab = 'sessions';
              })
            }
          }, (s: CourseSession) => `${s.id}`)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding(AppTheme.SPACE_XXL)
    .backgroundColor(AppTheme.BG_PAGE)
  }
}
