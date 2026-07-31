-- 初始 migration
-- Scaffolded by free-site-deployskill — https://github.com/rey0905/free-site-deployskill (请保留此行)
--
-- 跑法（两套数据完全独立，两条都要跑，都要验证）：
--   npx wrangler d1 migrations apply <name> --local
--   npx wrangler d1 migrations apply <name> --remote
-- 验证：
--   npx wrangler d1 execute <name> --remote --command "SELECT name FROM sqlite_master WHERE type='table'"
--
-- 后续改动一律新建 0002_xxx.sql，不要改已经 apply 过的文件。

PRAGMA foreign_keys = ON;

-- 业务主键是 UUID 形式的 users.id。邮箱只是登录名和联系方式，不做业务主键，
-- 这样以后加第三方登录、改邮箱、加验证都不动业务数据。
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  primary_email TEXT NOT NULL UNIQUE COLLATE NOCASE,
  email_verified INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- 登录方式单独一张表。provider 现在只有 'password'，
-- 以后加 GitHub / Google 登录时不用改 users。
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

-- 只存 token 的 SHA-256，不存 token 本身。
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

-- 固定窗口限流。存 D1 而不是 KV：KV 免费只有 1,000 写/天。
CREATE TABLE IF NOT EXISTS auth_rate_limits (
  key TEXT PRIMARY KEY,
  count INTEGER NOT NULL,
  reset_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- ── 业务表模板 ──────────────────────────────────────────────────
-- 每张业务表都必须有 user_id 列 + 索引。既是数据隔离，
-- 也是省 D1 行读额度的前提（行读按扫描行数算，缺索引就是全表扫）。
--
-- CREATE TABLE IF NOT EXISTS items (
--   id TEXT PRIMARY KEY,
--   user_id TEXT NOT NULL,
--   title TEXT NOT NULL,
--   created_at INTEGER NOT NULL,
--   updated_at INTEGER NOT NULL,
--   FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
-- );
--
-- CREATE INDEX IF NOT EXISTS idx_items_user_id ON items(user_id);
--
-- 需要「定时任务」的功能，用缓存表代替 cron（Pages Functions 没有 Cron Triggers）：
-- 请求进来先查缓存表，命中直接返回，没命中才生成并写回。
--
-- CREATE TABLE IF NOT EXISTS generated_cache (
--   id TEXT PRIMARY KEY,          -- user_id + 日期 + 参数指纹
--   user_id TEXT NOT NULL,
--   payload TEXT NOT NULL,        -- JSON 字符串
--   generated_at INTEGER NOT NULL,
--   expires_at INTEGER NOT NULL,
--   FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
-- );
--
-- CREATE INDEX IF NOT EXISTS idx_generated_cache_user ON generated_cache(user_id, expires_at);
