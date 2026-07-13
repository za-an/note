import { AppTheme } from '../AppTheme';
import { HandwritingDoc, Stroke, StrokePoint } from '../../model/Models';

/**
 * 手写画板：Canvas 矢量笔迹，压力值映射笔迹粗细。
 * 模拟器/鼠标压力恒定 1.0；真机 M-Pencil 接入点见 getPressure()。
 */
@Component
export struct HandwritingBoard {
  /** 初始笔迹 JSON（HandwritingDoc），空串为新画板 */
  initialJson: string = '';
  /** 笔迹变化回调（抬笔时触发，返回完整 JSON） */
  onStrokesChanged: (json: string) => void = (json: string) => {
  };
  @State tool: string = 'pen'; // pen | eraser
  @State strokeCount: number = 0;
  private strokes: Stroke[] = [];
  private currentStroke: Stroke | null = null;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private readonly baseWidth: number = 3;
  private readonly eraserWidth: number = 24;

  aboutToAppear(): void {
    if (this.initialJson.trim() !== '') {
      try {
        const doc: HandwritingDoc = JSON.parse(this.initialJson) as HandwritingDoc;
        this.strokes = doc.strokes;
        this.strokeCount = this.strokes.length;
      } catch (e) {
        this.strokes = [];
      }
    }
  }

  /**
   * 压力获取挂载点：真机 M-Pencil 支持后改读 touch 事件压力值 / Pen Kit；
   * 模拟器与鼠标恒定 1.0。数据结构已按 0~1 压力存储，UI 无需改动。
   */
  private getPressure(): number {
    return 1.0;
  }

  private emit(): void {
    const doc: HandwritingDoc = { strokes: this.strokes };
    this.onStrokesChanged(JSON.stringify(doc));
  }

  private drawSegment(from: StrokePoint, to: StrokePoint, stroke: Stroke): void {
    this.ctx.beginPath();
    this.ctx.lineCap = 'round';
    this.ctx.lineJoin = 'round';
    this.ctx.strokeStyle = stroke.eraser ? AppTheme.BG_CARD : stroke.color;
    this.ctx.lineWidth = stroke.width * ((from.p + to.p) / 2);
    this.ctx.moveTo(from.x, from.y);
    this.ctx.lineTo(to.x, to.y);
    this.ctx.stroke();
  }

  private redraw(): void {
    this.ctx.clearRect(0, 0, this.ctx.width, this.ctx.height);
    this.ctx.fillStyle = AppTheme.BG_CARD;
    this.ctx.fillRect(0, 0, this.ctx.width, this.ctx.height);
    for (const s of this.strokes) {
      for (let i = 1; i < s.points.length; i++) {
        this.drawSegment(s.points[i - 1], s.points[i], s);
      }
    }
  }

  private handleTouch(event: TouchEvent): void {
    if (event.touches.length === 0 && event.type !== TouchType.Up) {
      return;
    }
    if (event.type === TouchType.Down) {
      const t: TouchObject = event.touches[0];
      const p: StrokePoint = { x: t.x, y: t.y, p: this.getPressure() };
      const isEraser: boolean = this.tool === 'eraser';
      this.currentStroke = {
        points: [p],
        width: isEraser ? this.eraserWidth : this.baseWidth,
        color: AppTheme.TEXT_PRIMARY,
        eraser: isEraser
      };
    } else if (event.type === TouchType.Move && this.currentStroke !== null) {
      const t: TouchObject = event.touches[0];
      const p: StrokePoint = { x: t.x, y: t.y, p: this.getPressure() };
      const pts: StrokePoint[] = this.currentStroke.points;
      pts.push(p);
      if (pts.length >= 2) {
        this.drawSegment(pts[pts.length - 2], pts[pts.length - 1], this.currentStroke);
      }
    } else if (event.type === TouchType.Up && this.currentStroke !== null) {
      if (this.currentStroke.points.length > 1) {
        this.strokes.push(this.currentStroke);
        this.strokeCount = this.strokes.length;
        this.emit();
      }
      this.currentStroke = null;
    }
  }

  @Builder
  toolButton(label: string, key: string) {
    Text(label)
      .fontSize(AppTheme.FONT_BODY)
      .fontColor(this.tool === key ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(AppTheme.RADIUS_BTN)
      .backgroundColor(this.tool === key ? AppTheme.PRIMARY : AppTheme.BG_PAGE)
      .onClick(() => {
        this.tool = key;
      })
  }

  build() {
    Column({ space: AppTheme.SPACE_S }) {
      Row({ space: AppTheme.SPACE_S }) {
        this.toolButton('✒️ 笔', 'pen')
        this.toolButton('🧽 橡皮', 'eraser')
        Blank()
        Text(`${this.strokeCount} 笔`)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
        Text('撤销')
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .onClick(() => {
            if (this.strokes.length > 0) {
              this.strokes.pop();
              this.strokeCount = this.strokes.length;
              this.redraw();
              this.emit();
            }
          })
        Text('清空')
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.DANGER)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .onClick(() => {
            this.strokes = [];
            this.strokeCount = 0;
            this.redraw();
            this.emit();
          })
      }
      .width('100%')

      Canvas(this.ctx)
        .width('100%')
        .layoutWeight(1)
        .borderRadius(AppTheme.RADIUS_CARD)
        .backgroundColor(AppTheme.BG_CARD)
        .onReady(() => {
          this.redraw();
        })
        .onTouch((event: TouchEvent) => {
          this.handleTouch(event);
        })
    }
    .width('100%')
    .height('100%')
  }
}
