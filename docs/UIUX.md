# SiriusX Platform UI/UX 设计规范

> 面向分布式 AI Agent 任务执行平台的用户体验设计文档

---

## 📚 文档导航

- [核心设计原则](#核心设计原则) - 分布式系统的 UX 思考
- [信息架构](#信息架构) - 完整的用户旅程地图
- [设计系统](#设计系统) - 颜色、字体、组件、交互模式
- [页面设计规范](#页面设计规范) - 每个页面的详细设计
- [实时通信设计](#实时通信设计) - Fetch Streaming、断线恢复
- [Auth 与租户体验](#auth-与租户体验) - 安全边界的用户体验
- [分阶段实施路线图](#分阶段实施路线图) - UI/UX 演进计划
- [性能与可访问性](#性能与可访问性) - 性能优化与无障碍设计
- [设计决策记录](#设计决策记录) - 重要的设计权衡

---

## 🎯 核心设计原则

SiriusX 是一个分布式、可扩展的 AI Agent 任务执行平台。UI/UX 设计必须反映系统的核心架构特性，让用户理解并信任这个复杂系统。

### 1. 透明的异步性 (Transparent Asynchronicity)

**原则**：用户应该清楚地知道系统正在做什么、为什么需要等待、进度如何。

**体现**：
- 明确区分 Task（长期容器）和 Run（短期执行）的状态
- 实时流式输出让用户感知 AI 正在"思考"和"工作"
- 队列等待时显示预期等待时间（基于 Queue wait latency p95）
- 工具调用过程可视化（thinking_delta、tool_start/end 事件）

**反例**：❌ 只显示 "Loading..." 而不说明是在等待队列、执行 AI、还是持久化数据

---

### 2. 可恢复的连续性 (Recoverable Continuity)

**原则**：用户可以随时离开、刷新、切换设备，系统应该无缝恢复上下文。

**体现**：
- Task 是持久化的工作空间，不是一次性对话
- 断线恢复通过 `afterSequence=<N>` 精确补齐缺失事件
- 历史页展示所有任务，按时间排序
- 任务详情页加载时显示完整的对话历史、产物和 Run 状态

**架构支撑**：
- Run-scoped event sequence（阶段 0）
- Postgres 作为唯一事实来源
- S3 Workspace revision 两阶段提交

---

### 3. 渐进式披露 (Progressive Disclosure)

**原则**：优先展示核心信息，复杂细节按需展开。

**体现**：
- 首页只展示 Agent 选择，不暴露复杂的配置选项
- 任务详情页默认只显示对话区和产物列表
- 高级选项（如 model 选择、skills 配置）收起在折叠面板
- 文件树懒加载，按需展开深层目录

---

### 4. 故障可见性 (Visible Failures)

**原则**：系统故障不应该被隐藏，用户需要知道发生了什么、能否恢复。

**体现**：
- Task 状态包含 `running_degraded`（部分功能降级但可继续）
- Run 状态包含 `completed_with_warnings`（完成但有警告）
- 错误消息清晰分类（网络错误、Auth 失败、Control Worker 崩溃、Sandbox 创建失败）
- 提供恢复路径（重试、取消、回退到上一个版本）

**架构支撑**：
- Event persistence lag 监控（< 5s 目标，> 10s 告警）
- LeaseSweeper 自动恢复过期 Run
- Control Worker 崩溃后新 Control Worker 可接手

---

### 5. 分布式系统的 UX 约束

**原则**：承认分布式系统的固有特性，设计时考虑延迟、并发、一致性。

**体现**：
- 轮询间隔 1000ms 是性能与实时性的平衡
- 文件树更新可能有延迟，显示 "Syncing..." 状态
- 并发冲突时明确提示（Workspace revision 乐观锁失败）
- 不承诺"实时协作"（同一 Task 多 Run 串行执行）

**不做的事**：
- ❌ 不实现 WebSocket 双向通信（阶段 0-2 使用 Fetch Streaming 单向流）
- ❌ 不支持同一 Task 多用户并发编辑（需要 CRDT 或 OT，复杂度过高）

---

## 📐 信息架构

### 用户旅程地图

```
[首页 - Agent Catalog]
    ↓ 选择 Agent
[任务创建弹窗 - 选 Agent / Model，不输入 prompt]
    ↓ POST /api/task（不消费 prompt，§5.1）
[任务详情页 - 空白状态]
    ↓ 用户手动输入首条消息 → POST /api/task/:id/message（§5.2，不使用 sessionStorage 中转）
[任务详情页 - 执行中]
    ├─ 实时流式输出（Fetch Streaming）
    ├─ 工具调用可视化
    ├─ 产物实时更新
    └─ 文件树同步
    ↓ Run 完成
[任务详情页 - 等待用户输入]
    ↓ 用户继续对话 / 关闭任务
[任务详情页 - 已完成]
    ↓ 返回首页 / 查看历史
[历史页]
    ↓ 点击任务卡片
[任务详情页 - 恢复历史]
```

### 核心概念的视觉映射

| 概念 | 视觉表现 | 用户理解 |
|------|----------|----------|
| **Task** | 整个页面 + 顶部标题 | "这是我的工作空间" |
| **Run** | 对话区的一轮交互 + Run Badge | "AI 正在处理我的这条消息" |
| **Worker** | 不直接可见（后台） | "系统正在工作中..." |
| **Sandbox** | 工具调用进度（"Running bash..."） | "AI 正在执行命令" |
| **Workspace** | 右侧文件树面板 | "这是 AI 生成的文件" |
| **Queue** | "Waiting for worker..." 提示 | "前面还有其他任务在排队" |

### 状态层次结构

```
Task 状态（顶层）
├─ running（任务开放中）
│   ├─ 无 active run → 等待用户输入
│   └─ 有 active run → 显示 Run 状态
├─ running_degraded（降级运行）
├─ completed（已完成）
├─ failed（失败）
└─ cancelled（已取消）

Run 状态（次级）
├─ queued（队列中）→ 显示等待时间估算
├─ running（执行中）→ 显示实时流
├─ completed（完成）→ 显示完成标记
├─ completed_with_warnings（完成但有警告）
├─ failed（失败）→ 显示错误信息
└─ cancelled（已取消）
```

---

## 🎨 设计系统

### 颜色系统

基于 Tailwind CSS v4 自定义变量，语义化命名。

#### 品牌色

| 变量名 | 用途 | 示例 |
|--------|------|------|
| `primary` | 主要交互、链接、高亮 | 按钮、链接、激活状态 |
| `secondary` | 次要交互、队列状态 | 队列 Badge、取消状态 |
| `accent` | 强调、新功能提示 | 新产物提示、通知徽章 |

#### 语义色

| 变量名 | 用途 | 示例 |
|--------|------|------|
| `destructive` | 危险操作、错误、失败 | 删除按钮、错误 Badge |
| `success` | 成功、完成 | 完成 Badge、成功提示 |
| `warning` | 警告、降级状态 | 降级 Badge、警告提示 |
| `info` | 信息、帮助 | 信息提示、帮助文本 |

#### 表面色

| 变量名 | 用途 | 示例 |
|--------|------|------|
| `canvas` | 页面背景 | 全局背景色 |
| `surface` | 卡片背景 | 对话气泡、卡片 |
| `surface-subtle` | 次级表面 | hover 状态、禁用状态 |
| `surface-emphasis` | 强调表面 | 高亮卡片、激活状态 |

#### 文本色

| 变量名 | 用途 | 示例 |
|--------|------|------|
| `ink` | 主要文本 | 标题、正文 |
| `body` | 正文文本 | 描述、说明 |
| `muted` | 次要文本 | 辅助信息、时间戳 |
| `on-dark` | 深色背景上的文本 | Hero 区文案 |

#### 状态颜色映射

| Task/Run 状态 | Badge 颜色 | 图标 |
|---------------|-----------|------|
| `queued` | `secondary` | Clock |
| `running` | `primary` | Loader2 (旋转) |
| `completed` | `success` (outline) | CheckCircle2 |
| `completed_with_warnings` | `warning` | AlertTriangle |
| `failed` | `destructive` | XCircle |
| `cancelled` | `secondary` | XCircle |
| `running_degraded` | `warning` | AlertCircle |

---

### 字体系统

| 类型 | 字体族 | 用途 | 示例 |
|------|--------|------|------|
| **标题** | `font-serif` | 品牌标语、页面标题、Agent 名称 | Hero 区、Agent 卡片标题 |
| **正文** | `font-sans` | 正文、按钮、表单、描述 | 对话消息、输入框、按钮文字 |
| **代码** | `font-mono` | 代码块、文件路径、技术信息 | 代码块、文件树路径 |

#### 字号层级

| 层级 | Tailwind 类 | 用途 | 示例 |
|------|-------------|------|------|
| Hero | `text-5xl` (48px) | 首页品牌标语 | "AI-Powered Development" |
| H1 | `text-4xl` (36px) | 页面主标题 | 历史页标题 |
| H2 | `text-3xl` (30px) | 区域标题 | Agent Catalog 标题 |
| H3 | `text-2xl` (24px) | 卡片标题 | Agent 卡片名称 |
| H4 | `text-xl` (20px) | 次级标题 | Task 标题 |
| Body | `text-base` (16px) | 正文 | 对话消息、描述 |
| Small | `text-sm` (14px) | 辅助信息 | 时间戳、状态文本 |
| Tiny | `text-xs` (12px) | 标签、徽章 | Badge 文字 |

---

### 间距系统

#### 布局容器

| 类型 | 最大宽度 | 用途 |
|------|---------|------|
| 窄容器 | `max-w-[980px]` | 对话区、表单 |
| 宽容器 | `max-w-[1440px]` | Agent Catalog、历史页 |
| 全宽 | 无限制 | 任务详情页（含文件树） |

#### 内边距

| 位置 | 移动端 | 桌面端 |
|------|--------|--------|
| 水平内边距 | `px-5` (20px) | `px-10` (40px) |
| 顶部内边距 | `pt-[60px]` | `pt-[80px]` |
| 区域间距 | `space-y-6` (24px) | `space-y-8` (32px) |

---

### 组件库

#### Button 变体

| 变体 | 外观 | 用途 | 示例 |
|------|------|------|------|
| `default` | 实心主色 | 主要操作 | "Start Task"、"Send" |
| `secondary` | 实心次色 | 次要操作 | 导航激活状态 |
| `outline` | 边框 + 透明背景 | 取消操作 | "Cancel" |
| `ghost` | 透明背景 + hover 显示 | 图标按钮 | 返回按钮、关闭按钮 |
| `destructive` | 实心红色 | 危险操作 | "Delete Task" |

#### Badge 变体

| 变体 | 外观 | 用途 | 示例 |
|------|------|------|------|
| `default` | 实心主色 | 运行中状态 | "Running" |
| `secondary` | 实心灰色 | 队列、取消状态 | "Queued"、"Cancelled" |
| `success` | 绿色边框 | 完成状态 | "Completed" |
| `warning` | 黄色背景 | 警告、降级 | "Degraded" |
| `destructive` | 红色背景 | 失败状态 | "Failed" |

#### Card 变体

用于 Agent Catalog 和历史页：

| 变体 | 背景色 | 用途 |
|------|--------|------|
| `light` | 浅色 | Agent 卡片（循环第 1 个） |
| `parchment` | 米黄色 | Agent 卡片（循环第 2 个） |
| `dark` | 深色 | Agent 卡片（循环第 3 个） |

---

### 动画与过渡

| 动画类型 | 实现 | 用途 |
|---------|------|------|
| **页面淡入** | `animate-fade-in` | 页面加载时 |
| **卡片 hover** | `transition-all duration-200 hover:scale-[1.02]` | Agent 卡片、Task 卡片 |
| **卡片 active** | `active:scale-[0.99]` | 点击反馈 |
| **图标 hover** | `transition-transform duration-500 hover:scale-110` | Agent 图标 |
| **加载动画** | `animate-spin` | Loader2 图标 |
| **脉冲动画** | `animate-pulse` | 骨架屏 |

#### 过渡时长

| 场景 | 时长 | 缓动函数 |
|------|------|----------|
| 快速反馈 | 200ms | `ease-out` |
| 舒适过渡 | 300ms | `ease-in-out` |
| 强调动画 | 500ms | `ease-in-out` |

---

### 图标系统

使用 `lucide-react` 图标库，16px / 20px / 24px 三种尺寸。

#### 核心图标映射

| 概念 | 图标 | 用途 |
|------|------|------|
| Task | `FileText` | 任务卡片、文件列表 |
| Run | `Play` | Run 状态指示 |
| Agent | `Bot` | Agent 消息头像 |
| User | `User` | 用户消息头像 |
| Workspace | `Folder` | 工作区、文件夹 |
| File | `FileText` | 文件节点 |
| Created | `FilePlus` | 新建文件状态 |
| Modified | `FileEdit` | 修改文件状态 |
| Deleted | `FileX` | 删除文件状态 |
| Queue | `Clock` | 队列状态 |
| Success | `CheckCircle2` | 成功、完成 |
| Error | `XCircle` | 错误、失败 |
| Warning | `AlertTriangle` | 警告、降级 |
| Loading | `Loader2` | 加载中 |
| Back | `ArrowLeft` | 返回导航 |
| Close | `X` | 关闭弹窗 |
| Send | `Send` | 发送消息 |
| Download | `Download` | 下载文件 |

---

## 📄 页面设计规范

### 1. 全局导航 (GlobalNav)

**位置**：固定顶部，所有页面共享

**结构**：
```
[Logo + "SiriusX"] [Agents] [History] [              ] [User Menu]
```

**设计规范**：
- 高度：`h-16` (64px)
- 背景：`surface` + `border-b`
- Logo：圆形 S 图标 + "SiriusX" 文字（font-serif）
- 导航链接：Button `ghost` 变体，激活状态改为 `secondary`
- 用户菜单（阶段 3）：头像 + 下拉菜单（租户切换、登出）

**交互**：
- Logo 点击返回首页
- 导航链接高亮当前页面
- 移动端自动收起为汉堡菜单

**实施阶段**：
- ✅ 阶段 0：基础导航（Logo + Agents / History）
- 🔄 阶段 3：用户菜单（Auth 完成后）

---

### 2. 首页 - Agent Catalog (`/`)

**用户目标**：快速选择合适的 AI Agent 开始任务

**API**：`GET /api/agents` - 拉取 Agent 列表

**布局**：
```
[GlobalNav]
[Hero 区域]
  - 品牌标语："AI-Powered Development"
  - 描述："Distributed AI Agent Task Execution Platform"
[Agent 卡片网格]
  - 响应式布局：1 列（移动）/ 2 列（平板）/ 3 列（桌面）
  - 卡片循环应用 light / parchment / dark 背景
[Footer]
  - 版权信息 + GitHub 链接
```

**Agent 卡片设计**：
- **图标**：使用专业图标（lucide-react），不是 emoji
  - Architecture Advisor → `Package`
  - Code Reviewer → `FileCheck`
  - Debug Assistant → `Bug`
  - Research Agent → `Search`
- **标题**：font-serif，text-2xl
- **副标题**：text-sm，muted 色
- **描述**：2-3 行简介
- **按钮**："Select Agent"（default 变体）

**交互**：
- hover：卡片缩放 1.02x，图标缩放 1.1x
- 点击卡片任意位置 = 点击按钮
- 加载失败：显示 toast "Failed to load agents. Using default catalog."

**优化建议**（P1）：
- 支持 Agent 搜索和分类过滤
- 显示 Agent 热度（最近使用次数）
- 支持收藏 Agent

**实施阶段**：
- ✅ 阶段 0：基础 Agent Catalog
- 🔄 阶段 1：搜索和过滤
- 🔄 阶段 2：热度和收藏

---

### 3. 任务创建弹窗 (NewTaskModal)

**用户目标**：快速输入初始需求，启动任务

**API**：`POST /api/task` - 创建 Task（不消费 prompt）

**设计规范**：
- 居中模态窗口，max-w-lg
- 背景遮罩：半透明黑色 + 点击关闭
- 卡片：圆角 lg + 阴影 xl

**内容结构**（阶段 0：不含 prompt 字段，prompt 在任务详情页发送）：
```
[Agent 图标 - 方形容器]
[Agent 标题 - font-serif text-2xl]
[Agent 副标题 - text-sm]
─────────────────────
[Label: "Task title (optional)"]
[Input: 任务标题，可选，留空则使用 "Untitled Task"]
─────────────────────
[Cancel] [Start Task]
```

> Prompt 输入放在任务详情页（见下方 4.2 对话区）；阶段 1+ 可考虑在弹窗内提供"首条消息"快捷输入。

**交互**：
- 自动聚焦 "Start Task" 按钮
- 提交中：按钮文字 "Starting..."，禁用按钮
- **成功**：关闭弹窗，跳转到任务详情页，显示**空状态**（"Start a conversation with your AI agent."），由用户手动发送首条消息（对齐 STAGE0_SPEC §5.2）
- **失败**（P0）：显示 inline 错误消息，保留选择

**数据流**（对齐 STAGE0_SPEC §5.1 / §5.2）：
```
1. POST /api/task { agent, model, title? }
   → 创建 Task，返回 taskId（不消费 prompt，不创建 run）
2. 跳转到 /task/:taskId
3. 任务详情页检测到无消息，显示空状态
4. 用户手动输入并发送首条消息 → POST /api/task/:taskId/message
```

> 🚨 **禁止使用 sessionStorage / URL query 中转首条 prompt**（STAGE0_SPEC §5.2）。首条 prompt 必须由用户在任务详情页手动发送。

**实施阶段**：
- ✅ 阶段 0：基础创建流程
- 🔄 阶段 0 P0：失败反馈
- 🔄 阶段 1：高级选项（model 选择、skills 配置）

---

### 4. 任务详情页 (`/task/[taskId]`)

**用户目标**：与 AI Agent 持续对话，查看执行进度和产物

**API**：
- `GET /api/task/:taskId` - 轮询获取 Task 详情（1000ms 间隔）
- `POST /api/task/:taskId/message` - 发送消息并订阅 Fetch Streaming
- `GET /api/task/:taskId/files` - 获取文件树
- `GET /api/task/:taskId/artifacts` - 获取产物列表
- `POST /api/task/:taskId/close` - 关闭任务

**布局**：
```
[GlobalNav]
[TopBar: 返回 | 任务标题 | Task Badge | Run Badge | Close]
┌────────────────────────────────┬────────────┐
│                                │            │
│   TaskConversation             │  FileTree  │
│   (对话区)                      │  Panel     │
│                                │            │
│                                │  (桌面端   │
│                                │   固定)    │
├────────────────────────────────┤            │
│   InputArea                    │            │
│   (输入区)                      │            │
└────────────────────────────────┴────────────┘
       (移动端文件树折叠到底部)
```

#### 4.1 顶部栏 (TopBar)

**设计规范**：
- 高度：h-14 (56px)
- 背景：surface + border-b
- 左右内边距：px-4

**内容结构**：
```
[← Back] [Task 标题...] [Task Badge] [Run Badge] [Close Task]
```

**组件说明**：
- **Back 按钮**：ArrowLeft 图标 + "Back"，ghost 变体
- **任务标题**：truncate，最大宽度自适应
- **Task Badge**：显示 Task 状态（running / completed / failed）
- **Run Badge**：显示最新 Run 状态（仅当有 active run 时）
- **Close Task 按钮**：CheckCircle2 图标 + "Close Task"
  - 仅在 `task.status === 'running'` 时显示
  - 点击时弹出确认对话框（P0）

**确认对话框设计（P0）**：
```
⚠️ Close this task?

This will cancel any running execution and mark 
the task as completed. You can still view it in 
your history.

[Cancel] [Close Task]
```

**实施阶段**：
- ✅ 阶段 0：基础顶部栏
- 🔄 阶段 0 P0：关闭确认对话框

---

#### 4.2 对话区 (TaskConversation)

**用户目标**：查看完整对话历史、实时流式输出、工具调用进度

**设计规范**：
- 背景：canvas
- 内边距：p-4 md:p-6
- 最大宽度：max-w-[980px]
- 自动滚动到底部（可手动停止）

**消息布局**：
```
┌─ 用户消息 ──────────────────┐
│ [User 图标]                  │
│ 用户输入的文本...             │
│ [时间戳]                     │
└──────────────────────────────┘
    (右对齐，灰色背景)

┌─ 助手消息 ──────────────────┐
│ [Bot 图标]                   │
│ AI 回复的文本...              │
│ [工具调用面板]               │
│ [时间戳]                     │
└──────────────────────────────┘
    (左对齐，白色背景)
```

**工具调用面板设计（P0）**：
```
┌─ Tool Call ─────────────────┐
│ 🔧 Running bash              │
│ ─────────────────────────   │
│ $ npm install lodash         │
│ ─────────────────────────   │
│ ✓ Completed in 2.3s          │
│ [View Output ▼]              │
└──────────────────────────────┘
```

**流式输出状态**：
- 打字机效果：逐字显示
- 思考状态：显示 "💭 Thinking..." + 旋转 Loader2
- 工具调用：显示工具名称 + 执行状态
- 完成状态：显示 ✓ 图标 + "Completed"

**空状态**：
- Task queued：显示 "⏳ Waiting for worker..."
- 无消息：显示引导文案 "Start a conversation with your AI agent."

**事件类型映射**：

| 事件类型 | UI 表现 | 图标 |
|---------|---------|------|
| `assistant_delta` | 打字机文本流 | Bot |
| `thinking_delta` | "💭 Thinking..." | Loader2 |
| `tool_start` | "🔧 Running {toolName}" | Wrench |
| `tool_update` | 进度条更新 | - |
| `tool_end` | "✓ Completed in {duration}" | CheckCircle2 |
| `turn_complete` | 完成标记 | - |
| `error` | 错误消息气泡 | XCircle |

**Markdown 渲染**：
- 代码块：语法高亮 + 复制按钮
- 内联代码：`code` 背景色 + mono 字体
- 粗体：`**text**` → **加粗**
- 标题：`## H2`、`### H3`
- 列表：有序 / 无序列表
- 链接：可点击，primary 色

**实施阶段**：
- ✅ 阶段 0：基础消息流
- 🔄 阶段 0 P0：工具调用可视化
- 🔄 阶段 1：思考过程展示
- 🔄 阶段 2：消息历史导航（上箭头）

---

#### 4.3 输入区 (InputArea)

**用户目标**：快速输入后续消息，继续对话

**显示条件**：仅在 `task.status === 'running'` && 无 active run 时显示

**设计规范**：
```
┌────────────────────────────────┐
│ [Textarea]                     │
│ Type your message...           │
│                                │
└────────────────────────────────┘
                    [Send 按钮 →]
```

**功能**：
- 自动高度调整（最小 3 行，最大 10 行）
- `Cmd/Ctrl + Enter` 发送
- `Shift + Enter` 换行
- 发送中禁用输入和按钮
- 空内容时禁用发送按钮

**提示文案**：
- 默认："Type your message..."
- hover 显示 tooltip："Cmd+Enter to send, Shift+Enter for new line"

**实施阶段**：
- ✅ 阶段 0：基础输入
- 🔄 阶段 2：多行提示

---

#### 4.4 文件树面板 (TaskFileTreePanel)

**用户目标**：查看 AI 生成的文件和修改状态

**API**：`GET /api/task/:taskId/files` - 懒加载文件树

**布局**：
- 桌面端：右侧固定面板，宽度 `w-80` (320px)
- 移动端：底部可折叠抽屉

**设计规范**：
```
┌─ Workspace Files ──────────┐
│ 📁 12 files                │
│ ⚠️ Syncing... (如有)       │
├────────────────────────────┤
│ 📂 src/                    │
│   📄 index.ts       ●      │
│   📄 utils.ts       ●      │
│ 📂 docs/                   │
│   📄 README.md      +      │
└────────────────────────────┘
```

**文件状态标记**：
- **Created**：绿色 `+` 或 FilePlus 图标
- **Modified**：蓝色 `●` 或点
- **Deleted**：红色 `×` 或 FileX 图标

**交互（P1）**：
- 点击文件：预览内容（右侧弹出面板）
- hover 显示完整路径
- 右键菜单：下载、复制路径、查看 diff

**懒加载策略**：
- 初始加载：深度 2，最多 50 个节点
- 点击文件夹：展开加载子节点
- 大型文件树显示 "Load more..." 按钮

**实施阶段**：
- ✅ 阶段 0：基础文件树
- 🔄 阶段 1：懒加载
- 🔄 阶段 2：文件预览和下载
- 🔄 阶段 3：Diff 视图

---

### 5. 历史页 (`/history`)

**用户目标**：快速找到过去的任务，继续或查看结果

**API**：`GET /api/task?userId=<userId>` - 按 userId 拉取任务列表

**布局**：
```
[GlobalNav]
[Hero 区域]
  - 标题："Task History"
  - 描述："View and resume your previous tasks"
[搜索和过滤栏]（P1）
[TaskCard 列表]
  - 垂直排列，gap-4
[分页控件]（P1）
```

**TaskCard 设计**：
```
┌─────────────────────────────────┐
│ [Agent 图标] Architecture Advisor│
│                                 │
│ "为支付系统设计架构方案..."      │
│                                 │
│ 📅 2026-06-15 14:30 [Completed] │
└─────────────────────────────────┘
```

**交互**：
- hover：边框高亮（primary/30）+ 轻微上移
- active：缩放 0.99x
- 整张卡片可点击

**空状态**：
```
📭
No tasks yet.
Create your first task from the Agent Catalog.
[Go to Catalog]
```

**加载状态**：3 个骨架屏卡片（animate-pulse）

**错误状态**：
```
❌ Failed to load tasks
[Try again]
```

**搜索和过滤（P1）**：
```
[🔍 Search tasks...] [Filter: All ▼] [Sort: Recent ▼]
```

- 搜索：按任务标题、Agent 名称
- 过滤：All / Running / Completed / Failed
- 排序：Recent / Oldest / Agent / Status

**实施阶段**：
- ✅ 阶段 0：基础历史列表
- 🔄 阶段 1：搜索和过滤
- 🔄 阶段 2：分页和排序

---

## 🔄 实时通信设计

### Fetch Streaming 实现

**技术选型**：使用 Fetch API + `ReadableStream`，不使用 EventSource 或 WebSocket

**为什么**：
- Fetch Streaming 支持 POST 请求（可携带 body）
- 可以自定义 headers（如 Auth token）
- 支持取消（AbortController）
- Next.js 原生支持

**数据格式**：
```
data: {"type":"run_started","sequence":1,"payload":{"runId":"..."}}
data: {"type":"assistant_delta","sequence":2,"payload":{"delta":"..."}}
data: {"type":"tool_start","sequence":3,"payload":{"toolName":"bash","input":"..."}}
data: {"type":"tool_end","sequence":4,"payload":{"output":"...","duration":2300}}
data: {"type":"turn_complete","sequence":5,"payload":{"runId":"..."}}
```

**客户端实现**：
```typescript
const response = await fetch(`/api/task/${taskId}/message`, {
  method: 'POST',
  body: JSON.stringify({ content: message }),
  signal: abortController.signal,
});

const reader = response.body.getReader();
const decoder = new TextDecoder();

while (true) {
  const { done, value } = await reader.read();
  if (done) break;
  
  const chunk = decoder.decode(value);
  const lines = chunk.split('\n');
  
  for (const line of lines) {
    if (line.startsWith('data: ')) {
      const event = JSON.parse(line.slice(6));
      handleEvent(event);
    }
  }
}
```

---

### 断线恢复设计

**问题**：用户刷新页面、网络断开、浏览器崩溃后如何恢复？

**方案**：Run-scoped event sequence + 补齐机制

**实现流程**：
```
1. 前端追踪 lastSequence（每条事件的 sequence 号）
2. 刷新页面时从 localStorage 读取 lastSequence
3. 调用 GET /api/task/:taskId/runs/:runId/events?afterSequence=<N>
4. 补齐缺失的事件
5. 继续订阅 Fetch Streaming（如果 run 仍在执行）
```

**前端状态管理**：
```typescript
interface RunRecoveryState {
  runId: string;
  lastSequence: number;
  status: 'running' | 'completed' | 'failed';
  recoveredAt?: number;
}

// 存储在 localStorage
localStorage.setItem(
  `siriusx-run-${taskId}`,
  JSON.stringify(recoveryState)
);
```

**UX 反馈**：
```
┌─────────────────────────────┐
│ ⚠️ Connection lost          │
│ Recovering...               │
│ [Recovered 12 events]       │
└─────────────────────────────┘
```

**边界情况**：
- Control Worker 崩溃：新 Control Worker 接手，前端自动补齐
- API 节点重启：前端轮询检测恢复，补齐事件
- Postgres 持久化失败：Run 状态变为 `completed_with_warnings`

**实施阶段**：
- ✅ 阶段 0：基础断线恢复
- 🔄 阶段 1：智能重连（指数退避）

---

### 轮询优化策略

**问题**：无限轮询浪费资源，需要智能停止

**方案**：仅在有 active run 时轮询

**判断逻辑**：
```typescript
function shouldPoll(task: Task): boolean {
  if (task.status !== 'running') return false;
  
  const latestRun = task.runs?.[0];
  if (!latestRun) return false;
  
  return ['queued', 'running'].includes(latestRun.status);
}
```

**轮询策略**：
- 有 active run：1000ms 间隔
- 无 active run：停止轮询
- 失败后重试：指数退避（1s → 2s → 4s → 8s，最大 30s）

**UX 反馈**：
```
[轮询中] → 显示 "Syncing..." 小图标
[轮询停止] → 图标消失
[轮询失败] → 显示 "⚠️ Connection error. Retrying in 8s..."
```

**实施阶段**：
- ✅ 阶段 0：基础轮询
- 🔄 阶段 1：智能停止和重试

---

## 🔐 Auth 与租户体验

### Session-based Auth 设计

**目标**：简单、安全、多租户隔离

**登录页设计**：
```
┌─────────────────────────────┐
│   SiriusX Logo              │
│                             │
│   Welcome back              │
│                             │
│   [Email input]             │
│   [Password input]          │
│   [Remember me]             │
│                             │
│   [Log in]                  │
│                             │
│   Don't have an account?    │
│   [Sign up]                 │
└─────────────────────────────┘
```

**Session 机制**：
- Cookie 名称：`siriusx.sid`
- 存储：Redis（支持多 API 节点共享）
- 过期时间：7 天（默认）
- httpOnly + secure + sameSite=lax

**租户切换（企业版）**：
```
[User Avatar ▼]
  ├─ Morgan Woods
  ├─ Current: Acme Corp
  ├─────────────────
  ├─ Switch Tenant
  │   ├─ Acme Corp    ✓
  │   ├─ Beta Labs
  │   └─ Personal
  ├─────────────────
  ├─ Settings
  └─ Log out
```

**权限边界**：
- Task 创建时自动设置 `tenantId` 和 `userId`
- S3 key 强制前缀：`s3://bucket/tenants/<tenantId>/...`
- API 中间件验证：所有请求必须有 `authContext`

**实施阶段**：
- ✅ 阶段 0 P0：Session-based Auth
- 🔄 阶段 3：OAuth（Google / GitHub）
- 🔄 阶段 4：租户切换（企业版）

---

## 🗺️ 分阶段实施路线图

### 阶段 0：基础体验修正（3-4 周）

**目标**：修复关键 UX 阻塞点，建立安全边界

#### P0 修正清单

| # | 功能 | 当前问题 | 目标 | 优先级 |
|---|------|---------|------|--------|
| 1 | Auth 登录页 | 无登录机制 | Session-based Auth + 登录/注册页 | P0 |
| 2 | 任务创建失败反馈 | 失败时无提示 | 显示 inline 错误消息 | P0 |
| 3 | 关闭任务确认 | 单击即关闭 | 添加确认对话框 | P0 |
| 4 | 工具调用可视化 | 无工具执行进度 | 显示 tool_start/end 面板 | P0 |
| 5 | 断线恢复 | 刷新丢失未持久化事件 | 通过 afterSequence 补齐 | P0 |

#### UI 组件清单

- ✅ 登录页（`/login`）
- ✅ 注册页（`/register`）
- ✅ Auth 中间件（前端 + 后端）
- ✅ 确认对话框组件（`ConfirmDialog`）
- ✅ 工具调用面板（`ToolCallPanel`）
- ✅ 错误 Toast 组件（`ErrorToast`）
- ✅ 断线恢复提示（`RecoveryBanner`）

---

### 阶段 1：功能完整性（2-3 周）

**目标**：补全核心功能，提升用户体验

#### P1 功能清单

| # | 功能 | 描述 | 实施工作量 |
|---|------|------|-----------|
| 1 | 文件预览 | 点击文件树节点预览内容 | 2 天 |
| 2 | 下载产物 | 下载单个文件 / 全部文件 | 1 天 |
| 3 | 历史页搜索 | 按标题、Agent 搜索 | 2 天 |
| 4 | 历史页过滤 | 按状态、时间过滤 | 1 天 |
| 5 | 轮询失败重试 | 自动重试 + 手动重试按钮 | 1 天 |
| 6 | Agent 图标专业化 | 替换 emoji 为 lucide-react | 1 天 |
| 7 | 接口失败提示 | Agent Catalog 失败显示 banner | 0.5 天 |

#### UI 组件清单

- ✅ 文件预览抽屉（`FilePreviewDrawer`）
- ✅ 下载按钮（支持单个 / 批量）
- ✅ 搜索框组件（`SearchInput`）
- ✅ 过滤器组件（`FilterDropdown`）
- ✅ 重试按钮（`RetryButton`）

---

### 阶段 2：体验优化（2-3 周）

**目标**：提升交互流畅性和信息密度

#### P2 优化清单

| # | 功能 | 描述 | 预期效果 |
|---|------|------|---------|
| 1 | 文件树折叠/搜索 | 大型文件树性能优化 | 支持 1000+ 文件 |
| 2 | 消息历史导航 | 上箭头回到上一条消息 | 类似终端体验 |
| 3 | 任务预览 | 历史页显示首条消息摘要 | 快速识别任务 |
| 4 | 多行输入提示 | 输入框提示快捷键 | 减少用户困惑 |
| 5 | Back 按钮智能化 | 记住来源页面 | 提升导航体验 |
| 6 | 队列等待时间估算 | 基于 p95 显示预计等待 | 降低焦虑感 |
| 7 | 思考过程展示 | 显示 thinking_delta 内容 | 增强透明度 |

---

### 阶段 3：高级功能（3-4 周）

**目标**：支持团队协作和高级工作流

#### 功能清单

- OAuth 登录（Google / GitHub）
- 租户切换（企业版）
- Task 分享（生成分享链接）
- Task 模板（保存常用配置）
- Workspace diff 视图
- 批量操作（批量关闭、归档）
- 通知中心（Run 完成通知）

---

### 阶段 4：企业级特性（持续）

- 角色权限管理（RBAC）
- 审计日志
- 使用量统计 Dashboard
- 成本监控
- API Key 管理
- Webhook 集成

---

## ⚡ 性能与可访问性

### 性能目标

| 指标 | 目标值 | 测量方法 |
|------|--------|---------|
| 首屏加载（FCP） | < 1.5s | Lighthouse |
| 最大内容绘制（LCP） | < 2.5s | Lighthouse |
| 首次输入延迟（FID） | < 100ms | Lighthouse |
| 累积布局偏移（CLS） | < 0.1 | Lighthouse |
| 页面切换 | < 200ms | 自定义监控 |
| 消息发送响应 | < 100ms | 自定义监控 |

### 性能优化策略

#### 1. 代码分割

```typescript
// 路由级别代码分割
const TaskPage = lazy(() => import('@/app/task/[taskId]/page'));
const HistoryPage = lazy(() => import('@/app/history/page'));

// 组件级别代码分割
const FilePreviewDrawer = lazy(() => import('@/components/FilePreviewDrawer'));
```

#### 2. 资源优化

- 图片：使用 Next.js `<Image>` 组件，自动优化
- 字体：预加载 serif/sans/mono 字体
- 图标：Tree-shaking（只导入用到的图标）

#### 3. 数据缓存

- SWR 或 React Query 管理 API 缓存
- localStorage 缓存 Agent Catalog（7 天）
- IndexedDB 缓存大型文件树（按需清理）

#### 4. 渲染优化

- 虚拟滚动（对话区 > 100 条消息时）
- 文件树懒加载（按需展开）
- 骨架屏（避免布局抖动）

---

### 可访问性（WCAG 2.1 AA 标准）

#### 1. 语义化 HTML

- 使用 `<button>` 而非 `<div onClick>`
- 使用 `<nav>`、`<main>`、`<article>` 等语义标签
- 表单使用 `<label>` 关联输入框

#### 2. 键盘导航

- 所有交互元素可通过 Tab 键访问
- Enter 键触发按钮
- Esc 键关闭弹窗
- 焦点陷阱（Modal 内部）

#### 3. ARIA 标注

```tsx
<button aria-label="Send message">
  <Send className="w-4 h-4" />
</button>

<div role="status" aria-live="polite">
  Waiting for worker...
</div>
```

#### 4. 颜色对比度

- 正文文本：至少 4.5:1
- 大文本（≥18px）：至少 3:1
- UI 组件：至少 3:1

#### 5. 焦点可见性

```css
.focus-visible\:outline-primary {
  outline: 2px solid var(--primary);
  outline-offset: 2px;
}
```

#### 6. 屏幕阅读器支持

- 实时更新使用 `aria-live`
- 加载状态使用 `role="status"`
- 错误消息使用 `role="alert"`

---

## 📝 设计决策记录

### DDR-001: 为什么使用 Fetch Streaming 而非 WebSocket？

**日期**：2026-06-15  
**状态**：已采纳

**背景**：
- 需要实时传输 AI 生成的文本流
- 考虑过 SSE、WebSocket、Fetch Streaming

**决策**：使用 Fetch Streaming

**理由**：
1. **POST 支持**：可以在请求体中携带消息内容
2. **Auth 友好**：可以自定义 headers（如 Bearer token）
3. **取消支持**：通过 AbortController 取消请求
4. **Next.js 原生支持**：无需额外配置
5. **单向流足够**：AI → 用户是主流场景，不需要双向实时

**缺点**：
- 不支持服务端主动推送（但通过轮询可弥补）
- 浏览器兼容性略差于 SSE（但现代浏览器都支持）

**替代方案**：
- WebSocket：双向实时，但需要额外服务器配置，Auth 复杂
- SSE：简单但只支持 GET，无法携带 body

---

### DDR-002: 为什么任务创建不消费 prompt？

**日期**：2026-06-15  
**状态**：已采纳

**背景**：
- 旧版 `POST /api/task` 接受 prompt 并立即创建 run
- 新架构要求 Task 创建和 Run 执行分离

**决策**：Task 创建只创建空白容器，prompt 通过 `/message` 端点发送

**理由**：
1. **边界清晰**：Task = 容器，Run = 执行单元
2. **权限控制**：可以在 `/message` 端点单独限流
3. **失败隔离**：Task 创建失败 ≠ Run 执行失败
4. **审计友好**：可以精确追踪每条消息的来源

**影响**：
- 前端需要两步操作：先创建 Task，再发送消息
- 用户感知：无影响（自动化处理）

---

### DDR-003: 为什么文件树不支持实时协作？

**日期**：2026-06-15  
**状态**：已采纳

**背景**：
- 考虑过支持多用户同时编辑同一 Task

**决策**：同一 Task 多 Run 串行执行，不支持并发编辑

**理由**：
1. **复杂度过高**：需要 CRDT 或 OT 算法，工程量巨大
2. **场景不匹配**：AI Agent 任务通常是个人工作，非团队协作
3. **冲突检测已足够**：Workspace revision 乐观锁可防止并发冲突
4. **性能考虑**：实时同步会增加服务器负担

**替代方案**：
- Task 分享功能（只读）
- 任务模板（复制后独立编辑）

---

### DDR-004: 为什么轮询间隔是 1000ms？

**日期**：2026-06-15  
**状态**：已采纳

**背景**：
- 需要平衡实时性和服务器负担

**决策**：1000ms 轮询间隔

**理由**：
1. **实时性足够**：Run 平均时长 5-10 分钟，1 秒延迟可接受
2. **服务器负担可控**：100 用户 × 1 req/s = 100 QPS
3. **Event persistence lag < 5s**：1 秒轮询可以在 5 秒内发现状态变化

**优化**：
- 仅在有 active run 时轮询
- 失败后指数退避

---

## 🎨 视觉示例

### 首页 - Agent Catalog

```
┌─────────────────────────────────────────────────┐
│  [Logo] SiriusX    [Agents] [History]   [User] │
├─────────────────────────────────────────────────┤
│                                                 │
│         AI-Powered Development                  │
│    Distributed AI Agent Task Execution          │
│                                                 │
├─────────────────────────────────────────────────┤
│  ┌─────────┐  ┌─────────┐  ┌─────────┐        │
│  │ 📦      │  │ 🔍      │  │ 🐛      │        │
│  │ Arch    │  │ Code    │  │ Debug   │        │
│  │ Advisor │  │ Reviewer│  │ Helper  │        │
│  │         │  │         │  │         │        │
│  │[Select] │  │[Select] │  │[Select] │        │
│  └─────────┘  └─────────┘  └─────────┘        │
└─────────────────────────────────────────────────┘
```

---

### 任务详情页 - 执行中

```
┌──────────────────────────────────────────────────┐
│ [← Back] 支付系统架构设计 [Running] [Close Task]│
├────────────────────────────────┬─────────────────┤
│                                │ 📁 Workspace    │
│ [User 图标]                    │ ─────────────── │
│ 为支付系统设计架构方案         │ 📂 docs/        │
│ 14:30                          │   📄 arch.md ● │
│                                │ 📂 src/         │
│ [Bot 图标]                     │   📄 api.ts  + │
│ 我来帮你设计一个高可用...      │                 │
│                                │                 │
│ 🔧 Running bash                │                 │
│ ─────────────────────────      │                 │
│ $ tree src/                    │                 │
│ ✓ Completed in 1.2s            │                 │
│                                │                 │
│ 💭 Thinking...                 │                 │
├────────────────────────────────┤                 │
│ [Type message...] [Send →]    │                 │
└────────────────────────────────┴─────────────────┘
```

---

## 🔗 相关文档

- [ARCHITECTURE.md](./ARCHITECTURE.md) - 系统架构和核心原则
- [IMPLEMENTATION.md](./IMPLEMENTATION.md) - 实施计划和性能目标
- [API端点.md](./modules/API端点.md) - 完整 API 规范
- [前端优化.md](./modules/前端优化.md) - 前端性能优化策略
- [Auth实现详解.md](./modules/Auth实现详解.md) - 认证和授权设计

---

## 📮 反馈和迭代

**设计原则**：
- 用户反馈优先于架构完美
- 快速迭代优于一次性完美
- 可测量优于主观判断

**反馈渠道**：
- GitHub Issues（功能请求、Bug 报告）
- 用户访谈（每月 5-10 位用户）
- 使用数据分析（Mixpanel / Amplitude）

**迭代周期**：
- 每 2 周发布一个小版本（bug fix + 小优化）
- 每 1-2 月发布一个大版本（新功能）

---

_文档版本：v2.0_  
_最后更新：2026-06-15_  
_作者：浮浮酱 (Yuki - 猫娘工程师)_ ฅ'ω'ฅ
