# Stage 3：可恢复任务 MVP

> 一个完整可用的长任务工作台：每次执行都有状态，任务可取消、可恢复、可查看过程。

---

## 这层产品是什么

Stage 3 解决“任务跑久了我不知道发生什么”的问题。用户可以放心发起较长任务，看见执行过程，必要时取消，刷新后还能知道任务处于什么状态。

---

## 核心用户路径

```text
创建任务
  -> 发送需求
  -> 系统创建一次 run
  -> 页面显示 run 事件流
  -> 用户刷新页面
  -> 页面恢复 run 状态和已持久化事件
  -> run 完成后显示产物
```

---

## 必须有

- Stage 2 的任务工作台。
- `Task` 和 `Run` 概念分离。
- 每次用户消息创建一个 run。
- run 状态：`queued | running | completed | failed | cancelled`。
- run 事件流。
- run 取消。
- active run 冲突处理。
- 失败后用户可以继续下一轮。

---

## 最小数据

```text
task_runs
  id
  task_id
  status
  prompt
  started_at
  completed_at
  error

task_events
  id
  task_id
  run_id
  sequence
  type
  payload
  created_at
```

Stage 3 可以仍然单进程运行。重点是用户可见的任务状态和恢复体验。

---

## 明确不做

- 不做多 Worker。
- 不做 Redis 队列。
- 不做 run lease。
- 不做跨节点恢复。
- 不做不丢事件承诺。
- 不做同一 task 多 run 并发。

---

## 完成标准

- 每次执行都有 run 记录。
- 刷新后能看到当前 run 状态。
- 用户能取消 running run。
- run 失败后 task 不报废。
- 同一 task 正在 running 时，新消息返回明确冲突提示。
- 事件能按顺序展示。

---

## 这一层的 MVP 价值

用户得到的是一个可靠得多的 AI 工作台。长任务不再像一次性聊天请求，用户能看见过程、处理失败、继续迭代。
