# 免费建站部署手册（单文件版·发给任何 AI 用）

**给拿到这个文件的人**：你用 AI 做好了一个网页，想让它变成一个真正的网站——自己能打开、发给朋友也能打开。把这整个文件发给一个**能在你电脑上执行命令的 AI**（Claude Code、Codex CLI、Cursor、Windsurf 等，纯网页聊天版不行），说"照这个做"。你需要：装了 Node 20 以上的电脑，和一个免费的 Cloudflare 或 GitHub 账号（都不用绑卡）。中间有两三步（浏览器里点授权、面板里点按钮）AI 会停下来让你自己操作，其余不用你动手。

---

**以下是给 AI 的操作手册。**

## 总则

1. **交付物是一个公开 URL**：用户自己能打开，发给别人也能打开。本地文件、localhost 不算完成。收尾让用户手机上开一次。
2. **不用 localStorage 冒充保存**。用户要"内容不丢/换设备还在/每个用户有自己的数据"→ 必须走数据库+账号（L2/L3）。
3. **全程免费**。每层开工前把下文额度表对应数字贴给用户。任何一步只有付费能做，停下来说清价格。
4. **每步验证后才往下走**。验证命令都在文中，不过就修，不要跳。
5. 给非技术用户执行时：每步先用人话解释，命令结果贴出来，报错先给用户看原文。
6. **必须停下来交给用户的事**（做不了别硬试，也别假装做完）：`wrangler login` / `gh auth login` 的浏览器授权——**用户没有账号时先引导注册**（Cloudflare: dash.cloudflare.com/sign-up，免费不绑卡，注册完再 login）；Cloudflare 面板连 GitHub 仓库；DNS 记录；把仓库设为 public 前征得用户同意；私有仓库的 clone（用户在系统终端做）。
7. **被沙盒或权限拦住时绝不暗中绕过**——不提权、不改参数钻洞、不开子代理绕。让用户把项目文件夹开成工作区，或把命令挪到系统终端跑。走 IDE 自身的权限对话框申请更高权限（用户明确点同意）是合法正路，不算绕过。沙盒里 gh 报 "token in keyring is invalid" 且所有账号同时失效，多半是读不到系统钥匙串的假象：先让用户在系统终端 `gh auth status` 验证，别引导重新登录。代理和直连双双失败（fetch failed + DNS 解析不了）= 沙盒网络隔离，是网络不是认证。已有内容的项目目录先用它，绝不清空重建。**两次即停**：同一操作被拦两次立即停止，换工具/换参数/开子代理重跑都算第三次尝试；停下来报三件事（卡在哪步、被什么拦、用户要在系统终端跑什么）。交还给用户是正确完成方式，不是失败。

## 第零步：选平台

问用户：**这个站以后要不要后端（登录、多用户数据、服务端 API）？**

- 纯展示、永远静态、代码可公开 → **GitHub Pages**（下一节），走完即结束。
- 现在或将来要后端，或拿不准 → **Cloudflare**（再下一节）。静态一样免费，以后原地加后端不搬家。GitHub Pages 免费版仓库必须公开，且永远加不了后端。
- 代码在**私有仓库**不影响 Cloudflare：CLI 直推不经过 GitHub；Git 集成在面板授权 Cloudflare 的 GitHub App 即可，免费计划支持私有仓库。只有 GitHub Pages 免费版要求公开。

同时问：要到哪一层？L0 只上线静态页 / L1 加 `/api` / L2 加数据库 / L3 加账号系统。用户的需求已经暗示层级时直接指出（"笔记要存下来"→L3）。

## 分支 A：GitHub Pages（纯展示）

先确认用户同意仓库公开。`gh auth status` 不通过就停下来让用户跑 `gh auth login`。

坑：站点在 `https://<用户名>.github.io/<仓库名>/` 子路径下，**绝对路径 `/xxx` 全 404**。纯 HTML 用相对路径；Vite 设 `base: '/<仓库名>/'`；SPA 把 index.html 复制成 404.html。不支持自定义响应头。

```sh
git init && git add -A && git commit -m "init"
gh repo create <仓库名> --public --source=. --push
# 无构建（HTML 在仓库根）：
gh api repos/{owner}/<仓库名>/pages -X POST -f "source[branch]=main" -f "source[path]=/"
# 有构建：设 base 后用官方 Actions workflow（actions/configure-pages + upload-pages-artifact + deploy-pages，node 20，build 后 cp dist/index.html dist/404.html），再:
gh api repos/{owner}/<仓库名>/pages -X POST -f "build_type=workflow"
```

验证：`gh api repos/{owner}/<仓库名>/pages --jq '.html_url,.status'`，然后 curl 该 URL 得 200，浏览器确认资源没 404（样式全裂=子路径坑）。额度（软限制）：站点 1GB、带宽约 100GB/月，展示页碰不到。

## 分支 B：Cloudflare

### 免费额度（核准于 2026-07，会变，可疑时去 developers.cloudflare.com 重查）

| 服务 | 免费额度 | 超限表现 |
|---|---|---|
| Pages 静态请求/带宽 | **不限量** | — |
| Pages 构建 | 500 次/月，并发 1 | 排队/失败 |
| Workers/Functions 请求 | 100,000 次/天 | Error 1027 |
| Workers CPU | 10 ms/次 | Error 1102 |
| 出站 fetch | 50 个/请求 | 报错 |
| D1 行读 | 500 万/天（**按扫描行数算，不是返回数**） | 当天读写全拒 |
| D1 行写 | 10 万/天 | 同上 |
| D1 存储/库数 | 5 GB；10 个库/账号（一个项目占 2 个） | 拒绝写入/建库 |
| D1 查询数 | 50 条/次调用 | 报错 |
| KV 写 | 仅 1,000/天 → **默认不用 KV，用 D1** | 报错 |
| Workers AI | 10,000 Neurons/天，**不能超额付费** | 报错，须做降级路径 |

**省额度四条**：① 前端保持纯静态（不限量），只有 `/api/*` 计额度；② 永远不全表扫——业务表 `user_id` 建索引、查询带 `WHERE user_id=?`、`SELECT` 列明字段；③ 外部 API 一律服务端代理+缓存；④ 前端不准 `setInterval` 轮询（5 秒一次挂一天=1.7 万请求）。

### 分层（累加，每层部署+验证后才进下一层）

L0 静态上线 → L1 同域 `/api/*` → L2 D1 数据库 → L3 账号 → L4 收尾（域名/secrets/AI）。

### Step 1 探测项目

- **用户给的是 GitHub 链接**（给的是本地文件夹就跳过这条）：先拿代码。匿名 `curl -sI https://github.com/<owner>/<repo>` 探测——200=公开，AI 直接 clone（沙盒拦 git 就下 zip：`codeload.github.com/<owner>/<repo>/zip/refs/heads/main`）；404=按私有处理，停下来让用户系统终端 clone。**绝不为了方便获取建议改 public，更不得代改可见性**。CLI 直推不需要 git，拿到文件即可。
- 有 package.json：认构建命令和输出目录（Vite=dist）；有 react-router 等 → 需要 SPA fallback；已有 wrangler.toml → 二次运行走增量。
- **没有 package.json、只有 HTML**（AI 生成页面常态）：无构建，目录本身就是部署目录，`_headers` 放 index.html 旁边。检查内联 `<script>`/`<style>` 和 CDN 引用——见 L0 第 3 步。
- Next.js SSR 与本流程冲突：问用户是否 `output: 'export'` 纯静态导出。
- **后端是 Python/PHP 等非 JS 语言**（Flask/FastAPI/Django/Streamlit…）：推不上去，Workers 只跑 JS/TS/WASM。停下来给用户两条路：前端照常上线+后端照本手册骨架移植成 Functions（小 CRUD 移植很快，账号系统下文现成），或后端另找托管。前端框架（React/Vue/Svelte/纯 HTML）无所谓。
- **文案语言**：本手册模板里用户可见的报错是中文，站点是其他语言就改成对应语言，逻辑不动。CJK 自定义字体一套 5–15 MB，优先系统字体栈或子集化。

再问部署方式：**CLI 直推**（无 git 也行，一条命令上线）或 **GitHub 集成**（push 自动部署，需面板连仓库）。差异只有三处：上线动作、首次配置、环境变量填在哪（CLI 用 `wrangler pages secret put`；面板要 production/preview 两套都填）。**用户选定的方式中途走不通（如沙盒拦死 git），停下来说明卡点、让用户重新选，不得静默换路线**——改用户拍板过的决定不是 AI 的权限。

### Step 2 前置检查

`node -v`（≥20）；`npx wrangler whoami` 不通过先看失败类型：not authenticated → 让用户 `npx wrangler login`；fetch failed / DNS 失败 → 网络问题（沙盒常见），让用户在系统终端跑 whoami 确认，别让已登录的用户重新授权。

### Step 3 L0 静态上线

1. 写入 `_headers` 到静态目录（有构建：`public/`；无构建：index.html 旁）。**放项目根不生效，必须进最终部署目录**：

```
/*
  Content-Security-Policy: default-src 'self'; base-uri 'none'; connect-src 'self'; font-src 'self' data:; form-action 'self'; frame-ancestors 'none'; img-src 'self' data: blob:; manifest-src 'self'; object-src 'none'; script-src 'self'; style-src 'self'; upgrade-insecure-requests
  Strict-Transport-Security: max-age=31536000
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Resource-Policy: same-origin
  Permissions-Policy: accelerometer=(), camera=(), geolocation=(), microphone=(), payment=(), usb=()
  Referrer-Policy: no-referrer
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  X-Robots-Tag: noindex, nofollow, noarchive, nosnippet, noimageindex

/assets/*
  Cache-Control: public, max-age=31536000, immutable
```

（`X-Robots-Tag` 那行是私人站挡搜索引擎的，要被收录就删。`/assets/*` 路径按实际构建输出调整。）

2. 有客户端路由才写 `_redirects`（多页站不要写）：

```
/*    /index.html   200
```

3. **CSP 校准**：模板全 `'self'` 最严。外部 CDN/字体优先下载本地；**内联 `<script>` 会被拦到白屏**——优先抽成 `.js`/`.css` 文件，不好抽就在 `script-src`/`style-src` 加 `'unsafe-inline'` 并告知用户是妥协。
4. 部署。CLI 分支：

```sh
npx wrangler pages project create <name> --production-branch main
npm run build   # 无构建项目跳过
npx wrangler pages deploy <outdir>   # 无构建项目 outdir 就是 . （确认目录里没杂物）
```

Git 分支：让用户面板操作 Workers & Pages → Create → Pages → Connect to Git → 填构建命令和输出目录，停下来等 URL。

5. 验证：`curl -sI https://<name>.pages.dev/` 得 200 且有 CSP 头；SPA 子路由 curl 得 200；浏览器 console 无 CSP 报错。

### Step 4 L1 加 `/api/*`

写入 `functions/api/[[path]].ts`（**必须在项目根**，`[[path]]` 双层中括号）：

```ts
type Env = {
  DB: D1Database;
};

type D1Database = {
  prepare: (query: string) => D1PreparedStatement;
  batch: (statements: D1PreparedStatement[]) => Promise<unknown[]>;
};

type D1PreparedStatement = {
  bind: (...values: unknown[]) => D1PreparedStatement;
  first: <T>() => Promise<T | null>;
  all: <T>() => Promise<{ results: T[] }>;
  run: () => Promise<unknown>;
};

export const onRequest = async (context: {
  request: Request;
  env: Env;
}): Promise<Response> => {
  const { request, env } = context;
  const url = new URL(request.url);
  const path = url.pathname.replace(/^\/api\/?/, '/');
  const method = request.method.toUpperCase();

  try {
    if (method === 'GET' && path === '/health') {
      return json({ ok: true });
    }

    // 业务路由往这里加。带路径参数用正则：
    // const m = /^\/items\/([^/]+)$/.exec(path);
    // if (method === 'DELETE' && m) { ... decodeURIComponent(m[1]) ... }

    throw new HttpError('接口不存在', 404);
  } catch (error) {
    if (error instanceof HttpError) {
      return json({ error: error.message }, error.status);
    }
    console.error(error);   // 调试: npx wrangler pages deployment tail
    return json({ error: '服务器出错了，请稍后再试' }, 500);
  }
};

// _headers 的 CSP/HSTS 不会落到 Functions 响应上（实测），安全头这里自己带
function json(body: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'referrer-policy': 'no-referrer',
      'x-content-type-options': 'nosniff',
      ...headers
    }
  });
}

class HttpError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    return await request.json();
  } catch {
    throw new HttpError('请求格式不正确', 400);
  }
}

// 所有写库的用户输入都过一遍，防超长 body 吃存储
function text(value: unknown, maxLength: number): string {
  return String(value ?? '').slice(0, maxLength);
}
```

tsconfig 报 `Cannot find name 'Request'` → `"lib": ["es2022", "dom"]` 或装 `@cloudflare/workers-types`。

验证：`npm run build && npx wrangler pages dev <outdir>`，`curl localhost:8788/api/health` 得 `{"ok":true}`，`/api/nope` 得 404 JSON。再部署打线上同样两条。

### Step 5 L2 加 D1

```sh
npx wrangler d1 create <name>            # 生产库
npx wrangler d1 create <name>-preview    # 预览库，必须分开，否则预览分支写生产数据
```

写入项目根 `wrangler.toml`（**这文件进 git，绝不放密钥**；密钥用 `npx wrangler pages secret put KEY`）：

```toml
name = "<name>"
compatibility_date = "<今天日期>"
pages_build_output_dir = "<outdir>"

[[d1_databases]]
binding = "DB"
database_name = "<name>"
database_id = "<生产库id>"
preview_database_id = "<预览库id>"
```

写入 `migrations/0001_initial.sql`（后续改动新建 0002，不改已 apply 的文件）：

```sql
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  primary_email TEXT NOT NULL UNIQUE COLLATE NOCASE,
  email_verified INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS auth_identities (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  provider TEXT NOT NULL,
  provider_subject TEXT NOT NULL,
  password_hash TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE (provider, provider_subject),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  user_agent TEXT,
  ip_hash TEXT,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at);

CREATE TABLE IF NOT EXISTS auth_rate_limits (
  key TEXT PRIMARY KEY,
  count INTEGER NOT NULL,
  reset_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- 业务表模板：每张都必须有 user_id + 索引（数据隔离 + 省行读额度）
-- CREATE TABLE IF NOT EXISTS items (
--   id TEXT PRIMARY KEY,
--   user_id TEXT NOT NULL,
--   title TEXT NOT NULL,
--   created_at INTEGER NOT NULL,
--   updated_at INTEGER NOT NULL,
--   FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
-- );
-- CREATE INDEX IF NOT EXISTS idx_items_user_id ON items(user_id);
```

迁移，**local 和 remote 是两套独立数据，都要跑、都要验证**：

```sh
npx wrangler d1 migrations apply <name> --local
npx wrangler d1 execute <name> --local  --command "SELECT name FROM sqlite_master WHERE type='table'"
npx wrangler d1 migrations apply <name> --remote
npx wrangler d1 execute <name> --remote --command "SELECT name FROM sqlite_master WHERE type='table'"
```

### Step 6 L3 加账号

以下代码全部加进 `functions/api/[[path]].ts`，来自一个线上验证过的站，**照抄不要重写**。Workers 上没有 bcrypt/argon2，只能用 Web Crypto 的 PBKDF2。

设计要点：密码 PBKDF2 慢哈希；session token 只存哈希；浏览器只拿 HttpOnly cookie；限流存 D1（KV 免费写额度太少）；业务主键是 UUID 的 `user_id`，邮箱只是登录名；"账号不存在"和"密码错"返回同一文案；任何返回给前端的数据库行都过白名单映射（防止把 password_hash 漏出去）。

在路由区加：

```ts
    if (method === 'POST' && path === '/auth/register') return await register(request, env);
    if (method === 'POST' && path === '/auth/login')    return await login(request, env);
    if (method === 'POST' && path === '/auth/logout')   return await logout(request, env);
    if (method === 'GET'  && path === '/auth/me') {
      const user = await requireUser(request, env);
      return json({ user: publicUser(user) });
    }
```

需要登录的业务路由第一行调 `const user = await requireUser(request, env);`，查询全部带 `user.id`。

```ts
const SESSION_COOKIE = 'app_session';
const SESSION_MAX_AGE_SECONDS = 60 * 60 * 24 * 30;
const PASSWORD_ITERATIONS = 100000;
// 10ms CPU 上限：注册/登录报 Error 1102 就把迭代降到 50000/30000，
// 但绝不换成单轮 SHA-256（等于没有慢哈希）。

type SessionUser = {
  id: string;
  primary_email: string;
  email_verified: number;
  session_id?: string;
};

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
  if (existing) throw new HttpError('这个邮箱已经注册，请直接登录', 409);

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

  if (!identity || !identity.password_hash) throw new HttpError('邮箱或密码不正确', 401);
  if (!(await verifyPassword(password, identity.password_hash))) {
    throw new HttpError('邮箱或密码不正确', 401);
  }

  return await createSessionResponse(request, env, identity.user_id, 200);
}

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

  // Secure 按协议动态加，否则本地 http 开发时浏览器不存 cookie
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
  if (existing.count >= limit) throw new HttpError('请求太频繁，请稍后再试', 429);

  await env.DB.prepare(
    'UPDATE auth_rate_limits SET count = ?, updated_at = ? WHERE key = ?'
  ).bind(existing.count + 1, now, key).run();
}

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

验证（本地 8788 或线上）：注册 201+HttpOnly cookie；重复注册 409；短密码 400；密码错 401 且文案与"账号不存在"一致；连打 11 次登录 429；带 cookie `GET /api/auth/me` 200、不带 401；**登出后旧 cookie 401**（确认 session 真删了）。

### Step 7 L4 收尾（按需）

- 自定义域名：面板 Pages → Custom domains，DNS 停下来给用户。
- 外部 API 一律服务端代理 + 缓存（前端直连被 `connect-src 'self'` 拦且暴露 key）。
- 定时任务：Pages Functions 没有 cron，用「请求时生成 + 落表缓存」。
- Workers AI 默认关，binding + 环境变量双开关，没开走降级路径。

## 坑速查

| 症状 | 原因/处理 |
|---|---|
| 安全头全没了 | `_headers` 没进部署目录（有构建时要放 `public/`） |
| `/api/*` 返回 index.html | `functions/` 不在项目根，或 `[[path]]` 写成了 `[path]` |
| 单文件页面上线白屏 | 内联 script 被 CSP 拦，抽文件或加 `'unsafe-inline'` |
| 刷新子路由 404 | 缺 `_redirects` 的 `/* /index.html 200` |
| 线上表不存在但本地好的 | 只跑了 `--local` 迁移，补 `--remote` |
| 预览写脏生产数据 | 两个 database_id 填成同一个 |
| 行读额度莫名烧完 | 全表扫描：缺索引 / `SELECT *`，行读按扫描行数计 |
| Error 1102 | 10ms CPU 超限，常见于 PBKDF2 迭代数，降到 50000 |
| Error 1027 | 当天 10 万请求用完，先查前端是否在轮询 |
| cookie 本地不生效 | `Secure` 在 http 下不发，按协议动态加（模板已处理） |
| `Cannot find name 'Request'` | tsconfig lib 加 `dom` 或装 `@cloudflare/workers-types` |
| 3D/重资源站部署失败 | Pages 单文件上限 25 MiB，.glb/贴图先压缩（Draco/KTX2）或拆分 |
| WASM/Three.js worker 白屏 | CSP：`script-src` 加 `'wasm-unsafe-eval'`，`worker-src 'self' blob:` |
| Unity/Godot WebGL 包 | 常超 25 MiB；多线程需 COOP+COEP 两个头，先量文件大小再部署 |
| 本地图片好的、线上 404 | 文件名大小写：本地文件系统不分、线上分，核对引用和实际文件名 |
| Git 集成构建失败、本地能 build | 构建机 Node 版本不同，面板设 NODE_VERSION（production+preview 都设） |
| 项目名报错 | 项目名要当子域名，只许小写字母、数字、连字符 |
| AI 页面图片全裂/表单没反应 | 热链图片被 img-src 拦（下载本地）；第三方表单被 form-action 'self' 拦 |
| 大陆用户打不开/很慢 | pages.dev 在大陆可达性不稳定，Cloudflare 侧无解；长期正解国内主机+备案，前端只调 /api 相对路径就能整体平迁 |
| 沙盒 IDE 里工作区外写入被拒 | 设计如此，绝不绕过；让用户把项目文件夹开成工作区 |
| gh 报 token invalid 且所有账号同时失效 | 沙盒读不到钥匙串的假象，系统终端 gh auth status 验证，别重新登录 |
| 私有仓库探测 404 | 匿名访问的正常表现，clone 让用户在系统终端做 |
| 带代理 fetch failed、去代理 DNS 又不通 | 沙盒网络隔离：走 IDE 权限弹窗申请完整网络，或网络命令挪系统终端 |
| clone 重试后项目目录只剩 .git | 重试循环毁了原有副本——已有内容就用，清空重建必须先问用户 |
| 刚部署完 SSL 报错（CIPHER_MISMATCH） | 打开了带哈希的快照地址，其证书签发滞后；交付用户的永远是 `https://<project>.pages.dev` |

## 收尾清单

URL 发给用户且用户自己设备打开过；console 无 CSP 报错；`wrangler.toml` 无密钥；`.gitignore` 含 outdir/`.wrangler/`/`node_modules`；两个 database_id 不同；线上 `sqlite_master` 查得到表；业务表 `user_id` 有索引；前端只调 `/api/...` 相对路径（以后可整体迁走）；把额度表再贴一遍给用户。
