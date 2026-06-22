# Stage 6：安全执行 MVP

> 一个完整可用的安全版 Agent 产品：命令、解释器、浏览器等不可信执行进入沙箱。

---

## 这层产品是什么

Stage 6 解决“AI 执行工具太危险”的问题。用户仍然用同一个工作台，但工具执行不再直接发生在可信控制面或普通 Worker 主机环境里。

---

## 核心用户路径

```text
用户发起需要工具的任务
  -> Worker 构造 RunSpec
  -> Sandbox Runtime 创建隔离环境
  -> Agent 在沙箱中执行工具
  -> 沙箱回传事件和 workspace 提交建议
  -> 控制面校验并提交结果
```

---

## 必须有

- Stage 5 的服务化执行产品。
- Sandbox Runtime 服务。
- Docker sandbox provider。
- run-scoped capability token。
- workspace 挂载或 materialize。
- sandbox 结束后销毁。
- orphan sandbox 清理。
- 控制面做最终权限和路径校验。

---

## 明确不做

- 不做 sandbox pool。
- 不做节点亲和性。
- 不做 MicroVM。
- 不做用户自定义 host extension。
- 不让 sandbox 持有长期数据库或 S3 凭证。
- 不让 sandbox 直接推进 task 状态。

---

## 完成标准

- shell 命令不在 API/Worker 主进程直接执行。
- sandbox 只能访问当前 run 的 workspace。
- sandbox 没有长期云凭证。
- run 结束后 sandbox 被销毁。
- sandbox 创建失败时，用户看到明确错误。
- 控制面仍是 task/run/workspace 的事实来源。

---

## 这一层的 MVP 价值

用户可以更放心地让 AI 运行命令、解释器和浏览器。这是从“能用”走向“敢用”的关键层。
