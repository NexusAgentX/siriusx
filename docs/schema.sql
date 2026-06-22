-- SiriusX Platform Database Schema
-- PostgreSQL 16+
-- 
-- 部署说明：
-- 1. 本文件包含完整的表结构、索引、约束
-- 2. 适用于从零初始化数据库
-- 3. 生产环境建议使用迁移工具（如 node-pg-migrate）管理版本
-- 4. 所有时间戳使用 bigint（Unix milliseconds），SQL 示例统一使用 EXTRACT(EPOCH FROM NOW())::bigint * 1000

-- ============================================================================
-- 用户和租户（Auth 模块）
-- ============================================================================

-- 租户表
CREATE TABLE IF NOT EXISTS tenants (
  id TEXT PRIMARY KEY,                    -- tenant_<uuid>
  name TEXT NOT NULL,                     -- 租户名称
  slug TEXT NOT NULL UNIQUE,              -- URL 友好标识符
  owner_user_id TEXT,                     -- 租户所有者（外键关联 users.id）
  plan TEXT NOT NULL DEFAULT 'free',      -- 套餐：free | pro | enterprise
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at BIGINT NOT NULL,
  updated_at BIGINT
);

CREATE INDEX IF NOT EXISTS tenants_slug_idx ON tenants(slug);
CREATE INDEX IF NOT EXISTS tenants_owner_idx ON tenants(owner_user_id);

COMMENT ON TABLE tenants IS '租户表：多租户隔离的基础';
COMMENT ON COLUMN tenants.slug IS 'URL 友好标识符，用于子域名或路径';

-- 用户表
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,                    -- user_<uuid>
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,            -- bcrypt hash
  tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'user',      -- user | tenant_admin | admin
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at BIGINT NOT NULL,
  last_login_at BIGINT,
  updated_at BIGINT
);

CREATE INDEX IF NOT EXISTS users_tenant_id_idx ON users(tenant_id);
CREATE INDEX IF NOT EXISTS users_email_idx ON users(email);
CREATE INDEX IF NOT EXISTS users_role_idx ON users(role);

COMMENT ON TABLE users IS '用户表：存储用户凭据和基本信息';
COMMENT ON COLUMN users.password_hash IS 'bcrypt hash，cost=10';

-- ============================================================================
-- 任务执行核心（Task 模块）
-- ============================================================================

-- 任务表
CREATE TABLE IF NOT EXISTS tasks (
  id TEXT PRIMARY KEY,                    -- task_<uuid>
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'running'  -- running | running_degraded | completed | failed | cancelled
    CHECK (status IN ('running', 'running_degraded', 'completed', 'failed', 'cancelled')),

  -- Workspace 引用
  workspace_id TEXT NOT NULL,             -- 本地目录名（单节点开发用）
  workspace_ref TEXT,                     -- durable workspace 引用（阶段 0+ S3）
  latest_workspace_revision TEXT,         -- 最新已提交的 revision

  -- Agent 版本锁定
  agent TEXT NOT NULL,                    -- Agent 名称
  agent_ref TEXT,                         -- Git ref 或版本标识
  agent_commit TEXT,                      -- Git commit hash
  template_dir TEXT,                      -- Agent 模板目录路径

  -- 模型配置
  model TEXT,                             -- 使用的模型

  -- 状态追踪
  warnings TEXT[],                        -- 警告信息列表
  error TEXT,                             -- 失败原因

  -- 时间戳
  created_at BIGINT NOT NULL,
  started_at BIGINT,
  completed_at BIGINT,
  updated_at BIGINT
);

CREATE INDEX IF NOT EXISTS tasks_user_created_idx ON tasks(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS tasks_tenant_created_idx ON tasks(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS tasks_status_idx ON tasks(status);
CREATE INDEX IF NOT EXISTS tasks_workspace_ref_idx ON tasks(workspace_ref);

COMMENT ON TABLE tasks IS '任务表：表示一个用户可持续迭代的工作空间';
COMMENT ON COLUMN tasks.workspace_ref IS '阶段 0+ 使用，格式：workspace://<tenantId>/<taskId>/<revision>（S3-backed）';
COMMENT ON COLUMN tasks.agent_commit IS 'Agent 版本锁定，确保执行一致性';

-- 任务消息表
CREATE TABLE IF NOT EXISTS task_messages (
  id TEXT PRIMARY KEY,                    -- msg_<uuid>
  task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  run_id TEXT,                            -- 关联的 run（可选；FK 在 task_runs 建表后用 ALTER TABLE 添加，避免循环外键）
  role TEXT NOT NULL                      -- user | assistant | tool
    CHECK (role IN ('user', 'assistant', 'tool')),
  parts JSONB NOT NULL,                   -- MessagePart[] 序列化
  created_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS task_messages_task_created_idx ON task_messages(task_id, created_at ASC);
CREATE INDEX IF NOT EXISTS task_messages_run_idx ON task_messages(run_id);

COMMENT ON TABLE task_messages IS '任务消息表：存储用户和助手的对话历史';
COMMENT ON COLUMN task_messages.parts IS 'MessagePart 数组：text | tool-call | tool-result';

-- 任务执行单元表（Run）
CREATE TABLE IF NOT EXISTS task_runs (
  id TEXT PRIMARY KEY,                    -- run_<uuid>
  task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  message_id TEXT REFERENCES task_messages(id) ON DELETE SET NULL,  -- 触发本次 run 的用户消息 ID
  status TEXT NOT NULL DEFAULT 'queued'   -- queued | running | completed | completed_with_warnings | failed | cancelled
    CHECK (status IN ('queued', 'running', 'completed', 'completed_with_warnings', 'failed', 'cancelled')),
  prompt TEXT NOT NULL,                   -- 用户输入
  attempt INT NOT NULL DEFAULT 1,         -- 重试次数（从 1 开始）

  -- Workspace 版本控制（乐观锁）
  base_workspace_revision TEXT,           -- 本次 run 基于的版本
  committed_workspace_revision TEXT,      -- 本次 run 提交的版本

  -- 事件序列（断线恢复）
  last_event_sequence INT NOT NULL DEFAULT 0,

  -- 分布式调度（Lease）
  lease_owner_node_id TEXT,               -- 持有 lease 的 Worker 节点 ID
  lease_expires_at BIGINT,                -- Lease 过期时间
  heartbeat_at BIGINT,                    -- 最后心跳时间

  -- 状态追踪
  warnings TEXT[],                        -- 警告信息列表
  error TEXT,                             -- 失败原因
  
  -- 时间戳
  created_at BIGINT NOT NULL,
  started_at BIGINT,
  completed_at BIGINT,
  updated_at BIGINT
);

CREATE INDEX IF NOT EXISTS task_runs_task_created_idx ON task_runs(task_id, created_at ASC);
CREATE INDEX IF NOT EXISTS task_runs_status_idx ON task_runs(status);
CREATE INDEX IF NOT EXISTS task_runs_lease_expires_idx ON task_runs(lease_expires_at) WHERE status = 'running';
CREATE INDEX IF NOT EXISTS task_runs_message_idx ON task_runs(message_id);

COMMENT ON TABLE task_runs IS '任务执行单元表：每条用户消息触发一次执行';
COMMENT ON COLUMN task_runs.attempt IS '重试次数，用于指数退避策略';
COMMENT ON COLUMN task_runs.base_workspace_revision IS '乐观锁：防止并发修改冲突';
COMMENT ON COLUMN task_runs.last_event_sequence IS '该 run 最后一个 event 的 sequence';

-- 🚨 循环外键处理：task_messages.run_id -> task_runs(id)
-- task_messages 和 task_runs 互相引用，必须先建表再用 ALTER TABLE 添加外键（见 STAGE0_SPEC §3.1）。
ALTER TABLE task_messages
  ADD CONSTRAINT task_messages_run_id_fkey
  FOREIGN KEY (run_id) REFERENCES task_runs(id) ON DELETE SET NULL;

-- 任务事件表
CREATE TABLE IF NOT EXISTS task_events (
  id TEXT PRIMARY KEY,                    -- evt_<uuid>
  task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  run_id TEXT NOT NULL REFERENCES task_runs(id) ON DELETE CASCADE,
  sequence INT NOT NULL,                  -- Run-scoped 序列号（从 1 开始）
  type TEXT NOT NULL,                     -- 事件类型
  payload JSONB NOT NULL,                 -- 事件内容
  created_at BIGINT NOT NULL,

  -- 唯一约束：同一个 run 内 sequence 必须唯一
  UNIQUE(task_id, run_id, sequence)
);

CREATE INDEX IF NOT EXISTS task_events_task_created_idx ON task_events(task_id, created_at ASC);
CREATE INDEX IF NOT EXISTS task_events_run_seq_idx ON task_events(run_id, sequence ASC);

COMMENT ON TABLE task_events IS '任务事件表：存储执行过程中的所有事件';
COMMENT ON COLUMN task_events.sequence IS 'Run-scoped 序列号，用于断线恢复';
COMMENT ON COLUMN task_events.task_id IS '冗余字段，必须与 run_id 对应的 task_id 一致（应用层保证）';

-- 🚨 数据完整性约束说明：
-- task_events.task_id 必须等于 task_runs.task_id（通过 run_id 关联）
-- 由于 PostgreSQL 不支持跨表 CHECK 约束，这个约束由应用层保证
-- 写入时必须先查询 run.task_id，确保一致性

-- 任务产物表
CREATE TABLE IF NOT EXISTS task_artifacts (
  task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  path TEXT NOT NULL,                     -- 文件路径
  kind TEXT NOT NULL                      -- document | file | code | image
    CHECK (kind IN ('document', 'file', 'code', 'image')),
  status TEXT NOT NULL                    -- generated | modified | template | deleted
    CHECK (status IN ('generated', 'modified', 'template', 'deleted')),
  workspace_revision TEXT,                -- 关联的 workspace revision

  -- S3 存储引用（阶段 0+ 使用）
  object_key TEXT,                        -- S3 对象键
  etag TEXT,                              -- S3 ETag，用于校验
  content_type TEXT,
  size_bytes BIGINT,

  updated_at BIGINT NOT NULL,

  PRIMARY KEY (task_id, path)
);

CREATE INDEX IF NOT EXISTS task_artifacts_task_updated_idx ON task_artifacts(task_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS task_artifacts_revision_idx ON task_artifacts(workspace_revision);

COMMENT ON TABLE task_artifacts IS '任务产物表：存储生成的文件元数据';
COMMENT ON COLUMN task_artifacts.object_key IS 'S3 对象键，格式：tenants/<tenantId>/tasks/<taskId>/artifacts/...';

-- 任务摘要表（上下文优化）
CREATE TABLE IF NOT EXISTS task_summaries (
  task_id TEXT PRIMARY KEY REFERENCES tasks(id) ON DELETE CASCADE,
  summary TEXT NOT NULL,                  -- 压缩后的上下文摘要
  run_count INT NOT NULL DEFAULT 0,       -- 已完成的 run 数量
  token_count BIGINT NOT NULL DEFAULT 0,  -- 累计 token 数
  artifact_count INT NOT NULL DEFAULT 0,  -- 产物数量
  updated_at_run_count INT NOT NULL DEFAULT 0, -- 上次更新摘要时的 run 数量
  consecutive_failures INT NOT NULL DEFAULT 0, -- 连续失败次数
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);

COMMENT ON TABLE task_summaries IS '任务摘要表：压缩上下文，避免超过 context window';
COMMENT ON COLUMN task_summaries.consecutive_failures IS '连续失败次数计数；阶段 0 仅写 warning 和 counter，不自动切换 task 到 running_degraded（见 STAGE0_SPEC §5.7）';

-- ============================================================================
-- Workspace 版本控制（阶段 0+：local 和 S3 双轨，见 STAGE0_SPEC §8）
-- ============================================================================

-- Workspace Revision 表
CREATE TABLE IF NOT EXISTS workspace_revisions (
  id TEXT PRIMARY KEY,                    -- rev_<uuid>
  task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  workspace_ref TEXT NOT NULL,            -- workspace://<tenantId>/<taskId>
  revision TEXT NOT NULL,                 -- 单调递增或内容寻址
  base_revision TEXT,                     -- 基于的版本
  
  -- 两阶段提交状态机
  status TEXT NOT NULL DEFAULT 'pending'  -- pending | uploading | committed | failed
    CHECK (status IN ('pending', 'uploading', 'committed', 'failed')),
  
  -- S3 引用
  manifest_object_key TEXT,               -- S3 manifest 路径
  manifest_etag TEXT,                     -- Manifest ETag
  
  committed_run_id TEXT REFERENCES task_runs(id),
  
  -- 时间戳
  created_at BIGINT NOT NULL,
  committed_at BIGINT,                    -- 提交成功时间
  expires_at BIGINT,                      -- pending/uploading 状态的 TTL
  
  UNIQUE(task_id, revision)
);

CREATE INDEX IF NOT EXISTS workspace_revisions_task_created_idx ON workspace_revisions(task_id, created_at DESC);
CREATE INDEX IF NOT EXISTS workspace_revisions_status_expires_idx ON workspace_revisions(status, expires_at) 
  WHERE status IN ('pending', 'uploading');

COMMENT ON TABLE workspace_revisions IS 'Workspace 版本表：两阶段提交保证 PG + S3 一致性';
COMMENT ON COLUMN workspace_revisions.status IS 'pending → uploading → committed 或 failed';
COMMENT ON COLUMN workspace_revisions.expires_at IS 'pending/uploading 状态超时后自动清理';

-- ============================================================================
-- 任务执行锁（防止并发）
-- ============================================================================

CREATE TABLE IF NOT EXISTS task_locks (
  task_id TEXT PRIMARY KEY REFERENCES tasks(id) ON DELETE CASCADE,
  run_id TEXT NOT NULL,                   -- 当前持有锁的 run
  owner_node_id TEXT NOT NULL,            -- 持有锁的 Worker 节点
  expires_at BIGINT NOT NULL,
  heartbeat_at BIGINT NOT NULL,
  created_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS task_locks_expires_idx ON task_locks(expires_at);

COMMENT ON TABLE task_locks IS '任务执行锁：保证同一 Task 串行执行';

-- ============================================================================
-- 审计日志（安全和合规）
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_logs (
  id TEXT PRIMARY KEY,                    -- log_<uuid>
  tenant_id TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  actor_type TEXT NOT NULL                -- user | api-token | worker | system
    CHECK (actor_type IN ('user', 'api-token', 'worker', 'system')),
  action TEXT NOT NULL,                   -- task:create | task:delete | workspace:read | ...
  resource_type TEXT NOT NULL,            -- task | workspace | artifact | user
  resource_id TEXT,
  ip_address TEXT,
  user_agent TEXT,
  metadata JSONB,
  created_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS audit_logs_tenant_created_idx ON audit_logs(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS audit_logs_user_created_idx ON audit_logs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS audit_logs_resource_idx ON audit_logs(resource_type, resource_id);
CREATE INDEX IF NOT EXISTS audit_logs_action_idx ON audit_logs(action);

-- ============================================================================
-- 说明：阶段 0-2 采用 Stateless Sandbox 策略
-- ============================================================================

-- 阶段 0-2 不实现 sandbox_leases 表
-- Sandbox 随 run 创建/销毁，状态仅存在于 Sandbox runtime 进程内存
-- Orphan 容器通过 Docker labels 扫描清理，不依赖数据库

-- 未来扩展（阶段 4+）：如果需要 task-scoped sandbox pool，再引入 sandbox_leases 表

-- ============================================================================
-- ALTER TABLE task_events SET (autovacuum_vacuum_scale_factor = 0.05);

-- 3. 分区策略（数据量大时）
-- 未来可以对 task_events、audit_logs 按月分区

-- ============================================================================
-- 迁移脚本模板
-- ============================================================================

-- 新增字段示例：
-- ALTER TABLE tasks ADD COLUMN IF NOT EXISTS new_field TEXT;
-- CREATE INDEX IF NOT EXISTS tasks_new_field_idx ON tasks(new_field);

-- 数据迁移示例：
-- UPDATE tasks SET new_field = 'default_value' WHERE new_field IS NULL;

-- 回滚示例：
-- ALTER TABLE tasks DROP COLUMN IF EXISTS new_field;
