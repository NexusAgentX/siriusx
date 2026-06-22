# Stage 2：本地工作区 MVP

> 一个完整可用的任务工作台：AI 可以围绕一个本地 workspace 产出文件、修改文件、展示产物。

---

## 这层产品是什么

Stage 2 把聊天助手升级成任务工作台。用户不只是得到一段回答，还能得到文档、代码、报告、配置文件等可检查、可下载、可继续迭代的产物。

---

## 核心用户路径

```text
创建任务
  -> 输入目标：“生成一个支付系统架构文档”
  -> AI 在 workspace 中写文件
  -> 用户在右侧看到文件树和产物
  -> 用户打开文件检查
  -> 继续要求修改
  -> AI 更新同一个 workspace
```

---

## 必须有

- Stage 1 的聊天和本机工具能力。
- 每个任务一个本地 workspace。
- 文件树。
- 文件内容预览。
- 产物列表。
- 下载单个文件或打包下载。
- 文件新增/修改/删除状态。
- path guard，禁止逃出 workspace。

---

## 最小数据

```text
tasks
  id
  title
  workspace_path
  status
  created_at
  updated_at

task_artifacts
  task_id
  path
  kind
  status
  size_bytes
  updated_at
```

数据库可以是 SQLite 或 Postgres；重点是产品闭环，不是分布式存储。

---

## 明确不做

- 不做 S3。
- 不做多机器共享 workspace。
- 不做 workspace revision 两阶段提交。
- 不做 Docker 沙箱。
- 不做多人协作。
- 不做复杂任务状态机。

---

## 完成标准

- AI 能生成至少一个文件。
- 用户能在 UI 打开这个文件。
- 用户能要求 AI 修改这个文件。
- UI 能显示文件已修改。
- workspace 只能访问任务目录内部。
- 下载产物可用。

---

## 这一层的 MVP 价值

用户得到的是一个能产出实际文件的 AI 工作台。它已经可以用来写方案、生成代码片段、整理报告或修改小项目。
