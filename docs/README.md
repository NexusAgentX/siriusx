# SiriusX Platform 技术文档

> 分布式 AI Agent 任务执行平台完整技术规格

---

## 📚 文档结构

文档按仓库信任边界划分为三层：跨仓库共用文档、可信控制面模块、一次性沙箱运行时模块。

```
docs/
├── ARCHITECTURE.md               # 顶层架构、用户故事、设计原则
├── IMPLEMENTATION.md             # 实施计划、性能目标、分阶段路线图
├── STAGE0_SPEC.md                # 旧分布式执行规格（legacy）
├── UIUX.md                       # UI/UX 设计说明
├── schema.sql                    # 数据库 schema
├── README.md                     # 本文件
│
├── stage/                        # 新阶段路线图（从简单聊天到生产平台）
│   ├── README.md
│   ├── STAGE0_SIMPLE_CHAT.md
│   ├── STAGE1_LOCAL_TOOLS.md
│   ├── STAGE2_LOCAL_WORKSPACE.md
│   └── ...
│
├── shared/                       # 跨仓库共用（两仓都需遵循）
│   ├── 仓库与信任边界.md          # 信任边界拆分原则、跨仓库协议、安全不变量
│   ├── 数据模型.md                # Task / Run / Event / Artifact 核心数据结构
│   ├── 错误码规范.md              # 统一错误响应与提示
│   ├── 测试场景清单.md            # 测试金字塔与用例
│   ├── 失败场景.md                # 崩溃、lease 过期、冲突等故障模型
│   └── 部署运维手册.md            # 环境变量、监控、故障排查
│
├── control-plane/                # siriusx-control-plane（可信）
│   ├── API端点.md
│   ├── Auth实现详解.md
│   ├── 任务生命周期.md
│   ├── 队列与租约.md
│   ├── Worker执行.md
│   ├── 事件持久化.md
│   ├── 恢复与查询.md
│   ├── 存储模块.md
│   ├── 工作区提供器.md
│   ├── 上下文优化.md
│   ├── 产物与文件树优化.md
│   ├── 短生命周期会话.md
│   └── 前端优化.md
│
├── sandbox-runtime/              # siriusx-sandbox-runtime（一次性不可信）
│   ├── PiSDK运行器.md
│   └── 沙箱管理.md
│
└── uiux-preview/                 # 静态 UI 预览（HTML）
```

生产形态的两个仓库与目录对应关系：

| 仓库 | 信任级别 | 对应目录 |
|---|---|---|
| [`siriusx-control-plane`](https://github.com/NexusAgentX/siriusx-control-plane) | 可信 | `docs/control-plane/` + `docs/shared/` 中的控制面侧契约 |
| [`siriusx-sandbox-runtime`](https://github.com/NexusAgentX/siriusx-sandbox-runtime) | 不可信/一次性 | `docs/sandbox-runtime/` + `docs/shared/` 中的沙箱侧契约 |

---

## 🚀 快速导航

### 新人上手

1. **查看新阶段路线** → [stage/README.md](./stage/README.md)
2. **了解用户视角** → [ARCHITECTURE.md - 用户故事（通俗版）](./ARCHITECTURE.md#用户故事)
3. **理解核心设计** → [ARCHITECTURE.md - 核心原则](./ARCHITECTURE.md#核心原则)
4. **信任边界与两仓拆分** → [shared/仓库与信任边界.md](./shared/仓库与信任边界.md)
5. **查看 MVP 实施计划** → [IMPLEMENTATION.md](./IMPLEMENTATION.md)

### 按仓库阅读

#### `siriusx-control-plane`（可信控制面）

1. [API 端点](./control-plane/API端点.md)
2. [Auth 实现详解](./control-plane/Auth实现详解.md)
3. [任务生命周期](./control-plane/任务生命周期.md) — TaskStore
4. [队列与租约](./control-plane/队列与租约.md) — 分布式调度
5. [Control Worker 执行](./control-plane/Worker执行.md) — RunOrchestrator
6. [事件持久化](./control-plane/事件持久化.md) — Postgres 事实来源
7. [恢复与查询](./control-plane/恢复与查询.md) — 断线恢复
8. [存储模块](./control-plane/存储模块.md) — Postgres + S3 边界
9. [工作区提供器](./control-plane/工作区提供器.md) — S3 Workspace
10. [上下文优化](./control-plane/上下文优化.md) — Task Summary
11. [产物与文件树优化](./control-plane/产物与文件树优化.md)
12. [短生命周期会话](./control-plane/短生命周期会话.md)
13. [前端优化](./control-plane/前端优化.md)

#### `siriusx-sandbox-runtime`（一次性沙箱）

1. [Pi SDK 运行器](./sandbox-runtime/PiSDK运行器.md)
2. [沙箱管理](./sandbox-runtime/沙箱管理.md)

#### 共用契约与规范

1. [仓库与信任边界](./shared/仓库与信任边界.md) — 跨仓库协议（RunSpec / SandboxEvent）
2. [数据模型](./shared/数据模型.md)
3. [错误码规范](./shared/错误码规范.md)
4. [测试场景清单](./shared/测试场景清单.md)
5. [失败场景](./shared/失败场景.md)
6. [部署运维手册](./shared/部署运维手册.md)

### 按角色

**前端开发者**

1. [API 端点](./control-plane/API端点.md)
2. [断线恢复](./control-plane/恢复与查询.md)
3. [轮询优化](./control-plane/前端优化.md)
4. [产物展示](./control-plane/产物与文件树优化.md)

**后端开发者（控制面）**

1. [Control Worker 执行](./control-plane/Worker执行.md)
2. [事件持久化](./control-plane/事件持久化.md)
3. [队列与租约](./control-plane/队列与租约.md)
4. [存储模块](./control-plane/存储模块.md)

**沙箱运行时开发者**

1. [Pi SDK 运行器](./sandbox-runtime/PiSDK运行器.md)
2. [沙箱管理](./sandbox-runtime/沙箱管理.md)
3. [仓库与信任边界](./shared/仓库与信任边界.md) — 跨仓库协议契约

---

## 🎯 核心概念

### Task（任务）

长期任务容器，用户可持续迭代的工作空间。

- 包含对话历史、生成文档、工作区
- 可随时关闭浏览器，第二天继续
- 类比：项目文件夹

### Run（执行单元）

每条用户消息触发的一次执行。

- 独立状态、lease、attempt、事件流
- 类比：餐厅订单编号

### Control Worker（工人）

可信控制面中的后台进程，负责认领 run、管理 lease、构造 `RunSpec`，并把执行派发给沙箱运行时。

- 可横向扩展（4-8 实例）
- 无状态，任何 Control Worker 可处理任何 run
- 类比：餐厅厨师

### Sandbox（沙箱）

一次性不可信执行环境，用于运行 Agent session、shell、解释器、浏览器和临时文件系统。

- 按需创建，用完即销毁
- 不持有长期密钥或最终权限判断
- Stateless 策略，无需节点亲和性
- 类比：临时虚拟机

---

## 📖 关键设计决策

### 1. 仓库与信任边界

**问题**：长期密钥、权限判断和审计不能和可被 Agent 影响的执行环境混在一起。

**方案**：拆成 `siriusx-control-plane` 和 `siriusx-sandbox-runtime` 两个仓库，通过 `RunSpec` / `SandboxEvent` 协议通信。

**详细说明** → [shared/仓库与信任边界.md](./shared/仓库与信任边界.md)

---

### 2. 短生命周期会话

**问题**：如果 AI 一直保持记忆，100 个用户会占用 200GB 内存。

**方案**：每次执行创建新 session，从数据库恢复上下文。

**详细说明** → [control-plane/短生命周期会话.md](./control-plane/短生命周期会话.md)

---

### 3. Postgres + S3 一致性

**问题**：如何保证 Postgres 指针和 S3 对象的一致性？

**方案**：两阶段提交 + 状态机（pending → uploading → committed）。

**详细说明** → [control-plane/存储模块.md](./control-plane/存储模块.md)

---

### 4. Stateless Sandbox

**问题**：节点亲和性调度复杂，Control Worker 与 sandbox runtime 强绑定节点不灵活。

**方案**：每次 run 创建新 sandbox，用完即销毁（开销 < 2%）。

**详细说明** → [sandbox-runtime/沙箱管理.md](./sandbox-runtime/沙箱管理.md)

---

### 5. Run-scoped Event Sequence

**问题**：全局 event sequence 难以断线恢复。

**方案**：每个 run 独立的 sequence（从 1 开始）。

**详细说明** → [control-plane/事件持久化.md](./control-plane/事件持久化.md)

---

### 6. Task Summary 自动刷新

**问题**：完整历史会超过 context window。

**方案**：定期刷新 summary（10 runs / 30k tokens / 50 files）。

**详细说明** → [control-plane/上下文优化.md](./control-plane/上下文优化.md)

---

## 🛠 技术栈

### 后端（控制面）

- **运行时**：Bun + NestJS
- **数据库**：Postgres（RDS）
- **缓存/队列**：Redis（ElastiCache）
- **存储**：S3

### 沙箱运行时

- **AI SDK**：Pi SDK
- **执行环境**：Docker 起步，后续可替换为 gVisor / MicroVM

### 前端

- **框架**：Next.js 16 SSR
- **样式**：Tailwind CSS v4
- **实时通信**：SSE / WebSocket

### 基础设施

- **容器**：Docker
- **编排**：Docker Compose（开发） / Kubernetes（生产）
- **监控**：Prometheus + Grafana

---

## 🗺 MVP Pyramid

| Stage | 用户得到什么 | 入口 |
|---:|---|---|
| 0 | 最小聊天 MVP | [stage/README.md](./stage/README.md) |
| 1 | 本机工具助手 MVP | [stage/README.md](./stage/README.md) |
| 2 | 本地工作区 MVP | [stage/README.md](./stage/README.md) |
| 3 | 可恢复任务 MVP | [stage/README.md](./stage/README.md) |
| 4 | 个人/小团队产品 MVP | [stage/README.md](./stage/README.md) |
| 5 | 服务化执行 MVP | [stage/README.md](./stage/README.md) |
| 6 | 安全执行 MVP | [stage/README.md](./stage/README.md) |
| 7 | 多节点 SaaS MVP | [stage/README.md](./stage/README.md) |
| 8 | 生产运营 MVP | [stage/README.md](./stage/README.md) |
| 9 | 平台生态 MVP | [stage/README.md](./stage/README.md) |

**实施总览** → [IMPLEMENTATION.md](./IMPLEMENTATION.md)

---

## 📊 生产参考指标

Stage 7+ 才需要按下面指标评估：

| 指标 | 目标值 |
|---|---|
| 并发 task 数 | 100-500 |
| 单 run 平均时长 | 5-10 分钟 |
| Queue wait latency (p95) | < 60s |
| Run execution time (p95) | < 15 分钟 |
| Event persistence lag | < 5s |
| Sandbox creation success rate | > 95% |
| Workspace commit success rate | > 99% |

**详细说明** → [IMPLEMENTATION.md - Stage 7+ 生产参考指标](./IMPLEMENTATION.md#stage-7-生产参考指标)

---

## 💰 生产参考成本

| 项目 | 月成本 |
|---|---|
| Compute / EC2 | $200-400 |
| RDS Postgres | $100 |
| ElastiCache Redis | $50 |
| S3 / Object Storage | $10+ |
| **合计** | **$360-560+** |

这不是 Stage 0 的成本模型。

---

## 📝 文档维护

### 更新原则

1. **架构变更**：更新 ARCHITECTURE.md 和相关模块文档
2. **新增模块**：按所属仓库放入 `control-plane/` 或 `sandbox-runtime/`，跨仓契约放入 `shared/`，并更新本 README
3. **实施进度**：更新 IMPLEMENTATION.md 的 checkbox
4. **保持同步**：代码实现后及时更新文档

### 文档审查

- 每个 PR 如果涉及架构变更，必须同步更新文档
- 每月进行一次文档一致性审查

---

文档是活的，随着系统演进持续更新。
