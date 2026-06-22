# Legacy：SiriusX 分布式执行规格

> 这是旧路线中的 Stage 0 规格，定位是“分布式 SaaS 执行地基”。它不再代表新的 MVP pyramid Stage 0。

新的 Stage 0 是 [最小聊天 MVP](./stage/STAGE0_SIMPLE_CHAT.md)：一个能运行、能流式回复、能给用户即时价值的最小聊天产品。

当前实施应以 [MVP Pyramid](./stage/README.md) 和 [IMPLEMENTATION.md](./IMPLEMENTATION.md) 为准。本文件保留为 Stage 5-7 的分布式执行参考：API/Worker 拆分、共享存储、队列、租约、沙箱运行时和多节点恢复。

---

## 0. Legacy 定位

本文件描述的是旧阶段体系中的“先搭完整分布式地基”方案。这个方案在技术上仍有参考价值，但不适合作为产品起步阶段。

新旧阶段映射：

| 本文件能力 | 新 MVP pyramid 对应阶段 |
|---|---:|
| Auth、租户隔离、Agent Catalog | Stage 4 / Stage 7 |
| Redis Queue、ResultBus、API/Worker 拆分 | Stage 5 |
| S3 Workspace、artifact 大对象存储 | Stage 5 |
| Sandbox Runtime、capability token | Stage 6 |
| Run lease、LeaseSweeper、多 Worker 恢复 | Stage 7 |
| 监控、审计、部署运维 | Stage 8 |

如果本文内容与 `docs/stage/` 下的新阶段文档冲突，实施时以后者为准。

---

## 1. 旧范围

旧阶段 0 的目标是把 SiriusX 的 SaaS 执行地基收敛成可运行、可恢复、可测试的最小生产边界。它不是新的 MVP pyramid Stage 0，也不代表当前起步阶段。

### 1.1 旧阶段 0 包含

- Auth、租户隔离、CSRF、审计 actor 统一。
- 可执行 schema/migration 作为数据库唯一契约。
- Task 创建与用户 prompt 完全分离。
- 同一 Task 只允许一个 active run。
- `TaskQueue` 支持 memory 和 redis driver。
- `ResultBus` 支持 memory 和 redis driver。
- Run lease、claim/release、heartbeat、retry、cancel、close。
- Workspace Provider 支持 local 和 S3 双轨 driver。
- Run-scoped event sequence，Postgres-only 事件恢复。
- 异步批量事件落库，实时流优先。
- Run-scoped stateless sandbox，bash/shell 懒创建。
- Pi tool routing 和 Agent extension allowlist。
- Summary 与 title system background jobs。
- Artifact/file API。
- dev profile 和 distributed profile 验收。

### 1.2 旧阶段 0 不包含

- 同一 Task 的 per-task run queue。
- S3 event backup 或“不丢事件”承诺。
- 独立 `GET /stream` SSE 订阅端点。
- 独立 DLQ。
- Task-scoped sandbox pool。
- `sandbox_leases` 表、model、repository。
- 用户自定义 host extension。
- OAuth、RBAC、租户切换、分享、Webhook。
- S3 增量上传、本地 blob cache、workspace diff 视图。
- 正式 worker node registry。

---

## 2. 部署 Profile

阶段 0 必须支持两个 profile。实现、测试和文档必须明确当前 profile，不能隐式混用。

| Profile | API/Control Worker | Workspace | Queue | ResultBus | Session Store | 适用场景 |
|---|---|---|---|---|---|---|
| `dev` | 单进程或同节点 | `local` | `memory` | `memory` | `memory` | 本地开发、单进程测试 |
| `distributed` | API/Control Worker 分离 | `s3` 或 `local-shared-volume` | `redis` | `redis` | `redis` | 多进程、多 Control Worker、最小 SaaS 原型 |

### 2.1 Dev Profile Session 存储

`dev` profile 允许使用 `MemorySessionStore`，仅用于本地开发和单进程测试。

`distributed` profile 必须使用 Redis Session Store，支持多 API 节点共享 session。

实现时必须提供 `SessionStore` 接口：

```typescript
interface SessionStore {
  get(sessionId: string): Promise<Session | null>;
  set(sessionId: string, session: Session, ttl: number): Promise<void>;
  delete(sessionId: string): Promise<void>;
}
```

并实现两个 driver：
- `MemorySessionStore`（dev only）
- `RedisSessionStore`（distributed）

### 2.2 Local Workspace 拓扑限制

`local` 是一等 Workspace Provider，但它不等于”任意多 Worker 各自本地磁盘也可恢复”。

`local` 只支持：

- 单节点 API + Control Worker。
- 单节点多进程，但共享同一 POSIX 目录。
- 多节点共享卷，例如 NFS/EFS/挂载到所有 Worker 的同一路径。

`local` 不支持：

- 多 Control Worker 使用各自独立本地磁盘。
- Control Worker 崩溃后由另一台无共享目录 Control Worker materialize 上一轮 workspace。

`s3` 支持无共享磁盘的 API/Control Worker 分离部署。

---

## 3. 数据库契约

阶段 0 以可执行 schema/migration 为数据库唯一契约。TypeScript interface、模块文档、示例代码必须对齐 schema/migration；若冲突，以 schema/migration 为准。

### 3.1 Migration 要求

- 从零初始化必须可执行。
- 表创建顺序不能包含不可执行的循环外键。
- 如 `task_messages.run_id` 与 `task_runs.message_id` 互相引用，必须先建表，再用 `ALTER TABLE ADD CONSTRAINT` 添加外键。
- 所有时间戳使用 Unix milliseconds，类型为 `BIGINT`。
- 所有状态枚举必须使用数据库 `CHECK` 或等价约束。
- 必须包含必要索引，至少覆盖 task/history、run status、event run sequence、workspace revision、tenant audit 查询。

### 3.2 必需表

阶段 0 必须包含：

- `tenants`
- `users`
- `tasks`
- `task_messages`
- `task_runs`
- `task_events`
- `task_artifacts`
- `task_summaries`
- `workspace_revisions`
- `task_locks`
- `audit_logs`

阶段 0 禁止包含：

- `sandbox_leases`

### 3.3 统一字段决策

- 原始消息字段统一为 `task_messages.parts`。
- Summary 文本字段统一为 `task_summaries.summary`，不得再使用 `content`。
- Event payload 字段统一为 `task_events.payload`。
- Artifact 字段统一为 schema 中的 snake_case，API 层可转换为 camelCase。
- `actor_type` 统一为 `user | api-token | worker | system`。

---

## 4. Auth、租户、CSRF、审计

### 4.1 AuthContext

```typescript
interface AuthContext {
  userId: string;
  tenantId: string;
  email?: string;
  role?: "user" | "tenant_admin" | "admin";
  actorType: "user" | "api-token" | "worker" | "system";
  scopes: string[];
  tokenId?: string;
}
```

含义：

- `user`：浏览器 session 用户。
- `api-token`：自动化客户端。
- `worker`：Worker 使用 service credential 执行队列任务。
- `system`：后台 sweeper、GC、title generation、summary refresh 等系统任务。

### 4.2 Session Auth

- Browser 用户使用 session cookie：`siriusx.sid`。
- Session 存储支持 memory（dev profile）和 redis（distributed profile）。
- 所有用户态资源的 `userId`、`tenantId` 从 `AuthContext` 派生。
- API 不接受 body 中的 `userId`、`tenantId` 覆盖。

### 4.3 CSRF

阶段 0 采用双入口 CSRF：

- `POST /api/auth/register` 成功后返回 `csrfToken`，并设置可读 cookie `XSRF-TOKEN`。
- `POST /api/auth/login` 成功后返回 `csrfToken`，并设置可读 cookie `XSRF-TOKEN`。
- `GET /api/auth/csrf` 登录后可调用，用于刷新或补取 token。
- 所有非 `GET` / `HEAD` / `OPTIONS` 写请求必须携带 `X-XSRF-TOKEN`。
- `POST /api/auth/logout` 也必须校验 CSRF。

CSRF 错误必须区分：

- `CSRF_TOKEN_MISSING`
- `CSRF_TOKEN_INVALID`

### 4.4 授权规则

- Task owner 可读写自己的 Task。
- Tenant admin 可读写本租户 Task。
- Platform admin 可按平台策略访问。
- Workspace file 和 artifact 复用 Task read 权限，并必须经过 path guard。
- Worker 使用内部 service credential claim job，不使用浏览器 session。

### 4.5 审计

以下操作必须写审计或至少提供可审计日志：

- task create / close
- message create
- run create / cancel / fail / complete
- workspace read / commit
- artifact read / download
- summary refresh
- title generation
- GC / sweeper

---

## 5. Task 与 Run 生命周期

### 5.1 Task 创建

`POST /api/task` 只创建 Task 和 workspace，不消费 prompt，不创建 run，不创建 Pi session，不创建 sandbox。

请求体：

```json
{
  "agent": "architecture",
  "model": "claude-opus-4-8"
}
```

`title` 可选。若未提供，后端设置临时标题，例如：

- `Untitled Task`
- `<Agent Name> Task`

创建流程：

```text
derive authContext
  -> resolve AgentCatalog entry
  -> snapshot agent metadata into task
  -> create workspace through selected WorkspaceProvider
  -> create Task(status=running)
  -> return task
```

Task 创建必须锁定：

- `agent`
- `agent_ref`
- `agent_commit`
- `template_dir`
- selected `model`

客户端不能提交或覆盖这些锁定字段，除 `agent` / `model` 选择外。

### 5.2 前端首条消息流程

阶段 0 前端采用“空任务页”流程：

```text
user selects agent
  -> POST /api/task
  -> navigate to /task/:taskId
  -> task page shows empty state
  -> user manually sends first message
  -> POST /api/task/:taskId/message
```

不得使用 `sessionStorage` 作为首条 prompt 中转。

### 5.3 首条消息后生成 title

首条 user message 创建后，系统异步生成 title：

- title generation 是 system background job。
- 不创建 TaskRun。
- 不写入 conversation。
- 使用 LLM。
- 输入只包含首条 user prompt、Agent name、可选 model。
- 成功后更新 `tasks.title`。
- 失败时保留临时标题，写 warning，不影响 run。
- 审计 actorType 为 `system`。

### 5.4 Message 创建与 Run 创建

`POST /api/task/:taskId/message` 创建一轮执行。

请求体：

```json
{
  "prompt": "设计支付系统架构"
}
```

流程：

```text
validate task is open
  -> reject if active run exists
  -> create user message(parts)
  -> create TaskRun(status=queued, attempt=1)
  -> enqueue TaskTurnJob
  -> subscribe ResultBus channel for this run
  -> return fetch streaming response
```

### 5.5 同一 Task 串行策略

同一 Task 同时只允许一个 active run。

Active run 定义：

- `queued`
- `running`

如果新消息到达时已有 active run：

- 返回 HTTP `409`
- code: `RUN_CONFLICT`
- 不创建 message
- 不创建 run
- 不入队

阶段 0 不实现 per-task run queue。

#### 5.5.1 原子性实现要求

并发 `/message` 请求必须通过以下机制之一保证原子性，防止两个 queued run 同时创建：

**选项 A：数据库事务 + 条件插入**

```sql
BEGIN TRANSACTION;
-- 检查 active run
SELECT COUNT(*) FROM task_runs
WHERE task_id = ? AND status IN ('queued', 'running')
FOR UPDATE;  -- 行锁

-- 若无 active run，创建 message 和 run
INSERT INTO task_messages ...;
INSERT INTO task_runs ...;
COMMIT;
```

**选项 B：Partial Unique Index**

```sql
CREATE UNIQUE INDEX idx_task_active_run_unique
ON task_runs(task_id)
WHERE status IN ('queued', 'running');
```

此索引会在插入第二个 active run 时触发唯一约束冲突，返回 `409 RUN_CONFLICT`。

**选项 C：Task-Level Message Creation Lock**

使用 `task_locks` 表或 Redis distributed lock 保护整个 message + run 创建流程：

```typescript
await taskLock.acquire(taskId, { timeout: 5000 });
try {
  const activeRun = await checkActiveRun(taskId);
  if (activeRun) throw new RunConflictError();
  await createMessage(...);
  await createRun(...);
} finally {
  await taskLock.release(taskId);
}
```

AI 实现时必须选择其中一种机制，并在集成测试中验证并发场景。

### 5.6 Run 状态

```typescript
type TaskRunStatus =
  | "queued"
  | "running"
  | "completed"
  | "completed_with_warnings"
  | "failed"
  | "cancelled";
```

`completed_with_warnings` 只用于：

- Pi 执行成功。
- assistant message 已持久化。
- workspace commit 已成功。
- 但部分事件 flush 失败，导致事件日志不完整。

以下情况必须是 `failed`：

- assistant message 持久化失败。
- workspace commit 失败。
- Pi/tool/sandbox 执行失败且不可重试或超过重试次数。

### 5.7 Task 状态

```typescript
type TaskStatus =
  | "running"
  | "running_degraded"
  | "completed"
  | "failed"
  | "cancelled";
```

阶段 0 保留 `running_degraded` 枚举，但不自动切换。Summary refresh 失败只写 warning 和 failure counter。

---

## 6. Queue、Lease、Retry、Cancel、Close

### 6.1 Queue Driver

阶段 0 必须定义 `TaskQueue` 接口，并实现：

- `MemoryTaskQueue`
- `RedisTaskQueue`

`memory` 只用于 dev profile。`redis` 用于 distributed profile。

Queue job 至少包含：

```typescript
interface TaskTurnJob {
  type: "task_turn";
  taskId: string;
  runId: string;
  messageId: string;
}
```

System background jobs 可以使用同一 queue 的不同 job type：

```typescript
type SystemJob =
  | { type: "generate_title"; taskId: string; messageId: string }
  | { type: "refresh_summary"; taskId: string; completedRunId: string };
```

#### 6.1.1 Queue 与 Lease 职责边界

**Redis Queue 职责：**
- 仅承载 job delivery（任务投递）。
- 不是调度状态的事实来源。
- visibility timeout 只用于防止 Worker crash 后 job 永久丢失。

**Postgres Run Lease 职责：**
- `task_runs` 表的 `status`、`lease_owner_node_id`、`lease_expires_at` 是调度真相。
- Control Worker claim 前必须通过 conditional update 在 PG 中 claim run。
- 重复 job 必须幂等跳过（检查 run status）。

**防止双重重试的协议：**

```typescript
// Worker 收到 queue job 后
async function processTaskTurnJob(job: TaskTurnJob) {
  // 1. 尝试 claim run（conditional update）
  const claimed = await claimRun({
    runId: job.runId,
    expectedStatus: "queued",
    nodeId: workerNodeId,
    leaseExpiry: now + 90_000,
  });

  // 2. 若已被 claim 或状态不符，幂等跳过
  if (!claimed) {
    logger.info("Run already claimed or not queued, skipping", job);
    return; // ACK job，不重试
  }

  // 3. 执行 run
  await executeRun(job.runId);

  // 4. 释放 lease
  await releaseRun(job.runId);
}
```

**禁止的实现：**
- 同时依赖 Redis redelivery 和 PG LeaseSweeper 重新入队，导致同一 run 被重复入队。
- Worker 直接执行 job 而不先在 PG 中 claim run。

### 6.2 Run Lease

阶段 0 必须实现 run lease：

- claim run 时设置 `lease_owner_node_id`、`lease_expires_at`、`heartbeat_at`。
- heartbeat interval: `30s`。
- lease timeout: `90s`。
- Worker 执行期间持续 heartbeat。
- lease 过期后 sweeper 可重新入队。
- claim/release/extend 必须使用 conditional update，防止非 owner 修改。

### 6.3 Task Lock

即使 API 层已经阻止同 Task active run，Control Worker 仍必须使用 task execution lock 作为后端保护。

- 同一时刻同一 Task 只能有一个 Control Worker 执行 run。
- lock 必须有 owner 和 expiry。
- Control Worker 崩溃后 lock 可过期释放。

### 6.4 Retry

阶段 0 统一重试策略：

- `MAX_ATTEMPTS = 3`
- retry delay: `5s`, `30s`, `120s`
- jitter 可选
- 阶段 0 不实现独立 DLQ
- 超过最大次数后 run `failed`

可重试错误：

- Worker crash / lease timeout
- 临时 DB 错误
- 临时 Redis 错误
- 临时 S3/object storage 错误
- Sandbox create/exec timeout
- ResultBus 临时失败
- Workspace materialize 临时失败

不可重试错误：

- Auth/permission failure
- invalid model
- Agent/template missing
- prompt validation failure
- path guard violation
- workspace optimistic conflict
- deterministic Pi auth/model config failure

### 6.5 Cancel Run

`POST /api/task/:taskId/runs/:runId/cancel`

允许取消：

- `queued`
- `running`

语义：

- `queued`：标记 run 为 `cancelled`；如果 queue 无法删除 job，Control Worker claim 前必须检查 run 状态并跳过。
- `running`：设置 cancel requested 状态或直接 conditional update；Worker event loop/heartbeat loop 检测后 abort Pi session。
- sandbox exec 必须支持 `AbortSignal` 或等价中断。
- run 结束时销毁 sandbox。
- 发布 `run_cancelled` 事件。
- 完成与取消竞态通过 conditional update 决定，先成功者生效。

非 active run cancel 返回：

- HTTP `409`
- code: `RUN_NOT_ACTIVE`

### 6.6 Close Task

`POST /api/task/:taskId/close`

规则：

- 只有 task owner、tenant admin 或具备 task write scope 的 actor 可操作。
- 如果没有 active run：task status -> `completed`。
- 如果存在 queued run：先 cancel queued run，再 close。
- 如果存在 running run：返回 HTTP `409`，code: `RUN_ACTIVE`。用户必须先 cancel run。
- close 后拒绝新的 `/message`，返回 `TASK_CLOSED`。
- close 不删除 messages、runs、events、workspace、artifacts。
- close 可触发 best-effort resource cleanup。

---

## 7. ResultBus 与事件持久化

### 7.1 ResultBus Driver

阶段 0 必须定义 `ResultBus` 接口，并实现：

- `MemoryResultBus`
- `RedisResultBus`

`memory` 只用于 API + Control Worker 同进程。`redis` 用于 API/Control Worker 分离或多节点。

Channel 必须 run-scoped：

```text
task:{taskId}:run:{runId}
```

### 7.2 Fetch Streaming

`POST /api/task/:taskId/message` 返回 fetch streaming response，不使用 EventSource。

事件格式：

```text
data: {"type":"run_started","sequence":1,"payload":{"runId":"run_123"}}

data: {"type":"assistant_delta","sequence":2,"payload":{"delta":"hello"}}
```

每个事件使用统一 envelope：

```typescript
interface TaskEventEnvelope {
  id?: string;
  taskId: string;
  runId: string;
  sequence: number;
  type: TaskEventType;
  payload: unknown;
  createdAt: number;
}
```

Streaming response 可以省略 `id/taskId/runId/createdAt`，但持久化事件必须完整保存。

### 7.3 事件类型

阶段 0 事件类型统一为：

```typescript
type TaskEventType =
  | "run_started"
  | "assistant_delta"
  | "thinking_delta"
  | "tool_start"
  | "tool_update"
  | "tool_end"
  | "turn_complete"
  | "error"
  | "run_cancelled";
```

禁止使用 `task_error`。

### 7.4 Sequence

- `sequence` 是 run-scoped。
- 每个 run 从 1 开始。
- `(task_id, run_id, sequence)` 必须唯一。
- 查询按 `sequence ASC`。
- 恢复主路径使用 `afterSequence`。

#### 7.4.1 Sequence 分配机制

Event sequence 必须由 Postgres `task_runs.last_event_sequence` 原子分配：

```typescript
// Worker 发布事件前原子递增
const { sequence } = await db.query(`
  UPDATE task_runs
  SET last_event_sequence = last_event_sequence + 1
  WHERE run_id = ?
  RETURNING last_event_sequence AS sequence
`);

// 使用分配的 sequence 发布事件
await resultBus.publish({ ...event, sequence });
```

**崩溃恢复语义：**

- Control Worker 崩溃后，已分配但未发布/未落库的 sequence 会形成 gap（跳号）。
- 这是允许的，客户端不得把 sequence 连续性当作事件完整性保证。
- `GET events?afterSequence=N` 返回 `sequence > N` 的所有已持久化事件，gap 不影响语义。
- 事件完整性只能通过 run status 判断：`completed` 才保证事件流完整。

**禁止的实现：**

- 内存计数器：崩溃后无法恢复，导致 sequence 重复。
- 批量预留：增加 gap 范围，且无法保证 run 跨 Worker 时的全局递增。

### 7.5 写入时序

阶段 0 采用实时优先：

```text
Pi event
  -> assign run-scoped sequence
  -> publish to ResultBus
  -> append to Worker memory buffer
  -> async batch flush to Postgres
```

Flush 策略：

- interval: `100ms`
- max batch size: `50 events`
- 参数可配置
- `turn_complete` 前必须强制 flush 当前 run pending events

### 7.6 恢复保证

Postgres 是唯一可恢复事件源。

阶段 0 不实现：

- S3 event backup
- durable event WAL
- 不丢事件保证

如果 Control Worker 崩溃：

- 已发布到前端但尚未写入 Postgres 的事件允许丢失。
- 新 Control Worker 只能从 Postgres 恢复已持久化事件。
- 前端只能通过 `GET events?afterSequence=` 补齐已持久化事件。

### 7.7 事件 flush 失败

- flush 失败重试 3 次。
- 仍失败时，如果 assistant message 和 workspace commit 已成功，run 标记为 `completed_with_warnings`。
- warning 至少包含 `event_persistence_incomplete`。
- UI 必须提示事件记录可能不完整。

---

## 8. Workspace Provider

### 8.1 统一接口

```typescript
interface WorkspaceProvider {
  create(input: {
    tenantId: string;
    taskId: string;
    templateDir: string;
  }): Promise<{ workspaceRef: string; revision: string }>;

  materialize(input: {
    workspaceRef: string;
    revision: string;
    taskId: string;
    runId: string;
  }): Promise<{ workspaceDir: string; baseRevision: string }>;

  commit(input: {
    workspaceRef: string;
    workspaceDir: string;
    taskId: string;
    runId: string;
    baseRevision: string;
  }): Promise<{ workspaceRef: string; revision: string }>;
}
```

### 8.2 Driver

阶段 0 必须支持：

- `LocalWorkspaceProvider`
- `S3WorkspaceProvider`

两者都必须通过同一套 contract tests：

- `create`
- `materialize`
- `commit`
- revision pointer
- path guard
- artifact indexing
- repeated materialize after commit

### 8.3 Revision

- `tasks.latest_workspace_revision` 只能指向 committed revision。
- `workspace_revisions.status` 为 `pending | uploading | committed | failed`。
- `commit()` 必须创建新 revision，并以乐观锁推进 latest pointer。
- Worker materialize 时必须检查 revision 为 committed。
- Worker run 记录：
  - `base_workspace_revision`
  - `committed_workspace_revision`

#### 8.3.1 Commit 与 Revision 推进职责

**WorkspaceProvider.commit() 职责：**

```typescript
async commit(input: CommitInput): Promise<CommitResult> {
  // 1. 上传 workspace 到存储层（local copy 或 S3 upload）
  const newRevision = await uploadWorkspace(input.workspaceDir);

  // 2. 在 PG 中创建 workspace_revisions 记录
  await db.insert("workspace_revisions", {
    revision: newRevision,
    taskId: input.taskId,
    runId: input.runId,
    status: "committed",
    createdAt: Date.now(),
  });

  // 3. 以乐观锁推进 tasks.latest_workspace_revision
  const updated = await db.query(`
    UPDATE tasks
    SET latest_workspace_revision = ?
    WHERE task_id = ? AND latest_workspace_revision = ?
  `, [newRevision, input.taskId, input.baseRevision]);

  if (!updated) {
    throw new WorkspaceConflictError("Optimistic lock failed");
  }

  return { workspaceRef: input.workspaceRef, revision: newRevision };
}
```

**职责边界：**
- `WorkspaceProvider.commit()` 内部拥有 `TaskStore` 依赖（通过构造函数注入或配置传入）。
- Worker 只需调用 `workspaceProvider.commit()`，不需要手动写 PG。
- 上传 workspace、创建 revision、推进 pointer 必须在同一事务或补偿逻辑中完成。

**禁止的实现：**
- Worker 先调用 `workspaceProvider.upload()`，再手动调用 `taskStore.updateRevision()`，导致职责分散。
- `commit()` 不创建 revision 记录，只上传文件，由外部调用者推进 pointer。

### 8.4 S3 Provider

S3 key 必须包含 tenant/task 前缀：

```text
tenants/<tenantId>/tasks/<taskId>/workspace/revisions/<revision>/manifest.json
tenants/<tenantId>/tasks/<taskId>/workspace/blobs/<sha256>
tenants/<tenantId>/tasks/<taskId>/artifacts/<revision>/<path>
```

阶段 0 S3 使用全量上传/下载即可，不实现增量优化。

### 8.5 Path Guard

Workspace 和 file API 必须拒绝：

- 绝对路径
- `../`
- 反斜杠 escape
- symlink escape
- 隐藏系统目录越权访问

---

## 9. Sandbox 与 Pi Tool Routing

### 9.1 Sandbox 策略

阶段 0 采用 run-scoped stateless sandbox：

- 不落库。
- 不实现 `sandbox_leases`。
- 首次 bash/shell 工具调用时懒创建。
- 同一 run 内复用同一个 sandbox。
- run 结束后 best-effort destroy。
- orphan sweep 通过 Docker labels 清理。
- sandbox 挂载当前 run materialized workspace dir。

### 9.2 Pi 运行位置

阶段 0：

- Pi AgentSession 在 `siriusx-sandbox-runtime` 的一次性 sandbox 内运行。
- Control Worker 只构造 `RunSpec`、维护 lease、持久化事件和推进 workspace revision。
- bash/shell、解释器、浏览器和 Agent extension 禁止直接在 Control Worker 所在宿主执行。
- 沙箱运行时只接收 run-scoped 短期 capability token，不持有长期数据库、S3 或用户凭证。

### 9.3 Agent Extension 策略

默认禁用 Agent repo 自带 extension。

允许的工具必须由 AgentCatalog 显式 allowlist，并声明执行位置：

- `host-safe`
- `sandboxed`

bash/shell 只能是 `sandboxed`。

阶段 0 不支持用户自定义 host extension。

---

## 10. Summary 与 Title Background Jobs

### 10.1 原始对话

原始对话必须完整保存：

- `task_messages.parts` 是事实来源。
- 生成 summary 不得删除、截断或覆盖原始消息。
- LLM 可在需要时参考原始消息。

### 10.2 Run 上下文

每个 run 构建上下文时使用：

```text
last successful task summary
  + recent N messages
  + artifact manifest
  + current user prompt
```

如果没有 summary，则使用空 summary。

### 10.3 Summary Refresh

阶段 0 必须实现 summary refresh：

- 每个 run 完成后触发一次异步 refresh。
- refresh 是 system background job。
- 不创建 TaskRun。
- 不写入 conversation。
- 成功 upsert `task_summaries`。
- 失败增加 `consecutive_failures`，写 warning，不阻塞用户。
- 不自动切换 task 到 `running_degraded`。

#### 10.3.1 Summary Refresh 输入

原始消息完整保存在 `task_messages.parts`，但 summary refresh 不能全量读入，否则长任务会不可执行。

**输入规范：**

```typescript
interface SummaryRefreshInput {
  taskId: string;
  completedRunId: string;
  previousSummary: string | null; // 上一版 summary
  recentMessages: Array<{
    role: "user" | "assistant";
    parts: Array<{ type: "text"; text: string }>;
    createdAt: number;
  }>; // 自上次 summary 后的新消息
  artifactManifest: Array<{
    name: string;
    path: string;
    mimeType: string;
    size: number;
  }>;
  completedRunInfo: {
    status: "completed" | "completed_with_warnings";
    duration: number;
    eventCount: number;
  };
}
```

**消息窗口策略：**

- 如果是首次 summary（无 `previousSummary`），读取全部消息，但最多 50 条。
- 如果已有 summary，读取 `updated_at_run_count` 之后的消息，最多 20 条。
- 如果单条消息超过 10K tokens，截断为前 5K + 后 1K，中间插入 `[... truncated ...]`。

**必要时分页/截断：**

```typescript
async function getSummaryRefreshInput(
  taskId: string,
  completedRunId: string
): Promise<SummaryRefreshInput> {
  const prevSummary = await getLatestSummary(taskId);
  const lastRunCount = prevSummary?.updated_at_run_count ?? 0;

  const recentMessages = await db.query(`
    SELECT role, parts, created_at
    FROM task_messages
    WHERE task_id = ? AND run_count > ?
    ORDER BY created_at ASC
    LIMIT ?
  `, [taskId, lastRunCount, prevSummary ? 20 : 50]);

  // 截断过长消息
  const truncated = recentMessages.map(truncateMessage);

  return {
    taskId,
    completedRunId,
    previousSummary: prevSummary?.summary ?? null,
    recentMessages: truncated,
    artifactManifest: await getArtifactManifest(taskId),
    completedRunInfo: await getRunInfo(completedRunId),
  };
}
```

**禁止的实现：**
- 全量读取所有消息，导致长任务 OOM。
- 每次从头重新生成 summary，忽略 `previousSummary`。

### 10.4 Summary 字段

`task_summaries` 至少包含：

- `task_id`
- `summary`
- `run_count`
- `token_count`
- `artifact_count`
- `updated_at_run_count`
- `consecutive_failures`
- `last_successful_run_id`
- `created_at`
- `updated_at`

### 10.5 Title Generation

见 [5.3 首条消息后生成 title](#53-首条消息后生成-title)。

---

## 11. Artifact 与 File API

### 11.1 Artifact Index

Control Worker 校验沙箱运行时返回的 artifact manifest 和 workspace commit proposal 后，必须更新 artifact index。

Artifact index 存在 Postgres，文件内容存在 workspace/object storage。

### 11.2 API

阶段 0 定义三类 API。

#### GET /api/task/:taskId/artifacts

读取 PG artifact index，用于右侧产物列表。

响应格式：

```json
{
  "artifacts": [
    {
      "id": "artifact_123",
      "taskId": "task_123",
      "name": "architecture.md",
      "path": "docs/architecture.md",
      "mimeType": "text/markdown",
      "size": 2048,
      "createdAt": 1718100000000,
      "revision": "rev_456"
    }
  ]
}
```

#### GET /api/task/:taskId/files?path=<path>&depth=<n>

读取当前 committed workspace manifest，懒加载文件树。

查询参数：
- `path`（可选）：目录路径，默认为根目录 `/`
- `depth`（可选）：递归深度，默认 `1`

响应格式：

```json
{
  "path": "/",
  "entries": [
    { "name": "src", "type": "directory", "size": 0 },
    { "name": "README.md", "type": "file", "size": 1024 }
  ]
}
```

#### GET /api/task/:taskId/files/content?path=<path>

读取文件内容。使用 query 参数避免 `:path` 捕获 slash 的路由歧义。

查询参数：
- `path`（必需）：文件相对路径

响应：
- `Content-Type` 根据文件 MIME type 设置
- Body 为文件原始内容

错误：
- `400 PATH_TRAVERSAL`：path guard 拒绝
- `404 FILE_NOT_FOUND`：文件不存在
- `403 ACCESS_DENIED`：无 Task read 权限

#### GET /api/task/:taskId/runs/:runId/events

恢复接口，用于客户端断线重连后补齐已持久化事件。

查询参数：
- `afterSequence`（可选）：返回 `sequence > afterSequence` 的事件，默认 `0`（返回全部）
- `limit`（可选）：分页限制，默认 `100`，最大 `1000`

响应格式：

```json
{
  "events": [
    {
      "id": "evt_123",
      "taskId": "task_123",
      "runId": "run_456",
      "sequence": 5,
      "type": "assistant_delta",
      "payload": { "delta": "hello" },
      "createdAt": 1718100000000
    }
  ],
  "hasMore": false
}
```

权限：
- 必须校验 `runId` 属于 `taskId`
- 必须校验调用者对 `taskId` 有 read 权限

### 11.3 权限和安全

所有 artifact/file API 必须：

- 校验 Task read 权限。
- 使用 path guard。
- 不暴露本地绝对路径。
- 不允许浏览器直接拼接内部 S3 key 作为权限边界。

---

## 12. 错误码

阶段 0 统一错误格式：

```json
{
  "statusCode": 409,
  "code": "RUN_CONFLICT",
  "message": "A run is already active for this task",
  "timestamp": 1718100000000,
  "path": "/api/task/task_123/message"
}
```

### 12.1 状态冲突使用 409

| 场景 | HTTP | Code |
|---|---:|---|
| 新消息但已有 active run | 409 | `RUN_CONFLICT` |
| close task 但有 running run | 409 | `RUN_ACTIVE` |
| cancel 非 active run | 409 | `RUN_NOT_ACTIVE` |
| task 已关闭后继续发消息 | 409 | `TASK_CLOSED` |
| workspace optimistic conflict | 409 | `WORKSPACE_CONFLICT` |

### 12.2 Auth / CSRF

| 场景 | HTTP | Code |
|---|---:|---|
| 未登录 | 401 | `AUTH_REQUIRED` |
| session 过期 | 401 | `AUTH_SESSION_EXPIRED` |
| 无权限 | 403 | `ACCESS_DENIED` |
| CSRF 缺失 | 403 | `CSRF_TOKEN_MISSING` |
| CSRF 无效 | 403 | `CSRF_TOKEN_INVALID` |

### 12.3 Validation

| 场景 | HTTP | Code |
|---|---:|---|
| prompt 为空 | 400 | `PROMPT_EMPTY` |
| agent 不存在 | 404 | `AGENT_NOT_FOUND` |
| model 不支持 | 400 | `INVALID_MODEL` |
| path guard 拒绝 | 400 | `PATH_TRAVERSAL` |

---

## 13. 验收测试

### 13.1 Dev Profile

必须验证：

- register/login/csrf/logout。
- create task 不创建 run。
- task detail 空状态。
- 手动发送首条 message 后创建 run。
- 同 task active run 冲突返回 `RUN_CONFLICT`。
- fetch streaming 收到 run-scoped events。
- run complete 后 assistant message 持久化。
- summary refresh job 被触发。
- title generation job 更新临时标题。
- local workspace create/materialize/commit。
- bash/shell 首次调用懒创建 sandbox。
- run 结束销毁 sandbox。

### 13.2 Distributed Profile

必须验证：

- API 与 Worker 分离时，Redis queue 可投递 run。
- Redis ResultBus 可把 Worker events 转发给 API stream。
- Run lease heartbeat 正常。
- Worker crash 后 lease 过期，run 可重试。
- S3 workspace 或 local shared volume 能被另一个 Worker materialize。
- `GET events?afterSequence=` 只能补齐 PG 已持久化事件。
- close running task 返回 `RUN_ACTIVE`。
- cancel running run 发布 `run_cancelled`。

### 13.3 Contract Tests

必须有：

- WorkspaceProvider contract tests。
- TaskStore schema/migration smoke test。
- Queue driver contract tests。
- ResultBus driver contract tests。
- Auth tenant isolation tests。
- Path guard tests。
- Event sequence ordering tests。

---

## 14. 旧文档定点修正清单

后续同步旧文档时，优先修正以下冲突。

### 14.1 必须改

- `control-plane/Worker执行.md`：删除“run-002 进入队列等待”示例，改为 active run 时 `409 RUN_CONFLICT`。
- `sandbox-runtime/PiSDK运行器.md`：把 `task_error` 改为 `error`。
- `control-plane/事件持久化.md`：删除流程图中的 `S3 Backup` 阶段 0 暗示，明确 PG-only 恢复。
- `control-plane/存储模块.md`：把 `workspace_ref 阶段 3+` 改为阶段 0 契约，并说明 local/S3 双轨。
- `schema.sql`：修复循环外键，补齐 actor type、summary 字段、可执行初始化。
- `control-plane/Auth实现详解.md`：补齐 `/api/auth/csrf`，register/login 返回 `csrfToken`，统一 actor type。
- `UIUX.md`：`POST /message` body 改为 `prompt`，删除 `sessionStorage` 首条 prompt 中转流程。
- `control-plane/上下文优化.md`：字段名 `content` 改为 `summary`，刷新策略改为每 run 后异步、不阻塞。
- `control-plane/API端点.md`：补齐 `GET /artifacts`、`GET /files/content?path=`、`RUN_ACTIVE`、409 状态冲突。

### 14.2 标记为 future/backlog

- per-task run queue。
- S3 event backup。
- independent SSE stream endpoint。
- DLQ。
- sandbox pool / sandbox lease。
- incremental S3 upload/cache。
- OAuth/RBAC/tenant switching/share/webhook。

---

## 15. 执行原则

阶段 0 实施时，AI 必须优先遵守：

1. 不从旧文档推断与本文冲突的行为。
2. 不实现本文明确列为 non-scope 的能力。
3. 数据库以可执行 migration 为唯一契约。
4. 所有跨进程能力必须能在 distributed profile 下验证。
5. 所有实时事件恢复说明必须承认 PG-only 的可靠性边界。
