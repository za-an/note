import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { ClassCourse } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

/** 课程封面配色（按 id 取模，仿 Notein 彩色笔记本封面） */
const COVER_COLORS: string[] = ['#21D5CE', '#5B8DEF', '#FF9F43', '#F5554A', '#9B8AFB', '#34C77B'];

/**
 * 课程库（Notein 文档库形态）：
 * 大标题 + 课程封面网格 + 右下角圆形 FAB（创建/加入浮层表单）。
 */
@Component
export struct LibraryPage {
  onEnterCourse: () => void = () => {
  };
  onLogout: () => void = () => {
  };
  onOpenSettings: () => void = () => {
  };
  @State courses: ClassCourse[] = [];
  @State showForm: boolean = false;
  @State formCourseName: string = '';
  @State formClassName: string = '';
  @State formInviteCode: string = '';

  aboutToAppear(): void {
    this.loadCourses();
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private coverColor(cc: ClassCourse): string {
    return AppTheme.cover(cc.id);
  }

  private async loadCourses(): Promise<void> {
    try {
      this.courses = JSON.parse(
        await Api.get(`/courses?user_id=${GlobalState.userId()}`)) as ClassCourse[];
    } catch (e) {
      this.toast(`加载课程失败：${(e as Error).message}`);
    }
  }

  private async createCourse(): Promise<void> {
    if (this.formCourseName.trim() === '' || this.formClassName.trim() === '') {
      this.toast('请填写课程名与班级名');
      return;
    }
    interface CreateBody {
      name: string;
      class_name: string;
      teacher_id: number;
    }

    const body: CreateBody = {
      name: this.formCourseName.trim(),
      class_name: this.formClassName.trim(),
      teacher_id: GlobalState.userId()
    };
    try {
      const cc: ClassCourse = JSON.parse(await Api.post('/courses', body)) as ClassCourse;
      this.toast(`已创建，邀请码 ${cc.invite_code}`);
      this.showForm = false;
      this.formCourseName = '';
      this.formClassName = '';
      await this.loadCourses();
    } catch (e) {
      this.toast(`创建失败：${(e as Error).message}`);
    }
  }

  private async joinCourse(): Promise<void> {
    if (this.formInviteCode.trim().length !== 6) {
      this.toast('请输入 6 位邀请码');
      return;
    }
    interface JoinBody {
      user_id: number;
      invite_code: string;
    }

    const body: JoinBody = { user_id: GlobalState.userId(), invite_code: this.formInviteCode.trim() };
    try {
      await Api.post('/courses/join', body);
      this.toast('加入成功');
      this.showForm = false;
      this.formInviteCode = '';
      await this.loadCourses();
    } catch (e) {
      this.toast(`加入失败：${(e as Error).message}`);
    }
  }

  private enter(cc: ClassCourse): void {
    GlobalState.course = cc;
    this.onEnterCourse();
  }

  // ---------- UI ----------
  @Builder
  courseCard(cc: ClassCourse) {
    Column() {
      // 彩色几何封面（仿 Notein 笔记本封面）
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.coverColor(cc))
        // 几何装饰：错落圆形 + 方块
        Circle()
          .width(90)
          .height(90)
          .fill('rgba(255,255,255,0.18)')
          .position({ x: 120, y: -20 })
        Circle()
          .width(50)
          .height(50)
          .fill('rgba(255,255,255,0.14)')
          .position({ x: 20, y: 70 })
        Column()
          .width(34)
          .height(34)
          .borderRadius(10)
          .rotate({ angle: 18 })
          .backgroundColor('rgba(0,0,0,0.10)')
          .position({ x: 150, y: 76 })
        Text(cc.name.substring(0, 1))
          .fontSize(40)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .margin({ left: AppTheme.SPACE_L, top: AppTheme.SPACE_L })
      }
      .width('100%')
      .height(128)
      .clip(true)

      // 信息
      Column({ space: AppTheme.SPACE_XS }) {
        Text(cc.name)
          .fontSize(AppTheme.FONT_SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${cc.class_name} · ${cc.teacher_name ?? ''}`)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .maxLines(1)
        Row({ space: 4 }) {
          Text('邀请码')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
          Text(cc.invite_code)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.PRIMARY_DEEP)
            .fontWeight(FontWeight.Medium)
        }
      }
      .width('100%')
      .padding(AppTheme.SPACE_M)
      .alignItems(HorizontalAlign.Start)
    }
    .borderRadius(AppTheme.RADIUS_CARD)
    .backgroundColor(AppTheme.BG_CARD)
    .clip(true)
    .shadow({ radius: 18, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 5 })
    .onClick(() => {
      this.enter(cc);
    })
  }

  @Builder
  formOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(17,17,17,0.35)')
        .onClick(() => {
          this.showForm = false;
        })

      Column({ space: AppTheme.SPACE_L }) {
        Text(GlobalState.isTeacher() ? '新建课程' : '加入课程')
          .fontSize(AppTheme.FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.INK)

        if (GlobalState.isTeacher()) {
          TextInput({ placeholder: '课程名，如：数据结构', text: this.formCourseName })
            .fontSize(AppTheme.FONT_BODY)
            .height(44)
            .borderRadius(AppTheme.RADIUS_CARD)
            .backgroundColor(AppTheme.BG_PAGE)
            .onChange((v: string) => {
              this.formCourseName = v;
            })
          TextInput({ placeholder: '班级名，如：计科2301', text: this.formClassName })
            .fontSize(AppTheme.FONT_BODY)
            .height(44)
            .borderRadius(AppTheme.RADIUS_CARD)
            .backgroundColor(AppTheme.BG_PAGE)
            .onChange((v: string) => {
              this.formClassName = v;
            })
          Button('创建课程')
            .width('100%')
            .height(44)
            .fontSize(AppTheme.FONT_BODY)
            .fontColor('#FFFFFF')
            .backgroundColor(AppTheme.INK)
            .borderRadius(999)
            .onClick(() => {
              this.createCourse();
            })
        } else {
          TextInput({ placeholder: '输入 6 位邀请码', text: this.formInviteCode })
            .fontSize(AppTheme.FONT_BODY)
            .height(44)
            .maxLength(6)
            .borderRadius(AppTheme.RADIUS_CARD)
            .backgroundColor(AppTheme.BG_PAGE)
            .onChange((v: string) => {
              this.formInviteCode = v;
            })
          Button('加入课程')
            .width('100%')
            .height(44)
            .fontSize(AppTheme.FONT_BODY)
            .fontColor('#FFFFFF')
            .backgroundColor(AppTheme.INK)
            .borderRadius(999)
            .onClick(() => {
              this.joinCourse();
            })
        }

        Text('取消')
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .onClick(() => {
            this.showForm = false;
          })
      }
      .width(380)
      .padding(AppTheme.SPACE_XL)
      .borderRadius(20)
      .backgroundColor(AppTheme.BG_CARD)
      .shadow({ radius: 32, color: 'rgba(17,17,17,0.15)', offsetX: 0, offsetY: 8 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: AppTheme.SPACE_L }) {
        // 头部
        Row({ space: AppTheme.SPACE_M }) {
          Column({ space: AppTheme.SPACE_XS }) {
            Text('我的课程')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.INK)
            Text(GlobalState.user === null ? '' :
              `${GlobalState.user.name} · ${GlobalState.isTeacher() ? '教师' : '学生'}`)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_TERTIARY)
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
          Row({ space: AppTheme.SPACE_S }) {
            Text('⚙')
              .fontSize(18)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .width(40)
              .height(40)
              .textAlign(TextAlign.Center)
              .borderRadius(20)
              .backgroundColor(AppTheme.BG_SUNKEN)
              .onClick(() => {
                this.onOpenSettings();
              })
            Text('切换身份')
              .fontSize(AppTheme.FONT_BODY)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .borderRadius(999)
              .backgroundColor(AppTheme.BG_SUNKEN)
              .onClick(() => {
                this.onLogout();
              })
          }
        }
        .width('100%')

        if (this.courses.length === 0) {
          Column({ space: AppTheme.SPACE_M }) {
            Text('📚').fontSize(48)
            Text(GlobalState.isTeacher() ? '还没有课程，点右下角 + 新建' : '还没有课程，点右下角 + 凭邀请码加入')
              .fontSize(AppTheme.FONT_BODY)
              .fontColor(AppTheme.TEXT_TERTIARY)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.courses, (cc: ClassCourse) => {
              GridItem() {
                this.courseCard(cc)
              }
            }, (cc: ClassCourse) => `${cc.id}`)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr')
          .columnsGap(AppTheme.SPACE_L)
          .rowsGap(AppTheme.SPACE_L)
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .padding(AppTheme.SPACE_XXL)

      // FAB
      Text('＋')
        .fontSize(28)
        .fontColor('#FFFFFF')
        .width(56)
        .height(56)
        .textAlign(TextAlign.Center)
        .borderRadius(28)
        .backgroundColor(AppTheme.PRIMARY)
        .shadow({ radius: 16, color: 'rgba(5,206,145,0.4)', offsetX: 0, offsetY: 6 })
        .margin(AppTheme.SPACE_XXL)
        .onClick(() => {
          this.showForm = true;
        })

      if (this.showForm) {
        this.formOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_PAGE)
  }
}
