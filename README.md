# 智慧伴学系统 Demo

面向鸿蒙生态的课堂 AI 协同学习工具。本仓库为 Demo 阶段代码，跑通「录音 → 云端转写 → RAG 提纲/问答 → 班级共享」核心闭环。

- 需求文档：`产品需求文档.md`
- 实现流程：`实现流程.md`

## 目录结构

```
note/
├─ server/        FastAPI 服务端（业务 + AI 层）
├─ client/        HarmonyOS ArkTS 客户端（横屏，6 页面）
├─ 产品需求文档.md
└─ 实现流程.md
```

## 服务端

技术栈：FastAPI + SQLModel(SQLite) + Chroma + OpenAI 兼容 LLM。

```bash
cd server
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt      # Windows；Linux/mac 用 .venv/bin/pip
cp .env.example .env                                # 按需填 LLM_API_KEY（不填走 Mock）
.venv/Scripts/python -m uvicorn app.main:app --port 8000
```

启动后：
- API 文档：http://127.0.0.1:8000/docs
- 健康检查：http://127.0.0.1:8000/health
- 预置数据：教师「王老师」+学生「小明/小红」，示例集合「计科2301-数据结构」，邀请码 `888888`，1 节已转写课时。

### 关键设计
- **ASR 适配层**（`app/services/asr/`）：`ASRProvider` 抽象接口，默认 `MockASRProvider` 返回预置课堂文本；接入华为云 SIS / 讯飞时新增实现类并在 `__init__.py` 注册，改 `.env` 的 `ASR_PROVIDER` 即可切换。
- **LLM**（`app/services/llm.py`）：OpenAI 兼容协议，`base_url/api_key/model` 可配；未配 key 时降级 Mock，保证离线可演示。
- **知识库隔离**（`app/services/rag.py`）：Chroma 按 `class_course_id` 分 collection（`cc_<id>`），检索强制携带集合 ID，跨集合零共享。已验证：向集合 A 发布提纲后，集合 B 问同样问题返回「本课程资料中未找到」。

### API 概览（前缀 `/api/v1`）
| 模块 | 端点 |
|------|------|
| auth | `GET /auth/users` |
| courses | `GET/POST /courses`、`POST /courses/join` |
| sessions | 创建课时、`POST /sessions/{id}/chunks/{seq}` 上传分片转写、`POST .../outline/generate` 生成提纲、`POST .../outline/review` 教师审核发布 |
| notes | 笔记 CRUD、`POST /notes/{id}/share` 共享+质量评估入库 |
| chat | 会话管理、`POST /chat/ask` 集合限定 SSE 流式问答 |

## 客户端

技术栈：HarmonyOS NEXT + ArkTS/ArkUI（Stage 模型，API 12+）。横屏锁定，简洁风，无动画（预留扩展）。

用 DevEco Studio 打开 `client/` 目录，等待 hvigor Sync，选平板模拟器横屏运行。详见 `client/README.md`。

页面：P1 集合列表 / P2 录音 / P3 课时详情三栏 / P4 Obsidian 式 AI 笔记 / P5 笔记(MD+手写) / P6 教师审核。

联调时把 `client/.../service/Api.ets` 的 `BASE_URL` 指向服务端（默认 `http://127.0.0.1:8000/api/v1`；模拟器访问宿主机需用相应回环地址）。

## 测试

### 服务端一键冒烟测试
```bash
cd server
.venv/Scripts/python -m uvicorn app.main:app --port 8000   # 终端1：启动服务
.venv/Scripts/python smoke_test.py                          # 终端2：跑测试
```
`smoke_test.py` 覆盖全链路 10 项：健康检查、预置账号、建集合/邀请码加入、分片上传转写、提纲生成、教师发布入库、集合限定问答（SSE+来源）、跨集合隔离、笔记共享质量评估。全部 PASS 即服务端正常。

### 手动调试
浏览器打开 http://127.0.0.1:8000/docs（Swagger UI），可逐个接口点 "Try it out" 调试；SSE 问答接口建议用 curl：`curl -N -X POST .../api/v1/chat/ask -H "Content-Type: application/json" -d @body.json`。

### 重置演示数据
删除 `server/smartstudy.db` 和 `server/data/` 后重启服务，将重新生成预置数据（两者必须一起删，保持业务库与向量库一致）。

## 已验证的闭环
录音分片上传→Mock 转写落库→生成 Markdown 提纲→教师发布入知识库→集合限定问答（带引用来源、流式）→跨集合隔离→笔记共享质量评估入库，均已通过接口冒烟测试。

## 待办（Demo 后）
- 接入真实云端 ASR（实现 `ASRProvider`）
- 客户端页面对接真实接口（当前 mock 数据）
- 手写笔记压感（需真机 MatePad + M-Pencil）
- 协同层：NFC 配对 / 局域网互抓 / 跨端流转（`client/.../service/collab/` 占位）
- UI 动画
