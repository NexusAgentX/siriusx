# SiriusX 平台实施计划

> 分阶段实施路线图、性能目标和容量规划

---

## 目录

- [性能目标和容量规划](#性能目标和容量规划)
- [实施优先级](#实施优先级)
- [最小可行原型验证](#最小可行原型验证)
- [当前阶段不做的事](#当前阶段不做的事)

---

## 性能目标和容量规划

### 目标负载

| 指标 | 目标值 |
|---|---|
| 并发 task 数 | 100-500 |
| 单 task run 频率 | 5-10 runs/小时 |
| 单 run 平均时长 | 5-10 分钟 |
| 事件流吞吐（峰值） | 1000 events/秒 |

### 资源估算

| 资源 | 配置 | 说明 |
|---|---|---|
| API 节点 | 2-4 实例<br/>2 vCPU / 4 GB RAM | 处理 HTTP 请求、SSE 流 |
| Control Worker 节点 | 4-8 实例<br/>4 vCPU / 8 GB RAM | 认领 run、维护 lease、构造 `RunSpec`、持久化事件 |
| Sandbox Runtime 节点 | 按需扩缩<br/>4 vCPU / 8 GB RAM 起 | 执行 Pi session、shell、解释器、浏览器和临时文件系统 |
| Postgres | RDS db.t3.medium<br/>2 vCPU / 4 GB | 持久化状态 |
| Redis | ElastiCache cache.t3.small<br/>2 GB | 队列 + ResultBus |
| S3 | 100 GB/月增长 | Workspace + Artifacts |

### 成本估算（AWS us-east-1）

| 项目 | 月成本 |
|---|---|
| EC2 实例 | $200-400 |
| RDS Postgres | $100 |
| ElastiCache Redis | $50 |
| S3 存储 | $10（初期） |
| **总计** | **$360-560** |

### 关键指标（监控和告警）

**🚨 P2 修正：明确指标口径**

| 指标 | 目标值 | 告警阈值 | 说明 |
|---|---|---|---|
| Queue wait latency (p95) | < 60s | > 120s | 从 enqueue 到 Control Worker claim |
| Run execution time (p50) | 5-10 min | - | 从 claim 到 complete |
| Run execution time (p95) | < 15 min | > 20 min | 包含所有 Pi session 执行 |
| End-to-end latency (p95) | < 16 min | > 21 min | queue wait + execution |
| Event persistence lag | < 5s | > 10s | 实时流 vs 数据库延迟 |
| Sandbox creation success rate | > 95% | < 90% | - |
| Workspace commit success rate | > 99% | < 95% | - |
| Queue length | - | > 100 | queued runs 数量 |
| Run lease expiration rate | - | > 5% | 因心跳停止而过期的比例 |

---

## 实施优先级

### 阶段 0：基础设施修正（3-4 周）

修正架构边界冲突，为多节点部署做准备。**阶段 0 包含仓库信任边界和 Auth，这是安全边界的基础。**

#### 0. 🎯 仓库与信任边界（P0 - 必须先定）

**目标**：按信任边界拆成 `siriusx-control-plane` 和 `siriusx-sandbox-runtime`

**为什么放在阶段 0**：
- 长期密钥、权限判断、审计和人工审批必须留在可信控制面
- Agent session、shell、解释器、浏览器和临时文件系统必须进入一次性沙箱运行时
- 后续 Control Worker、Sandbox、Pi SDK 和部署文档都依赖这条边界

**实施清单**：

- [ ] 定义 `RunSpec`、`SandboxEvent`、`ArtifactManifest`、`WorkspaceCommitProposal` 版本化协议
- [ ] 控制面只通过 `SandboxRuntimeClient` 调用沙箱运行时，不直接执行不可信 shell/browser/interpreter
- [ ] 沙箱运行时只接收 run-scoped 短期 capability token，不持有数据库、S3 或用户凭证主密钥
- [ ] 控制面负责最终权限判断、路径 guard、事件持久化和 workspace revision 推进
- [ ] 本地 Docker Compose 可以同时启动两个服务，但必须保留网络、环境变量和凭证边界

#### 1. 🎯 Auth 和租户边界（P0 - 必须最先完成）

**目标**：建立安全边界，所有用户态资源从 authContext 派生权限

**为什么放在阶段 0**：
- Task、workspace、S3 key、artifact 设计都依赖租户隔离
- 没有 Auth，最小原型无法验证多租户安全性
- 企业级 SaaS 的鉴权、tenant、path guard 是基础设施，不是功能特性

**实施清单**：

- [ ] **Session-based Auth**
  - 实现简单登录（email + password，OAuth 留到后期）
  - Session 存储在 Redis（支持多 API 节点共享）
  - Session 结构：`{ userId, tenantId, email, createdAt, expiresAt }`
  
- [ ] **AuthContext 中间件**
  ```typescript
  interface AuthContext {
    userId: string;
    tenantId: string;
    actorType: "user" | "api-token";
    scopes: string[];
  }
  
  // 所有 API 端点从 req.authContext 读取，不接受 body.userId
  app.use(authMiddleware); // 从 session/token 派生 authContext
  ```

- [ ] **租户隔离验证**
  - Task 创建时自动设置 `tenantId` 和 `userId` 来自 `req.authContext`
  - S3 key 必须包含 `tenantId` 前缀：`s3://bucket/tenants/<tenantId>/tasks/<taskId>/...`
  - TaskStore 所有写入操作记录 `actorUserId` / `actorType`（审计）
  
- [ ] **授权规则**
  - Task owner 可读写
  - Tenant admin 可读写租户内所有 Task
  - Workspace file / artifact 复用 Task read 权限，并经过 path guard

- [ ] **API 端点改造**
  - `POST /api/task` 不接受 `body.userId`，从 `req.authContext` 读取
  - `GET /api/task/:taskId` 检查当前用户是否有权限
  - 所有 S3 presigned URL 生成前检查权限

#### 2. 🎯 Event runId/sequence 改造

**目标**：支持 run-scoped 事件序列和断线恢复

- [ ] 增加 `task_runs.last_event_sequence` 字段
- [ ] 增加 `task_events(task_id, run_id, sequence)` 唯一约束
- [ ] 实现 `appendEvents()` 批量写入
- [ ] **明确本地 WAL 是 best-effort**（见下方）
- [ ] 增加 run-scoped event 查询接口
  ```
  GET /api/task/:taskId/runs/:runId/events?afterSequence=<N>
  ```

**🚨 P0 修正：本地 WAL 不支持跨节点恢复**

```typescript
// 明确定义：本地 WAL 仅用于同一 Control Worker 进程内的短期缓存
// Control Worker 崩溃后，新 Control Worker 只能从 Postgres 已持久化的事件恢复

class EventPersistenceService {
  private localWAL: Map<string, Event[]> = new Map(); // 内存中，不跨节点
  
  async appendEvents(runId: string, events: Event[]) {
    // 1. 先写本地 WAL（best-effort，同进程内防丢失）
    this.localWAL.set(runId, [...(this.localWAL.get(runId) || []), ...events]);
    
    try {
      // 2. 批量写入 Postgres（事实来源）
      await this.taskStore.appendEvents(runId, events);
      
      // 3. 成功后清理本地 WAL
      this.localWAL.delete(runId);
    } catch (error) {
      // 4. 持久化失败：标记 run 为 completed_with_warnings
      // 本地 WAL 保留，等待重试或人工介入
      logger.error(`Event persistence failed for run ${runId}`, error);
      throw error;
    }
  }
  
  // Control Worker 崩溃后，新 Control Worker 只能从 Postgres 恢复
  async recoverRun(runId: string): Promise<Event[]> {
    return await this.taskStore.getRunEvents(runId); // 只从 PG 读取
  }
}
```

#### 3. 🎯 Task 创建分离 prompt

**目标**：Task 创建不再消费用户 prompt

- [ ] `POST /api/task` 只创建 Task 和 workspace，不创建 run
- [ ] 前端改为创建后立即调用 `POST /api/task/:taskId/message`
- [ ] 更新 API 测试和文档

#### 4. 🎯 Task 锁定 Agent 版本

**目标**：确保 Task 执行一致性

- [ ] 使用现有 `tasks.agent`、`agent_ref`、`agent_commit`、`template_dir` 字段锁定版本
- [ ] Agent Catalog 支持版本管理
- [ ] Task 创建时从 AgentCatalog 快照 Agent 版本
- [ ] `agent_ref` 存储 Git ref 或版本标识（如 `v1.0.0` 或 `main`）
- [ ] `agent_commit` 存储 Git commit hash（用于精确版本锁定）

#### 5. 🎯 Workspace revision 两阶段提交

**目标**：Postgres + S3 一致性保证

- [ ] 增加 `workspace_revisions.status` 字段（pending / uploading / committed / failed）
- [ ] 增加 `workspace_revisions.expires_at` 和 `committed_at` 字段
- [ ] 实现 PG 先行 + S3 上传 + 状态推进流程
- [ ] 实现 Storage GC 策略
  - 每小时扫描过期的 pending/uploading revision
  - 每日清理失败 revision 的 S3 对象（7 天保留期）
  - 每周清理 orphan blobs（30 天保留期）

#### 6. 🎯 Workspace revision 并发控制

**目标**：防止并发修改冲突

- [ ] 增加 `task_runs.base_workspace_revision` 和 `committed_workspace_revision` 字段
- [ ] 实现乐观锁
  ```sql
  UPDATE tasks 
  SET latest_workspace_revision = ? 
  WHERE id = ? AND latest_workspace_revision = ?
  ```
- [ ] 实现 WorkspaceConflictError 处理

#### 7. 🎯 S3 Workspace Provider 基础实现

**目标**：支持多 Control Worker 节点无状态访问 workspace

**🚨 为什么必须在阶段 0**：
- 多 Control Worker 节点不能依赖本地磁盘（参见 [工作区提供器.md](./control-plane/工作区提供器.md)）
- 阶段 1 要求 2+ Control Worker 并发处理，必须先有共享存储
- 本地 workspace 只能用于单节点开发环境

**实施清单（简化版）**：

- [ ] 实现 `S3WorkspaceProvider` 基础功能
  - `create()`：复制 Agent template 到 S3
  - `materialize()`：从 S3 下载 manifest 和 blobs 到本地临时目录
  - `commit()`：上传变更到 S3，推进 PG revision pointer
  
- [ ] 实现 manifest 和 blob 管理
  - Manifest 格式：`{ files: { [path]: { hash, size } } }`
  - Blob 存储：`s3://bucket/tenants/<tenantId>/tasks/<taskId>/workspace/blobs/<hash>`
  
- [ ] 实现 read-after-write 一致性检查
  - S3 强一致性保证（2020 年后）
  - 上传后立即验证 HEAD 请求

**阶段 0 不实现的优化**（留到阶段 3）：
- 增量上传（只上传变更的 blobs）
- 本地缓存（避免重复下载）
- 并行上传/下载

---

### 阶段 1：队列和 Control Worker 扩容（2-3 周）

**前置条件**：阶段 0 的 S3 Workspace Provider 已完成

支持 2+ Control Worker 节点并发处理多个 task。

#### 1. 🎯 Redis Queue 集成

- [ ] 使用 BullMQ 或 Redis Streams
- [ ] 实现 `TaskQueue` 接口
- [ ] 实现队列监控指标

#### 2. 🎯 Run Lease 管理

- [ ] 实现 `RunLeaseManager` 独立心跳线程
- [ ] lease 过期时间：90s
- [ ] 心跳间隔：30s
- [ ] `task_runs.lease_owner_node_id` 字段
- [ ] `task_runs.lease_expires_at` 字段
- [ ] 实现 `LeaseSweeper`（每分钟检测过期 lease）

#### 3. 🎯 Task Summary 异步刷新（后台 job，不阻塞 run）

- [ ] 每个 run 完成后触发一次异步 refresh（system background job）
- [ ] 实现 §10.3.1 输入窗口策略（首次最多 50 条，后续最多 20 条）
- [ ] 失败递增 `consecutive_failures` 并写 warning（**不**自动切换 `running_degraded`）
- [ ] LLM 生成 summary
- [ ] 实现前端手动刷新按钮（可选）

---

### 阶段 2：Stateless Sandbox（3-4 周）

每个 run 独立创建 sandbox，避免节点亲和性复杂度。

#### 1. 🎯 Stateless Sandbox Provider（🚨 P1 修正）

**目标**：完全 Stateless，删除 sandbox_leases 表

**为什么 Stateless**：
- 简化架构，无需节点亲和性调度
- Control Worker 崩溃后任意 Control Worker 可接手（无 sandbox 状态依赖）
- Sandbox 创建开销 < 2%，性能影响可接受

**实施清单**：

- [ ] 实现 `LocalDockerSandboxProvider`
  - `create()`：创建全新 Docker 容器，挂载 workspace
  - `exec()`：执行命令
  - `destroy()`：立即销毁容器
  
- [ ] 每次 run 创建全新容器
  ```typescript
  async executeRun(run: TaskRun) {
    let sandbox: Sandbox | null = null;
    
    try {
      // 只在需要执行 bash/shell 时创建
      if (needsSandbox(run)) {
        sandbox = await sandboxProvider.create({
          taskId: run.taskId,
          runId: run.id,
          workspaceRef: run.base_workspace_revision,
        });
      }
      
      await piRunner.execute(run, sandbox);
    } finally {
      // run 结束后立即销毁
      if (sandbox) {
        await sandboxProvider.destroy(sandbox.id);
      }
    }
  }
  ```

- [ ] **不实现 `sandbox_leases` 表**（schema、model、repository 都不创建）
- [ ] 优化 base image（预装常用依赖，减少创建时间）
- [ ] 实现 orphan 容器清理（通过 Docker labels 扫描，不依赖数据库）
  ```typescript
  async sweepOrphanContainers() {
    // 扫描带有 siriusx.managed=true 标签的容器
    const containers = await docker.listContainers({
      filters: { label: ['siriusx.managed=true'] }
    });
    
    for (const container of containers) {
      const uptime = Date.now() - container.Created * 1000;
      if (uptime > 30 * 60 * 1000) { // 30 分钟
        await docker.removeContainer(container.Id, { force: true });
      }
    }
  }
  ```

**性能分析**：
- Sandbox 创建开销：2-5 秒
- 单 run 平均时长：5-10 分钟
- **开销占比：< 2%**（可接受）

**未来扩展**（阶段 4+）：
- 如果发现 sandbox 创建开销过大，可引入 task-scoped sandbox pool
- 这时才需要 `sandbox_leases` 表和节点亲和性调度

---

### 阶段 3：S3 Workspace 性能优化（2-3 周）

**前置条件**：阶段 0 的基础 S3 Workspace Provider 已稳定运行

优化 S3 Workspace 性能，减少网络开销。

**注意**：Auth 已在阶段 0 完成，本阶段专注于性能优化。

#### 1. S3 Workspace 增量上传和缓存

- [ ] 实现增量 diff（基于 base revision manifest，只上传变更的 blobs）
- [ ] 实现本地 blob 缓存（避免重复下载相同文件）
- [ ] 实现并行上传/下载（提升大文件性能）
- [ ] 实现 LRU 缓存淘汰策略

#### 2. Artifact 增量索引优化

- [ ] 实现增量 diff（基于 base revision manifest）
- [ ] 实现 `ArtifactIndexer.indexArtifacts()`
- [ ] 文件树改成懒加载接口
  ```
  GET /api/task/:taskId/files?path=<path>&depth=<N>
  ```

---

### 阶段 4：生产优化（持续）

1. **监控和可观测性**
   - Prometheus + Grafana
   - 关键指标 dashboard
   - 告警规则

2. **成本优化**
   - S3 lifecycle 策略
   - Postgres 连接池优化
   - Control Worker 自动扩缩容

3. **性能优化**
   - Event batching
   - Connection pooling
   - 缓存策略

4. **灾难恢复**
   - Postgres 自动备份
   - S3 跨区域复制
   - 故障演练

---

## 最小可行原型验证（2-3 周）

在完整实施前，建议先用最小原型验证核心假设。

**🚨 P0 修正：原型必须包含 Auth**

### 原型范围

**部署架构**：
- 2 API 节点 + 2 Control Worker 节点 + sandbox runtime（本地 Docker Compose）
- Postgres + Redis（单实例）
- **实现阶段 0（包含 Auth）+ 阶段 1 + 阶段 2**

**为什么原型必须包含 Auth**：
- 验证多租户隔离是否正确
- 验证 S3 key 的 tenant 前缀是否生效
- 验证 authContext 是否正确传递
- 没有 Auth 的原型无法验证真实 SaaS 场景

### 验证目标

| # | 验证点 | 通过标准 |
|---|---|---|
| 1 | Auth 租户隔离和权限边界 | 不同租户无法访问彼此的 Task；S3 key 包含正确的 tenantId 前缀 |
| 2 | Control Worker 崩溃恢复 | 另一个 Control Worker 能接管并恢复 run |
| 3 | API 节点重启恢复 | 前端通过 event sequence 恢复 |
| 4 | Workspace 连续性 | 连续 run 串行执行且 workspace 正确传递 |
| 5 | Event 持久化降级 | 持久化失败时降级策略生效 |
| 6 | Workspace 冲突检测 | Revision 冲突检测生效 |

### 成功标准

原型稳定运行 **1000+ runs** 无严重故障。

### 测试场景

```typescript
// 场景 1：正常多轮对话
async function testNormalConversation() {
  const task = await createTask("Architecture Advisor");
  
  for (let i = 0; i < 10; i++) {
    await sendMessage(task.id, `请求 ${i + 1}`);
    await waitForRunComplete(task.id);
  }
  
  await closeTask(task.id);
}

// 场景 2：Control Worker 崩溃恢复
async function testWorkerCrash() {
  const task = await createTask("Architecture Advisor");
  const run = await sendMessage(task.id, "设计支付系统");
  
  // 在 run 执行中途杀掉 Control Worker
  await sleep(5000);
  await killWorker(1);
  
  // 验证另一个 Control Worker 接管
  await waitForRunComplete(task.id, run.id);
}

// 场景 3：并发任务
async function testConcurrentTasks() {
  const tasks = await Promise.all([
    createTask("Architecture Advisor"),
    createTask("Architecture Advisor"),
    createTask("Architecture Advisor"),
  ]);
  
  await Promise.all(tasks.map(task => 
    sendMessage(task.id, "设计支付系统")
  ));
  
  // 验证所有 run 都成功完成
  for (const task of tasks) {
    await waitForRunComplete(task.id);
  }
}
```

---

## 当前阶段不做的事

为了聚焦核心架构，以下内容**暂不实施**：

- ❌ 不切换到 Pi RPC 主链路
- ❌ 不使用 Pi JSON mode 作为执行链路
- ❌ 不把每个 Pi session 放进独立 Docker 容器
- ❌ 不让 Pi session 文件成为 SiriusX 的 durable state
- ❌ 不支持同一 task 多 run 并发修改同一个 workspace
- ❌ 不在第一阶段直接引入 OpenShell 或 Kubernetes sandbox
- ❌ 不在第一阶段引入正式 WorkerNode registry；先用 queue lease 表达节点归属（🚨 阶段 0-2 Stateless：无 sandbox lease）
- ❌ 不在 retry 时自动降级 model 或切换 sandbox provider，除非后续有显式 policy
- ❌ 不默认信任 Agent Repo 自带 extension 在 host 上运行；必须经过 allowlist 或隔离路由

---

## 参考文档

### 外部文档

- [Pi Containerization](https://pi.dev/docs/latest/containerization)
- [Pi Sessions](https://pi.dev/docs/latest/sessions)
- [Pi Extensions](https://pi.dev/docs/latest/extensions)

### 内部文档

- [架构概览](./ARCHITECTURE.md)
- [共享设计](./shared/) - 数据模型、错误码、测试、部署运维等跨仓库文档
- [控制面模块](./control-plane/) - API、Auth、Task 生命周期、队列、Worker、存储等
- [沙箱运行时模块](./sandbox-runtime/) - Pi SDK、沙箱管理
