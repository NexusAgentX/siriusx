# SiriusX Platform 技术文档

> 分布式 AI Agent 任务执行平台完整技术规格

---

## 📚 文档结构

```
docs/SiriusX/
├── ARCHITECTURE.md           # 顶层架构、用户故事、设计原则
├── IMPLEMENTATION.md          # 实施计划、性能目标、分阶段路线图
├── README.md                  # 本文件
└── modules/                   # 模块详细设计
    ├── 仓库与信任边界.md
    ├── 数据模型.md
    ├── 存储模块.md
    ├── 任务生命周期.md
    ├── 队列与租约.md
    ├── Worker执行.md
    ├── PiSDK运行器.md
    ├── 工作区提供器.md
    ├── 沙箱管理.md
    ├── 事件持久化.md
    ├── 恢复与查询.md
    ├── 前端优化.md
    ├── 上下文优化.md
    ├── 产物与文件树优化.md
    ├── 短生命周期会话.md
    ├── API端点.md
    ├── Auth实现详解.md
    ├── 部署运维手册.md
    ├── 测试场景清单.md
    ├── 失败场景.md
    └── 错误码规范.md
```

---

## 🚀 快速导航

### 新人上手

1. **了解用户视角** → [ARCHITECTURE.md - 用户故事（通俗版）](./ARCHITECTURE.md#用户故事)
2. **理解核心设计** → [ARCHITECTURE.md - 核心原则](./ARCHITECTURE.md#核心原则)
3. **查看实施计划** → [IMPLEMENTATION.md](./IMPLEMENTATION.md)

### 工程师视角

1. **系统拓扑** → [ARCHITECTURE.md - 分布式拓扑](./ARCHITECTURE.md#分布式拓扑)
2. **仓库与信任边界** → [仓库与信任边界.md](./modules/仓库与信任边界.md)
3. **数据模型** → [数据模型.md](./modules/数据模型.md)
4. **存储设计** → [存储模块.md](./modules/存储模块.md)
5. **队列和调度** → [队列与租约.md](./modules/队列与租约.md)

### 前端开发者

1. **API 端点** → [API端点.md](./modules/API端点.md)
2. **断线恢复** → [恢复与查询.md](./modules/恢复与查询.md)
3. **轮询优化** → [前端优化.md](./modules/前端优化.md)
4. **产物展示** → [产物与文件树优化.md](./modules/产物与文件树优化.md)

### 后端开发者

1. **Control Worker 执行** → [Worker执行.md](./modules/Worker执行.md)
2. **Pi SDK 集成** → [PiSDK运行器.md](./modules/PiSDK运行器.md)
3. **Sandbox 管理** → [沙箱管理.md](./modules/沙箱管理.md)
4. **事件持久化** → [事件持久化.md](./modules/事件持久化.md)

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

**详细说明** → [仓库与信任边界.md](./modules/仓库与信任边界.md)

---

### 2. 短生命周期会话

**问题**：如果 AI 一直保持记忆，100 个用户会占用 200GB 内存。

**方案**：每次执行创建新 session，从数据库恢复上下文。

**详细说明** → [短生命周期会话.md](./modules/短生命周期会话.md)

---

### 3. Postgres + S3 一致性

**问题**：如何保证 Postgres 指针和 S3 对象的一致性？

**方案**：两阶段提交 + 状态机（pending → uploading → committed）。

**详细说明** → [存储模块.md](./modules/存储模块.md)

---

### 4. Stateless Sandbox

**问题**：节点亲和性调度复杂，Control Worker 与 sandbox runtime 强绑定节点不灵活。

**方案**：每次 run 创建新 sandbox，用完即销毁（开销 < 2%）。

**详细说明** → [沙箱管理.md](./modules/沙箱管理.md)

---

### 5. Run-scoped Event Sequence

**问题**：全局 event sequence 难以断线恢复。

**方案**：每个 run 独立的 sequence（从 1 开始）。

**详细说明** → [事件持久化.md](./modules/事件持久化.md)

---

### 6. Task Summary 自动刷新

**问题**：完整历史会超过 context window。

**方案**：定期刷新 summary（10 runs / 30k tokens / 50 files）。

**详细说明** → [上下文优化.md](./modules/上下文优化.md)

---

## 🛠 技术栈

### 后端

- **控制面运行时**：Bun + NestJS
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

## 📊 性能目标

| 指标 | 目标值 |
|---|---|
| 并发 task 数 | 100-500 |
| 单 run 平均时长 | 5-10 分钟 |
| Queue wait latency (p95) | < 60s |
| Run execution time (p95) | < 15 分钟 |
| Event persistence lag | < 5s |
| Sandbox creation success rate | > 95% |
| Workspace commit success rate | > 99% |

**详细说明** → [IMPLEMENTATION.md - 性能目标](./IMPLEMENTATION.md#性能目标和容量规划)

---

## 💰 成本估算

| 项目 | 月成本 |
|---|---|
| EC2（6-12 实例） | $200-400 |
| RDS Postgres | $100 |
| ElastiCache Redis | $50 |
| S3 存储 | $10 |
| **总计** | **$360-560** |

---

## 🗺 实施路线图

### 阶段 0：基础设施修正

修正架构边界冲突，为多节点部署做准备。**阶段 0 包含仓库信任边界和 Auth，这是安全边界的基础。**

**目标清单**：
- 🎯 仓库与信任边界
- 🎯 Auth 和租户边界
- 🎯 Event runId/sequence 改造
- 🎯 Task 创建分离 prompt
- 🎯 Task 锁定 Agent 版本
- 🎯 Workspace revision 两阶段提交
- 🎯 Workspace revision 并发控制

### 阶段 1：队列和 Control Worker 扩容

支持 2+ Control Worker 节点并发处理。

**目标清单**：
- 🎯 Redis Queue 集成
- 🎯 Run Lease 管理
- 🎯 Task Summary 异步刷新（后台 job，不阻塞 run）
- 🎯 前端优化

### 阶段 2：Stateless Sandbox

按需创建 sandbox，简化故障恢复。

- ✅ Stateless Sandbox Provider

### 阶段 3：S3 Workspace 性能优化

S3 Workspace 增量上传、本地缓存、并行传输优化。

**注意**：S3 Workspace 基础实现已在阶段 0 完成，本阶段专注于性能优化。

### 阶段 4：生产优化（持续）

监控、成本优化、性能调优和灾难恢复。


---

## ✅ 最小可行原型

**目标**：2 API + 2 Control Worker + 独立 sandbox runtime，稳定运行 1000+ runs

**验证点**：
1. Auth 租户隔离和权限边界
2. Control Worker 崩溃恢复
3. API 节点重启恢复
4. Workspace 连续性
5. Event 持久化降级
6. Workspace 冲突检测

**详细说明** → [IMPLEMENTATION.md - 最小可行原型验证](./IMPLEMENTATION.md#最小可行原型验证)

---

## 📝 文档维护

### 更新原则

1. **架构变更**：更新 ARCHITECTURE.md 和相关模块文档
2. **新增模块**：在 modules/ 下创建新文档，更新本 README
3. **实施进度**：更新 IMPLEMENTATION.md 的 checkbox
4. **保持同步**：代码实现后及时更新文档

### 文档审查

- 每个 PR 如果涉及架构变更，必须同步更新文档
- 每月进行一次文档一致性审查

---

## 🔗 相关文档

- [根目录 AGENTS.md](../AGENTS.md) - 开发者上手指南
- [ARCHITECTURE.md](./ARCHITECTURE.md) - 平台架构

---

## 💬 反馈和贡献

如发现文档错误或有改进建议，请：

1. 提交 Issue 说明问题
2. 或直接提交 PR 修复

文档是活的，随着系统演进持续更新。
