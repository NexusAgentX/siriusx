# Stage 5：服务化执行 MVP

> 一个完整可用的后台执行产品：Web 服务负责交互，Worker 负责长任务执行。

---

## 这层产品是什么

Stage 5 解决“长任务阻塞 Web 服务”的问题。用户体验不变，但后台从单进程执行升级为 API + Worker 模式。

这仍然可以先是单机部署，但已经是服务化架构。

---

## 核心用户路径

```text
用户发送任务消息
  -> API 创建 run 并入队
  -> Worker 领取 run
  -> Worker 执行 Agent 和工具
  -> API 将事件流给前端
  -> 用户看到任务完成和产物
```

---

## 必须有

- Stage 4 的完整产品体验。
- API 和 Worker 可分进程运行。
- Postgres 作为主要事实来源。
- Redis queue。
- Redis ResultBus 或等价事件转发。
- S3 / MinIO 保存 workspace 和大对象。
- Worker 失败时 run 有明确状态。

---

## 明确不做

- 不做多 Worker 自动接管。
- 不做 run lease。
- 不做沙箱。
- 不做多节点高可用。
- 不做不丢事件承诺。
- 不做 Kubernetes。

---

## 完成标准

- API 进程不直接执行长任务。
- Worker 停止时，新任务不会让 API 崩溃。
- Worker 恢复后可以继续处理 queued run。
- 用户能看到 Worker 执行过程。
- workspace 和 artifact 不依赖 API 进程本地目录。

---

## 这一层的 MVP 价值

用户得到的是更稳定的任务产品：Web 交互和后台执行解耦，长任务不会拖垮前端服务。
