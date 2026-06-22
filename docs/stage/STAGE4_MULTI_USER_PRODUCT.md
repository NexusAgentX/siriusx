# Stage 4：个人/小团队产品 MVP

> 一个完整可用的多用户产品：用户能登录、管理自己的历史任务、选择不同 Agent。

---

## 这层产品是什么

Stage 4 把本地工具变成小团队可以使用的产品。每个用户有自己的任务历史和工作区，不会互相看见数据。

---

## 核心用户路径

```text
注册 / 登录
  -> 进入 Dashboard
  -> 选择 Agent
  -> 创建任务
  -> 使用工作台完成任务
  -> 回到历史页面继续旧任务
```

---

## 必须有

- Stage 3 的可恢复任务工作台。
- 登录 / 注册 / 登出。
- session cookie。
- CSRF 防护。
- 用户自己的任务历史。
- 基础 Agent Catalog。
- 用户只能访问自己的任务。

---

## 最小 Agent Catalog

```text
agents
  id
  name
  description
  default_model
  enabled
```

Agent 先可以是内置配置，不需要 marketplace。

---

## 明确不做

- 不做 OAuth。
- 不做复杂 RBAC。
- 不做租户切换。
- 不做分享。
- 不做 Webhook。
- 不做多节点 session 共享。
- 不做企业 admin console。

---

## 完成标准

- 两个用户不能互相访问 task。
- 登录后能完整使用 Stage 3 功能。
- 登出后不能继续访问任务。
- 用户能在历史页面找到旧任务。
- 用户能选择至少两个 Agent。

---

## 这一层的 MVP 价值

小团队可以把 SiriusX 部署成内部工具，而不是只能单人本机使用。
