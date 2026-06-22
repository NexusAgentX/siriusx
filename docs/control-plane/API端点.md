# API 端点详细规格

> 完整的 HTTP API 定义，包含请求/响应格式、错误码、鉴权规则

---

## 通用规范

### 基础 URL

```
开发环境: http://localhost:3000
生产环境: https://api.siriusx.com
```

### 鉴权方式

所有端点（除 `/api/auth/*`）都需要 Session Cookie：

```
Cookie: siriusx.sid=<session-id>
```

**🚨 CSRF 保护（阶段 0 必需）**：

所有写操作（POST/PUT/DELETE/PATCH）必须携带 CSRF token：

```
X-XSRF-TOKEN: <csrf-token>
```

**获取 CSRF token**：

1. 登录后，从 `/api/auth/csrf` 获取 token
2. 或从 Cookie `XSRF-TOKEN` 读取（自动设置）

**示例**：

```bash
# 获取 CSRF token
curl -X GET https://api.siriusx.com/api/auth/csrf \
  -H "Cookie: siriusx.sid=<session-id>"

# 响应
{
  "csrfToken": "a1b2c3d4e5f6..."
}

# 使用 CSRF token 发送写请求
curl -X POST https://api.siriusx.com/api/task \
  -H "Cookie: siriusx.sid=<session-id>" \
  -H "X-XSRF-TOKEN: a1b2c3d4e5f6..." \
  -H "Content-Type: application/json" \
  -d '{"title": "New Task", "agent": "architecture"}'
```

未登录返回：

```json
{
  "statusCode": 401,
  "code": "AUTH_REQUIRED",
  "message": "Please login to continue"
}
```

CSRF token 缺失或无效返回：

```json
{
  "statusCode": 403,
  "code": "CSRF_TOKEN_INVALID",
  "message": "CSRF token is missing or invalid"
}
```

### 通用响应头

```
Content-Type: application/json
X-Request-ID: <uuid>
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1718100000
```

### 错误响应格式

```json
{
  "statusCode": 400,
  "code": "VALIDATION_ERROR",
  "message": "Invalid request body",
  "errors": [
    {
      "field": "title",
      "message": "Title is required"
    }
  ]
}
```

---

## Auth 端点

### POST /api/auth/register

注册新用户并创建租户

**请求体**：

```json
{
  "email": "user@example.com",
  "password": "SecureP@ss123",
  "tenantName": "Acme Corp"
}
```

**验证规则**：
- `email`: 必填，有效邮箱格式
- `password`: 必填，最小 8 字符，包含大小写字母和数字
- `tenantName`: 必填，2-100 字符

**响应**：`201 Created`

```json
{
  "userId": "user_507f1f77bcf86cd799439011",
  "tenantId": "tenant_507f1f77bcf86cd799439012",
  "email": "user@example.com",
  "role": "tenant_admin",
  "csrfToken": "a1b2c3d4e5f6..."
}
```

**说明**：
- 注册成功后自动登录，设置 Session Cookie
- 响应包含 CSRF token（也会设置到 Cookie）

**错误码**：

| Code | Status | 说明 |
|---|---|---|
| `EMAIL_ALREADY_EXISTS` | 409 | 邮箱已注册 |
| `WEAK_PASSWORD` | 400 | 密码强度不足 |
| `INVALID_EMAIL` | 400 | 邮箱格式错误 |

---

### GET /api/auth/csrf

获取 CSRF token

**响应**：`200 OK`

```json
{
  "csrfToken": "a1b2c3d4e5f6..."
}
```

**说明**：
- 登录后调用此端点获取 CSRF token
- Token 也会自动设置到 Cookie `XSRF-TOKEN`
- 所有写操作（POST/PUT/DELETE/PATCH）必须携带 `X-XSRF-TOKEN` header

**错误码**：

| Code | Status | 说明 |
|---|---|---|
| `AUTH_REQUIRED` | 401 | 未登录 |

---

### POST /api/auth/login

用户登录

**请求体**：

```json
{
  "email": "user@example.com",
  "password": "SecureP@ss123"
}
```

**响应**：`200 OK`

```json
{
  "userId": "user_507f1f77bcf86cd799439011",
  "tenantId": "tenant_507f1f77bcf86cd799439012",
  "email": "user@example.com",
  "role": "tenant_admin",
  "csrfToken": "a1b2c3d4e5f6..."
}
```

**说明**：
- 登录成功后自动设置 Session Cookie
- 响应包含 CSRF token（也会设置到 Cookie）

**错误码**：

| Code | Status | 说明 |
|---|---|---|
| `INVALID_CREDENTIALS` | 401 | 邮箱或密码错误 |
| `ACCOUNT_DISABLED` | 403 | 账户已被禁用 |

---

### POST /api/auth/logout

退出登录

**请求体**：无

**响应**：`204 No Content`

---

### GET /api/auth/me

获取当前用户信息

**响应**：`200 OK`

```json
{
  "userId": "user_507f1f77bcf86cd799439011",
  "tenantId": "tenant_507f1f77bcf86cd799439012",
  "email": "user@example.com",
  "role": "tenant_admin"
}
```

**错误码**：

| Code | Status | 说明 |
|---|---|---|
| `AUTH_REQUIRED` | 401 | 未登录 |

---

## Agent 端点

### GET /api/agents

获取 Agent Catalog 列表

**响应**：`200 OK`

```json
{
  "agents": [
    {
      "id": "architecture",
      "name": "Architecture Advisor",
      "description": "帮助设计系统架构",
      "version": "1.0.0",
      "tags": ["backend", "architecture"],
      "icon": "🏗️"
    },
    {
      "id": "frontend",
      "name": "Frontend Developer",
      "description": "构建现代前端应用",
      "version": "1.2.0",
      "tags": ["frontend", "react", "typescript"],
      "icon": "💻"
    }
  ]
}
```

---

## Task 端点

### POST /api/task

创建任务

**请求体**：

```json
{
  "title": "支付系统架构设计",
  "agent": "architecture",
  "model": "claude-opus-4-8"
}
```

**请求体**（对齐 STAGE0_SPEC §5.1）：

```json
{
  "agent": "architecture",
  "model": "claude-opus-4-8",
  "title": "支付系统架构设计"  // 可选
}
```

**验证规则**：
- `agent`: 必填，必须是有效的 Agent ID
- `model`: 可选，默认使用 Agent 推荐模型
- `title`: 可选，1-200 字符；未提供时后端设置临时标题（如 `Untitled Task`）
- `agentRef` / `agentCommit` / `templateDir`: 由后端从 AgentCatalog 锁定，不接受客户端提交

**响应**：`201 Created`

```json
{
  "task": {
    "id": "task_507f1f77bcf86cd799439013",
    "userId": "user_507f1f77bcf86cd799439011",
    "tenantId": "tenant_507f1f77bcf86cd799439012",
    "title": "支付系统架构设计",
    "status": "running",
    "workspaceId": "ws_507f1f77bcf86cd799439014",
    "agent": "architecture",
    "agentRef": "v1.0.0",
    "agentCommit": "abc123def456",
    "model": "claude-opus-4-8",
    "createdAt": 1718100000000
  }
}
```

**cURL 示例**：

```bash
curl -X POST https://api.siriusx.com/api/task \
  -H "Cookie: siriusx.sid=<session-id>" \
  -H "X-XSRF-TOKEN: <csrf-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "支付系统架构设计",
    "agent": "architecture",
    "model": "claude-opus-4-8"
  }'
```

**说明**：
- `userId` 和 `tenantId` 从 AuthContext 自动推导
- 创建后 Task 状态为 `running`，但没有 active run
- 必须调用 `/api/task/:taskId/message` 才能开始执行
- **必须携带 CSRF token**（所有 POST/PUT/DELETE 操作）

**错误码**：

| Code | Status | 说明 |
|---|---|---|
| `AGENT_NOT_FOUND` | 404 | Agent 不存在 |
| `INVALID_MODEL` | 400 | 模型不支持 |
| `QUOTA_EXCEEDED` | 429 | 超出配额限制 |

---

### GET /api/task

查询任务历史

**查询参数**：

```
limit: number = 20        // 每页数量（1-100）
cursor: string           // 分页游标
status: string           // 筛选状态：running | completed | failed
```

**响应**：`200 OK`

```json
{
  "tasks": [
    {
      "id": "task_507f1f77bcf86cd799439013",
      "title": "支付系统架构设计",
      "status": "running",
      "agent": "architecture",
      "model": "claude-opus-4-8",
      "createdAt": 1718100000000,
      "completedAt": null
    }
  ],
  "pagination": {
    "total": 42,
    "limit": 20,
    "nextCursor": "cursor_abc123"
  }
}
```

---

### GET /api/task/:taskId

获取任务详情

**路径参数**：
- `taskId`: Task ID

**响应**：`200 OK`

```json
{
  "task": {
    "id": "task_507f1f77bcf86cd799439013",
    "userId": "user_507f1f77bcf86cd799439011",
    "tenantId": "tenant_507f1f77bcf86cd799439012",
    "title": "支付系统架构设计",
    "status": "running",
    "workspaceId": "ws_507f1f77bcf86cd799439014",
    "agent": "architecture",
    "model": "claude-opus-4-8",
    "createdAt": 1718100000000
  },
  "messages": [
    {
      "id": "msg_507f1f77bcf86cd799439015",
      "role": "user",
      "parts": [
        { "type": "text", "text": "设计支付系统架构" }
      ],
      "createdAt": 1718100010000
    }
  ],
  "runs": [
    {
      "id": "run_507f1f77bcf86cd799439016",
      "status": "completed",
      "prompt": "设计支付系统架构",
      "createdAt": 1718100010000,
      "completedAt": 1718100300000
    }
  ],
  "artifacts": [
    {
      "path": "docs/ARCHITECTURE.md",
      "kind": "document",
      "status": "generated",
      "sizeBytes": 18420,
      "updatedAt": 1718100280000
    }
  ],
  "summary": {
    "summary": "用户正在设计支付系统...",
    "runCount": 3,
    "tokenCount": 25000,
    "artifactCount": 5,
    "updatedAt": 1718100300000
  }
}
```

**错误码**：

| Code | Status | 说明 |
|---|---|---|
| `TASK_NOT_FOUND` | 404 | Task 不存在 |
| `ACCESS_DENIED` | 403 | 无权限访问此 Task |

---

### POST /api/task/:taskId/message

发送消息并创建 run

**路径参数**：
- `taskId`: Task ID

**请求体**：

```json
{
  "prompt": "改成 REST 同步调用"
}
```

**响应方式**：`200 OK` + **Fetch Streaming Response**

**🚨 协议说明**：
- 本接口使用 `POST` 方法，返回流式响应（不是独立的 SSE `GET` endpoint）
- 前端使用 `fetch()` + `response.body.getReader()` 或支持流式的 HTTP 客户端
- `EventSource` 只能用于 `GET` 请求，**不兼容此接口**
- 每行是一个 JSON 对象，格式：`data: <json>\n\n`

**响应流格式**：

**🚨 统一使用 TaskEventEnvelope 格式**：所有事件都包裹在 `{ type, sequence, payload }` 结构中。

```
data: {"type":"run_started","sequence":1,"payload":{"runId":"run_507f1f77bcf86cd799439017"}}

data: {"type":"assistant_delta","sequence":2,"payload":{"delta":"我来修改"}}

data: {"type":"tool_start","sequence":3,"payload":{"toolName":"edit","toolCallId":"call_123"}}

data: {"type":"tool_end","sequence":4,"payload":{"toolCallId":"call_123","result":"success"}}

data: {"type":"turn_complete","sequence":5,"payload":{"runId":"run_507f1f77bcf86cd799439017"}}
```

**事件类型和 Payload 结构**：

| Event | 说明 | Payload 结构 | 阶段 |
|---|---|---|---|
| `run_started` | Run 开始执行 | `{ runId: string }` | 阶段 0 |
| `assistant_delta` | 助手回复增量 | `{ delta: string }` | 阶段 0 |
| `thinking_delta` | 思考过程增量 | `{ delta: string }` | 阶段 0 |
| `tool_start` | 工具调用开始 | `{ toolName: string, toolCallId: string, input?: unknown }` | 阶段 0 |
| `tool_update` | 工具调用进度更新 | `{ toolCallId: string, progress?: string }` | 阶段 0 |
| `tool_end` | 工具调用结束 | `{ toolCallId: string, result: unknown }` | 阶段 0 |
| `turn_complete` | 本轮完成 | `{ runId: string }` | 阶段 0 |
| `error` | 执行错误 | `{ code: string, message: string }` | 阶段 0 |
| `run_queued` | Run 排队中（未来扩展） | `{ runId: string, position?: number }` | 阶段 3+ |

**🚨 阶段 0-2 串行策略**：同一 Task 已有 active run 时返回 `409 RUN_CONFLICT`，不实现 `run_queued` 事件。

**错误码**：

| Code | Status | 说明 |
|---|---|---|
| `TASK_NOT_FOUND` | 404 | Task 不存在 |
| `TASK_CLOSED` | 409 | Task 已关闭（对齐 STAGE0_SPEC §12.1） |
| `RUN_CONFLICT` | 409 | 已有 active run 在执行 |
| `PROMPT_EMPTY` | 400 | Prompt 不能为空 |

---

### GET /api/task/:taskId/runs/:runId/events

查询 run 事件（断线恢复）

**路径参数**：
- `taskId`: Task ID
- `runId`: Run ID

**查询参数**：

```
afterSequence: number    // 从指定 sequence 之后查询
limit: number = 100      // 每次返回数量
```

**响应**：`200 OK`

```json
{
  "events": [
    {
      "id": "evt_507f1f77bcf86cd799439018",
      "taskId": "task_507f1f77bcf86cd799439013",
      "runId": "run_507f1f77bcf86cd799439017",
      "sequence": 5,
      "type": "assistant_delta",
      "payload": {
        "delta": "我来修改"
      },
      "createdAt": 1718100020000
    }
  ],
  "hasMore": false
}
```

**说明**：
- `sequence` 是 run-scoped，从 1 开始
- 用于前端断线重连后补齐缺失事件

---

### POST /api/task/:taskId/runs/:runId/cancel

取消 active run

**路径参数**：
- `taskId`: Task ID
- `runId`: Run ID

**请求体**：无

**响应**：`204 No Content`

**错误码**：

| Code | Status | 说明 |
|---|---|---|
| `RUN_NOT_FOUND` | 404 | Run 不存在 |
| `RUN_NOT_ACTIVE` | 409 | Run 不在执行中（对齐 STAGE0_SPEC §12.1） |
| `ACCESS_DENIED` | 403 | 无权限取消此 Run |

---

### POST /api/task/:taskId/close

关闭任务

**路径参数**：
- `taskId`: Task ID

**请求体**：无

**响应**：`200 OK`

```json
{
  "task": {
    "id": "task_507f1f77bcf86cd799439013",
    "status": "completed",
    "completedAt": 1718100400000
  }
}
```

**说明**（对齐 STAGE0_SPEC §6.6）：
- 无 active run：task status → `completed`
- 存在 queued run：先 cancel queued run（conditional update），再 close
- 存在 running run：返回 `409 RUN_ACTIVE`，用户必须先 cancel run
- close 后拒绝新的 `/message`，返回 `409 TASK_CLOSED`
- 清理 sandbox 资源（best-effort）
- 保留所有历史数据（messages / runs / events / workspace / artifacts）

**错误码**：

| Code | Status | 说明 |
|---|---|---|
| `TASK_NOT_FOUND` | 404 | Task 不存在 |
| `RUN_ACTIVE` | 409 | 存在 running run，需先 cancel |
| `ACCESS_DENIED` | 403 | 无权限关闭此 Task |

---

### GET /api/task/:taskId/files

查询 workspace 文件树（懒加载）

**路径参数**：
- `taskId`: Task ID

**查询参数**：

```
path: string = "."       // 目录路径
depth: number = 2        // 展开深度
```

**响应**：`200 OK`

```json
{
  "files": [
    {
      "path": "docs",
      "type": "directory",
      "children": [
        {
          "path": "docs/ARCHITECTURE.md",
          "type": "file",
          "sizeBytes": 18420,
          "updatedAt": 1718100280000
        }
      ]
    },
    {
      "path": "README.md",
      "type": "file",
      "sizeBytes": 1024,
      "updatedAt": 1718100260000
    }
  ]
}
```

**说明**：
- 返回指定路径下的文件树
- `depth` 控制递归深度，避免一次返回整个树

---

### GET /api/task/:taskId/files/content

读取文件内容。使用 query 参数避免 `:path` 捕获 slash 的路由歧义（对齐 STAGE0_SPEC §11.2）。

**路径参数**：
- `taskId`: Task ID

**查询参数**：
- `path`（必需）：文件相对路径

**示例**：

```
GET /api/task/task_123/files/content?path=docs/ARCHITECTURE.md
```

**响应**：`200 OK`

```
Content-Type: text/markdown
Content-Length: 18420

# 架构文档

...文件内容...
```

**错误码**：

| Code | Status | 说明 |
|---|---|---|
| `FILE_NOT_FOUND` | 404 | 文件不存在 |
| `PATH_TRAVERSAL` | 400 | 路径遍历攻击 |
| `ACCESS_DENIED` | 403 | 无权限访问 |

---

## 错误码汇总

### 通用错误

| Code | Status | 说明 |
|---|---|---|
| `AUTH_REQUIRED` | 401 | 需要登录 |
| `ACCESS_DENIED` | 403 | 无权限 |
| `NOT_FOUND` | 404 | 资源不存在 |
| `VALIDATION_ERROR` | 400 | 请求参数验证失败 |
| `INTERNAL_ERROR` | 500 | 服务器内部错误 |
| `SERVICE_UNAVAILABLE` | 503 | 服务暂时不可用 |

### Auth 相关

| Code | Status | 说明 |
|---|---|---|
| `EMAIL_ALREADY_EXISTS` | 409 | 邮箱已注册 |
| `WEAK_PASSWORD` | 400 | 密码强度不足 |
| `INVALID_CREDENTIALS` | 401 | 凭据错误 |
| `ACCOUNT_DISABLED` | 403 | 账户已禁用 |
| `NOT_LOGGED_IN` | 401 | 未登录 |

### Task 相关

| Code | Status | 说明 |
|---|---|---|
| `TASK_NOT_FOUND` | 404 | Task 不存在 |
| `TASK_CLOSED` | 409 | Task 已关闭（STAGE0_SPEC §12.1） |
| `AGENT_NOT_FOUND` | 404 | Agent 不存在 |
| `INVALID_MODEL` | 400 | 模型不支持 |
| `QUOTA_EXCEEDED` | 429 | 超出配额 |
| `RUN_CONFLICT` | 409 | Run 冲突 |
| `RUN_NOT_FOUND` | 404 | Run 不存在 |
| `RUN_NOT_ACTIVE` | 409 | Run 不活跃（STAGE0_SPEC §12.1） |
| `RUN_ACTIVE` | 409 | 存在 running run，需先 cancel（STAGE0_SPEC §6.6） |
| `PROMPT_EMPTY` | 400 | Prompt 为空 |

### Workspace 相关

| Code | Status | 说明 |
|---|---|---|
| `FILE_NOT_FOUND` | 404 | 文件不存在 |
| `PATH_TRAVERSAL` | 400 | 路径遍历攻击 |
| `WORKSPACE_CONFLICT` | 409 | Workspace 冲突 |

---

## Rate Limiting

### 限流策略

| 端点 | 限制 | 窗口 |
|---|---|---|
| `POST /api/auth/login` | 5 次 | 15 分钟 |
| `POST /api/auth/register` | 3 次 | 1 小时 |
| `POST /api/task` | 10 次 | 1 分钟 |
| `POST /api/task/:id/message` | 20 次 | 1 分钟 |
| 其他端点 | 100 次 | 1 分钟 |

### 超出限制响应

```json
{
  "statusCode": 429,
  "code": "RATE_LIMIT_EXCEEDED",
  "message": "Too many requests, please try again later",
  "retryAfter": 60
}
```

响应头：

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1718100060
Retry-After: 60
```

---

## 实时事件流

### Fetch Streaming 客户端示例

用于实时接收 run 事件流：

```javascript
async function subscribeToRun(taskId, runId, prompt) {
  // 🚨 必须携带 CSRF token
  const csrfToken = getCsrfToken(); // 从 Cookie 或 localStorage 读取
  
  const response = await fetch(`/api/task/${taskId}/message`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-XSRF-TOKEN': csrfToken,  // 🚨 CSRF token
    },
    body: JSON.stringify({ prompt }),
    credentials: 'include',
  });
  
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  
  let buffer = '';
  
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n\n');
    buffer = lines.pop() || '';
    
    for (const line of lines) {
      if (line.startsWith('data: ')) {
        const data = JSON.parse(line.slice(6));
        handleEvent(data);
        
        if (data.type === 'turn_complete') {
          reader.cancel();
          return;
        }
      }
    }
  }
}
```

### 断线恢复

```javascript
// 1. 记录最后一个 sequence
let lastSequence = 0;

async function handleEvent(envelope) {
  lastSequence = envelope.sequence;
  // 处理事件
}

// 2. 断线后补齐缺失事件
async function recover(taskId, runId) {
  const response = await fetch(
    `/api/task/${taskId}/runs/${runId}/events?afterSequence=${lastSequence}`
  );
  
  const { events } = await response.json();
  events.forEach(handleEvent);
}
```

---

## 测试示例

### cURL 示例

```bash
# 注册
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"Test123!","tenantName":"Test Corp"}' \
  -c cookies.txt

# 创建任务
curl -X POST http://localhost:3000/api/task \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{"title":"测试任务","agent":"architecture"}'

# 发送消息
curl -X POST http://localhost:3000/api/task/task_123/message \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{"prompt":"设计支付系统"}' \
  --no-buffer
```

### TypeScript 客户端示例

```typescript
class SiriusXClient {
  private baseUrl = 'http://localhost:3000';
  
  async register(input: {
    email: string;
    password: string;
    tenantName: string;
  }) {
    const response = await fetch(`${this.baseUrl}/api/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(input),
      credentials: 'include',
    });
    
    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.message);
    }
    
    return response.json();
  }
  
  async createTask(input: {
    title: string;
    agent: string;
    model?: string;
  }) {
    const response = await fetch(`${this.baseUrl}/api/task`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(input),
      credentials: 'include',
    });
    
    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.message);
    }
    
    return response.json();
  }
  
  async sendMessage(taskId: string, prompt: string) {
    const response = await fetch(
      `${this.baseUrl}/api/task/${taskId}/message`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prompt }),
        credentials: 'include',
      }
    );
    
    // 返回 ReadableStream 用于 SSE
    return response.body;
  }
}
```

---

## 前端集成指南

### React 示例

**🚨 使用 fetch streaming，不是 EventSource**

**🚨 必须追踪 currentRunId 用于断线恢复**

```typescript
interface TaskEventEnvelope {
  type: string;
  sequence: number;
  payload: unknown;
}

function TaskPage({ taskId }: { taskId: string }) {
  const [events, setEvents] = useState<TaskEventEnvelope[]>([]);
  const [lastSequence, setLastSequence] = useState(0);
  const [currentRunId, setCurrentRunId] = useState<string | null>(null);
  const abortControllerRef = useRef<AbortController | null>(null);
  
  const sendMessage = async (prompt: string) => {
    // 取消之前的订阅
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
    }
    
    abortControllerRef.current = new AbortController();
    
    try {
      const response = await fetch(`/api/task/${taskId}/message`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prompt }),
        credentials: 'include',
        signal: abortControllerRef.current.signal,
      });
      
      const reader = response.body!.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        
        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n\n');
        buffer = lines.pop() || '';
        
        for (const line of lines) {
          if (line.startsWith('data: ')) {
            const envelope: TaskEventEnvelope = JSON.parse(line.slice(6));
            
            // 从 run_started 事件提取 runId
            if (envelope.type === 'run_started') {
              setCurrentRunId((envelope.payload as any).runId);
            }
            
            setEvents((prev) => [...prev, envelope]);
            setLastSequence(envelope.sequence);
          }
        }
      }
    } catch (error) {
      if (error.name === 'AbortError') {
        return; // 用户取消
      }
      
      // 网络错误：补齐缺失事件（需要 currentRunId）
      if (currentRunId) {
        const response = await fetch(
          `/api/task/${taskId}/runs/${currentRunId}/events?afterSequence=${lastSequence}`
        );
        const { events: missedEvents } = await response.json();
        setEvents((prev) => [...prev, ...missedEvents]);
      }
    }
  };
  
  useEffect(() => {
    return () => {
      // 组件卸载时取消订阅
      if (abortControllerRef.current) {
        abortControllerRef.current.abort();
      }
    };
  }, []);
  
  return (
    <div>
      <MessageInput onSend={sendMessage} />
      <EventList events={events} />
    </div>
  );
}
```

---
