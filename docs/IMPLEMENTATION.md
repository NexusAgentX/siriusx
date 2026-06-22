# SiriusX MVP Pyramid 实施计划

> 从最小聊天产品逐层增强到生产级 Agent 平台。每个 stage 都是完整可用的 MVP，不是半成品技术骨架。

---

## 目录

- [实施原则](#实施原则)
- [阶段总览](#阶段总览)
- [推荐排期](#推荐排期)
- [Stage 0 起步标准](#stage-0-起步标准)
- [升级门槛](#升级门槛)
- [Stage 7+ 生产参考指标](#stage-7-生产参考指标)
- [旧 Stage 0 规格的定位](#旧-stage-0-规格的定位)

---

## 实施原则

SiriusX 采用 MVP pyramid，而不是一次性搭完整分布式地基。

每一层都必须满足：

1. 能运行。
2. 能被用户独立使用。
3. 有清楚的用户价值。
4. 失败时用户知道发生了什么，并能继续使用或重试。
5. 下一层是增强当前产品，不是补完当前产品才让它能用。

因此，Stage 0 不做 Auth、队列、沙箱、S3、Worker、租约。Stage 0 只做一个真正可用的最小聊天产品。

详细阶段说明见 [stage/README.md](./stage/README.md)。

---

## 阶段总览

| Stage | MVP | 用户价值 | 详细文档 |
|---:|---|---|---|
| 0 | 最小聊天 MVP | 用户能打开网页，输入问题，得到流式 AI 回复 | [STAGE0_SIMPLE_CHAT.md](./stage/STAGE0_SIMPLE_CHAT.md) |
| 1 | 本机工具助手 MVP | AI 能经确认后读取文件、搜索内容、执行命令 | [STAGE1_LOCAL_TOOLS.md](./stage/STAGE1_LOCAL_TOOLS.md) |
| 2 | 本地工作区 MVP | AI 能生成和修改文件，用户能查看产物 | [STAGE2_LOCAL_WORKSPACE.md](./stage/STAGE2_LOCAL_WORKSPACE.md) |
| 3 | 可恢复任务 MVP | 长任务有状态、可取消、可恢复 | [STAGE3_TASK_RUN_RUNTIME.md](./stage/STAGE3_TASK_RUN_RUNTIME.md) |
| 4 | 个人/小团队产品 MVP | 用户能登录、管理历史、选择 Agent | [STAGE4_MULTI_USER_PRODUCT.md](./stage/STAGE4_MULTI_USER_PRODUCT.md) |
| 5 | 服务化执行 MVP | API 和 Worker 分离，长任务不阻塞 Web | [STAGE5_SHARED_STORAGE_AND_QUEUE.md](./stage/STAGE5_SHARED_STORAGE_AND_QUEUE.md) |
| 6 | 安全执行 MVP | 命令、解释器、浏览器进入沙箱 | [STAGE6_SANDBOX_RUNTIME.md](./stage/STAGE6_SANDBOX_RUNTIME.md) |
| 7 | 多节点 SaaS MVP | 多 API、多 Worker、多租户、基本崩溃恢复 | [STAGE7_DISTRIBUTED_SAAS.md](./stage/STAGE7_DISTRIBUTED_SAAS.md) |
| 8 | 生产运营 MVP | 监控、告警、备份、限流、审计 | [STAGE8_PRODUCTION_HARDENING.md](./stage/STAGE8_PRODUCTION_HARDENING.md) |
| 9 | 平台生态 MVP | RBAC、集成、工作流、规模优化 | [STAGE9_ADVANCED_PLATFORM.md](./stage/STAGE9_ADVANCED_PLATFORM.md) |

---

## 推荐排期

排期取决于代码基础和人员熟悉度。下面是单个熟悉全栈工程师的保守估计。

| Stage | 建议周期 | 说明 |
|---:|---|---|
| 0 | 1-3 天 | 一个页面、一个 chat endpoint、流式回复 |
| 1 | 3-7 天 | 工具协议、确认 UI、shell/read/search 工具 |
| 2 | 1-2 周 | workspace、文件树、artifact、下载 |
| 3 | 1-2 周 | Task/Run/Event、取消、恢复、失败状态 |
| 4 | 1-2 周 | Auth、history、Agent Catalog、用户边界 |
| 5 | 2-3 周 | API/Worker、Postgres、Redis、S3/MinIO |
| 6 | 2-4 周 | Sandbox Runtime、Docker provider、capability token |
| 7 | 3-5 周 | lease、heartbeat、sweeper、多租户、多节点恢复 |
| 8 | 持续 | 监控、告警、备份、发布、runbook |
| 9 | 按子能力立项 | RBAC、Webhook、workflow、sandbox pool 等分别设计 |

不要为了“以后肯定需要”跳过前面阶段。每跳一层，都会增加调试面和产品不确定性。

---

## Stage 0 起步标准

Stage 0 的目标是最快拿到用户反馈。

### 必须做

- 一个可访问的聊天页面。
- 一个输入框和发送按钮。
- 一个停止生成按钮。
- 流式模型回复。
- 当前会话消息展示。
- 基础错误提示。
- 可以用 localStorage 保留最近一次会话。

### 可以不做

- 登录。
- 数据库。
- 多会话历史。
- 工具调用。
- 文件产物。
- 队列。
- 沙箱。
- Worker。
- 多 Agent。

### 验收

- 用户打开页面后 10 秒内知道怎么用。
- 用户能连续聊 20 轮。
- 停止生成可用。
- 模型失败时页面不崩溃。
- 即使后续阶段都不做，Stage 0 也能作为一个可用 AI 聊天入口。

---

## 升级门槛

每个 stage 完成后先问一个产品问题：用户是否真的需要下一层能力？

| 从 | 到 | 升级信号 |
|---:|---:|---|
| 0 | 1 | 用户想让 AI 看本地文件、跑命令、解释项目 |
| 1 | 2 | 用户想保存 AI 生成的文件，并围绕文件继续迭代 |
| 2 | 3 | 任务开始变长，需要状态、取消、恢复和失败处理 |
| 3 | 4 | 需要多人使用、历史管理、Agent 选择和基础权限 |
| 4 | 5 | 长任务影响 Web 响应，需要后台 Worker |
| 5 | 6 | 工具执行风险上升，需要隔离环境 |
| 6 | 7 | 需要多节点、多租户、崩溃接管 |
| 7 | 8 | 已经对外或跨团队使用，需要运维闭环 |
| 8 | 9 | 企业用户需要权限、集成、工作流和规模优化 |

---

## Stage 7+ 生产参考指标

这些指标不属于 Stage 0。它们只用于 Stage 7 之后评估多节点 SaaS。

| 指标 | 目标值 |
|---|---|
| 并发 task 数 | 100-500 |
| 单 task run 频率 | 5-10 runs/小时 |
| 单 run 平均时长 | 5-10 分钟 |
| 事件流吞吐峰值 | 1000 events/秒 |
| Queue wait latency p95 | < 60s |
| Run execution time p95 | < 15 分钟 |
| Event persistence lag | < 5s |
| Sandbox creation success rate | > 95% |
| Workspace commit success rate | > 99% |

### Stage 7+ 成本参考

| 项目 | 月成本 |
|---|---:|
| EC2 / compute | $200-400 |
| RDS Postgres | $100 |
| ElastiCache Redis | $50 |
| S3 / object storage | $10+ |
| 合计 | $360-560+ |

Stage 0-4 不应按这个成本模型设计。

---

## 旧 Stage 0 规格的定位

[STAGE0_SPEC.md](./STAGE0_SPEC.md) 是旧路线中的“分布式执行地基”规格。它不再代表新的 Stage 0。

在新的 MVP pyramid 中，旧 `STAGE0_SPEC.md` 更接近 Stage 5-7 的组合参考：

- API / Worker 分离。
- Redis Queue / ResultBus。
- S3 workspace。
- Task / Run / event sequence。
- run lease 和崩溃恢复。
- sandbox runtime。
- 多租户和 Auth。

实施新路线时，以 [stage/README.md](./stage/README.md) 和各 stage 文档为准。
