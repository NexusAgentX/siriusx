# SiriusX MVP Pyramid

> 每个 stage 都是一个完整可用的 MVP。后一个 stage 不是“补技术骨架”，而是在前一个可用产品之上变得更强。

---

## 核心定义

MVP pyramid 的重点是：**每一层都必须能给真实用户交付价值**。

Stage 0 不是技术地基，不是未来 SaaS 的半成品，也不是只有数据库和接口的骨架。Stage 0 是最小最小的可运行产品：用户打开它，马上能和 AI 对话，并得到有用回复。

后续每个 stage 都保持同一个标准：

- 能运行。
- 能被用户独立使用。
- 有清楚的用户价值。
- 有清楚的不做事项。
- 不要求用户理解后续架构才知道它有什么用。

---

## Pyramid 总览

| Stage | MVP 名称 | 这一层完整产品 | 新增用户价值 |
|---:|---|---|---|
| 0 | [最小聊天 MVP](./STAGE0_SIMPLE_CHAT.md) | 一个能流式回复的 AI 聊天网页 | 立刻获得 AI 回答 |
| 1 | [本机工具助手 MVP](./STAGE1_LOCAL_TOOLS.md) | 能经用户确认后调用本机工具的聊天助手 | AI 能帮用户查文件、跑命令、看结果 |
| 2 | [本地工作区 MVP](./STAGE2_LOCAL_WORKSPACE.md) | 带文件区和产物区的任务工作台 | AI 能产出文档、代码、文件 |
| 3 | [可恢复任务 MVP](./STAGE3_TASK_RUN_RUNTIME.md) | 长任务可跟踪、可取消、可恢复 | 用户能放心跑较长任务 |
| 4 | [个人/小团队产品 MVP](./STAGE4_MULTI_USER_PRODUCT.md) | 有登录、历史、Agent 选择的完整产品 | 多个用户能稳定使用自己的任务 |
| 5 | [服务化执行 MVP](./STAGE5_SHARED_STORAGE_AND_QUEUE.md) | API 和 Worker 分离的后台执行产品 | 长任务不阻塞 Web 服务 |
| 6 | [安全执行 MVP](./STAGE6_SANDBOX_RUNTIME.md) | 工具和代码在沙箱里运行的产品 | 用户能更放心地让 AI 执行命令 |
| 7 | [多节点 SaaS MVP](./STAGE7_DISTRIBUTED_SAAS.md) | 多 API、多 Worker、多租户 SaaS | 团队/客户能共享稳定服务 |
| 8 | [生产运营 MVP](./STAGE8_PRODUCTION_HARDENING.md) | 可观测、可备份、可告警的生产服务 | 运维人员能可靠运营 |
| 9 | [平台生态 MVP](./STAGE9_ADVANCED_PLATFORM.md) | 权限、集成、工作流、规模优化平台 | 企业能把它接入真实流程 |

---

## 推荐路线

```text
Stage 0  最小聊天
  -> Stage 1  本机工具
  -> Stage 2  本地工作区
  -> Stage 3  可恢复任务
  -> Stage 4  个人/小团队产品
  -> Stage 5  服务化执行
  -> Stage 6  安全执行
  -> Stage 7  多节点 SaaS
  -> Stage 8  生产运营
  -> Stage 9  平台生态
```

Stage 0-2：适合快速验证用户是否真的需要这个产品。

Stage 3-4：适合做个人或小团队内部工具。

Stage 5-7：适合进入早期 SaaS。

Stage 8-9：适合生产运营和企业平台化。

---

## 每层判断标准

一个 stage 只有满足以下条件，才算完成：

1. 用户不用看内部文档也知道它能解决什么问题。
2. 有一条完整的核心用户路径。
3. 失败时用户知道发生了什么，并能继续使用或重试。
4. 当前 stage 不依赖后续 stage 才能成立。
5. 下一个 stage 是“增强”，不是“补完当前 stage 才能用”。

---

## 与旧文档的关系

旧的 `docs/STAGE0_SPEC.md` 是一个重型分布式执行地基规格，更接近本 pyramid 的 Stage 5-7 组合。它仍可作为后续分布式阶段参考，但不再代表新的 Stage 0。

现有架构文档能力映射如下：

| 旧文档能力 | 新 Stage |
|---|---:|
| 简单对话、流式回复 | Stage 0 |
| shell / file / browser 工具 | Stage 1 |
| workspace、artifact、文件树 | Stage 2 |
| Task / Run / event sequence | Stage 3 |
| Auth、Agent Catalog、history | Stage 4 |
| Redis queue、ResultBus、S3 workspace | Stage 5 |
| sandbox runtime、capability token | Stage 6 |
| run lease、LeaseSweeper、多 Worker 恢复 | Stage 7 |
| 监控、备份、告警、限流、审计 | Stage 8 |
| RBAC、分享、Webhook、sandbox pool | Stage 9 |
