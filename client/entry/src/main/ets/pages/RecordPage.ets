import { audio } from '@kit.AudioKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { AppCard } from '../common/components/AppCard';
import { TranscriptSegment } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

type RecordState = 'idle' | 'recording' | 'paused' | 'finished';

const CHUNK_INTERVAL_MS: number = 4000;

/**
 * P2 课堂录音：AudioCapturer 采集 → 分片上传 → 云端 ASR（当前 Mock）转写实时回显。
 * 模拟器无麦克风权限/初始化失败时自动降级为「模拟模式」：定时上传占位分片，链路不断。
 */
@Component
export struct RecordPage {
  pathStack: NavPathStack = new NavPathStack();
  @State recordState: RecordState = 'idle';
  @State title: string = '';
  @State elapsedSec: number = 0;
  @State segments: TranscriptSegment[] = [];
  @State simulated: boolean = false;
  @State uploadFailures: number = 0;
  private sessionId: number = -1;
  private seq: number = 0;
  private capturer: audio.AudioCapturer | null = null;
  private pendingBuffers: ArrayBuffer[] = [];
  private chunkTimer: number = -1;
  private clockTimer: number = -1;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const now: Date = new Date();
    this.title = `${now.getMonth() + 1}月${now.getDate()}日课堂`;
  }

  aboutToDisappear(): void {
    this.stopTimers();
    this.releaseCapturer();
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private fmtDuration(): string {
    const m: number = Math.floor(this.elapsedSec / 60);
    const s: number = this.elapsedSec % 60;
    return `${m < 10 ? '0' : ''}${m}:${s < 10 ? '0' : ''}${s}`;
  }

  // ---------- 录音控制 ----------
  private async start(): Promise<void> {
    if (GlobalState.course === null) {
      this.toast('请先在首页选择课程集合');
      return;
    }
    interface CreateBody {
      class_course_id: number;
      title: string;
      creator_id: number;
    }

    const body: CreateBody = {
      class_course_id: GlobalState.courseId(),
      title: this.title.trim() === '' ? '未命名课时' : this.title.trim(),
      creator_id: GlobalState.userId()
    };
    try {
      interface SessionResp {
        id: number;
      }

      const resp: SessionResp = JSON.parse(await Api.post('/sessions', body)) as SessionResp;
      this.sessionId = resp.id;
    } catch (e) {
      this.toast(`创建课时失败：${(e as Error).message}`);
      return;
    }

    await this.initCapturer();
    this.recordState = 'recording';
    this.startTimers();
  }

  private async initCapturer(): Promise<void> {
    try {
      const perms: Permissions[] = ['ohos.permission.MICROPHONE'];
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const result = await atManager.requestPermissionsFromUser(ctx, perms);
      const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
      if (!granted) {
        this.simulated = true;
        this.toast('未授予麦克风权限，进入模拟模式');
        return;
      }
      const options: audio.AudioCapturerOptions = {
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
        },
        capturerInfo: {
          source: audio.SourceType.SOURCE_TYPE_MIC,
          capturerFlags: 0
        }
      };
      this.capturer = await audio.createAudioCapturer(options);
      this.capturer.on('readData', (buf: ArrayBuffer) => {
        this.pendingBuffers.push(buf.slice(0));
      });
      await this.capturer.start();
      this.simulated = false;
    } catch (e) {
      this.simulated = true;
      this.toast(`麦克风初始化失败，进入模拟模式`);
    }
  }

  private startTimers(): void {
    this.clockTimer = setInterval(() => {
      this.elapsedSec += 1;
    }, 1000);
    this.chunkTimer = setInterval(() => {
      this.flushChunk();
    }, CHUNK_INTERVAL_MS);
  }

  private stopTimers(): void {
    if (this.clockTimer >= 0) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
    if (this.chunkTimer >= 0) {
      clearInterval(this.chunkTimer);
      this.chunkTimer = -1;
    }
  }

  private releaseCapturer(): void {
    if (this.capturer !== null) {
      const c: audio.AudioCapturer = this.capturer;
      this.capturer = null;
      c.release();
    }
  }

  private mergeBuffers(): ArrayBuffer {
    const list: ArrayBuffer[] = this.pendingBuffers;
    this.pendingBuffers = [];
    let total: number = 0;
    for (const b of list) {
      total += b.byteLength;
    }
    if (total === 0) {
      // 模拟模式 / 静音间隙：上传占位字节（Mock ASR 不读内容）
      return new Uint8Array([0, 0, 0, 0]).buffer;
    }
    const out: Uint8Array = new Uint8Array(total);
    let offset: number = 0;
    for (const b of list) {
      out.set(new Uint8Array(b), offset);
      offset += b.byteLength;
    }
    return out.buffer;
  }

  private async flushChunk(): Promise<void> {
    if (this.sessionId < 0) {
      return;
    }
    const data: ArrayBuffer = this.mergeBuffers();
    const currentSeq: number = this.seq;
    this.seq += 1;
    try {
      const seg: TranscriptSegment =
        JSON.parse(await Api.uploadChunk(this.sessionId, currentSeq, data)) as TranscriptSegment;
      this.segments.push(seg);
      this.scroller.scrollEdge(Edge.Bottom);
    } catch (e) {
      this.uploadFailures += 1;
    }
  }

  private async pauseOrResume(): Promise<void> {
    if (this.recordState === 'recording') {
      this.recordState = 'paused';
      this.stopTimers();
      if (this.capturer !== null) {
        await this.capturer.stop();
      }
    } else if (this.recordState === 'paused') {
      this.recordState = 'recording';
      this.startTimers();
      if (this.capturer !== null) {
        await this.capturer.start();
      }
    }
  }

  private async finish(): Promise<void> {
    this.stopTimers();
    await this.flushChunk();
    this.releaseCapturer();
    try {
      await Api.post(`/sessions/${this.sessionId}/finish`);
    } catch (e) {
      // 网络异常不阻塞收尾
    }
    this.recordState = 'finished';
    GlobalState.currentSessionId = this.sessionId;
    this.toast('录音结束，转写已保存');
    this.pathStack.pop();
    this.pathStack.pushPathByName('sessionDetail', null);
  }

  // ---------- UI ----------
  @Builder
  waveBar(h: number) {
    Column()
      .width(4)
      .height(this.recordState === 'recording' ? h : 8)
      .borderRadius(2)
      .backgroundColor(this.recordState === 'recording' ? AppTheme.PRIMARY : AppTheme.DIVIDER)
      .margin({ left: 3, right: 3 })
  }

  build() {
    Row({ space: AppTheme.SPACE_L }) {
      // 左栏：录音控制
      Column({ space: AppTheme.SPACE_L }) {
        Text(GlobalState.course === null ? '' :
          `${GlobalState.course.name} · ${GlobalState.course.class_name}`)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .width('100%')

        TextInput({ text: this.title, placeholder: '本次课时标题' })
          .fontSize(AppTheme.FONT_SUBTITLE)
          .enabled(this.recordState === 'idle')
          .onChange((v: string) => {
            this.title = v;
          })

        AppCard() {
          Column({ space: AppTheme.SPACE_L }) {
            Text(this.fmtDuration())
              .fontSize(44)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.recordState === 'recording' ? AppTheme.PRIMARY : AppTheme.TEXT_PRIMARY)
            Row() {
              this.waveBar(14)
              this.waveBar(26)
              this.waveBar(38)
              this.waveBar(22)
              this.waveBar(44)
              this.waveBar(30)
              this.waveBar(18)
              this.waveBar(34)
              this.waveBar(26)
              this.waveBar(14)
            }
            .height(60)
            .alignItems(VerticalAlign.Center)

            if (this.simulated && this.recordState !== 'idle') {
              Text('模拟模式：无真实音频，定时上传占位分片')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.WARNING)
            }
            if (this.uploadFailures > 0) {
              Text(`${this.uploadFailures} 个分片上传失败（可稍后补传）`)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.DANGER)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }

        Row({ space: AppTheme.SPACE_M }) {
          if (this.recordState === 'idle') {
            Button('开始录音')
              .layoutWeight(1)
              .backgroundColor(AppTheme.PRIMARY)
              .borderRadius(AppTheme.RADIUS_BTN)
              .onClick(() => {
                this.start();
              })
          } else if (this.recordState === 'recording' || this.recordState === 'paused') {
            Button(this.recordState === 'recording' ? '暂停' : '继续')
              .layoutWeight(1)
              .backgroundColor(AppTheme.BG_CARD)
              .fontColor(AppTheme.PRIMARY)
              .borderRadius(AppTheme.RADIUS_BTN)
              .onClick(() => {
                this.pauseOrResume();
              })
            Button('结束')
              .layoutWeight(1)
              .backgroundColor(AppTheme.DANGER)
              .borderRadius(AppTheme.RADIUS_BTN)
              .onClick(() => {
                this.finish();
              })
          }
        }
        .width('100%')
      }
      .width(320)
      .height('100%')

      // 右栏：实时转写
      Column({ space: AppTheme.SPACE_M }) {
        Text('实时转写').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_SECONDARY).width('100%')
        Column() {
          AppCard({ fillHeight: true }) {
            if (this.segments.length === 0) {
              Column() {
                Text(this.recordState === 'idle' ?
                  '开始录音后，云端转写文字将在此实时显示' : '等待首个分片转写…')
                  .fontSize(AppTheme.FONT_BODY)
                  .fontColor(AppTheme.TEXT_TERTIARY)
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
            } else {
              List({ space: AppTheme.SPACE_L, scroller: this.scroller }) {
                ForEach(this.segments, (seg: TranscriptSegment) => {
                  ListItem() {
                    Column({ space: AppTheme.SPACE_XS }) {
                      Text(`#${seg.seq + 1} · ${Math.floor(seg.start_ms / 60000)}:${
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
                  }
                }, (seg: TranscriptSegment) => `${seg.seq}`)
              }
              .width('100%')
              .height('100%')
              .scrollBar(BarState.Auto)
            }
          }
        }
        .layoutWeight(1)
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
