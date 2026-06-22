# SiriusX

> 分布式 AI Agent 任务执行平台

SiriusX 是一个多租户、可水平扩展的 AI Agent 任务执行平台。用户在工作台中选择 Agent、发起任务，平台在可信控制面中维护长期任务状态，并把每轮执行派发到一次性沙箱运行时中完成。任务可在多轮对话中持续迭代，关闭浏览器或次日返回时全部内容仍在。

---

## 核心概念

| 概念 | 说明 |
|---|---|
| **Task** | 长期任务容器，用户可持续迭代的工作空间，包含对话、产物与 workspace |
| **Run** | 每条用户消息触发的一次执行，拥有独立状态、lease、attempt 和事件流 |
| **Control Worker** | 可信控制面的后台进程，认领 run、构造 `RunSpec`、持久化事件 |
| **Sandbox** | 一次性不可信执行环境（Docker → gVisor/MicroVM），运行 Pi AgentSession、shell、解释器、浏览器，用完即销毁 |

## 仓库结构

本仓库是 SiriusX 的文档与 UI 预览主仓，按仓库信任边界组织文档。生产代码计划拆分为两个仓库：

| 仓库 | 信任级别 | 职责 |
|---|---|---|
| `siriusx-control-plane` | 可信 | Web/API、Auth、租户、TaskStore、Queue、lease、审计、凭证代理 |
| `siriusx-sandbox-runtime` | 一次性/不可信 | Pi AgentSession、shell、解释器、浏览器、临时文件系统、容器适配 |

两仓通过版本化协议通信：控制面发送 `RunSpec`，沙箱运行时回传 `SandboxEvent`、`ArtifactManifest`、`WorkspaceCommitProposal`。

```
SiriusX/
├── AGENTS.md                       # 仓库协作约定
├── README.md                       # 本文件
└── docs/
    ├── ARCHITECTURE.md             # 顶层架构、用户故事、设计原则
    ├── IMPLEMENTATION.md           # 分阶段路线图、性能与容量规划
    ├── STAGE0_SPEC.md              # 阶段 0 规格细化
    ├── STAGE0_AUDIT_REPORT.md      # 阶段 0 架构审计
    ├── UIUX.md                     # UI/UX 设计说明
    ├── schema.sql                  # 数据库 schema
    ├── README.md                   # 文档导航（按仓库划分）
    ├── shared/                     # 跨仓库共用契约与规范
    │   ├── 仓库与信任边界.md
    │   ├── 数据模型.md
    │   ├── 错误码规范.md
    │   ├── 测试场景清单.md
    │   ├── 失败场景.md
    │   └── 部署运维手册.md
    ├── control-plane/              # siriusx-control-plane 模块设计
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
    ├── sandbox-runtime/            # siriusx-sandbox-runtime 模块设计
    │   ├── PiSDK运行器.md
    │   └── 沙箱管理.md
    └── uiux-preview/               # 静态 UI 预览（HTML）
```

## 技术栈

- **控制面**：Bun + NestJS
- **前端**：Next.js 16 SSR + Tailwind CSS v4
- **存储**：Postgres（事实来源）+ S3（workspace 与产物）+ Redis（队列与 ResultBus）
- **沙箱**：Pi SDK，Docker 起步，后续可替换为 gVisor / MicroVM
- **基础设施**：Docker Compose（开发） / Kubernetes（生产），Prometheus + Grafana

## 本地预览

目前仓库只包含文档和静态 UI 预览，无构建流水线。

```bash
# 直接打开静态预览首页
open docs/uiux-preview/index.html

# 或通过本地 HTTP 服务（避免浏览器本地文件限制）
python3 -m http.server 8080 --directory docs/uiux-preview
```

## 文档导航

- **文档总入口**：[docs/README.md](docs/README.md) — 按仓库与角色组织的完整导航
- **架构**：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 用户故事、核心原则、分布式拓扑
- **实施**：[docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) — 分阶段路线图与性能目标
- **信任边界**：[docs/shared/仓库与信任边界.md](docs/shared/仓库与信任边界.md) — 两仓拆分原则与跨仓库协议
- **控制面模块**：[docs/control-plane/](docs/control-plane/) — API、Auth、Task 生命周期、队列、Worker、存储等
- **沙箱运行时模块**：[docs/sandbox-runtime/](docs/sandbox-runtime/) — Pi SDK 运行器、沙箱管理
- **UI 预览**：[docs/uiux-preview/](docs/uiux-preview/) — 登录、Dashboard、任务详情、历史等静态页面

## 当前状态

仓库处于阶段 0（基础设施修正）—— 按信任边界拆仓、Auth 与租户隔离、event runId/sequence、workspace 两阶段提交等基础工作。参见 [STAGE0_SPEC.md](docs/STAGE0_SPEC.md) 与 [IMPLEMENTATION.md](docs/IMPLEMENTATION.md)。

## 贡献

- 架构变更必须同步更新 `docs/ARCHITECTURE.md` 和相关模块文档
- 新增模块按所属仓库放入 `docs/control-plane/` 或 `docs/sandbox-runtime/`；跨仓契约放入 `docs/shared/`，并更新 `docs/README.md`
- 视觉改动在 PR 中附截图
- 提交信息使用祈使句，可选 scope，例如 `docs: update task lifecycle spec`
