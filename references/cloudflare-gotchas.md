# 已知的坑

按"症状 → 原因 → 处理"组织。多数是从一个线上跑着的 Pages + Functions + D1 项目里实际踩出来的。

## 部署与静态资源

**安全头全部消失** — `_headers` 放在项目根目录了。它必须在**构建输出目录里**才生效。Vite/CRA 放 `public/`，Astro/SvelteKit 放 `static/`，构建时会被拷进输出目录。检查方法是 build 完看输出目录里有没有这个文件，别只看源码目录。

**`_headers` 不覆盖 Functions 响应里的关键头** — 实测：`_headers` 里的 `X-Frame-Options`、`Permissions-Policy`、`X-Robots-Tag` 会出现在 `/api/*` 的响应上，但 `Content-Security-Policy` 和 `Strict-Transport-Security` 不会。安全关键的头别指望 `_headers` 覆盖全部响应，在 Functions 的 `json()` helper 里自己再设一遍。函数自己设的同名 header 覆盖 `_headers`。

**刷新子路由 404** — 客户端路由没有 SPA fallback。加 `_redirects` 写 `/* /index.html 200`。注意 `200` 不是 `302`，那是重写不是跳转。

**部署完页面白屏，console 全是 CSP 报错** — CSP 写了 `script-src 'self'`，所有 CDN 脚本、Google Fonts、外部图片全被拦。要么把资源下载到本地，要么在 `_headers` 里明确放宽对应那一条指令。放宽了就告诉用户放宽了哪条、为什么，别悄悄改成 `'unsafe-inline'` 了事。

**Tailwind / 打包器注入内联样式被拦** — CSP 的 `style-src 'self'` 不允许内联 `<style>`。构建产物是外链 CSS 文件就没事；有内联就得加 `'unsafe-inline'` 到 `style-src`（只放宽 style，别顺手放宽 script）。

**AI 生成的单文件 HTML 一上线就白屏** — 这类页面的 JS 全写在内联 `<script>` 里，被模板 CSP 的 `script-src 'self'` 整个拦掉。console 里一排 CSP 报错。优先把内联代码抽成独立 `.js`/`.css` 文件；不好抽就在 `script-src`/`style-src` 加 `'unsafe-inline'`，并告知用户这是妥协。同类页面几乎必带 tailwind CDN 和 Google Fonts，一并处理（本地化或放宽对应指令）。

**AI 页面的图片全裂、表单提交没反应** — 热链的 Unsplash 等外部图片被 `img-src 'self' data: blob:` 拦；提交到 Formspree 之类第三方的表单被 `form-action 'self'` 拦。图片下载到本地；表单要么放宽 `form-action` 加对方域名，要么改成自己的 `/api` 路由（L1）。

## 语言与字体

**托管对语言无感** — UTF-8 全覆盖，中文英文阿拉伯语都一样；RTL 是前端 CSS 的事（`dir="rtl"`），与部署无关。确保 HTML 有 `<meta charset="UTF-8">` 即可。

**CJK webfont 巨大** — 英文字体几十 KB，一套中日韩字体 5–15 MB。CSP 要求本地化字体后这个问题会显性化。CJK 优先用系统字体栈（不发字体文件）；非要自定义字体就子集化（subset）再上。拉丁字母语言无此问题。

**模板文案是中文的** — 本 skill 的 Functions 骨架和账号代码里，用户可见的报错文案（"请先登录""邮箱或密码不正确"等）全是中文。站点是其他语言时，把这些字符串改成站点语言，别把中文报错弹给英文用户。

**大陆用户访问不稳定** — `*.pages.dev` 在中国大陆可达性时好时坏，自定义域名走 Cloudflare 代理也帮助有限，这是网络环境问题，Cloudflare 侧无解。主要受众在大陆的话如实告诉用户：短期能用但别指望稳定，长期正解是国内主机 + ICP 备案。本 skill 的「前端只调 `/api/...` 相对路径、不写死 Cloudflare 概念」规则就是为这种迁移留的门——迁移时后端在新家复刻同样路径，前端一行不改。

## 沙盒 IDE（Cursor 等）

在带沙盒的 IDE 代理里执行本 skill 时的三个典型症状，全部来自真实测试：

**工作区外写入被拒、workspace 显示 unknown** — 沙盒设计如此。正确动作：让用户把项目文件夹用 File → Open Folder 开成工作区，然后在工作区内干活。**绝不尝试绕过**——不加 `required_permissions` 之类的参数、不提权、不开子代理绕。绕过尝试本身就是错误行为，即使成功了也意味着在用户不知情的地方写文件。

**gh 报 "token in keyring is invalid"，且所有账号都"失效"** — 八成是假象：沙盒读不到 macOS 钥匙串，gh 拿不到 token 就报 invalid。所有账号同时"失效"是识别标志（真过期不会这么整齐）。先让用户在**系统终端**跑 `gh auth status` 验证；真终端有效，就把需要凭据的命令（clone、push、`wrangler login`）挪到系统终端让用户跑，**不要引导用户重新登录**——那会白白作废好的 token。

**私有仓库探测 404** — 匿名访问私有仓库的正常表现，不代表仓库不存在或配置错了。clone 交给用户在系统终端做（见「必须停下来」清单），拿到本地代码再继续。

**wrangler 一般不受钥匙串问题影响** — 它的 OAuth token 存在配置文件里（`~/Library/Preferences/.wrangler/` 或 `~/.config/.wrangler/`），沙盒通常读得到。preflight 报"未登录"前先确认 wrangler 真的装了——`npx --no-install` 在未安装时会静默失败，看起来像未登录。

**代理和直连双双失败** — 症状组合（真实案例）：带代理跑 → "Proxy environment variables detected" + fetch failed（沙盒够不到用户本机的代理进程）；清掉代理变量再跑 → 连 `api.cloudflare.com` 的 DNS 都解析不了（沙盒禁直连）。两条路都死 = 沙盒网络隔离，是网络问题不是认证问题，别开"重新 login"的药方。两条正路：① 走 IDE 自身的权限机制申请完整网络权限——弹窗让用户明确点同意的那种，这是合法途径，不是"绕过"；② 网络类命令（`wrangler deploy`、`git push`）挪到系统终端让用户跑，本地操作（build）留在 IDE 里做。

**重试循环毁掉了已有的项目副本** — 真实案例：目录里本来有完整可用的代码，AI 的 clone 重试把它清成只剩半个 `.git`。规则：目录已有内容就先检查再用它；任何"清空重建"必须先问用户；clone 失败的正确处置是停下来报告，不是换姿势反复试。

## 后端语言

**Workers 只跑 JS/TS/WASM** — 用户的 AI 写的后端如果是 Python（Flask/FastAPI/Django/Streamlit）、PHP、Ruby 等，推不上 Pages Functions，这是硬边界，不是配置问题。停下来向用户说明两条路：① 前端照常上线，后端照本 skill 的骨架移植成 Functions（小 CRUD 移植很快，认证直接用 auth-recipe 现成的）；② 后端放别家（Render/Fly 等有免费档但会休眠，额度自查）。Express/Node 后端同样不能直接跑（Workers 不是 Node），但 JS 逻辑照搬到 Functions 里改动最小。前端用什么框架（React/Vue/Svelte/纯 HTML）都无所谓，能构建成静态文件就行。

**构建次数快用完** — 免费 500 次/月，并发 1。GitHub 集成分支每个 push 都算一次构建，包括 PR 预览。频繁提交时改用 CLI 直推，或者把 CI 触发条件收窄。

**本地图片正常、线上 404** — macOS/Windows 文件系统不分大小写，线上分。`<img src="logo.png">` 配上实际文件 `Logo.PNG` 本地能显示、部署后裂。用 `find` 对一遍引用和实际文件名的大小写。

**Git 集成分支构建失败，本地明明能 build** — 构建机的 Node 版本和本地不一致。在面板环境变量里设 `NODE_VERSION`（如 `20`），production 和 preview 都设。

**项目建不了，名字报错** — Pages 项目名要当子域名用，只允许小写字母、数字、连字符。

**无构建项目 deploy 后文件数爆炸或速度极慢** — 直接 `wrangler pages deploy .` 把 node_modules、.git 一起推了（2 万文件上限）。要么清理目录，要么把页面文件挪进一个干净的子目录再推。

## 3D / WebGL / 重资源页面

浏览器渲染的 3D（Three.js、react-three-fiber、Babylon 等）对托管来说仍是纯静态文件，Pages 不限请求不限带宽，本身没问题。会踩的是：

**部署失败，报文件过大** — Pages 单文件上限 25 MiB。`.glb` 模型、HDR 贴图、视频容易超。处理顺序：① 压缩（glb 用 Draco/meshopt，贴图转 KTX2/WebP）；② 拆分模型分段加载；③ 还不行就把大资源放 R2（免费 10 GB 存储，但出流量额度要查当时文档并告知用户）。

**WASM 引擎白屏，console 报 CSP 拒绝** — WebAssembly 编译被 `script-src 'self'` 拦。在 `script-src` 加 `'wasm-unsafe-eval'`（只加这个，不要图省事加 `'unsafe-eval'`）。

**Web Worker 加载失败** — 引擎常用 blob: URL 起 worker。CSP 加 `worker-src 'self' blob:`。

**Unity / Godot 导出的 WebGL 包** — 最容易出问题的类别：单个 `.data`/`.wasm` 常超 25 MiB；引擎多线程需要 `SharedArrayBuffer`，要同时设 `Cross-Origin-Opener-Policy: same-origin` 和 `Cross-Origin-Embedder-Policy: require-corp`（模板 `_headers` 只带了前者，后者会连带要求所有跨域资源带 CORP 头，加之前告知用户影响）。遇到这类项目先量文件大小，超限就先解决资源问题再部署。

**函数完全不生效，`/api/*` 返回 index.html** — `functions/` 目录位置错了。它必须在**项目根**，不在构建输出目录里。`/api/*` 的 catch-all 路径是 `functions/api/[[path]].ts`，单层通配是 `[path]`，多层才是 `[[path]]`。

**构建工具把 `functions/` 打进 bundle 或报类型错** — `functions/` 不该被前端 import。Vite 默认不管它。TypeScript 项目要把 `functions` 加进 `tsconfig.json` 的 `include`，否则编辑器里没类型检查。

**`Cannot find name 'Request' / 'Response' / 'URL'`** — tsconfig 的 `lib` 里没有 DOM，也没装 `@cloudflare/workers-types`。两个办法：`"lib": ["es2022", "dom"]`（够用，零依赖），或者装 `@cloudflare/workers-types` 并在 `types` 里引用（更准，能查出 Workers 特有的 API）。前端和 Functions 的 lib 配置冲突时，给 `functions/` 单独一个 tsconfig。

**`env` 没有类型** — 手写一个 `type Env = { DB: D1Database; ... }`，或者跑 `npx wrangler types` 生成。手写更省事，绑定少的时候够用。

**本地 `pages dev` 起不来或路由不对** — 先 `npm run build`，再 `npx wrangler pages dev <outdir>`。让 wrangler 直接接管 dev server 的写法在不同 wrangler 版本里参数不一样，build 完再跑最稳。

**子请求超限** — 一个请求里最多 50 个出站 fetch。循环里给每条数据打一次外部 API 会瞬间超。改成批量接口或者分页缓存。

**`Error 1102 Worker exceeded resource limits`** — 撞了 10ms CPU 上限。常见来源是密码哈希迭代数、大 JSON 的解析和序列化、正则回溯。见 auth-recipe 里 PBKDF2 那节。

**`Error 1027`** — 当天 10 万请求用完了。先查是不是前端在轮询。

## D1

**线上报表不存在，本地明明好的** — `--local` 和 `--remote` 是两套完全独立的数据。两条迁移命令都要跑，都要用 `sqlite_master` 查一遍验证。

**预览分支把生产数据写脏了** — `wrangler.toml` 里 `database_id` 和 `preview_database_id` 填了同一个。建两个库，填两个不同的 id。

**行读额度莫名烧完** — 行读按**扫描**的行数算，不是返回的行数。缺索引的 `WHERE`、`SELECT *`、`ORDER BY` 未索引列都会全表扫。每张业务表给 `user_id` 建索引，查询里明确列字段。

**一次请求里查询报错超限** — 免费计划单次 Worker 调用最多 50 条 D1 查询。N+1 查询很容易超。用 `env.DB.batch([...])` 合并，或者一条 SQL 用 JOIN 解决。

**D1 库建不出来了** — 免费计划 10 个库上限，production + preview 一个项目占 2 个。

**外键不生效** — D1 里 `PRAGMA foreign_keys = ON;` 要写在 migration 开头。

## 认证与安全

**Workers 上没有 bcrypt / argon2** — 它们是原生模块，Workers 运行时没有。只能用 Web Crypto 的 PBKDF2（`crypto.subtle.deriveBits`）。

**cookie 在本地开发时不生效** — `Secure` 标记的 cookie 在 http 下不发送。按 `url.protocol === 'https:'` 动态决定是否加 `Secure`。

**跨域后 cookie 丢失** — 把 API 放到独立的 `*.workers.dev` 域名就会跨域，`SameSite=Lax` 的 cookie 不跟着发，还得开 CORS。同域 `/api/*` 是这套架构成立的前提，别拆。

**secrets 泄进 git** — `wrangler.toml` 是进版本库的。密钥走 `wrangler pages secret put`（CLI 分支）或面板环境变量（Git 分支）。Git 分支记得 production 和 preview 两套都填。

## 架构

**Pages Functions 没有 Cron Triggers** — 要定时只能另开一个独立 Worker（免费 5 个 trigger），但那会引入跨域。默认方案是「请求时生成 + 结果落表缓存」，用一张 cache 表按天或按参数缓存，天然省额度。

**以后想搬到自己的服务器，发现前端和 Cloudflare 缠死了** — 前端只调 `/api/...` 相对路径，不在前端出现任何 Cloudflare API、D1 id、绑定名。这样迁移只需要在新后端复刻同样的 `/api` 路径，前端一行不改。
