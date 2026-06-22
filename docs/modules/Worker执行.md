# Control Worker 执行

> Control Worker 从队列认领 run，构造 `RunSpec`，并调度一次性沙箱运行时执行

---

## 执行流程

```
claim job
  -> acquire run lease
  -> acquire task execution lock
  -> update run status=running
  -> record base_workspace_revision (当前 task.latest_workspace_revision)
  -> build RunContext from Postgres durable state (🚨 P0 修正)
  -> issue run-scoped capability token
  -> build RunSpec with workspace manifest ref
  -> dispatch SandboxRuntime.execute(runSpec)
  -> consume SandboxEvent stream
  -> publish events to ResultBus
  -> buffer events for Postgres persistence
  -> persist assistant messages on agent_end
  -> validate artifact manifest and workspace commit proposal
  -> commit workspace with optimistic lock (check base_workspace_revision)
  -> index artifacts
  -> refresh task summary if policy requires it
  -> update run status=completed (or completed_with_warnings)
  -> release task execution lock
  -> complete queue job
```

---

## Workspace Revision 并发控制（乐观锁）

沙箱运行时的执行以 workspace revision 为基准。沙箱只能返回 `WorkspaceCommitProposal`；Control Worker 负责路径校验、S3/PG 两阶段提交和乐观锁推进。

### TypeScript 实现

```typescript
async function executeRun(runInput: RunInput) {
  // 1. 获取 Task 当前的 latest_workspace_revision
  const task = await taskStore.getTask(runInput.taskId);
  const baseRevision = task.latest_workspace_revision;
  
  // 2. 记录该 run 的 base_revision
  await taskStore.updateRun(runInput.runId, {
    base_workspace_revision: baseRevision,
    status: "running",
  });
  
  // 3. 读取 committed workspace manifest（不在控制面执行代码）
  const workspaceManifest = await workspaceProvider.getManifest({
    workspaceRef: task.workspaceRef,
    revision: baseRevision,
    taskId: runInput.taskId,
    runId: runInput.runId,
  });
  
  // 4. 构造一次性 RunSpec，并派发给沙箱运行时
  const runSpec = await runSpecBuilder.build({
    ...runInput,
    agent: {
      name: task.agent,
      ref: task.agentRef,
      commit: task.agentCommit,
      templateDir: task.templateDir,
    },
    baseWorkspaceRevision: baseRevision,
    workspaceManifestRef: workspaceManifest.ref,
    capabilityToken: await credentialProxy.issueRunToken({
      taskId: runInput.taskId,
      runId: runInput.runId,
      ttlMs: 5 * 60 * 1000,
    }),
  });
  
  const result = await sandboxRuntimeClient.execute(runSpec, {
    onEvent: async (event) => {
      await resultBus.publish(event);
      await eventBuffer.append(event);
    },
  });
  
  // 5. Commit workspace（带 base revision 检查）
  try {
    await artifactIndexer.index(result.artifactManifest);
    
    const newRevision = await workspaceProvider.commitProposal({
      workspaceRef: task.workspaceRef,
      proposal: result.workspaceCommitProposal,
      baseRevision, // 必须匹配当前 task.latest_workspace_revision
      taskId: runInput.taskId,
      runId: runInput.runId,
    });
    
    // 6. 原子更新 task.latest_workspace_revision（乐观锁）
    const updated = await taskStore.updateTaskWorkspaceRevision({
      taskId: runInput.taskId,
      expectedRevision: baseRevision, // WHERE latest_workspace_revision = ?
      newRevision,
    });
    
    if (!updated) {
      // 其他 run 已经推进了 revision，当前 run 冲突
      throw new WorkspaceConflictError(
        `Workspace revision conflict: expected ${baseRevision}, but was already advanced by another run`
      );
    }
    
    // 7. 记录该 run 提交的 revision
    await taskStore.updateRun(runInput.runId, {
      committed_workspace_revision: newRevision,
      status: "completed",
    });
    
  } catch (error) {
    if (error instanceof WorkspaceConflictError) {
      // 策略：标记为 failed，要求用户重新发送 prompt（推荐）
      // 自动 rebase 并重试风险高，可能改变结果
      await taskStore.updateRun(runInput.runId, {
        status: "failed",
        error: "workspace_conflict_detected_please_retry",
      });
      
      logger.warn(
        `Run ${runInput.runId} failed due to workspace conflict. ` +
        `Base revision: ${baseRevision}, current revision may have advanced.`
      );
    } else {
      throw error;
    }
  }
}
```

### SQL 实现（Postgres 乐观锁）

```sql
-- 原子更新 latest_workspace_revision（乐观锁）
UPDATE tasks
SET 
  latest_workspace_revision = $1, 
  updated_at = EXTRACT(EPOCH FROM NOW())::bigint * 1000
WHERE 
  id = $2 
  AND latest_workspace_revision = $3
RETURNING *;

-- 如果返回 0 行，说明 revision 已被其他 run 推进，当前 run 冲突
```
---

## Control Worker 崩溃恢复

**🚨 P0 修正：新 Control Worker 只能从 Postgres 恢复**

```typescript
async function recoverRun(run: TaskRun): Promise<void> {
  // 1. 检查 attempt 上限
  if (run.attempt >= MAX_ATTEMPTS) {
    await taskStore.updateRun(run.id, {
      status: 'failed',
      error: 'Max attempts exceeded',
    });
    return;
  }
  
  // 2. 只从 Postgres 读取已持久化的事件
  const events = await taskStore.getRunEvents({
    taskId: run.taskId,
    runId: run.id,
  });
  
  // 3. 如果是 completed_with_warnings，仅记录警告
  // 🚨 注意：events_backup_s3_key 未在 schema 中定义
  // 阶段 0-2 简化方案：completed_with_warnings 仅标记警告
  // 不实现 S3 backup 恢复
  if (run.status === 'completed_with_warnings') {
    logger.warn(`Run ${run.id} completed with warnings: ${run.warnings?.join(', ')}`);
  }
  
  // 4. 从 Postgres 重建上下文
  const context = await buildRunContext({
    task: await taskStore.getTask(run.taskId),
    messages: await taskStore.getMessages(run.taskId),
    summary: await taskStore.getTaskSummary(run.taskId),
    events,  // 从 Postgres 恢复
    baseWorkspaceRevision: run.base_workspace_revision,
  });
  
  // 5. 递增 attempt，重新入队；新的 executeRun 会构造新的 RunSpec
  run.attempt++;
  await taskStore.updateRun(run.id, { attempt: run.attempt });
  await queue.enqueue({ runId: run.id, attempt: run.attempt });
}
```

**关键限制**：
- Control Worker 或沙箱运行时崩溃后，内存缓冲中未持久化的事件**已丢失**
- 新 Control Worker 只能从 **Postgres** 恢复已持久化的事件
- 阶段 0-2 **不实现** S3 事件备份恢复

---

## 重试策略

**🚨 P1 修正：MAX_ATTEMPTS 和统一退避时序（对齐 STAGE0_SPEC §6.4）**

阶段 0 **不实现独立 DLQ**；超过最大重试次数后只标记 run 为 `failed`，不投递死信队列。

```typescript
const MAX_ATTEMPTS = 3;  // 首次执行记为 attempt 1，最多执行 3 次
// 统一退避延迟（与 队列与租约.md、STAGE0_SPEC §6.4 一致）
const RETRY_DELAYS_MS = [5_000, 30_000, 120_000]; // 5s, 30s, 2m

async function handleRunFailure(run: TaskRun, error: Error) {
  if (run.attempt >= MAX_ATTEMPTS) {
    // 超过最大重试次数，标记为永久失败（阶段 0 不投递 DLQ）
    await taskStore.updateRun(run.id, {
      status: 'failed',
      error: `Max attempts (${MAX_ATTEMPTS}) exceeded: ${error.message}`,
    });
    return;
  }

  // 可重试错误：递增 attempt，按统一延迟重新入队
  await queue.enqueue({
    runId: run.id,
    attempt: run.attempt + 1,
  }, {
    delay: RETRY_DELAYS_MS[run.attempt - 1] ?? RETRY_DELAYS_MS[RETRY_DELAYS_MS.length - 1],
  });
}
```

---

## 冲突场景示例

**🚨 阶段 0-2 串行策略（对齐 STAGE0_SPEC §5.5）**：同一 Task 已有 active run 时，`POST /message` 必须返回 `409 RUN_CONFLICT`，不创建 run、不入队。

1. 用户在 `run-001` 执行中再次发送消息触发 `run-002`
2. `run-001` 已开始执行，记录 `base_workspace_revision = "v10"`
3. `/message` 检测到 active run（`run-001`），**返回 `409 RUN_CONFLICT`**，不创建 `run-002`
4. 前端提示"任务执行中，请稍后重试"，用户等待 `run-001` 完成
5. `run-001` 完成，commit workspace 到 revision `"v11"`，推进 `task.latest_workspace_revision = "v11"`
6. 用户重新发送消息，创建 `run-002`，记录 `base_workspace_revision = "v11"`（最新版本）
7. `run-002` 正常完成，commit workspace 到 revision `"v12"`

> Workspace revision 冲突（多个 active run 并发改 workspace）只在阶段 3+ 引入 per-task run queue 后才可能发生；阶段 0-2 的串行策略从源头避免。
---

## 并发策略

- WorkerPool 可以并发处理多个 task
- 同一个 task 默认串行处理 run（通过 task execution lock），避免多个 Pi session 同时修改同一 workspace
- Task execution lock 保证：同一时刻只有一个 run 在修改该 task 的 workspace
- 如果未来要支持同 task 并发 run，需要 workspace branch、patch merge 或 conflict resolution，**不在当前阶段做**

---

## 错误处理

### WorkspaceConflictError

当 `updateTaskWorkspaceRevision` 返回 `updated === false` 时，表示其他 run 已经推进了 workspace revision。

**策略**：
- 将当前 run 标记为 `failed`
- 要求用户重新发送 prompt（推荐方式）
- 不自动 rebase 并重试，因为自动合并可能改变执行结果

### 可重试错误

- 网络超时
- 数据库连接失败
- S3 临时不可用

**策略**：
- 递增 `attempt`，重新入队
- 统一退避：5s, 30s, 120s（见 STAGE0_SPEC §6.4）
- 超过 `MAX_ATTEMPTS` 后标记为 `failed`（阶段 0 不实现 DLQ）

### 不可重试错误

- Pi session 执行错误（代码错误、工具调用失败）
- Workspace conflict（并发冲突）
- Agent 配置错误

**策略**：
- 立即标记为 `failed`
- 不重试，等待用户修正

---

## 相关文档

- [数据模型](./数据模型.md) - TaskRun 状态定义
- [队列和租约](./队列与租约.md) - LeaseSweeper 重入队策略
- [事件持久化](./事件持久化.md) - 内存缓冲和恢复限制
