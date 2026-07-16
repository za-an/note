import { AppTheme } from '../common/AppTheme';
import { UserInfo } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';
import { CollabManager } from '../service/collab/CollabManager';
import { LibraryPage } from './LibraryPage';
import { OverviewPage } from './OverviewPage';
import { RecordPage } from './RecordPage';
import { SessionDetailPage } from './SessionDetailPage';
import { AiNotePage } from './AiNotePage';
import { NotesPage } from './NotesPage';
import { ReviewPage } from './ReviewPage';
import { SettingsPage } from './SettingsPage';

interface TabItem {
  key: string;
  label: string;
  teacherOnly: boolean;
}

const TABS: TabItem[] = [
  { key: 'overview', label: '概览', teacherOnly: false },
  { key: 'record', label: '录音', teacherOnly: false },
  { key: 'sessions', label: '课时', teacherOnly: false },
  { key: 'ai', label: 'AI 笔记', teacherOnly: false },
  { key: 'notes', label: '笔记', teacherOnly: false },
  { key: 'review', label: '审核', teacherOnly: true }
];

/**
 * 应用壳（Notein 活力风）：
 * 登录 → 课程库（彩色几何封面网格）→ 课程工作台（顶部标签栏 + 内容区）。
 * 协同能力（NFC/局域网互抓/跨端接续）收进设置页开关，默认开启。
 */
@Entry
@Component
struct Index {
  @StorageLink('currentTab') currentTab: string = 'overview';
  @StorageLink('continueRestoreTick') @Watch('onContinueRestore') restoreTick: number = 0;
  @State stage: string = 'login'; // login | library | workspace
  @State users: UserInfo[] = [];
  @State loadError: string = '';
  @State showSettings: boolean = false;

  aboutToAppear(): void {
    this.loadUsers();
    // 冷启动迁移恢复：EntryAbility 已写入状态，但 @Watch 不触发初始化
    const pending: string | undefined = AppStorage.get<string>('continueRestoreState');
    if (pending !== undefined && pending !== '') {
      this.onContinueRestore();
    }
  }

  /** 跨端迁移：目标端恢复学习状态 */
  onContinueRestore(): void {
    const state: string | undefined = AppStorage.get<string>('continueRestoreState');
    if (state === undefined || state === '') {
      return;
    }
    AppStorage.setOrCreate<string>('continueRestoreState', '');
    const tab: string = GlobalState.restoreFromJson(state);
    if (GlobalState.user === null) {
      this.stage = 'login';
      return;
    }
    if (GlobalState.course !== null) {
      this.currentTab = tab === '' ? 'overview' : tab;
      this.stage = 'workspace';
    } else {
      this.stage = 'library';
    }
  }

  private async loadUsers(): Promise<void> {
    try {
      this.users = JSON.parse(await Api.get('/auth/users')) as UserInfo[];
      this.loadError = '';
    } catch (e) {
      this.loadError = `无法连接服务端：${(e as Error).message}`;
    }
  }

  private login(u: UserInfo): void {
    GlobalState.user = u;
    this.stage = 'library';
    GlobalState.updateSnapshot('overview');
  }

  private avatarColor(u: UserInfo): string {
    return u.role === 'teacher' ? AppTheme.INK : AppTheme.PRIMARY;
  }

  // ============ 登录页 ============
  @Builder
  loginView() {
    Column() {
      Blank().layoutWeight(1)
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(96)
          .height(96)
          .borderRadius(28)
          .backgroundColor(AppTheme.PRIMARY)
        Text('伴')
          .fontSize(48)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .margin({ bottom: AppTheme.SPACE_XL })

      Text('智慧伴学')
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.INK)
      Text('课堂灵感 · 一触即达')
        .fontSize(AppTheme.FONT_SUBTITLE)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .margin({ top: AppTheme.SPACE_S, bottom: AppTheme.SPACE_XXL })

      if (this.loadError !== '') {
        Column({ space: AppTheme.SPACE_M }) {
          Text(this.loadError).fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.DANGER)
          Button('重试')
            .fontSize(AppTheme.FONT_BODY)
            .fontColor('#FFFFFF')
            .backgroundColor(AppTheme.PRIMARY)
            .borderRadius(999)
            .onClick(() => {
              this.loadUsers();
            })
        }
      } else {
        Row({ space: AppTheme.SPACE_XL }) {
          ForEach(this.users, (u: UserInfo) => {
            Column({ space: AppTheme.SPACE_M }) {
              Text(u.name.substring(0, 1))
                .fontSize(30)
                .fontColor('#FFFFFF')
                .width(72)
                .height(72)
                .textAlign(TextAlign.Center)
                .borderRadius(36)
                .backgroundColor(this.avatarColor(u))
              Text(u.name)
                .fontSize(AppTheme.FONT_SUBTITLE)
                .fontColor(AppTheme.TEXT_PRIMARY)
              Text(u.role === 'teacher' ? '教师' : '学生')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor('#FFFFFF')
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .borderRadius(999)
                .backgroundColor(u.role === 'teacher' ? AppTheme.INK : AppTheme.PRIMARY)
            }
            .padding(AppTheme.SPACE_XL)
            .borderRadius(20)
            .backgroundColor(AppTheme.BG_CARD)
            .shadow({ radius: 24, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 6 })
            .onClick(() => {
              this.login(u);
            })
          }, (u: UserInfo) => `${u.id}`)
        }
        Text('Demo 预置账号 · 点击头像进入')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .margin({ top: AppTheme.SPACE_L })
      }
      Blank().layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_WHITE)
  }

  // ============ 顶部标签栏 ============
  @Builder
  topTab(item: TabItem) {
    Column({ space: 5 }) {
      Text(item.label)
        .fontSize(AppTheme.FONT_BODY)
        .fontWeight(this.currentTab === item.key ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === item.key ? AppTheme.INK : AppTheme.TEXT_TERTIARY)
      Column()
        .width(20)
        .height(3)
        .borderRadius(2)
        .backgroundColor(this.currentTab === item.key ? AppTheme.PRIMARY : 'transparent')
    }
    .onClick(() => {
      this.currentTab = item.key;
      GlobalState.updateSnapshot(item.key);
    })
  }

  @Builder
  topBar() {
    Row({ space: AppTheme.SPACE_XL }) {
      Row({ space: AppTheme.SPACE_S }) {
        Text('‹')
          .fontSize(26)
          .fontColor(AppTheme.INK)
          .onClick(() => {
            CollabManager.stop();
            GlobalState.course = null;
            this.stage = 'library';
          })
        Column()
          .width(10)
          .height(10)
          .borderRadius(3)
          .backgroundColor(GlobalState.course === null ? AppTheme.PRIMARY : AppTheme.cover(GlobalState.courseId()))
        Text(GlobalState.course === null ? '智慧伴学' : GlobalState.course.name)
          .fontSize(AppTheme.FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.INK)
      }

      Blank()

      Row({ space: AppTheme.SPACE_XL }) {
        ForEach(TABS, (item: TabItem) => {
          if (!item.teacherOnly || GlobalState.isTeacher()) {
            this.topTab(item)
          }
        }, (item: TabItem) => item.key)
      }

      Blank()

      Row({ space: AppTheme.SPACE_M }) {
        Text('⚙')
          .fontSize(20)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .onClick(() => {
            this.showSettings = true;
          })
        Text(GlobalState.user === null ? '' : GlobalState.user.name.substring(0, 1))
          .fontSize(AppTheme.FONT_BODY)
          .fontColor('#FFFFFF')
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .borderRadius(18)
          .backgroundColor(GlobalState.isTeacher() ? AppTheme.INK : AppTheme.PRIMARY)
      }
    }
    .width('100%')
    .height(AppTheme.TOPBAR_HEIGHT)
    .padding({ left: AppTheme.SPACE_XL, right: AppTheme.SPACE_XL })
    .backgroundColor(AppTheme.BG_CARD)
    .border({ width: { bottom: 1 }, color: AppTheme.DIVIDER })
  }

  @Builder
  workspaceView() {
    Column() {
      this.topBar()
      Column() {
        if (this.currentTab === 'overview') {
          OverviewPage()
        } else if (this.currentTab === 'record') {
          RecordPage()
        } else if (this.currentTab === 'sessions') {
          SessionDetailPage()
        } else if (this.currentTab === 'ai') {
          AiNotePage()
        } else if (this.currentTab === 'notes') {
          NotesPage()
        } else if (this.currentTab === 'review') {
          ReviewPage()
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_SUNKEN)
  }

  build() {
    Stack() {
      if (this.stage === 'login') {
        this.loginView()
      } else if (this.stage === 'library') {
        LibraryPage({
          onEnterCourse: () => {
            this.currentTab = 'overview';
            this.stage = 'workspace';
            GlobalState.updateSnapshot('overview');
            CollabManager.start(); // 协同能力默认开启：进课程自动待命
          },
          onLogout: () => {
            GlobalState.user = null;
            this.stage = 'login';
          },
          onOpenSettings: () => {
            this.showSettings = true;
          }
        })
      } else {
        this.workspaceView()
      }

      if (this.showSettings) {
        SettingsPage({
          onClose: () => {
            this.showSettings = false;
          },
          onLogout: () => {
            CollabManager.stop();
            GlobalState.user = null;
            GlobalState.course = null;
            this.showSettings = false;
            this.stage = 'login';
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
