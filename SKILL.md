---
name: cloudflare-deploy
description: Put an already-designed frontend live on a real public URL, for free — GitHub Pages for pure static, or Cloudflare (Pages + Functions + D1 + auth) when a backend is or will be needed. Handles single-file AI-generated HTML pages as well as Vite/React builds. Use when the user wants to deploy, ship, publish or host a site (上线 / 部署 / 发布网页), share a page others can open, add a backend or database to a frontend, set up wrangler / Pages / D1 / pages.dev / GitHub Pages, or asks whether a design stays inside free quota. Layered — static only, +API, +database, or +accounts.
---

# 把做好的前端上线（免费）

前端已经设计好了。这个 skill 负责把它变成一个真正在线上的站，按需带 API、数据库和账号系统，全程不花钱。

## 交付标准（不可妥协）

1. **交付物是一个公开 URL**：用户自己能打开，发给别人、别人在自己的设备上也能打开。本地 HTML 文件、`localhost`、截图，都不算完成。收尾时把 URL 发给用户，让用户用手机开一次验证。
2. **不用 localStorage 冒充保存**。localStorage 换浏览器、换设备、清缓存就没了。用户表达过"内容不丢""换设备还在""每个用户有自己的数据"任意一种，就必须走 L2/L3（数据库/账号）。localStorage 只能作为明确告知局限后的单设备方案，且页面本身仍然要上线。

## 使用前提

这份文件是给 AI 助手读的操作手册，不是给人读的教程。执行它需要：

- **能在用户本机执行命令行的 AI**（Claude Code、Codex CLI、Cursor、Windsurf、Gemini CLI 等）。纯聊天窗口里的 AI 没有 shell，做不了部署。
- **本机装了 Node 20 以上**。
- **一个 Cloudflare 账号或 GitHub 账号**（都免费，不用绑卡）。
- **完整的 skill 目录**，不只是这个 SKILL.md。`assets/` 是模板，`references/` 是细节，`scripts/preflight.sh` 是环境检查。只拿到这一个文件时，向用户说明缺了模板，或让用户改用 `PORTABLE.md`（模板全部内联的单文件版，适合发给别人）。

给非技术用户执行时：每一步先用人话说这步在干什么，命令结果贴出来，报错先给用户看原文再动手改。

## 第零步：选平台

和后面的问题一起问用户：**这个站以后要不要后端（登录、多用户各自的数据、服务端 API）？**

- **纯展示，永远静态，代码可以公开** → GitHub Pages 更省事，走 `references/github-pages.md`，走完即结束，下面全部跳过。
- **现在或将来要后端** → Cloudflare，继续本文件。
- **拿不准** → Cloudflare。静态托管一样免费，以后原地长出后端，不用搬家；GitHub Pages 永远加不了后端。

注意 GitHub Pages 免费版**仓库必须公开**，代码不愿公开的直接排除。私有仓库不影响 Cloudflare 两条分支：CLI 直推根本不经过 GitHub；Git 集成分支在面板授权 Cloudflare 的 GitHub App 访问该私有仓库即可，免费计划就支持。

## 第一原则：免费

**每一层开始前，先把 `references/free-tier-limits.md` 里对应那段的额度数字贴给用户**，别等用户问。

三条硬约束：

1. 整个 L0–L4 不需要付费计划，也不需要绑信用卡。任何一步只有付费能做，停下来说清价格让用户决定。
2. 不在额度表里的 Cloudflare 服务（Queues、Hyperdrive、Durable Objects 等），用之前查 developers.cloudflare.com 的 pricing 页并贴给用户确认。
3. 遵守 `references/free-tier-limits.md` 结尾的「省额度四条规则」。省额度是设计约束，不是上线后再优化的事。

## 分层

累加式。用户选 L3 就依次走 L0→L1→L2→L3，每层真的部署一次并验证，出问题能定位到层。

| 层 | 做什么 | 主要额度消耗 |
|---|---|---|
| L0 | 静态站上线，拿到 `*.pages.dev` URL | 构建 500 次/月；静态请求不限量 |
| L1 | 同域 `/api/*` Pages Functions 骨架 | Workers 100,000 请求/天 |
| L2 | D1 数据库 + migrations | 500 万行读/天、10 万行写/天 |
| L3 | 邮箱密码账号 + session cookie + 限流 | 计入上面两项 |
| L4 | 自定义域名、secrets、外部 API 代理缓存、可选 Workers AI | 域名免费；Workers AI 10,000 Neurons/天 |

## 流程

### Step 1 探测现有项目

先看清楚再动手。项目分两种：

**A. 有构建流程**（有 package.json）：
- scripts 和依赖 → 构建命令、框架、输出目录（看 `vite.config.*` 等）
- 有客户端路由（react-router / vue-router / TanStack Router）→ 需要 SPA fallback
- 有 `wrangler.toml` → 二次运行，走增量路径，不要重新初始化

**B. 无构建流程**（没有 package.json，一个或几个 HTML 文件——AI 生成的网页大多长这样）：
- 项目目录本身就是部署目录，没有 build 这一步
- `_headers`、`_redirects` 直接放在 index.html 旁边
- **重点检查 HTML 里的内联 `<script>`/`<style>` 和 CDN 引用**（tailwind CDN、Google Fonts 几乎必有），CSP 处理见 Step 4 第 3 点

**Next.js 例外**：SSR/App Router 走 Pages 需要 next-on-pages/OpenNext，和本流程冲突。先问用户：导出纯静态（`output: 'export'`，可继续本流程）还是只帮到 L0。

**后端语言检查**：发现 Python/PHP/Ruby 后端（requirements.txt + app.py、manage.py 等）就**停下来**——Workers 只跑 JS/TS/WASM，推不上去。向用户说明两条路（前端照常上线+后端按骨架移植成 Functions / 后端另找托管），见 gotchas「后端语言」。前端框架无所谓，能构建成静态文件就行。

**文案语言**：本 skill 模板里用户可见的报错文案是中文。站点是其他语言时，落地前把这些字符串改成站点语言。CJK 站点若要自定义字体，先看 gotchas「语言与字体」（体积问题）。

### Step 2 问两个问题

和第零步的平台问题一起、一次问完，不要挤牙膏。有结构化提问工具就用，没有就直接问：

1. **要到哪一层**：L0 静态 / L1 加 API / L2 加数据库 / L3 加账号。每个选项标注额度成本。用户描述的需求已经暗示了层级时（"用户的笔记要存下来"→ L3），直接指出来，别让用户自己猜。
2. **部署方式**：wrangler CLI 直推，还是接 GitHub 自动构建。

两条分支只影响三件事，其余共用：

| | CLI 直推 | GitHub 集成 |
|---|---|---|
| 上线动作 | `npx wrangler pages deploy <outdir>` | `git push` |
| 首次配置 | `npx wrangler pages project create` | 停下来让用户去面板连仓库 |
| 环境变量 | `npx wrangler pages secret put KEY` | 面板里填，production 和 preview 两套都要填 |

### Step 3 前置检查

跑 `scripts/preflight.sh`。它检查 node、wrangler、登录状态，探测项目形态和 CSP 风险。

`wrangler whoami` 失败就**停下来**，让用户自己跑 `npx wrangler login` 完成浏览器 OAuth，等回报成功再继续。不要假装做完了。

### Step 4 L0 — 静态上线

1. 拷 `assets/_headers` 到静态目录（有构建：`public/` 或 `static/`；无构建：index.html 旁边）。**必须在最终部署目录里**，放错位置不生效。
2. 有客户端路由才拷 `assets/_redirects`。多页静态站不要拷，会把 404 变成首页。
3. **CSP 校准**——模板默认最严（全 `'self'`），按项目实际情况放宽，每放宽一条向用户说明：
   - 外部 CDN 脚本/字体：优先下载到本地改成相对引用；不行就放宽对应指令
   - **无构建的单文件页面**：内联 `<script>` 会被 `script-src 'self'` 直接拦掉、页面白屏。优先把内联代码抽成 `.js`/`.css` 文件；页面复杂不好抽时，放宽 `script-src`/`style-src` 加 `'unsafe-inline'` 并告知用户这是妥协
4. 部署：
   - CLI 分支：`npx wrangler pages project create <name> --production-branch main`，然后（有构建先 `npm run build`）`npx wrangler pages deploy <outdir>`。无构建项目 `<outdir>` 就是项目目录本身——确认里面没有 node_modules、.git 之外的杂物再推。
   - Git 分支：输出面板步骤（Workers & Pages → Create → Pages → Connect to Git → 选仓库 → 填构建命令和输出目录），**停下来**等用户回报 URL。

**验证，不过不往下走**：

```sh
curl -sI https://<project>.pages.dev/ | head -1                    # 200
curl -sI https://<project>.pages.dev/ | grep -i content-security   # 有 CSP
curl -so /dev/null -w '%{http_code}\n' https://<project>.pages.dev/<前端路由>  # SPA 应为 200
```

浏览器打开一次，console 有 CSP 拦截报错就回到第 3 点。最后让用户自己打开一次。

### Step 5 L1 — 加 `/api/*`

1. `assets/functions/api/[[path]].ts` → 项目根的 `functions/api/[[path]].ts`。`functions/` 必须在项目根，不能在构建输出目录里。
2. 骨架自带 `GET /api/health`、`json()`、`HttpError`、路由分发。业务路由往里加。
3. TypeScript 项目把 `functions` 加进 tsconfig 的 include；报 `Cannot find name 'Request'` 见 gotchas。

**本地验证**：

```sh
npm run build && npx wrangler pages dev <outdir>    # 无构建项目直接 pages dev .
curl -s localhost:8788/api/health                    # {"ok":true}
curl -s localhost:8788/api/nope -o /dev/null -w '%{http_code}\n'   # 404 且是 JSON
```

线上同样两条打 `*.pages.dev`。

### Step 6 L2 — 加 D1

1. 建两个库（先告诉用户：免费 10 个库/账号，一个项目占 2 个）：

```sh
npx wrangler d1 create <name>
npx wrangler d1 create <name>-preview
```

2. `assets/wrangler.toml` → 项目根，填两个 `database_id`。**preview 必须用单独的 id**，否则预览分支写生产库。
3. `assets/migrations/0001_initial.sql` → `migrations/`，按业务加表。**每张业务表都要 `user_id` 列 + 索引**。
4. 先本地再线上，两边都要验证（两套独立数据）：

```sh
npx wrangler d1 migrations apply <name> --local
npx wrangler d1 execute <name> --local --command "SELECT name FROM sqlite_master WHERE type='table'"
npx wrangler d1 migrations apply <name> --remote
npx wrangler d1 execute <name> --remote --command "SELECT name FROM sqlite_master WHERE type='table'"
```

### Step 7 L3 — 加账号

照 `references/auth-recipe.md` 抄，那是线上验证过的代码。不要重写，不要换 bcrypt（Workers 上没有）。

**验证**：

```sh
# 注册 → 201 + HttpOnly cookie；重复注册 → 409；短密码 → 400
# 密码错 → 401，文案和"账号不存在"完全一致；连打 11 次登录 → 429
# 带 cookie GET /api/auth/me → 200；不带 → 401；登出后旧 cookie → 401
```

注意 10ms CPU 上限，见 auth-recipe 的 PBKDF2 一节。

### Step 8 L4 — 收尾

按需做，每项先说额度：

- **自定义域名**：面板 Pages → Custom domains。DNS 那步停下来交给用户。100 个/项目。
- **secrets**：`npx wrangler pages secret put KEY`。绝不写进 wrangler.toml（进 git 的）。
- **外部 API**：一律服务端代理 + 缓存。前端直连被 `connect-src 'self'` 拦，且暴露 key。
- **定时任务**：Pages Functions 没有 cron。默认「请求时生成 + 落表缓存」。确实要 cron 才另开 Worker（免费 5 个 trigger），并说明会引入跨域。
- **Workers AI**：默认关。binding + 环境变量双开关，没开走降级路径。10,000 Neurons/天，超了报错，免费计划不能超额付费。

## 必须停下来交给用户的事

skill 做不了，别硬试，也别假装做完了：

1. `wrangler login` / `gh auth login` 的浏览器 OAuth
2. GitHub 集成分支在 Cloudflare 面板连仓库
3. 自定义域名的 DNS 记录
4. GitHub Pages 分支：把仓库设为 public 前，必须让用户明确同意代码公开

## 收尾检查清单

- [ ] 最终 URL 发给了用户，用户在自己设备上打开过
- [ ] `_headers` 在部署目录里，线上 `curl -I` 能看到 CSP
- [ ] 浏览器 console 没有 CSP 拦截报错
- [ ] 客户端路由刷新子路径返回 200
- [ ] `wrangler.toml` 里没有任何密钥
- [ ] `.gitignore` 含构建输出目录、`.wrangler/`、`node_modules`
- [ ] preview 和 production 的 `database_id` 不同
- [ ] 线上迁移跑过，`sqlite_master` 查得到表
- [ ] 业务表 `user_id` 有索引，没有裸 `SELECT *` 全表
- [ ] 前端只调 `/api/...` 相对路径，没写死 Cloudflare 概念
- [ ] 把额度表和「省额度四条规则」再贴一遍给用户

## 参考文件

- `references/free-tier-limits.md` — 核准过的免费额度、超限表现、省额度规则
- `references/github-pages.md` — 纯展示站走 GitHub Pages 的完整流程
- `references/cloudflare-gotchas.md` — 坑：症状 → 原因 → 处理
- `references/auth-recipe.md` — 账号系统完整实现
- `assets/` — `_headers`、`_redirects`、`wrangler.toml`、Functions 骨架、初始 migration
- `scripts/preflight.sh` — 环境检查
- `PORTABLE.md` — 模板全部内联的单文件版，**用来发给别人**（别的 AI 只拿到一个文件也能跑）

**维护注意**：改了本文件或 assets/ 里的模板，同步改 PORTABLE.md，两边不一致就是坑。
