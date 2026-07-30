# 账号系统（邮箱 + 密码 + session cookie）

这套代码来自一个线上跑着的 Pages + D1 项目，已经验证过。**照抄，别重写。**

唯一该改的是**用户可见的报错文案**（"请先登录""邮箱或密码不正确"等）——这里是中文，站点是别的语言就换成对应语言。逻辑一行都不要动。

设计取舍：
- 密码用 PBKDF2-HMAC-SHA256 慢哈希存储，不存明文也不用可逆加密
- session token 只把哈希存进数据库，数据库泄了也不能直接冒充登录
- 浏览器只拿到 `HttpOnly` cookie，前端 JS 读不到 token
- 注册和登录按邮箱和 IP 两个维度限流，限流状态存 D1
- 业务主键是 `crypto.randomUUID()` 生成的 `user_id`，邮箱只是登录名。以后加邮箱验证、换登录方式都不影响业务数据

## 表结构

见 `assets/migrations/0001_initial.sql`：`users`、`auth_identities`、`sessions`、`auth_rate_limits`。

`auth_identities` 单独一张表是为了以后能加第三方登录（`provider` 列），不用改 `users`。

**所有业务表都必须有 `user_id` 列并建索引。** 既是数据隔离，也是省 D1 行读额度的前提。

## 常量和类型

下面的代码全部放进 `functions/api/[[path]].ts`。`json()`、`HttpError`、`readJson()`、`text()` 骨架文件里已经有，不用重复定义。

```ts
const SESSION_COOKIE = 'app_session';
const SESSION_MAX_AGE_SECONDS = 60 * 60 * 24 * 30;
const PASSWORD_ITERATIONS = 100000;

type SessionUser = {
  id: string;
  primary_email: string;
  email_verified: number;
  session_id?: string;   // requireUser 的 JOIN 查询会带上
};
```

## 注册

```ts
async function register(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request);
  const email = normalizeEmail(body.email);
  const password = String(body.password ?? '');

  validateEmail(email);
  validatePassword(password);

  const ipHash = await requestIpHash(request);
  await enforceRateLimit(env, `register:ip:${ipHash}`, 10, 60 * 60 * 1000);
  await enforceRateLimit(env, `register:email:${email}`, 3, 60 * 60 * 1000);

  const existing = await env.DB.prepare(
    'SELECT id FROM auth_identities WHERE provider = ? AND provider_subject = ?'
  ).bind('password', email).first<{ id: string }>();

  if (existing) {
    throw new HttpError('这个邮箱已经注册，请直接登录', 409);
  }

  const now = Date.now();
  const userId = crypto.randomUUID();
  const passwordHash = await hashPassword(password);

  await env.DB.batch([
    env.DB.prepare(
      'INSERT INTO users (id, primary_email, email_verified, created_at, updated_at) VALUES (?, ?, ?, ?, ?)'
    ).bind(userId, email, 0, now, now),
    env.DB.prepare(
      `INSERT INTO auth_identities (
        id, user_id, provider, provider_subject, password_hash, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)`
    ).bind(crypto.randomUUID(), userId, 'password', email, passwordHash, now, now)
  ]);

  return await createSessionResponse(request, env, userId, 201);
}
```

用 `batch` 而不是两条独立 INSERT，既是原子性也省查询数（免费计划单次调用 50 条上限）。

## 登录

```ts
async function login(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request);
  const email = normalizeEmail(body.email);
  const password = String(body.password ?? '');

  validateEmail(email);
  await enforceRateLimit(env, `login:ip:${await requestIpHash(request)}`, 30, 15 * 60 * 1000);
  await enforceRateLimit(env, `login:email:${email}`, 10, 15 * 60 * 1000);

  const identity = await env.DB.prepare(
    'SELECT user_id, password_hash FROM auth_identities WHERE provider = ? AND provider_subject = ?'
  ).bind('password', email).first<{ user_id: string; password_hash: string }>();

  if (!identity || !identity.password_hash) {
    throw new HttpError('邮箱或密码不正确', 401);
  }
  if (!(await verifyPassword(password, identity.password_hash))) {
    throw new HttpError('邮箱或密码不正确', 401);
  }

  return await createSessionResponse(request, env, identity.user_id, 200);
}
```

账号不存在和密码错误返回**同一句话**，不泄露邮箱是否注册过。

## 登出

```ts
async function logout(request: Request, env: Env): Promise<Response> {
  const token = getCookie(request, SESSION_COOKIE);
  if (token) {
    await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?')
      .bind(await sha256Hex(token)).run();
  }
  return json({ ok: true }, 200, {
    'Set-Cookie': `${SESSION_COOKIE}=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax`
  });
}
```

## 发 session

```ts
async function createSessionResponse(
  request: Request, env: Env, userId: string, status = 200
): Promise<Response> {
  const token = randomToken();
  const tokenHash = await sha256Hex(token);
  const now = Date.now();

  await env.DB.prepare(
    `INSERT INTO sessions (
      id, user_id, token_hash, user_agent, ip_hash, created_at, last_seen_at, expires_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    crypto.randomUUID(), userId, tokenHash,
    request.headers.get('user-agent') ?? '',
    await requestIpHash(request),
    now, now, now + SESSION_MAX_AGE_SECONDS * 1000
  ).run();

  const user = await env.DB.prepare(
    'SELECT id, primary_email, email_verified FROM users WHERE id = ?'
  ).bind(userId).first<SessionUser>();
  if (!user) throw new HttpError('账号不存在', 404);

  const secure = new URL(request.url).protocol === 'https:' ? '; Secure' : '';
  const cookie = [
    `${SESSION_COOKIE}=${token}`,
    'Path=/',
    `Max-Age=${SESSION_MAX_AGE_SECONDS}`,
    'HttpOnly',
    'SameSite=Lax',
    secure
  ].filter(Boolean).join('; ');

  return json({ user: publicUser(user) }, status, { 'Set-Cookie': cookie });
}
```

`Secure` 按协议动态加，否则本地 http 开发时 cookie 根本不会被浏览器保存。

## 校验 session

```ts
async function requireUser(request: Request, env: Env): Promise<SessionUser> {
  const token = getCookie(request, SESSION_COOKIE);
  if (!token) throw new HttpError('请先登录', 401);

  const tokenHash = await sha256Hex(token);
  const now = Date.now();
  const user = await env.DB.prepare(
    `SELECT users.id, users.primary_email, users.email_verified, sessions.id AS session_id
     FROM sessions
     INNER JOIN users ON users.id = sessions.user_id
     WHERE sessions.token_hash = ? AND sessions.expires_at > ?`
  ).bind(tokenHash, now).first<SessionUser>();

  if (!user) throw new HttpError('登录已过期，请重新登录', 401);

  await env.DB.prepare('UPDATE sessions SET last_seen_at = ? WHERE id = ?')
    .bind(now, user.session_id).run();

  return user;
}
```

每个需要登录的路由第一行调它。一次 JOIN 查询拿到用户，别拆成两条。

`last_seen_at` 这条 UPDATE 每个请求写一行，计入 10 万行写/天。请求量大的话可以改成只在超过一定间隔时才更新。

## 限流

```ts
async function enforceRateLimit(
  env: Env, key: string, limit: number, windowMs: number
): Promise<void> {
  const now = Date.now();
  const existing = await env.DB.prepare(
    'SELECT count, reset_at FROM auth_rate_limits WHERE key = ?'
  ).bind(key).first<{ count: number; reset_at: number }>();

  if (!existing || existing.reset_at <= now) {
    await env.DB.prepare(
      'INSERT OR REPLACE INTO auth_rate_limits (key, count, reset_at, updated_at) VALUES (?, ?, ?, ?)'
    ).bind(key, 1, now + windowMs, now).run();
    return;
  }

  if (existing.count >= limit) {
    throw new HttpError('请求太频繁，请稍后再试', 429);
  }

  await env.DB.prepare(
    'UPDATE auth_rate_limits SET count = ?, updated_at = ? WHERE key = ?'
  ).bind(existing.count + 1, now, key).run();
}
```

固定窗口计数，够用。存 D1 而不是 KV，因为 KV 免费只有 1,000 写/天。

## 密码哈希

```ts
async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const hash = await pbkdf2(password, salt, PASSWORD_ITERATIONS);
  return `pbkdf2_sha256$${PASSWORD_ITERATIONS}$${base64UrlEncode(salt)}$${base64UrlEncode(hash)}`;
}

async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [algorithm, iterations, salt, expected] = stored.split('$');
  if (algorithm !== 'pbkdf2_sha256' || !iterations || !salt || !expected) return false;
  const hash = await pbkdf2(password, base64UrlDecode(salt), Number(iterations));
  return constantTimeEqual(hash, base64UrlDecode(expected));
}

async function pbkdf2(password: string, salt: Uint8Array, iterations: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits']
  );
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations }, key, 256
  );
  return new Uint8Array(bits);
}
```

哈希串把算法和迭代数写在里面，以后调整迭代数不影响老用户验证。

**免费计划的 10ms CPU 上限：** PBKDF2 是这套代码里唯一可能撞上限的地方。先用 100000 迭代，注册或登录返回 `Error 1102 Worker exceeded resource limits` 就往下调（50000 → 30000），并在提交里注明为什么调低。不要为了绕限制换成 SHA-256 单轮，那等于没有慢哈希。

## 工具函数

```ts
async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function requestIpHash(request: Request): Promise<string> {
  const ip = request.headers.get('CF-Connecting-IP')
    || request.headers.get('x-forwarded-for')
    || 'unknown';
  return await sha256Hex(ip);
}

function randomToken(): string {
  return base64UrlEncode(randomBytes(32));
}

function randomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlDecode(value: string): Uint8Array {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/')
    .padEnd(Math.ceil(value.length / 4) * 4, '=');
  return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i += 1) result |= a[i] ^ b[i];
  return result === 0;
}

function getCookie(request: Request, name: string): string | null {
  const cookie = request.headers.get('cookie') ?? '';
  const match = cookie.split(';').map((p) => p.trim()).find((p) => p.startsWith(`${name}=`));
  return match ? decodeURIComponent(match.slice(name.length + 1)) : null;
}

function normalizeEmail(value: unknown): string {
  return String(value ?? '').trim().toLowerCase();
}

function validateEmail(email: string): void {
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
    throw new HttpError('请输入有效邮箱', 400);
  }
}

function validatePassword(password: string): void {
  if (password.length < 12) throw new HttpError('密码至少需要 12 位', 400);
  if (password.length > 128) throw new HttpError('密码不能超过 128 位', 400);
}

function publicUser(user: SessionUser) {
  return { id: user.id, email: user.primary_email, emailVerified: user.email_verified === 1 };
}
```

`publicUser` 是必须的：直接把数据库行 JSON 化会把 `password_hash`、`token_hash` 之类漏给前端。**任何返回给前端的行都要过一层白名单映射。**

## 以后加邮箱验证码

现在为了零成本不强制验证。要加的话：新增 `email_verification_codes` 表、`POST /api/auth/send-code`、`POST /api/auth/verify-email`，验证通过把 `users.email_verified` 改成 1。这不改变 `user_id`，不影响已有业务数据。

发信本身 Cloudflare 免费额度里没有，要外接第三方（Resend、MailChannels 之类），先查对方的免费额度。

## 验证清单

```sh
BASE=http://localhost:8788   # 或 https://<project>.pages.dev

# 注册 → 201 + HttpOnly cookie
curl -si -X POST $BASE/api/auth/register -H 'content-type: application/json' \
  -d '{"email":"a@example.com","password":"a-long-enough-password"}' | grep -iE '^HTTP|set-cookie'

# 重复注册 → 409
# 密码短于 12 位 → 400
# 密码错 → 401，且返回和"账号不存在"完全一样的文案
# 带 cookie GET /api/auth/me → 200；不带 → 401
# 连续打 11 次登录 → 429
# 登出后再用旧 cookie → 401
```

最后一条一定要测：session 是不是真的从表里删掉了。
