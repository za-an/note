import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppTheme } from '../common/AppTheme';
import { ChatMessageInfo, ChatSessionInfo, Note, UiChatMessage } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

/** 划词命令待回填动作 */
interface PendingApply {
  mode: string; // none | insertAfter | replaceRange
  start: number;
  end: number;
}

/**
 * P4 AI 问答（Obsidian Copilot 式）：
 * 左栏（可折叠）会话+笔记列表 | 主区 MD 编辑器（划词命令） | 右侧 AI 面板（可收起）。
 */
@Component
export struct AiNotePage {
  pathStack: NavPathStack = new NavPathStack();
  // 左栏
  @State leftOpen: boolean = true;
  @State chatSessions: ChatSessionInfo[] = [];
  @State selectedChatIndex: number = -1;
  @State myNotes: Note[] = [];
  @State selectedNoteIndex: number = -1;
  // 编辑器
  @State editorText: string = '';
  @State noteTitle: string = '';
  @State selStart: number = 0;
  @State selEnd: number = 0;
  @State dirty: boolean = false;
  // AI 面板
  @State aiOpen: boolean = true;
  @State messages: UiChatMessage[] = [];
  @State inputText: string = '';
  @State asking: boolean = false;
  @State carryNote: boolean = true;
  @State refSelected: boolean[] = [];
  private pending: PendingApply = { mode: 'none', start: 0, end: 0 };
  private msgScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadChatSessions();
    this.loadNotes();
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private currentNote(): Note | null {
    return this.selectedNoteIndex < 0 || this.selectedNoteIndex >= this.myNotes.length ?
      null : this.myNotes[this.selectedNoteIndex];
  }

  // ---------- 数据加载 ----------
  private async loadChatSessions(): Promise<void> {
    try {
      this.chatSessions = JSON.parse(await Api.get(
        `/chat/sessions?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}`)) as ChatSessionInfo[];
    } catch (e) {
      this.chatSessions = [];
    }
  }

  private async loadNotes(): Promise<void> {
    try {
      const all: Note[] = JSON.parse(await Api.get(
        `/notes?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}`)) as Note[];
      this.myNotes = all.filter((n: Note) => n.owner_id === GlobalState.userId() && n.kind === 'md');
      this.refSelected = this.myNotes.map((n: Note) => false);
      if (this.myNotes.length > 0 && this.selectedNoteIndex < 0) {
        this.selectNote(0);
      }
    } catch (e) {
      this.myNotes = [];
    }
  }

  private selectNote(index: number): void {
    this.selectedNoteIndex = index;
    const n: Note | null = this.currentNote();
    if (n !== null) {
      this.editorText = n.content;
      this.noteTitle = n.title;
      this.dirty = false;
    }
  }

  private async createNote(): Promise<void> {
    interface NoteBody {
      class_course_id: number;
      owner_id: number;
      title: string;
      kind: string;
      content: string;
    }

    const body: NoteBody = {
      class_course_id: GlobalState.courseId(),
      owner_id: GlobalState.userId(),
      title: '随堂笔记',
      kind: 'md',
      content: ''
    };
    try {
      await Api.post('/notes', body);
      await this.loadNotes();
      this.selectNote(this.myNotes.length - 1);
      this.toast('已新建笔记');
    } catch (e) {
      this.toast(`新建失败：${(e as Error).message}`);
    }
  }

  private async saveNote(): Promise<void> {
    const n: Note | null = this.currentNote();
    if (n === null) {
      return;
    }
    interface UpdateBody {
      title: string;
      content: string;
    }

    const body: UpdateBody = { title: this.noteTitle, content: this.editorText };
    try {
      await Api.put(`/notes/${n.id}`, body);
      n.content = this.editorText;
      n.title = this.noteTitle;
      this.dirty = false;
      this.toast('已保存');
    } catch (e) {
      this.toast(`保存失败：${(e as Error).message}`);
    }
  }

  private async selectChat(index: number): Promise<void> {
    this.selectedChatIndex = index;
    const cs: ChatSessionInfo = this.chatSessions[index];
    try {
      const list: ChatMessageInfo[] = JSON.parse(
        await Api.get(`/chat/sessions/${cs.id}/messages`)) as ChatMessageInfo[];
      this.messages = list.map((m: ChatMessageInfo): UiChatMessage => {
        let sources: string[] = [];
        if (m.sources !== '') {
          try {
            sources = JSON.parse(m.sources) as string[];
          } catch (e) {
            sources = [];
          }
        }
        const ui: UiChatMessage = { role: m.role, content: m.content, sources: sources, streaming: false };
        return ui;
      });
    } catch (e) {
      this.messages = [];
    }
  }

  // ---------- 问答 ----------
  private buildContext(): string {
    const parts: string[] = [];
    if (this.carryNote && this.editorText.trim() !== '') {
      parts.push(`[当前笔记：${this.noteTitle}]\n${this.editorText}`);
    }
    for (let i = 0; i < this.myNotes.length; i++) {
      if (this.refSelected[i] && i !== this.selectedNoteIndex) {
        parts.push(`[引用笔记：${this.myNotes[i].title}]\n${this.myNotes[i].content}`);
      }
    }
    return parts.join('\n---\n');
  }

  private async ensureChatSession(firstQuestion: string): Promise<number> {
    if (this.selectedChatIndex >= 0 && this.selectedChatIndex < this.chatSessions.length) {
      return this.chatSessions[this.selectedChatIndex].id;
    }
    interface CreateChat {
      class_course_id: number;
      user_id: number;
      title: string;
    }

    const body: CreateChat = {
      class_course_id: GlobalState.courseId(),
      user_id: GlobalState.userId(),
      title: firstQuestion.length > 12 ? firstQuestion.substring(0, 12) + '…' : firstQuestion
    };
    const cs: ChatSessionInfo = JSON.parse(await Api.post('/chat/sessions', body)) as ChatSessionInfo;
    this.chatSessions = [cs].concat(this.chatSessions);
    this.selectedChatIndex = 0;
    this.messages = [];
    return cs.id;
  }

  private replaceLastMessage(m: UiChatMessage): void {
    this.messages.splice(this.messages.length - 1, 1, m);
  }

  private async send(question: string): Promise<void> {
    const q: string = question.trim();
    if (q === '' || this.asking) {
      return;
    }
    this.aiOpen = true;
    this.asking = true;
    let chatId: number = -1;
    try {
      chatId = await this.ensureChatSession(q);
    } catch (e) {
      this.toast(`创建会话失败：${(e as Error).message}`);
      this.asking = false;
      return;
    }
    const userMsg: UiChatMessage = { role: 'user', content: q, sources: [], streaming: false };
    const holder: UiChatMessage = { role: 'assistant', content: '', sources: [], streaming: true };
    this.messages.push(userMsg);
    this.messages.push(holder);
    this.msgScroller.scrollEdge(Edge.Bottom);

    Api.streamAsk(chatId, q, this.buildContext(), {
      onSources: (sources: string[]) => {
        const last: UiChatMessage = this.messages[this.messages.length - 1];
        const next: UiChatMessage =
          { role: 'assistant', content: last.content, sources: sources, streaming: true };
        this.replaceLastMessage(next);
      },
      onDelta: (delta: string) => {
        const last: UiChatMessage = this.messages[this.messages.length - 1];
        const next: UiChatMessage =
          { role: 'assistant', content: last.content + delta, sources: last.sources, streaming: true };
        this.replaceLastMessage(next);
        this.msgScroller.scrollEdge(Edge.Bottom);
      },
      onDone: () => {
        const last: UiChatMessage = this.messages[this.messages.length - 1];
        const next: UiChatMessage =
          { role: 'assistant', content: last.content, sources: last.sources, streaming: false };
        this.replaceLastMessage(next);
        this.asking = false;
        this.applyPending(next.content);
      },
      onError: (msg: string) => {
        const last: UiChatMessage = this.messages[this.messages.length - 1];
        const next: UiChatMessage = {
          role: 'assistant',
          content: last.content === '' ? `（请求失败：${msg}）` : last.content,
          sources: last.sources,
          streaming: false
        };
        this.replaceLastMessage(next);
        this.asking = false;
        this.pending = { mode: 'none', start: 0, end: 0 };
      }
    });
  }

  // ---------- 编辑器回填 ----------
  private insertAt(pos: number, text: string): void {
    const p: number = Math.min(Math.max(pos, 0), this.editorText.length);
    this.editorText = this.editorText.substring(0, p) + text + this.editorText.substring(p);
    this.dirty = true;
    this.saveNote();
  }

  private replaceRange(start: number, end: number, text: string): void {
    const s: number = Math.min(Math.max(start, 0), this.editorText.length);
    const e: number = Math.min(Math.max(end, s), this.editorText.length);
    this.editorText = this.editorText.substring(0, s) + text + this.editorText.substring(e);
    this.dirty = true;
    this.saveNote();
  }

  private applyPending(answer: string): void {
    if (this.pending.mode === 'insertAfter') {
      this.insertAt(this.pending.end, `\n${answer}\n`);
      this.toast('AI 结果已插入笔记');
    } else if (this.pending.mode === 'replaceRange') {
      this.replaceRange(this.pending.start, this.pending.end, answer);
      this.toast('AI 结果已替换选中内容');
    }
    this.pending = { mode: 'none', start: 0, end: 0 };
  }

  private selectedText(): string {
    if (this.selEnd > this.selStart) {
      return this.editorText.substring(this.selStart, this.selEnd);
    }
    return '';
  }

  private runCommand(cmd: string): void {
    const sel: string = this.selectedText();
    if (sel === '') {
      return;
    }
    if (cmd === 'ask') {
      this.pending = { mode: 'none', start: 0, end: 0 };
      this.send(sel);
    } else if (cmd === 'summarize') {
      this.pending = { mode: 'insertAfter', start: this.selStart, end: this.selEnd };
      this.send(`请总结以下内容：\n${sel}`);
    } else if (cmd === 'explain') {
      this.pending = { mode: 'insertAfter', start: this.selStart, end: this.selEnd };
      this.send(`请解释以下内容：\n${sel}`);
    } else if (cmd === 'continue') {
      this.pending = { mode: 'insertAfter', start: this.selStart, end: this.selEnd };
      this.send(`请续写以下内容，直接给出续写文本：\n${sel}`);
    }
  }

  private copyText(text: string): void {
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data);
    this.toast('已复制');
  }

  // ---------- UI ----------
  @Builder
  cmdButton(label: string, cmd: string) {
    Text(label)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontColor(AppTheme.PRIMARY)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(AppTheme.RADIUS_BTN)
      .backgroundColor(AppTheme.PRIMARY_LIGHT)
      .onClick(() => {
        this.runCommand(cmd);
      })
  }

  @Builder
  leftPaneView() {
    Column({ space: AppTheme.SPACE_M }) {
      Row() {
        Text('会话').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_SECONDARY)
        Blank()
        Text('+ 新会话')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.PRIMARY)
          .onClick(() => {
            this.selectedChatIndex = -1;
            this.messages = [];
          })
      }
      .width('100%')

      List({ space: AppTheme.SPACE_S }) {
        ForEach(this.chatSessions, (cs: ChatSessionInfo, index: number) => {
          ListItem() {
            Text(cs.title)
              .fontSize(AppTheme.FONT_BODY)
              .fontColor(this.selectedChatIndex === index ? AppTheme.PRIMARY : AppTheme.TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding(AppTheme.SPACE_S)
              .borderRadius(AppTheme.RADIUS_BTN)
              .backgroundColor(this.selectedChatIndex === index ? AppTheme.PRIMARY_LIGHT : 'transparent')
              .onClick(() => {
                this.selectChat(index);
              })
          }
        }, (cs: ChatSessionInfo) => `${cs.id}`)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Divider().color(AppTheme.DIVIDER)

      Row() {
        Text('我的 MD 笔记').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_SECONDARY)
        Blank()
        Text('+ 新建')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.PRIMARY)
          .onClick(() => {
            this.createNote();
          })
      }
      .width('100%')

      List({ space: AppTheme.SPACE_S }) {
        ForEach(this.myNotes, (n: Note, index: number) => {
          ListItem() {
            Text(n.title)
              .fontSize(AppTheme.FONT_BODY)
              .fontColor(this.selectedNoteIndex === index ? AppTheme.PRIMARY : AppTheme.TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding(AppTheme.SPACE_S)
              .borderRadius(AppTheme.RADIUS_BTN)
              .backgroundColor(this.selectedNoteIndex === index ? AppTheme.PRIMARY_LIGHT : 'transparent')
              .onClick(() => {
                this.selectNote(index);
              })
          }
        }, (n: Note) => `${n.id}`)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width(200)
    .height('100%')
    .padding(AppTheme.SPACE_M)
    .borderRadius(AppTheme.RADIUS_CARD)
    .backgroundColor(AppTheme.BG_CARD)
  }

  @Builder
  editorView() {
    Column({ space: AppTheme.SPACE_M }) {
      Row({ space: AppTheme.SPACE_M }) {
        Text(this.leftOpen ? '◀' : '▶')
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .onClick(() => {
            this.leftOpen = !this.leftOpen;
          })
        TextInput({ text: this.noteTitle, placeholder: '笔记标题' })
          .fontSize(AppTheme.FONT_SUBTITLE)
          .layoutWeight(1)
          .backgroundColor('transparent')
          .onChange((v: string) => {
            this.noteTitle = v;
            this.dirty = true;
          })
        if (this.dirty) {
          Text('未保存').fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.WARNING)
        }
        Button('保存')
          .fontSize(AppTheme.FONT_BODY)
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(AppTheme.RADIUS_BTN)
          .onClick(() => {
            this.saveNote();
          })
        Text(this.aiOpen ? 'AI ▶' : '◀ AI')
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.PRIMARY)
          .onClick(() => {
            this.aiOpen = !this.aiOpen;
          })
      }
      .width('100%')

      if (this.selEnd > this.selStart) {
        Row({ space: AppTheme.SPACE_S }) {
          Text('划词命令：').fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.TEXT_TERTIARY)
          this.cmdButton('问 AI', 'ask')
          this.cmdButton('总结', 'summarize')
          this.cmdButton('解释', 'explain')
          this.cmdButton('续写', 'continue')
        }
        .width('100%')
      }

      if (this.currentNote() === null) {
        Column({ space: AppTheme.SPACE_M }) {
          Text('还没有笔记').fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_TERTIARY)
          Button('新建随堂笔记')
            .backgroundColor(AppTheme.PRIMARY)
            .borderRadius(AppTheme.RADIUS_BTN)
            .onClick(() => {
              this.createNote();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        TextArea({ text: this.editorText, placeholder: '在此记录 Markdown 笔记，选中文本可唤起 AI 命令…' })
          .width('100%')
          .layoutWeight(1)
          .fontSize(AppTheme.FONT_BODY)
          .backgroundColor(AppTheme.BG_CARD)
          .borderRadius(AppTheme.RADIUS_CARD)
          .onChange((v: string) => {
            this.editorText = v;
            this.dirty = true;
          })
          .onTextSelectionChange((start: number, end: number) => {
            this.selStart = start;
            this.selEnd = end;
          })
      }
    }
    .layoutWeight(1)
    .height('100%')
  }

  @Builder
  aiPanelView() {
    Column({ space: AppTheme.SPACE_M }) {
      Text('AI 助手 · 仅依据本课程知识库作答')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width('100%')

      Row({ space: AppTheme.SPACE_S }) {
        Toggle({ type: ToggleType.Switch, isOn: this.carryNote })
          .selectedColor(AppTheme.PRIMARY)
          .height(20)
          .onChange((on: boolean) => {
            this.carryNote = on;
          })
        Text('携带当前笔记').fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.TEXT_SECONDARY)
        Blank()
      }
      .width('100%')

      if (this.myNotes.length > 1) {
        Text('@ 引用其他笔记：')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.myNotes, (n: Note, index: number) => {
            if (index !== this.selectedNoteIndex) {
              Text(`@${n.title}`)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(this.refSelected[index] ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .margin({ right: 6, bottom: 6 })
                .borderRadius(AppTheme.RADIUS_TAG)
                .backgroundColor(this.refSelected[index] ? AppTheme.PRIMARY : AppTheme.BG_PAGE)
                .onClick(() => {
                  const next: boolean[] = this.refSelected.slice(0);
                  next[index] = !next[index];
                  this.refSelected = next;
                })
            }
          }, (n: Note) => `${n.id}`)
        }
        .width('100%')
      }

      List({ space: AppTheme.SPACE_M, scroller: this.msgScroller }) {
        ForEach(this.messages, (m: UiChatMessage, index: number) => {
          ListItem() {
            Column({ space: AppTheme.SPACE_XS }) {
              Text(m.role === 'user' ? '我' : 'AI')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(m.role === 'user' ? AppTheme.PRIMARY : AppTheme.SUCCESS)
              Text(m.content + (m.streaming ? ' ▌' : ''))
                .fontSize(AppTheme.FONT_BODY)
                .fontColor(AppTheme.TEXT_PRIMARY)
                .lineHeight(20)
              if (m.sources.length > 0) {
                Text(`来源：${m.sources.join('；')}`)
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.TEXT_TERTIARY)
              }
              if (m.role === 'assistant' && !m.streaming && m.content !== '') {
                Row({ space: AppTheme.SPACE_S }) {
                  Text('插入光标处')
                    .fontSize(AppTheme.FONT_CAPTION)
                    .fontColor(AppTheme.PRIMARY)
                    .onClick(() => {
                      this.insertAt(this.selStart, `\n${m.content}\n`);
                      this.toast('已插入');
                    })
                  Text('替换选区')
                    .fontSize(AppTheme.FONT_CAPTION)
                    .fontColor(AppTheme.PRIMARY)
                    .onClick(() => {
                      if (this.selEnd > this.selStart) {
                        this.replaceRange(this.selStart, this.selEnd, m.content);
                        this.toast('已替换');
                      } else {
                        this.toast('请先在编辑器中选中要替换的文本');
                      }
                    })
                  Text('复制')
                    .fontSize(AppTheme.FONT_CAPTION)
                    .fontColor(AppTheme.TEXT_SECONDARY)
                    .onClick(() => {
                      this.copyText(m.content);
                    })
                }
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(AppTheme.SPACE_S)
            .borderRadius(AppTheme.RADIUS_BTN)
            .backgroundColor(m.role === 'user' ? AppTheme.PRIMARY_LIGHT : 'transparent')
          }
        }, (m: UiChatMessage, index: number) => `${index}_${m.content.length}_${m.streaming}`)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)

      Row({ space: AppTheme.SPACE_S }) {
        TextInput({ text: this.inputText, placeholder: '就本课程内容提问…' })
          .layoutWeight(1)
          .fontSize(AppTheme.FONT_BODY)
          .onChange((v: string) => {
            this.inputText = v;
          })
          .onSubmit(() => {
            const q: string = this.inputText;
            this.inputText = '';
            this.pending = { mode: 'none', start: 0, end: 0 };
            this.send(q);
          })
        Button(this.asking ? '…' : '发送')
          .fontSize(AppTheme.FONT_BODY)
          .enabled(!this.asking)
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(AppTheme.RADIUS_BTN)
          .onClick(() => {
            const q: string = this.inputText;
            this.inputText = '';
            this.pending = { mode: 'none', start: 0, end: 0 };
            this.send(q);
          })
      }
      .width('100%')
    }
    .width(320)
    .height('100%')
    .padding(AppTheme.SPACE_M)
    .borderRadius(AppTheme.RADIUS_CARD)
    .backgroundColor(AppTheme.BG_CARD)
  }

  build() {
    Row({ space: AppTheme.SPACE_L }) {
      if (this.leftOpen) {
        this.leftPaneView()
      }
      this.editorView()
      if (this.aiOpen) {
        this.aiPanelView()
      }
    }
    .width('100%')
    .height('100%')
    .padding(AppTheme.SPACE_L)
    .backgroundColor(AppTheme.BG_PAGE)
    .alignItems(VerticalAlign.Top)
  }
}
