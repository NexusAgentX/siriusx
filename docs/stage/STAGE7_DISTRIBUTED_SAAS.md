# Stage 7：多节点 SaaS MVP

> 一个完整可用的早期 SaaS：多 API、多 Worker、多租户，具备基本崩溃恢复。

---

## 这层产品是什么

Stage 7 把安全执行产品升级成可横向扩展的 SaaS。多个用户和团队可以共享一套服务，Worker 崩溃后任务可以被其他 Worker 接管。

---

## 核心用户路径

```text
租户用户登录
  -> 创建任务
  -> API 入队 run
  -> 任意 Worker claim run
  -> Worker heartbeat 维持 lease
  -> Worker 崩溃
  -> lease 过期
  -> 其他 Worker 接管或重试
  -> 用户最终看到任务状态和产物
```

---

## 必须有

- Stage 6 的安全执行产品。
- tenant 数据模型。
- tenant/user/task 权限边界。
- Redis session store。
- run lease。
- heartbeat。
- LeaseSweeper。
- 多 API 节点。
- 多 Worker 节点。
- S3/MinIO workspace 可被任意 Worker materialize。

---

## 明确不做

- 不做复杂企业 RBAC。
- 不做分享链接。
- 不做 Webhook。
- 不做 sandbox pool。
- 不做 S3 event backup。
- 不承诺未落库流式 token 不丢。
- 不做跨区域高可用。

---

## 完成标准

- 两个 API 节点可同时服务请求。
- 两个 Worker 节点可同时处理不同 task。
- 杀掉一个 Worker 后，run 能被接管或明确失败并可重试。
- 不同 tenant 不能互相访问 task、artifact、workspace。
- API 重启后用户能恢复任务状态。
- 连续 1000 个 run 无严重状态损坏。

---

## 这一层的 MVP 价值

SiriusX 可以作为早期 SaaS 对外试运行。它不是只适合单机或小团队，而是具备基本多租户和分布式恢复能力。
