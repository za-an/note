import { AppTheme } from '../common/AppTheme';
import { HomePage } from './HomePage';
import { RecordPage } from './RecordPage';
import { SessionDetailPage } from './SessionDetailPage';
import { AiNotePage } from './AiNotePage';
import { NotesPage } from './NotesPage';
import { ReviewPage } from './ReviewPage';

/**
 * 应用唯一 @Entry 页：持有 Navigation + NavPathStack，
 * 6 个业务页面均以 NavDestination 形式注册，统一转场容器（动画预留）。
 */
@Entry
@Component
struct Index {
  pathStack: NavPathStack = new NavPathStack();

  @Builder
  pageMap(name: string) {
    if (name === 'record') {
      NavDestination() {
        RecordPage({ pathStack: this.pathStack })
      }
      .title('课堂录音')
    } else if (name === 'sessionDetail') {
      NavDestination() {
        SessionDetailPage({ pathStack: this.pathStack })
      }
      .title('课时详情')
    } else if (name === 'aiNote') {
      NavDestination() {
        AiNotePage({ pathStack: this.pathStack })
      }
      .title('AI 问答')
    } else if (name === 'notes') {
      NavDestination() {
        NotesPage({ pathStack: this.pathStack })
      }
      .title('我的笔记')
    } else if (name === 'review') {
      NavDestination() {
        ReviewPage({ pathStack: this.pathStack })
      }
      .title('教师审核')
    }
  }

  build() {
    Navigation(this.pathStack) {
      HomePage({ pathStack: this.pathStack })
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_PAGE)
  }
}
