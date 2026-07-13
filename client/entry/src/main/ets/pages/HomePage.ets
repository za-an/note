import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { AppCard } from '../common/components/AppCard';
import { TwoPane } from '../common/components/TwoPane';
import { ClassCourse, CourseSession, UserInfo } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

/**
 * P1 首页：登录选身份 → 课程集合列表（创建/邀请码加入）→ 集合概览与功能入口。
 */
@Component
export struct HomePage {
  pathStack: NavPathStack = new NavPathStack();
  @State users: UserInfo[] = [];
  @State loggedIn: boolean = false;
  @State courses: ClassCourse[] = [];
  @State selectedIndex: number = 0;
  @State sessions: CourseSession[] = [];
  @State loading: boolean = false;
  @State loadError: string = '';
  // 内联表单
  @State showCreate: boolean = false;
  @State showJoin: boolean = false;
  @State formCourseName: string = '';
  @State formClassName: string = '';
  @State formInviteCode: string = '';

  aboutToAppear(): void {
    this.loadUsers();
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private async loadUsers(): Promise<void> {
    try {
      this.users = JSON.parse(await Api.get('/auth/users')) as UserInfo[];
      this.loadError = '';
    } catch (e) {
      this.loadError = `无法连接服务端：${(e as Error).message}`;
    }
  }

  private async login(u: UserInfo): Promise<void> {
    GlobalState.user = u;
    this.loggedIn = true;
    await this.loadCourses();
  }

  private async loadCourses(): Promise<void> {
    try {
      this.courses = JSON.parse(await Api.get(`/courses?user_id=${GlobalState.userId()}`)) as ClassCourse[];
      if (this.courses.length > 0) {
        if (this.selectedIndex >= this.courses.length) {
          this.selectedIndex = 0;
        }
        this.selectCourse(this.selectedIndex);
      }
    } catch (e) {
      this.toast(`加载课程失败：${(e as Error).message}`);
    }
  }

  private async selectCourse(index: number): Promise<void> {
    this.selectedIndex = index;
    GlobalState.course = this.courses[index];
    try {
      this.sessions = JSON.parse(
        await Api.get(`/sessions?class_course_id=${GlobalState.courseId()}`)) as CourseSession[];
    } catch (e) {
      this.sessions = [];
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
      this.showCreate = false;
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
      this.showJoin = false;
      this.formInviteCode = '';
      await this.loadCourses();
    } catch (e) {
      this.toast(`加入失败：${(e as Error).message}`);
    }
  }

  private go(name: string): void {
    if (GlobalState.course === null) {
      this.toast('请先选择课程集合');
      return;
    }
    this.pathStack.pushPathByName(name, null);
  }

  // ============ 登录视图 ============
  @Builder
  loginView() {
    Column({ space: AppTheme.SPACE_XL }) {
      Text('智慧伴学').fontSize(32).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT_PRIMARY)
      Text('课堂 AI 协同学习 · Demo').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_TERTIARY)

      if (this.loadError !== '') {
        Text(this.loadError).fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.DANGER)
        Button('重试').onClick(() => {
          this.loadUsers();
        })
          .backgroundColor(AppTheme.PRIMARY).borderRadius(AppTheme.RADIUS_BTN)
      } else {
        Text('选择身份进入（Demo 预置账号）').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_SECONDARY)
        Row({ space: AppTheme.SPACE_L }) {
          ForEach(this.users, (u: UserInfo) => {
            Column({ space: AppTheme.SPACE_S }) {
              Text(u.name.substring(0, 1))
                .fontSize(28)
                .fontColor('#FFFFFF')
                .width(64)
                .height(64)
                .textAlign(TextAlign.Center)
                .borderRadius(32)
                .backgroundColor(u.role === 'teacher' ? AppTheme.WARNING : AppTheme.PRIMARY)
              Text(u.name).fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_PRIMARY)
              Text(u.role === 'teacher' ? '教师' : '学生')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_TERTIARY)
            }
            .padding(AppTheme.SPACE_L)
            .borderRadius(AppTheme.RADIUS_CARD)
            .backgroundColor(AppTheme.BG_CARD)
            .onClick(() => {
              this.login(u);
            })
          }, (u: UserInfo) => `${u.id}`)
        }
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppTheme.BG_PAGE)
  }

  // ============ 左栏 ============
  @Builder
  leftPane() {
    Column({ space: AppTheme.SPACE_L }) {
      Row({ space: AppTheme.SPACE_M }) {
        Text(GlobalState.user === null ? '' : GlobalState.user.name.substring(0, 1))
          .fontSize(AppTheme.FONT_SUBTITLE)
          .fontColor('#FFFFFF')
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .borderRadius(20)
          .backgroundColor(GlobalState.isTeacher() ? AppTheme.WARNING : AppTheme.PRIMARY)
        Column({ space: 2 }) {
          Text(GlobalState.user === null ? '' : GlobalState.user.name)
            .fontSize(AppTheme.FONT_SUBTITLE)
            .fontColor(AppTheme.TEXT_PRIMARY)
          Text(GlobalState.isTeacher() ? '教师' : '学生')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
        Text('切换')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.PRIMARY)
          .onClick(() => {
            GlobalState.user = null;
            GlobalState.course = null;
            this.loggedIn = false;
          })
      }
      .width('100%')

      Row() {
        Text('我的课程集合').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_SECONDARY)
        Blank()
        if (GlobalState.isTeacher()) {
          Text('+ 创建')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.PRIMARY)
            .onClick(() => {
              this.showCreate = !this.showCreate;
              this.showJoin = false;
            })
        }
      }
      .width('100%')

      if (this.showCreate) {
        Column({ space: AppTheme.SPACE_S }) {
          TextInput({ placeholder: '课程名，如：数据结构', text: this.formCourseName })
            .fontSize(AppTheme.FONT_BODY)
            .onChange((v: string) => {
              this.formCourseName = v;
            })
          TextInput({ placeholder: '班级名，如：计科2301', text: this.formClassName })
            .fontSize(AppTheme.FONT_BODY)
            .onChange((v: string) => {
              this.formClassName = v;
            })
          Button('确认创建')
            .width('100%')
            .fontSize(AppTheme.FONT_BODY)
            .backgroundColor(AppTheme.PRIMARY)
            .borderRadius(AppTheme.RADIUS_BTN)
            .onClick(() => {
              this.createCourse();
            })
        }
        .padding(AppTheme.SPACE_M)
        .borderRadius(AppTheme.RADIUS_CARD)
        .backgroundColor(AppTheme.BG_CARD)
      }

      List({ space: AppTheme.SPACE_M }) {
        ForEach(this.courses, (course: ClassCourse, index: number) => {
          ListItem() {
            AppCard({
              selected: this.selectedIndex === index,
              clickable: true,
              onCardClick: () => {
                this.selectCourse(index);
              }
            }) {
              Column({ space: AppTheme.SPACE_XS }) {
                Text(course.name)
                  .fontSize(AppTheme.FONT_SUBTITLE)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppTheme.TEXT_PRIMARY)
                Text(`${course.class_name} · ${course.teacher_name ?? ''}`)
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.TEXT_SECONDARY)
                Text(`邀请码 ${course.invite_code}`)
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.TEXT_TERTIARY)
              }
              .alignItems(HorizontalAlign.Start)
            }
          }
        }, (course: ClassCourse) => `${course.id}`)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      if (this.showJoin) {
        Column({ space: AppTheme.SPACE_S }) {
          TextInput({ placeholder: '输入 6 位邀请码', text: this.formInviteCode })
            .fontSize(AppTheme.FONT_BODY)
            .maxLength(6)
            .onChange((v: string) => {
              this.formInviteCode = v;
            })
          Button('确认加入')
            .width('100%')
            .fontSize(AppTheme.FONT_BODY)
            .backgroundColor(AppTheme.PRIMARY)
            .borderRadius(AppTheme.RADIUS_BTN)
            .onClick(() => {
              this.joinCourse();
            })
        }
        .padding(AppTheme.SPACE_M)
        .borderRadius(AppTheme.RADIUS_CARD)
        .backgroundColor(AppTheme.BG_CARD)
      }

      Button('凭邀请码加入集合')
        .width('100%')
        .fontSize(AppTheme.FONT_BODY)
        .backgroundColor(AppTheme.BG_CARD)
        .fontColor(AppTheme.PRIMARY)
        .borderRadius(AppTheme.RADIUS_BTN)
        .onClick(() => {
          this.showJoin = !this.showJoin;
          this.showCreate = false;
        })
    }
    .width('100%')
    .height('100%')
  }

  // ============ 右栏 ============
  @Builder
  quickEntry(label: string, desc: string, route: string) {
    Column({ space: AppTheme.SPACE_XS }) {
      Text(label).fontSize(AppTheme.FONT_SUBTITLE).fontColor(AppTheme.PRIMARY)
      Text(desc).fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.TEXT_TERTIARY)
    }
    .layoutWeight(1)
    .padding(AppTheme.SPACE_L)
    .borderRadius(AppTheme.RADIUS_CARD)
    .backgroundColor(AppTheme.BG_CARD)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.go(route);
    })
  }

  @Builder
  rightPane() {
    if (this.courses.length === 0) {
      Column({ space: AppTheme.SPACE_M }) {
        Text('还没有课程集合').fontSize(AppTheme.FONT_SUBTITLE).fontColor(AppTheme.TEXT_SECONDARY)
        Text(GlobalState.isTeacher() ? '点击左上角「+ 创建」新建一个课程集合' : '点击下方按钮凭邀请码加入')
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Column({ space: AppTheme.SPACE_L }) {
        Text(GlobalState.course === null ? '' : `${GlobalState.course.name} · ${GlobalState.course.class_name}`)
          .fontSize(AppTheme.FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .width('100%')

        Row({ space: AppTheme.SPACE_L }) {
          this.quickEntry('课堂录音', '录音并实时转写', 'record')
          this.quickEntry('课时详情', '转写与提纲', 'sessionDetail')
          this.quickEntry('AI 问答笔记', '边问边记', 'aiNote')
        }
        .width('100%')

        Row({ space: AppTheme.SPACE_L }) {
          this.quickEntry('我的笔记', 'MD 与手写', 'notes')
          if (GlobalState.isTeacher()) {
            this.quickEntry('教师审核', '提纲发布', 'review')
          } else {
            Column() {
            }.layoutWeight(1)
          }
          Column() {
          }.layoutWeight(1)
        }
        .width('100%')

        Text('最近课时').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_SECONDARY).width('100%')
        List({ space: AppTheme.SPACE_M }) {
          ForEach(this.sessions, (s: CourseSession) => {
            ListItem() {
              AppCard({
                clickable: true,
                onCardClick: () => {
                  GlobalState.currentSessionId = s.id;
                  this.go('sessionDetail');
                }
              }) {
                Row() {
                  Text(s.title).fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_PRIMARY)
                  Blank()
                  Text(s.status === 'done' ? '已完成' : '转写中')
                    .fontSize(AppTheme.FONT_CAPTION)
                    .fontColor(s.status === 'done' ? AppTheme.SUCCESS : AppTheme.WARNING)
                }
                .width('100%')
              }
            }
          }, (s: CourseSession) => `${s.id}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
    }
  }

  build() {
    if (!this.loggedIn) {
      this.loginView()
    } else {
      TwoPane({
        leftPane: () => {
          this.leftPane()
        },
        rightPane: () => {
          this.rightPane()
        }
      })
    }
  }
}
