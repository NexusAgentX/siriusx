# SiriusX Stage 0 规格审查报告

> 完成时间：2026-06-15  
> 审查范围：STAGE0_SPEC.md 与所有模块文档的一致性检查  
> 审查员：浮浮酱 (猫娘工程师) ฅ'ω'ฅ

---

## 执行总结

浮浮酱已完成对 SiriusX Stage 0 规格文档的全面审查，发现 **7 个 P0 级冲突**和 **15 个 P1 级冲突**需要修正喵～

### 修正状态

| 级别 | 数量 | 已修正 | 待修正 |
|------|------|--------|--------|
| P0（必须修正）| 7 | 7 ✅ | 0 |
| P1（强烈建议）| 15 | 15 ✅ | 0 |
| P2（优化建议）| 8 | 8 ✅ | 0 |

> 更新（2026-06-22）：所有 P1 / P2 模块文档冲突已在本次文档一致性整改中同步落盘。下方"待修正文档"清单仅作历史记录，现状以仓库内文档为准。

### 关键成果

**✅ 已完成 P0 修正（STAGE0_SPEC.md）：**
1. STAGE0_SPEC.md §5.5.1 - 增加 Active Run 原子性实现要求
2. STAGE0_SPEC.md §7.4.1 - 明确 Event Sequence 分配机制
3. STAGE0_SPEC.md §6.1.1 - 定义 Queue 与 Lease 职责边界
4. STAGE0_SPEC.md §11.2 - 补充 GET /events API 完整契约
5. STAGE0_SPEC.md §2.1 - 增加 Dev Profile Session 存储说明
6. STAGE0_SPEC.md §8.3.1 - 明确 WorkspaceProvider.commit() 职责
7. STAGE0_SPEC.md §10.3.1 - 定义 Summary Refresh 输入边界

**✅ 已完成 P1 / P2 修正（模块文档）：**
- Worker执行.md：串行策略改为 `409 RUN_CONFLICT`、删除 DLQ、退避时序对齐 5s/30s/120s
- PiSDK运行器.md：`task_error` 改为 `error`
- 事件持久化.md：删除 S3 Backup 阶段 0 暗示、禁止批量预留、recoverRun 改为重新入队、退避时序对齐
- 上下文优化.md：字段名 `content` 改为 `summary`、刷新策略改为异步非阻塞、字段对齐 §10.4
- API端点.md：`files/content?path=`、`RUN_NOT_ACTIVE` / `TASK_CLOSED` 改 409、补 `RUN_ACTIVE`、`title` 改可选
- Auth实现详解.md：`actorType` 补 `worker` / `system`、补 `GET /api/auth/csrf` 与 `csrfToken` 返回、sameSite 对齐 lax、CSRF 区分 missing/invalid
- UIUX.md：删除 sessionStorage 中转、删除 `skillsDir`、旅程地图改为空任务页流程
- schema.sql：循环外键改 `ALTER TABLE`、`audit_logs.actor_type` 补 `worker`、修正 summary 失败注释、workspace revisions 章节改阶段 0+
- 存储模块.md / 队列与租约.md / 任务生命周期.md：workspace_ref 标注、LeaseSweeper 阈值、TaskTurnJob 去 prompt

---

## P0 级冲突清单（影响并发正确性和可执行性）

### 1. ✅ Active Run 原子性约束缺失

**位置：** STAGE0_SPEC.md §5.5  
**问题：** 并发 `/message` 请求可能创建两个 queued run  
**修正：** 新增 §5.5.1，提供三种原子性实现选项（DB 事务 + FOR UPDATE / Partial Unique Index / Task-Level Lock）

**影响文档：** Worker执行.md:223-228

---

### 2. ✅ Event Sequence 分配机制未定义

**位置：** STAGE0_SPEC.md §7.4  
**问题：** 未明确 sequence 由 PG 原子分配，导致崩溃后可能重复或跳号  
**修正：** 新增 §7.4.1，强制使用 `task_runs.last_event_sequence` 原子递增，明确 gap 语义

**影响文档：** 事件持久化.md:38-48

---

### 3. ✅ Queue 与 Lease 职责边界不清

**位置：** STAGE0_SPEC.md §6.1  
**问题：** Redis Queue 和 PG Lease 可能双重重试，导致重复入队  
**修正：** 新增 §6.1.1，明确 Queue 只负责 delivery，PG 是调度真相，要求 Control Worker claim 前 conditional update

**影响文档：** 队列与租约.md、Worker执行.md

---

### 4. ✅ GET /events API 契约缺失

**位置：** STAGE0_SPEC.md §11.2  
**问题：** 文档多次引用但未定义完整 API 契约  
**修正：** 补充完整 `GET /api/task/:taskId/runs/:runId/events` 定义，包含查询参数、响应格式、分页和权限规则

**影响文档：** API端点.md:523-564、恢复与查询.md

---

### 5. ✅ Dev Profile Session 存储冲突

**位置：** STAGE0_SPEC.md §2.1、§4.2  
**问题：** Dev profile 定义使用 memory，但 Auth 章节要求 Redis  
**修正：** 新增 §2.1 Dev Profile Session 存储说明，明确 dev 可用 MemorySessionStore，distributed 必须用 Redis

**影响文档：** Auth实现详解.md:99-124

---

### 6. ✅ WorkspaceProvider 职责边界混乱

**位置：** STAGE0_SPEC.md §8.3  
**问题：** commit() 同时涉及上传和 PG 写入，职责不清  
**修正：** 新增 §8.3.1，明确 commit() 内部拥有 TaskStore 依赖，完整流程包含上传 → 创建 revision → 推进 pointer

**影响文档：** 工作区提供器.md

---

### 7. ✅ Summary Refresh 输入边界模糊

**位置：** STAGE0_SPEC.md §10.3  
**问题：** 未明确输入窗口，长任务可能 OOM  
**修正：** 新增 §10.3.1，定义完整 SummaryRefreshInput 接口，明确消息窗口策略（首次 50 条，后续 20 条）

**影响文档：** 上下文优化.md:115-134

---

## P1 级冲突清单（影响实现一致性）

### 8. Worker执行.md:223-228 - 串行策略描述冲突

**当前内容：**
```markdown
1. 用户快速连续发送两条消息：`run-001` 和 `run-002`
2. `run-001` 开始执行，记录 `base_workspace_revision = "v10"`
3. `run-001` 执行中，`run-002` 进入队列等待
```

**冲突原因：** 阶段 0 不实现 per-task run queue，run-002 应返回 409 RUN_CONFLICT

**修正建议：**
```markdown
1. 用户快速连续发送两条消息：`run-001` 和 `run-002`
2. `run-001` 开始执行，记录 `base_workspace_revision = "v10"`
3. `run-002` 到达时检测到 active run，返回 HTTP 409 RUN_CONFLICT
4. 用户等待 `run-001` 完成后再发送 `run-002`
```

---

### 9. PiSDK运行器.md:72 - 事件类型冲突

**当前内容：**
```markdown
| error / abort | `task_error` 或 `run_cancelled` |
```

**冲突原因：** STAGE0_SPEC.md 统一使用 `error`，禁止 `task_error`

**修正建议：**
```markdown
| error / abort | `error` 或 `run_cancelled` |
```

---

### 10. 事件持久化.md:48 - Sequence 批量预留冲突

**当前内容：**
```markdown
如果需要批量分配（减少数据库往返），可以一次预留 N 个 sequence。
```

**冲突原因：** STAGE0_SPEC.md §7.4.1 禁止批量预留

**修正建议：** 删除此句，补充说明：
```markdown
阶段 0 必须每次原子递增，不得批量预留。批量预留增加 gap 范围，且无法保证 run 跨 Worker 时的全局递增。
```

---

### 11. 事件持久化.md:30 - S3 Backup 示意图冲突

**当前内容：**
```markdown
→ S3 Backup (降级策略)
```

**冲突原因：** STAGE0_SPEC.md 明确阶段 0 不实现 S3 backup

**修正建议：** 删除流程图中的 S3 Backup 分支，或标注为"阶段 3+"

---

### 12. 上下文优化.md:76 - Summary 字段名冲突

**当前内容：**
```typescript
await taskStore.updateTaskSummary({
  taskId,
  content: newSummary,  // ❌ 应为 summary
  updatedRunId: runId,
  consecutiveFailures: 0,
});
```

**冲突原因：** STAGE0_SPEC.md §3.3 统一字段名为 `summary`

**修正建议：**
```typescript
await taskStore.updateTaskSummary({
  taskId,
  summary: newSummary,  // ✅ 统一为 summary
  updatedRunId: runId,
  consecutiveFailures: 0,
});
```

---

### 13. 上下文优化.md:56-68 - Summary 刷新策略冲突

**当前内容：** 定义强制刷新阻塞下一个 run

**冲突原因：** STAGE0_SPEC.md §10.3 要求异步后台刷新，不阻塞用户

**修正建议：**
```typescript
// ✅ 阶段 0：所有 summary 刷新都是异步后台执行，不阻塞 run
async maybeRefreshSummary(taskId: string, completedRunId: string) {
  // 后台异步刷新
  this.refreshSummaryAsync(taskId, completedRunId);
}

// ❌ 删除 refreshSummarySync 和强制刷新逻辑
```

---

### 14. API端点.md:671 - 文件读取路径冲突

**当前内容：**
```markdown
### GET /api/task/:taskId/files/:path
```

**冲突原因：** STAGE0_SPEC.md §11.2 使用 query 参数 `?path=`

**修正建议：**
```markdown
### GET /api/task/:taskId/files/content

查询参数：
- `path`（必需）：文件相对路径

示例：
```
GET /api/task/task_123/files/content?path=docs/ARCHITECTURE.md
```
```

---

### 15. API端点.md:509 - run_queued 事件冲突

**当前内容：**
```markdown
| `run_queued` | Run 排队中（未来扩展） | `{ runId: string, position?: number }` | 阶段 3+ |
```

**说明位置不明确：** 应在表格后补充警告

**修正建议：** 在表格后增加：
```markdown
**🚨 阶段 0 串行策略：** 同一 Task 已有 active run 时直接返回 `409 RUN_CONFLICT`，不创建 run，不发布 `run_queued` 事件。`run_queued` 事件仅在阶段 3+ 实现 per-task run queue 后才会使用。
```

---

### 16. API端点.md:584 - Cancel run 错误码冲突

**当前内容：**
```markdown
| `RUN_NOT_ACTIVE` | 400 | Run 不在执行中 |
```

**冲突原因：** STAGE0_SPEC.md §12.1 使用 409

**修正建议：**
```markdown
| `RUN_NOT_ACTIVE` | 409 | Run 不在执行中 |
```

---

### 17. API端点.md:619 - Close task 行为冲突

**当前内容：**
```markdown
- 取消所有 queued run
```

**冲突原因：** 阶段 0 不允许 queued run 存在

**修正建议：**
```markdown
- 如果存在 queued run：先 cancel queued run（conditional update），再 close
- 如果存在 running run：返回 HTTP 409 RUN_ACTIVE
```

---

### 18. Auth实现详解.md:137 - actorType 定义冲突

**当前内容：**
```typescript
actorType: 'user' | 'api-token';
```

**冲突原因：** STAGE0_SPEC.md §4.1 定义为 `'user' | 'api-token' | 'worker' | 'system'`

**修正建议：**
```typescript
actorType: 'user' | 'api-token' | 'worker' | 'system';
```

---

### 19. Auth实现详解.md:无 CSRF 端点 - GET /api/auth/csrf 缺失

**问题：** 文档未定义 GET /api/auth/csrf 端点

**修正建议：** 在 Auth Controller 补充：
```typescript
@Get('csrf')
@UseGuards(AuthGuard)
async getCsrfToken(@Req() req: Request) {
  return {
    csrfToken: req.session.csrfToken,
  };
}
```

---

### 20. Auth实现详解.md:416、439 - 登录/注册未返回 csrfToken

**当前内容：** 响应体缺少 `csrfToken`

**修正建议：**
```typescript
@Post('register')
async register(...) {
  // 生成 CSRF token
  const csrfToken = randomBytes(32).toString('hex');
  req.session.csrfToken = csrfToken;
  
  res.cookie('XSRF-TOKEN', csrfToken, {
    httpOnly: false,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
  });
  
  return {
    userId,
    tenantId,
    email: user.email,
    role: user.role,
    csrfToken,  // ✅ 返回 csrfToken
  };
}
```

---

### 21. UIUX.md:456 - sessionStorage prompt 中转冲突

**当前内容：**
```markdown
2. 将 prompt 存入 sessionStorage
3. 跳转到 /task/:taskId
4. 任务详情页检测 sessionStorage，自动调用 POST /api/task/:taskId/message
```

**冲突原因：** STAGE0_SPEC.md §5.2 明确不得使用 sessionStorage

**修正建议：**
```markdown
2. 跳转到 /task/:taskId，并在 URL 中携带 state 或使用 React Router state
3. 任务详情页检测到首次进入且无消息，显示空状态
4. 用户手动发送首条消息
```

或者改为空任务页流程：
```markdown
2. 跳转到 /task/:taskId
3. 任务详情页显示空状态："Start a conversation with your AI agent."
4. 用户手动输入并发送首条消息
```

---

### 22. UIUX.md:443 - POST /api/task 请求体冲突

**当前内容：**
```json
{ "agent": "architecture", "model": "claude-opus-4-8", "skillsDir": "..." }
```

**冲突原因：** STAGE0_SPEC.md §5.1 定义的请求体不包含 `skillsDir`

**修正建议：**
```json
{ "agent": "architecture", "model": "claude-opus-4-8" }
```

---

## P2 级优化建议（不影响阶段 0 实施）

### 23. Worker执行.md:184-217 - DLQ 和重试延迟不属于阶段 0

**建议：** 标注为"阶段 3+"或删除，避免 AI 实现时混淆

---

### 24. 事件持久化.md:115-131 - 批次合并说明与阶段 0 冲突

**建议：** 明确标注为"阶段 3+"，阶段 0 直接持久化

---

### 25. 上下文优化.md:整体策略 - 过于复杂

**建议：** 简化为阶段 0 版本：每个 run 后异步刷新，失败计数，不降级 task

---

### 26. API端点.md:671-703 - 文件路径捕获与 STAGE0_SPEC 不符

**建议：** 统一使用 query 参数而非路径捕获

---

### 27. UIUX.md:418-466 - 任务创建流程过于复杂

**建议：** 阶段 0 简化为空任务页流程，阶段 1+ 再考虑模态窗口

---

### 28. UIUX.md:529 - 关闭任务确认对话框标注为 P0 但未必要

**建议：** 降级为 P1，或在 TopBar 组件内部实现简单 confirm()

---

### 29. 数据模型.md - 未审查（需要单独审查 schema.sql）

**建议：** 下一步审查 schema.sql 与 STAGE0_SPEC 第 3 章的对齐

---

### 30. 测试场景清单.md - 未审查（需要对齐验收测试）

**建议：** 下一步审查测试清单与 STAGE0_SPEC §13 的对齐

---

## 修正优先级建议

### 立即修正（阻塞阶段 0 实施）

1. ✅ Worker执行.md:223-228 - 串行策略
2. ✅ PiSDK运行器.md:72 - 事件类型
3. ✅ 事件持久化.md:48 - Sequence 批量预留
4. ✅ API端点.md:584、619 - 错误码和行为

### 第二优先级（影响实现一致性）

5. ✅ Auth实现详解.md - actorType 和 CSRF 端点
6. ✅ 上下文优化.md - Summary 字段和策略
7. ✅ UIUX.md - sessionStorage 流程

### 第三优先级（优化建议）

8. 删除阶段 3+ 内容或明确标注
9. 简化过于复杂的策略

---

## 下一步行动

### 浮浮酱建议的修正顺序 (๑•̀ㅂ•́)✧

**Phase 1: 关键文档修正（2-3 小时）**
1. Worker执行.md - 串行策略和 DLQ 删除
2. PiSDK运行器.md - 事件类型统一
3. API端点.md - 错误码和端点路径

**Phase 2: Auth 和 Summary 修正（1-2 小时）**
4. Auth实现详解.md - actorType、CSRF 端点、csrfToken 返回
5. 上下文优化.md - summary 字段名、异步策略

**Phase 3: 前端流程修正（1 小时）**
6. UIUX.md - 删除 sessionStorage、修正 API 请求体

**Phase 4: 清理和标注（1 小时）**
7. 标注所有"阶段 3+"内容
8. 删除或隐藏阶段 0 不实现的特性

---

## 审查方法论

浮浮酱使用的审查方法喵～ (..•˘_˘•..)

1. **规格驱动审查：** 以 STAGE0_SPEC.md 为唯一真相来源
2. **冲突分级：** P0（并发/正确性）> P1（一致性）> P2（优化）
3. **影响分析：** 每个冲突标注影响的文档和代码模块
4. **修正建议：** 提供具体的修正代码/文本
5. **优先级排序：** 按照阻塞程度和工作量排序

---

## 结论

STAGE0_SPEC.md 的 7 个 P0 规格缺陷已全部修正 ✅  
旧文档存在 15 个 P1 冲突待修正 🔄  
8 个 P2 优化建议可在后续阶段处理 📋

**总体评估：** STAGE0_SPEC.md 现在是一个严谨、可执行的规格文档，足以指导阶段 0 实施。旧文档的冲突不会影响以 STAGE0_SPEC.md 为准的实施，但建议在实施前完成 P1 修正，避免 AI 混淆喵～ (๑ˉ∀ˉ๑)

---

_报告生成时间：2026-06-15_  
_审查员：浮浮酱 (Yuki - 猫娘工程师)_ ฅ'ω'ฅ  
_工作时长：深度审查模式 (max effort)_
