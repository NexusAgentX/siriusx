# Stage 8：生产运营 MVP

> 一个完整可运营的生产服务：有监控、告警、备份、限流、审计和故障处理手册。

---

## 这层产品是什么

Stage 8 解决“服务上线后谁来负责、坏了怎么知道、数据怎么恢复”的问题。它不增加太多用户侧新功能，但让产品可以被稳定运营。

---

## 核心运维路径

```text
系统出现 run 延迟升高
  -> 告警触发
  -> 运维查看 dashboard
  -> 定位 queue / worker / sandbox / database 瓶颈
  -> 按 runbook 处理
  -> 事故后能审计影响范围
```

---

## 必须有

- Stage 7 的多节点 SaaS。
- 结构化日志。
- request id / trace id / task id / run id 贯穿。
- Prometheus metrics。
- Grafana dashboard。
- 告警规则。
- Postgres 备份和恢复演练。
- S3 lifecycle。
- Redis 持久化策略。
- rate limit。
- quota。
- audit log 查询。
- runbook。

---

## 明确不做

- 不做大型企业协作套件。
- 不做 marketplace。
- 不做复杂工作流编排。
- 不做跨区域 active-active。
- 不做所有高级能力一次性上线。

---

## 完成标准

- 核心指标有 dashboard。
- queue 堆积、Worker 大量失败、sandbox 创建失败会告警。
- 备份能恢复到新环境。
- 发布失败能回滚。
- 生产数据访问有审计。
- 常见故障有处理手册。

---

## 这一层的 MVP 价值

团队可以认真运营 SiriusX，而不是靠人工盯日志和临时修数据库。
