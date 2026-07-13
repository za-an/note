/**
 * 全局主题常量 —— 简洁风：单主色 + 中性灰阶，无渐变无重投影。
 * 后续动画参数（时长、曲线）也集中在此扩展。
 */
export class AppTheme {
  // 主色
  static readonly PRIMARY: string = '#2E7DFF';
  static readonly PRIMARY_LIGHT: string = '#EAF1FF';

  // 灰阶
  static readonly BG_PAGE: string = '#F5F7FA';
  static readonly BG_CARD: string = '#FFFFFF';
  static readonly TEXT_PRIMARY: string = '#1A1A1A';
  static readonly TEXT_SECONDARY: string = '#666666';
  static readonly TEXT_TERTIARY: string = '#999999';
  static readonly DIVIDER: string = '#E5E8EC';

  // 语义色
  static readonly SUCCESS: string = '#34C77B';
  static readonly WARNING: string = '#FF9F43';
  static readonly DANGER: string = '#F5554A';

  // 圆角
  static readonly RADIUS_CARD: number = 12;
  static readonly RADIUS_BTN: number = 8;
  static readonly RADIUS_TAG: number = 4;

  // 间距
  static readonly SPACE_XS: number = 4;
  static readonly SPACE_S: number = 8;
  static readonly SPACE_M: number = 12;
  static readonly SPACE_L: number = 16;
  static readonly SPACE_XL: number = 24;
  static readonly SPACE_XXL: number = 32;

  // 字号
  static readonly FONT_TITLE: number = 20;
  static readonly FONT_SUBTITLE: number = 16;
  static readonly FONT_BODY: number = 14;
  static readonly FONT_CAPTION: number = 12;

  // 布局
  static readonly LEFT_PANE_WIDTH: number = 280;
}
