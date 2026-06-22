# SiriusX 平台架构

> 分布式 AI Agent 任务执行平台架构文档

---

## 目录

- [用户故事](#用户故事)
  - [通俗版](#通俗版)
  - [技术版](#技术版)
- [设计目标](#设计目标)
- [核心原则](#核心原则)
- [仓库与信任边界](#仓库与信任边界)
- [分布式拓扑](#分布式拓扑)
- [状态归属](#状态归属)
- [落地前必须对齐的代码冲突](#落地前必须对齐的代码冲突)

---

## 用户故事

### 通俗版

#### 场景：小明需要设计一个支付系统

小明是一名前端工程师，老板要求他设计一套支付系统的架构方案。他不太熟悉后端架构设计，于是打开 SiriusX 平台寻求帮助。

---

#### 第 1 步：创建任务

小明在首页看到几个 AI 助手卡片，选择了 **"Architecture Advisor"**（架构顾问）。点击后弹出对话框，他输入：

> "为支付系统设计架构方案，要求高可用、可扩展"

点击"开始任务"后，系统创建了一个 **Task（任务）**。

**这个 Task 就像一个项目文件夹**：
- 📁 里面有对话记录
- 📁 有 AI 生成的文档
- 📁 还有一个工作区（workspace），AI 可以在里面创建和修改文件

**重要的是**：这个任务不是一次性的聊天，小明可以随时回来继续，即使关闭浏览器或者第二天再打开，所有内容都还在。

---

#### 第 2 步：AI 开始工作（第一轮）

小明进入任务页面，看到：
- 左侧是对话区，显示他的问题
- 右侧是"产物列表"，等会儿 AI 生成的文档会出现在这里

系统后台发生了什么？（你不需要懂技术细节，但这里解释一下）

1. **系统创建了一个"执行单元"**（叫 run-001）
   - 就像你在餐厅点了一道菜，厨房收到一个订单编号

2. **有一个"工人"接单了**（叫 Control Worker）
   - 系统可能有多个 Control Worker 同时工作，就像餐厅有多个厨师
   - Control Worker 负责调度一次性沙箱，让 AI 处理小明的请求

3. **AI 开始生成内容**
   - AI 一边写一边把内容**实时流式传输**给小明（就像打字机一样，一个字一个字地显示）
   - 同时，内容也被保存到数据库，防止丢失

4. **AI 可能需要运行命令**
   - 比如生成架构图、验证配置文件
   - 系统会创建一个**隔离的 Docker 容器**（像一个临时的虚拟电脑），让 AI 在里面安全地执行命令
   - 执行完后，容器被销毁，不留痕迹

几分钟后，AI 生成了一份架构方案文档，保存在右侧的"产物列表"里。第一轮完成！

---

#### 第 3 步：小明继续迭代（第二轮）

小明看完文档后，觉得"事件驱动架构"太复杂了，他在对话框里继续问：

> "事件驱动太复杂了，改成 REST 同步调用"

系统创建了第二个执行单元（run-002）。

**关键点**：
- 这次的 AI **不是接着上一轮的记忆**继续（那样会占用太多资源）
- 而是读取数据库里的**对话历史**和**已生成的文档**，重新理解上下文
- 就像你今天问
一个问题，明天再去，医生翻看你的病历后继续看诊

**详细解释** → 参见 [短生命周期会话设计](#短生命周期会话设计)

AI 修改了架构方案，更新了文档。小明看到右侧的文件状态变成了"已修改"（蓝色标记）。

---

#### 第 4 步：再次迭代（第三轮）

小明又想加个功能：

> "加个 Redis 缓存层，把热点数据缓存起来"

系统创建 run-003，AI 继续在同一个工作区里修改文档。

---

#### 第 5 步：完成任务

小明满意了，点击右上角的 **"关闭任务"** 按钮。

系统做了以下事情：
- 标记任务为"已完成"
- 保存所有对话记录、文档、修改历史
- 清理临时资源（如果有用过的 Docker 容器）

以后小明可以在"历史"页面找到这个任务，查看当时的所有内容。

---

#### 用户体验总结

| 你看到的 | 背后发生的 |
|---|---|
| 对话框输入问题 | 系统创建一个 Task（任务） |
| AI 打字机般地回复 | 实时流式传输 + 同时保存到数据库 |
| 右侧出现新文档 | AI 在工作区里创建了文件 |
| 文件显示"已修改" | AI 更新了已有文件，系统记录了版本 |
| 刷新页面后内容还在 | 所有数据都持久化存储了 |
| 第二天继续对话 | 系统从数据库读取历史，恢复上下文 |
| 关闭任务 | 标记完成，清理临时资源 |

---

#### 背后的黑科技（可选阅读）

##### 为什么不会丢失内容？

**🚨 阶段 0-2 可靠性保证**：

只有已写入 Postgres 的事件能恢复。系统采用"尽力而为"策略：

1. **实时流**：你立刻看到 AI 的回复（通过 SSE）
2. **本地缓冲**：Control Worker 进程内存缓冲未持久化事件（best-effort）
3. **数据库**：批量写入 Postgres，永久保存（唯一可靠来源）

**关键限制**：
- Control Worker 崩溃后，内存缓冲中未持久化的事件**会丢失**
- 新 Control Worker 只能从 Postgres 恢复已持久化的事件
- 未来扩展（阶段 3+）才实现 S3 事件备份

这是简化架构的权衡，适合 MVP 阶段。生产环境可以通过更频繁的批量写入（如每 100ms）减少丢失风险。

##### 为什么可以多人同时使用？

系统可以"水平扩展"：
- 想象一个餐厅，人多的时候可以增加厨师和服务员
- SiriusX 可以增加更多的 API 节点（接待员）和 Control Worker 节点（厨师）
- 每个人的任务是独立的"项目文件夹"，互不干扰

##### 为什么第二轮不接着第一轮的记忆？

这叫"短生命周期会话"：
- 如果一直保持 AI 的"记忆"，会占用大量服务器资源
- 就像餐厅不会让厨师一直站在你桌边，而是做完一道菜就去做下一桌的
- 需要的时候，从"菜单"（数据库）里恢复上下文就行

##### 为什么要用 Docker 容器？

安全隔离：
- 如果 AI 需要运行命令（如测试代码、生成图表），不能直接在服务器上执行
- Docker 容器就像一个"临时虚拟机"，AI 在里面做什么都不会影响外部
- 用完就销毁，下次再创建新的

---

### 技术版

小明是一名前端工程师，他需要为公司的支付系统设计一套高可用、可扩展、便于后续落地的架构方案。他打开 SiriusX 平台，在 Dashboard 上选择 **Architecture Advisor**，输入第一轮需求："为支付系统设计架构方案，要求高可用、可扩展"。平台立即创建一个 Task，并进入任务工作台。这个 Task 不是一次性的聊天请求，而是一个可恢复的工作空间：里面有 Agent 模板、`AGENTS.md`、技能目录、生成文档和后续多轮修改记录。

小明不知道自己连到的是哪台 API 节点，也不需要知道。SiriusX 的 API Runtime 可以水平扩容，任何一台 API 节点都只负责鉴权、创建 Task、写入持久化状态、入队 run、转发事件和查询结果。它不拥有长期 Pi session，也不拥有长期执行环境。Task 创建完成后，TaskStore 和 workspace storage 才是这个任务的事实来源。

进入 Task 页面后，小明看到任务标题、对话区、当前 run 状态和右侧产物列表。系统把他的第一条需求保存为用户消息，并创建 `run-001`，状态为 `queued`。这个 run 被写入分布式队列。某个 Control Worker 节点认领它，拿到 run lease，并获得这个 Task 的执行锁。Control Worker 从 Postgres 和 S3 构造一次性 `RunSpec`，发送给沙箱运行时。沙箱运行时在隔离环境中创建短生命周期 Pi SDK `AgentSession`，流式生成回复，并把文本、工具调用、错误和完成事件回传给控制面；控制面再推送到 ResultBus，并批量写入 TaskStore。

沙箱运行时是一次性的：Agent session、shell、解释器、浏览器和临时文件系统都在里面。它只拿短期、run-scoped 的 capability token，不持有长期密钥，也不做最终权限判断。Sandbox 在 run 结束后立即销毁，无需节点亲和性调度。这种 Stateless Sandbox 策略简化了故障恢复和负载均衡。

第一轮完成后，`run-001` 变为 `completed`，但 Task 仍然保持开放状态。小明继续输入："事件驱动太复杂了，改成 REST 同步调用"。系统创建 `run-002`，而不是复用上一轮的 Pi session。多轮连续性来自 TaskStore 中的消息、summary、run 记录、事件日志，以及 workspace 中已经生成和修改过的文件。`run-002` 可以被调度到任意 Control Worker 节点。新的 Control Worker 会从持久化状态和 workspace 的 latest committed revision 重建 Pi 上下文，而不是依赖内存里的旧 session。

如果 Control Worker 或沙箱运行时在执行过程中崩溃，run lease 会在 90 秒后过期（心跳停止）。LeaseSweeper 检测到过期 lease，将 run 重新放回队列。另一个 Control Worker 会接手，先从 TaskStore 读取 run 的事件日志、消息、task summary 和 workspace base revision，再构造新的 `RunSpec`，交给新的沙箱运行时执行。已经发给前端的事件有 run-scoped sequence，页面刷新后可以从 `afterSequence=<N>` 继续恢复。

小明再次补充："加个 Redis 缓存层，把热点数据缓存起来"。系统创建 `run-003`，继续在同一个 workspace 上迭代。每一轮 run 都有自己的状态、事件流、lease、attempt、base_workspace_revision 和错误边界。Control Worker 通过乐观锁检查 base_workspace_revision，防止并发冲突。页面只在存在 active run 时显示执行中状态；Task 本身保持开放不代表系统仍在后台执行。最终小明确认方案后点击 **Close Task**。平台先把 Task 标记为 `completed`，取消或拒绝新的 run，再异步清理该 Task 的 sandbox（如果有）。最终任务保留完整的消息、run、事件摘要、产物记录和清理状态，方便日后查看或审计。

---

## 设计目标

SiriusX 的生产形态是多节点 SaaS。API Runtime、Control Worker、ResultBus、Queue、workspace 和 sandbox runtime 都必须允许水平扩容。任何单个进程或节点的内存都不能成为事实来源。

---

## 核心原则

**🚨 P0 修正：增加安全边界优先原则**

- **安全边界优先**：Auth 和租户隔离是阶段 0 基础，所有用户态资源从 authContext 派生权限
- **仓库按信任边界拆分**：`siriusx-control-plane` 保存长期状态和控制能力，`siriusx-sandbox-runtime` 只运行一次性不可信执行
- **Postgres 是唯一事实来源**：`TaskStore` 保存 tasks、messages、runs、events、artifacts、task summary、run leases
- `Task` 是长期任务容器，表示一个用户可持续迭代的工作空间
- `Run` 是每条用户消息触发的一次执行，拥有独立状态、lease、attempt、事件流和失败边界
- **短生命周期会话**：Pi SDK `AgentSession` 是单个 run 的执行上下文，运行在沙箱运行时内，不跨节点持久化
- Control Worker 节点可以横向扩展；run 通过分布式队列、lease 和 task lock 调度，再以 `RunSpec` 派发给沙箱运行时
- **Stateless Sandbox**（阶段 0-2）：每个 run 创建全新 sandbox，用完即销毁，无节点亲和性
- 执行环境通过沙箱运行时管理；本地 Docker 只是一个 provider，不是架构边界
- 前端实时流和后端持久化解耦：实时可以细粒度，落库需要合并和批量
- **Task open ≠ run active**：前端只在存在 active run 时刷新或订阅执行状态

---

## 仓库与信任边界

SiriusX 拆成两个主要仓库：

| 仓库 | 信任级别 | 职责 |
|---|---|---|
| `siriusx-control-plane` | 可信 | Web/API、Auth、tenant、TaskStore、Queue、lease、审计、人工审批、凭证代理、workspace revision 指针 |
| `siriusx-sandbox-runtime` | 不可信/一次性 | Pi AgentSession、shell、解释器、浏览器、临时文件系统、容器/MicroVM 适配、资源限制、事件上报和销毁 |

控制面不能执行不可信 shell、解释器或浏览器；沙箱运行时不能持有长期密钥、直接做最终权限判断或直接推进 Task 状态。两者通过版本化协议通信：控制面发送 `RunSpec`，沙箱运行时回传 `SandboxEvent`、`ArtifactManifest` 和 `WorkspaceCommitProposal`。详细契约见 [仓库与信任边界](./modules/仓库与信任边界.md)。

---

## 分布式拓扑

**🚨 P1 修正：删除 sandbox_leases 表（阶段 0-2 Stateless）**

```text
Control-plane repo: siriusx-control-plane
  |
  v
agent-frontend
  |
  | HTTP / run-scoped fetch streaming
  v
API Runtime pool
  |-- TaskController
  |-- TaskService
  |-- AgentCatalog
  |-- AuthMiddleware (🆕 阶段 0)
  |
  | writes / reads
  v
Postgres TaskStore
  |-- tasks
  |-- task_messages
  |-- task_runs
  |-- task_events
  |-- task_artifacts
  |-- task_summaries
  |-- workspace_revisions
  `-- task_locks

S3 / Object Storage
  |-- workspace snapshots and revision manifests
  |-- generated artifact content
  |-- large tool outputs and debug logs
  `-- downloadable archives

Redis / Queue / ResultBus
  |-- queued run jobs
  |-- run leases / visibility timeout
  |-- session store (🆕 阶段 0)
  `-- run-scoped pubsub channels

Control Worker pool
  |-- TaskWorker / RunOrchestrator
  |-- WorkerPool
  |-- ArtifactIndexer
  |-- WorkspaceProvider
  |-- CredentialProxy
  `-- SandboxRuntimeClient

  | sends RunSpec with short-lived capability token
  v

Sandbox-runtime repo: siriusx-sandbox-runtime
  |-- PiSdkRunner
  |-- shell / interpreter / browser
  |-- temporary filesystem
  |-- LocalDockerSandboxProvider      阶段 0-2 实现
  |-- gVisor / MicroVM providers      未来扩展
  `-- event and commit proposal stream
```

**🚨 阶段 0-2 不需要 sandbox_leases 表**

---

## 状态归属

**🚨 P0/P1 修正：删除 Sandbox lease，明确 Postgres 是唯一事实来源**

| 状态 | 归属 | 说明 |
|---|---|---|
| Task metadata | Postgres TaskStore | durable |
| Messages | Postgres TaskStore | durable |
| Runs | Postgres TaskStore | durable |
| Run events | Postgres TaskStore + ResultBus | durable + realtime |
| Task summary | Postgres TaskStore | durable context compression |
| Artifacts | Postgres TaskStore + S3 | PG stores index/metadata, S3 stores content |
| Workspace files | S3-backed WorkspaceProvider | durable shared workspace |
| Workspace revisions | Postgres TaskStore + S3 | PG stores revision pointer, S3 stores manifest/blob |
| Large tool output | S3 + Postgres pointer | avoid bloating event rows |
| Run queue | Redis/BullMQ/Streams | distributed scheduling |
| Run lease | Queue + TaskStore | crash recovery |
| Task execution lock | TaskStore or Redis lock | same-task serial execution |
| **Auth session** | **Redis** | **多 API 节点共享（🆕 阶段 0）** |
| Pi AgentSession | Sandbox runtime memory | ephemeral per run |
| Capability token | Control plane issued, sandbox runtime consumed | short-lived, run-scoped |

**Sandbox 状态（阶段 0-2 Stateless）**：
- 无 `sandbox_leases` 表
- Sandbox 随 run 创建/销毁，状态仅存在于沙箱运行时内存
- Orphan 容器通过 Docker labels 扫描清理，不依赖数据库

**关键改进**：
- Postgres 是唯一事实来源，Control Worker 崩溃后新 Control Worker 只从 Postgres 恢复
- 内存缓冲（如事件缓冲）是 best-effort，不支持跨节点恢复
- Pi session 不作为 SaaS durable state，可以导出 debug artifact，但不能作为恢复任务的事实来源

---

## 落地前必须对齐的代码冲突

当前代码和本规格之间有三处必须先修正的边界冲突：

| 冲突 | 当前代码 | 目标规格 | 迁移要求 |
|---|---|---|---|
| `POST /api/task` 是否消费 prompt | 创建接口仍要求 `prompt` 字段 | 只创建 Task 和 workspace；prompt 必须走 `/message` | 改后端 DTO、前端创建流程和测试，Task 创建不得创建 run |
| Task 是否锁定 Agent 版本 | Task 只保存 `agent` 和 `model` | Task 必须固化 `agentRef`、`agentCommit`、`templateDir` | 由后端从 `AgentCatalog` 解析，客户端不能提交这些锁定字段 |
| Event 是否可精确恢复 | `TaskEvent` 无 `runId` / `sequence` | Event 必须 run-scoped，并有 run-local sequence | 写入、查询、SSE backfill、前端合流都以 `runId + sequence` 为边界 |

这三项是后续队列、Control Worker 扩容、断线恢复和审计能力的前置条件，不能推迟到后期补丁。

---

## 短生命周期会话设计

详细解释 → 参见 [短生命周期会话](./modules/短生命周期会话.md)

---

## 相关文档

- [实施计划](./IMPLEMENTATION.md) - 性能目标、容量规划、分阶段路线图
- [模块详细设计](./modules/) - 各子系统的详细技术规格
