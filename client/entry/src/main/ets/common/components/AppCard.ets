import { AppTheme } from '../AppTheme';

/**
 * 通用卡片组件。样式属性以参数形式暴露，
 * 便于后续挂属性动画 / 共享元素转场而不改调用方结构。
 */
@Component
export struct AppCard {
  cardRadius: number = AppTheme.RADIUS_CARD;
  cardPadding: number = AppTheme.SPACE_L;
  cardBgColor: string = AppTheme.BG_CARD;
  cardBorderColor: string = 'transparent';
  cardBorderWidth: number = 0;
  @Prop selected: boolean = false;
  clickable: boolean = false;
  fillHeight: boolean = false;
  onCardClick: () => void = () => {
  };
  @BuilderParam content: () => void = this.empty;

  @Builder
  empty() {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .height(this.fillHeight ? '100%' : 'auto')
    .padding(this.cardPadding)
    .borderRadius(this.cardRadius)
    .backgroundColor(this.selected ? AppTheme.PRIMARY_LIGHT : this.cardBgColor)
    .border({
      width: this.selected ? 1 : this.cardBorderWidth,
      color: this.selected ? AppTheme.PRIMARY : this.cardBorderColor
    })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      if (this.clickable) {
        this.onCardClick();
      }
    })
  }
}
