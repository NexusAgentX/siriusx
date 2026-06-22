# Auth 实现详解

> 阶段 0 必读：完整的认证和租户隔离实现指南

---

## 技术选型

### Session 管理

**选择**：`express-session` + `connect-redis`

**理由**：
- 成熟稳定，NestJS 原生支持
- Redis 支持多 API 节点共享 session
- 支持滚动过期（用户活跃时自动续期）

### 密码加密

**选择**：`bcrypt`

**理由**：
- 行业标准
- 自动加盐
- 计算成本可调节（防止暴力破解）

---

## 数据模型

### users 表

```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY,                    -- uuid
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,            -- bcrypt hash
  tenant_id TEXT NOT NULL,                -- 所属租户
  role TEXT NOT NULL DEFAULT 'user',      -- user | admin | tenant_admin
  created_at BIGINT NOT NULL,
  last_login_at BIGINT,
  is_active BOOLEAN NOT NULL DEFAULT true
);

CREATE INDEX users_tenant_id_idx ON users(tenant_id);
CREATE INDEX users_email_idx ON users(email);
```

### tenants 表

```sql
CREATE TABLE tenants (
  id TEXT PRIMARY KEY,                    -- uuid
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,              -- URL 友好标识
  created_at BIGINT NOT NULL,
  owner_user_id TEXT,                     -- 租户创建者
  plan TEXT NOT NULL DEFAULT 'free',      -- free | pro | enterprise
  is_active BOOLEAN NOT NULL DEFAULT true
);

CREATE INDEX tenants_slug_idx ON tenants(slug);
```

### sessions 表（Redis，自动管理）

```typescript
// Redis key: sess:${sessionId}
interface SessionData {
  userId: string;
  tenantId: string;
  email: string;
  role: string;
  createdAt: number;
  lastActiveAt: number;
}
```

---

## NestJS 实现

### 1. 安装依赖

```bash
bun add express-session connect-redis bcrypt
bun add -D @types/express-session @types/bcrypt
```

### 2. Session 配置

**文件**：`packages/agent-runtime/src/session.config.ts`

```typescript
import session from 'express-session';
import RedisStore from 'connect-redis';
import { createClient } from 'redis';

export function createSessionMiddleware() {
  const redisClient = createClient({
    url: process.env.REDIS_URL || 'redis://localhost:6379',
  });
  
  redisClient.connect().catch(console.error);
  
  const redisStore = new RedisStore({
    client: redisClient,
    prefix: 'sess:',
  });
  
  return session({
    store: redisStore,
    secret: process.env.SESSION_SECRET || 'change-me-in-production',
    resave: false,
    saveUninitialized: false,
    cookie: {
      secure: process.env.NODE_ENV === 'production', // HTTPS only in prod
      httpOnly: true,
      maxAge: 7 * 24 * 60 * 60 * 1000, // 7 天
      // 🚨 统一 sameSite=lax（与 §CSRF 的 XSRF-TOKEN cookie 保持一致；strict 会破坏 OAuth/跳转回链）
      sameSite: 'lax',
    },
    name: 'siriusx.sid', // 自定义 cookie 名称
  });
}
```

> Session store 也可以替换为 `MemorySessionStore`（仅 dev profile，见 STAGE0_SPEC §2.1）；distributed profile 必须使用 Redis。

### 3. AuthContext 类型定义

**文件**：`packages/agent-runtime/src/auth/auth-context.ts`

```typescript
export interface AuthContext {
  userId: string;
  tenantId: string;
  email?: string;
  role?: 'user' | 'tenant_admin' | 'admin';
  // 对齐 STAGE0_SPEC §4.1：worker 用于 Control Worker service credential；system 用于后台 sweeper/GC/title/summary job
  actorType: 'user' | 'api-token' | 'worker' | 'system';
  scopes: string[];
  tokenId?: string;
}

// 扩展 Express Request 类型
declare module 'express-session' {
  interface SessionData {
    userId?: string;
    tenantId?: string;
    email?: string;
    role?: string;
    csrfToken?: string; // STAGE0_SPEC §4.3：register/login 写入，写请求校验
  }
}

declare global {
  namespace Express {
    interface Request {
      authContext?: AuthContext;
    }
  }
}
```

### 4. Auth Guard（核心中间件）

**文件**：`packages/agent-runtime/src/auth/auth.guard.ts`

```typescript
import { Injectable, CanActivate, ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { Request } from 'express';

@Injectable()
export class AuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request>();
    const session = request.session;
    
    // 检查 session 是否存在且有效
    if (!session?.userId || !session?.tenantId) {
      throw new UnauthorizedException({
        code: 'AUTH_REQUIRED',
        message: 'Please login to continue',
      });
    }
    
    // 构造 AuthContext
    request.authContext = {
      userId: session.userId,
      tenantId: session.tenantId,
      email: session.email || '',
      role: (session.role as any) || 'user',
      actorType: 'user',
      scopes: this.deriveScopes(session.role || 'user'),
    };
    
    return true;
  }
  
  private deriveScopes(role: string): string[] {
    switch (role) {
      case 'admin':
        return ['task:read', 'task:write', 'task:delete', 'admin:*'];
      case 'tenant_admin':
        return ['task:read', 'task:write', 'task:delete', 'tenant:*'];
      case 'user':
      default:
        return ['task:read', 'task:write'];
    }
  }
}
```

### 5. Auth Service（登录/注册逻辑）

**文件**：`packages/agent-runtime/src/auth/auth.service.ts`

```typescript
import { Injectable, UnauthorizedException, ConflictException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { randomUUID } from 'crypto';

interface User {
  id: string;
  email: string;
  password_hash: string;
  tenant_id: string;
  role: string;
  is_active: boolean;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly db: PgClientLike, // 注入数据库连接
  ) {}
  
  async register(input: {
    email: string;
    password: string;
    tenantName: string;
  }): Promise<{ userId: string; tenantId: string }> {
    const { email, password, tenantName } = input;
    
    // 检查邮箱是否已存在
    const existing = await this.db.query(
      'SELECT id FROM users WHERE email = $1',
      [email]
    );
    
    if (existing.rows.length > 0) {
      throw new ConflictException({
        code: 'EMAIL_ALREADY_EXISTS',
        message: 'This email is already registered',
      });
    }
    
    // 🚨 使用事务保证一致性
    const client = await this.db.connect();
    
    try {
      await client.query('BEGIN');
      
      // 创建租户
      const tenantId = `tenant_${randomUUID()}`;
      const tenantSlug = this.generateSlug(tenantName);
      
      await client.query(
        `INSERT INTO tenants (id, name, slug, created_at)
         VALUES ($1, $2, $3, $4)`,
        [tenantId, tenantName, tenantSlug, Date.now()]
      );
      
      // 创建用户
      const userId = `user_${randomUUID()}`;
      const passwordHash = await bcrypt.hash(password, 10);
      
      await client.query(
        `INSERT INTO users (id, email, password_hash, tenant_id, role, created_at)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [userId, email, passwordHash, tenantId, 'tenant_admin', Date.now()]
      );
      
      // 更新租户 owner
      await client.query(
        'UPDATE tenants SET owner_user_id = $1 WHERE id = $2',
        [userId, tenantId]
      );
      
      await client.query('COMMIT');
      
      return { userId, tenantId };
      
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }
  
  async login(input: {
    email: string;
    password: string;
  }): Promise<User> {
    const { email, password } = input;
    
    const result = await this.db.query(
      `SELECT id, email, password_hash, tenant_id, role, is_active
       FROM users
       WHERE email = $1`,
      [email]
    );
    
    const user = result.rows[0] as User | undefined;
    
    if (!user) {
      throw new UnauthorizedException({
        code: 'INVALID_CREDENTIALS',
        message: 'Invalid email or password',
      });
    }
    
    if (!user.is_active) {
      throw new UnauthorizedException({
        code: 'ACCOUNT_DISABLED',
        message: 'Account is disabled',
      });
    }
    
    // 验证密码
    const isPasswordValid = await bcrypt.compare(password, user.password_hash);
    
    if (!isPasswordValid) {
      throw new UnauthorizedException({
        code: 'INVALID_CREDENTIALS',
        message: 'Invalid email or password',
      });
    }
    
    // 更新最后登录时间
    await this.db.query(
      `UPDATE users SET last_login_at = NOW() WHERE id = $1`,
      [user.id]
    );
    
    return user;
  }
  
  async getMe(userId: string): Promise<User> {
    const result = await this.db.query(
      `SELECT id, email, tenant_id, role, is_active
       FROM users
       WHERE id = $1`,
      [userId]
    );
    
    const user = result.rows[0] as User | undefined;
    
    if (!user) {
      throw new UnauthorizedException({
        code: 'USER_NOT_FOUND',
        message: 'User not found',
      });
    }
    
    if (!user.is_active) {
      throw new UnauthorizedException({
        code: 'ACCOUNT_DISABLED',
        message: 'Account is disabled',
      });
    }
    
    return user;
  }
}
```

### 6. Auth Controller（HTTP 端点）

**文件**：`packages/agent-runtime/src/auth/auth.controller.ts`

```typescript
import { Controller, Post, Get, Body, Req, Res, HttpCode, UseGuards } from '@nestjs/common';
import { Request, Response } from 'express';
import { randomBytes } from 'crypto';
import { AuthService } from './auth.service';

@Controller('api/auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  // 🚨 STAGE0_SPEC §4.3：register/login 成功后必须返回 csrfToken，并设置可读 cookie XSRF-TOKEN
  private issueCsrfToken(req: Request, res: Response): string {
    const csrfToken = randomBytes(32).toString('hex');
    req.session.csrfToken = csrfToken;
    res.cookie('XSRF-TOKEN', csrfToken, {
      httpOnly: false, // 前端需要读取，放入 X-XSRF-TOKEN header
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax', // 与 session cookie 对齐
    });
    return csrfToken;
  }

  @Post('register')
  async register(
    @Body() body: { email: string; password: string; tenantName: string },
    @Req() req: Request,
    @Res() res: Response,
  ) {
    const { userId, tenantId } = await this.authService.register(body);

    // 自动登录
    const user = await this.authService.login({
      email: body.email,
      password: body.password,
    });

    req.session.userId = user.id;
    req.session.tenantId = user.tenant_id;
    req.session.email = user.email;
    req.session.role = user.role;

    const csrfToken = this.issueCsrfToken(req, res);

    res.status(201).json({
      userId,
      tenantId,
      email: user.email,
      role: user.role,
      csrfToken, // ✅ 返回 csrfToken
    });
  }

  @Post('login')
  @HttpCode(200)
  async login(
    @Body() body: { email: string; password: string },
    @Req() req: Request,
    @Res() res: Response,
  ) {
    const user = await this.authService.login(body);

    req.session.userId = user.id;
    req.session.tenantId = user.tenant_id;
    req.session.email = user.email;
    req.session.role = user.role;

    const csrfToken = this.issueCsrfToken(req, res);

    res.json({
      userId: user.id,
      tenantId: user.tenant_id,
      email: user.email,
      role: user.role,
      csrfToken, // ✅ 返回 csrfToken
    });
  }

  // 🚨 STAGE0_SPEC §4.3 / API端点.md：登录后可调用，用于刷新或补取 token
  @Get('csrf')
  @UseGuards(AuthGuard)
  async getCsrfToken(@Req() req: Request) {
    return { csrfToken: req.session.csrfToken };
  }

  @Post('logout')
  @HttpCode(204)
  async logout(@Req() req: Request, @Res() res: Response) {
    req.session.destroy((err) => {
      if (err) {
        throw new Error('Failed to logout');
      }
      res.clearCookie('siriusx.sid');
      res.clearCookie('XSRF-TOKEN');
      res.sendStatus(204);
    });
  }

  @Get('me')
  @UseGuards(AuthGuard)
  async getMe(@Req() req: Request) {
    const authContext = req.authContext!;
    const user = await this.authService.getMe(authContext.userId);
    return {
      userId: user.id,
      tenantId: user.tenant_id,
      email: user.email,
      role: user.role,
    };
  }
}
```

---
---

## CSRF 防护

**🚨 P0 安全要求**

Session cookie 用于写操作时必须配合 CSRF token：

### 1. Double Submit Cookie 模式

CSRF token 在 `AuthController.issueCsrfToken()` 中统一生成（register/login 调用，见上方 Controller）。同时：

- 写入 `req.session.csrfToken`（服务端比对用）。
- 设置前端可读 cookie `XSRF-TOKEN`（`httpOnly: false`，`sameSite: 'lax'`，与 session cookie 一致）。
- register/login 响应体同时返回 `csrfToken`（STAGE0_SPEC §4.3）。

`GET /api/auth/csrf` 可在登录后刷新或补取 token。

### 2. CSRF Guard

```typescript
@Injectable()
export class CsrfGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request>();
    
    // 只检查写操作
    if (['GET', 'HEAD', 'OPTIONS'].includes(request.method)) {
      return true;
    }
    
    const sessionToken = request.session.csrfToken;
    const headerToken = request.headers['x-xsrf-token'];

    // 🚨 STAGE0_SPEC §4.3 / §12.2：区分 missing 和 invalid
    if (!headerToken) {
      throw new ForbiddenException({
        code: 'CSRF_TOKEN_MISSING',
        message: 'CSRF token is missing',
      });
    }
    if (!sessionToken || sessionToken !== headerToken) {
      throw new ForbiddenException({
        code: 'CSRF_TOKEN_INVALID',
        message: 'CSRF token validation failed',
      });
    }
    
    return true;
  }
}
```

### 3. 应用到写操作端点

```typescript
@Controller('api/task')
@UseGuards(AuthGuard, CsrfGuard)  // 同时应用 Auth 和 CSRF
export class TaskController {
  @Post()
  async createTask(
    @Body() input: CreateTaskDto,
    @Req() req: Request,
  ): Promise<Task> {
    const authContext = req.authContext!;
    
    return await this.taskService.create({
      ...input,
      userId: authContext.userId,      // 从 authContext 提取
      tenantId: authContext.tenantId,  // 不信任 body
    });
  }
}
```

---

## 租户隔离实现

### 1. Task 查询时验证权限
```typescript
async getTask(taskId: string, authContext: AuthContext): Promise<Task> {
  const task = await this.taskStore.get(taskId);
  
  if (!task) {
    throw new NotFoundException({
      code: 'TASK_NOT_FOUND',
      message: 'Task not found',
    });
  }
  
  // 权限检查
  const hasAccess = 
    task.userId === authContext.userId ||                    // Task owner
    task.tenantId === authContext.tenantId &&                // Same tenant
    authContext.role === 'tenant_admin' ||                   // Tenant admin
    authContext.role === 'admin';                            // Platform admin
  
  if (!hasAccess) {
    throw new ForbiddenException({
      code: 'ACCESS_DENIED',
      message: 'You do not have permission to access this task',
    });
  }
  
  return task;
}
```

### 3. S3 Key 隔离

**文件**：`packages/workspace-io/src/s3.ts`

```typescript
export class S3WorkspaceProvider implements WorkspaceProvider {
  private buildS3Key(tenantId: string, taskId: string, path: string): string {
    // ✅ 强制租户前缀
    const sanitizedPath = this.sanitizePath(path);
    return `tenants/${tenantId}/tasks/${taskId}/${sanitizedPath}`;
  }
  
  private sanitizePath(path: string): string {
    // 防止路径遍历攻击
    if (path.includes('..') || path.startsWith('/')) {
      throw new Error('Invalid path: path traversal detected');
    }
    
    if (path.includes('\\')) {
      throw new Error('Invalid path: backslash not allowed');
    }
    
    return path.replace(/^\/+/, '');
  }
  
  async readFile(input: {
    tenantId: string;
    taskId: string;
    path: string;
  }): Promise<Buffer> {
    const key = this.buildS3Key(input.tenantId, input.taskId, input.path);
    
    const response = await this.s3Client.send(
      new GetObjectCommand({
        Bucket: this.bucketName,
        Key: key,
      })
    );
    
    return Buffer.from(await response.Body!.transformToByteArray());
  }
}
```

---

## 审计日志

### audit_logs 表

```sql
CREATE TABLE audit_logs (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  user_id TEXT,
  actor_type TEXT NOT NULL,              -- user | api-token | system
  action TEXT NOT NULL,                   -- task:create | task:delete | ...
  resource_type TEXT NOT NULL,            -- task | workspace | artifact
  resource_id TEXT,
  ip_address TEXT,
  user_agent TEXT,
  metadata JSONB,
  created_at BIGINT NOT NULL
);

CREATE INDEX audit_logs_tenant_created_idx ON audit_logs(tenant_id, created_at DESC);
CREATE INDEX audit_logs_user_created_idx ON audit_logs(user_id, created_at DESC);
CREATE INDEX audit_logs_resource_idx ON audit_logs(resource_type, resource_id);
```

### 审计装饰器

```typescript
export function Audit(action: string) {
  return function (
    target: any,
    propertyKey: string,
    descriptor: PropertyDescriptor,
  ) {
    const originalMethod = descriptor.value;
    
    descriptor.value = async function (...args: any[]) {
      const result = await originalMethod.apply(this, args);
      
      // 记录审计日志
      const authContext = args.find((arg) => arg?.userId && arg?.tenantId);
      
      if (authContext) {
        await this.auditService.log({
          tenantId: authContext.tenantId,
          userId: authContext.userId,
          actorType: authContext.actorType,
          action,
          resourceType: 'task',
          resourceId: result.id,
        });
      }
      
      return result;
    };
    
    return descriptor;
  };
}

// 使用
@Audit('task:create')
async createTask(...) { ... }
```

---

## 测试验证

### 1. 租户隔离测试

```typescript
describe('Tenant Isolation', () => {
  it('should prevent cross-tenant task access', async () => {
    // 租户 A 创建 task
    const taskA = await createTask({ tenantId: 'tenant-a', userId: 'user-a' });
    
    // 租户 B 尝试访问
    await expect(
      getTask(taskA.id, { tenantId: 'tenant-b', userId: 'user-b' })
    ).rejects.toThrow('ACCESS_DENIED');
  });
  
  it('should allow tenant admin to access all tasks in tenant', async () => {
    const task = await createTask({ tenantId: 'tenant-a', userId: 'user-a' });
    
    // Tenant admin（不是 task owner）也能访问
    const result = await getTask(task.id, {
      tenantId: 'tenant-a',
      userId: 'admin-a',
      role: 'tenant_admin',
    });
    
    expect(result.id).toBe(task.id);
  });
});
```

### 2. S3 Key 隔离测试

```typescript
describe('S3 Key Isolation', () => {
  it('should enforce tenant prefix in S3 keys', () => {
    const key = buildS3Key('tenant-a', 'task-1', 'docs/README.md');
    expect(key).toBe('tenants/tenant-a/tasks/task-1/docs/README.md');
  });
  
  it('should reject path traversal attempts', () => {
    expect(() => 
      buildS3Key('tenant-a', 'task-1', '../../../etc/passwd')
    ).toThrow('path traversal detected');
  });
});
```

---

## 生产部署清单

- [ ] 修改 `SESSION_SECRET` 为强随机字符串（至少 32 字符）
- [ ] 启用 HTTPS（cookie secure flag）
- [ ] 配置 Redis 持久化（RDB + AOF）
- [ ] 配置 Redis 密码
- [ ] 配置 rate limiting（防止暴力破解）
- [ ] 配置 CORS（只允许前端域名）
- [ ] 配置 CSP（Content Security Policy）
- [ ] 启用审计日志
- [ ] 配置日志脱敏（不记录密码）
- [ ] 配置 session 过期策略（活跃续期 + 绝对过期）

---

## 常见问题

### Q1: 为什么不用 JWT？

Session-based 更适合 SaaS：
- 可以主动撤销（JWT 无法撤销）
- 不需要在前端存储敏感信息
- 支持滚动过期（用户活跃时自动续期）
- Redis 性能足够（< 1ms）

### Q2: 如何支持 API Token？

后续可以扩展：
```typescript
if (req.headers.authorization?.startsWith('Bearer ')) {
  const token = req.headers.authorization.slice(7);
  const decoded = await verifyApiToken(token);
  req.authContext = {
    userId: decoded.userId,
    tenantId: decoded.tenantId,
    actorType: 'api-token',
    // ...
  };
}
```

### Q3: 如何实现多租户数据库隔离？

当前方案是**共享数据库 + 行级隔离**（所有表包含 `tenant_id`）。

未来可升级为**每租户独立数据库**（需要连接池路由）。
