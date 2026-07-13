import { AppTheme } from '../AppTheme';

/**
 * 可复用双栏容器：左栏固定宽 280vp，右栏自适应。
 * 横屏「左列表 + 右内容」布局的统一骨架。
 */
@Component
export struct TwoPane {
  leftWidth: number = AppTheme.LEFT_PANE_WIDTH;
  gap: number = AppTheme.SPACE_L;
  @BuilderParam leftPane: () => void = this.empty;
  @BuilderParam rightPane: () => void = this.empty;

  @Builder
  empty() {
  }

  build() {
    Row({ space: this.gap }) {
      Column() {
        this.leftPane()
      }
      .width(this.leftWidth)
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
