# free-site-deployskill

[中文](#中文说明) | [English](#english)

把 AI 帮你做好的网页，免费变成一个真正的网站——自己能打开，发给别人也能打开。

Turn the web page your AI built into a real website, for free — one that you can open, and that anyone you share the link with can open too.

---

## 中文说明

> **完全没碰过代码？** 直接看 **[《小白教程》](小白教程.md)** ——手把手到"复制这行、粘贴到终端、按回车"的程度，不需要任何编程知识。下面的内容看不懂没关系，教程里都进行了详尽地解释。

### 这是什么

一份给 AI 助手读的部署手册。你用 AI（Claude、ChatGPT、Cursor 等）做好了一个网页，但它只在你电脑上——这份手册教你的 AI 把它推到线上，全程免费，不用绑信用卡。

支持四档，按需选：

| 档位 | 能做什么 |
|---|---|
| 只上线 | 静态页面拿到一个公开网址 |
| 加接口 | 网站有自己的后端 `/api` |
| 加数据库 | 数据存下来，不靠浏览器缓存 |
| 加账号 | 用户注册登录，换设备数据还在 |

纯展示页还有更简单的 GitHub Pages 路线，手册会先问你要哪种。

### 怎么用

**方式一（推荐）：只发一个文件。** 把 [`PORTABLE.md`](PORTABLE.md) 整个文件发给任何**能在你电脑上执行命令的 AI**（Claude Code、Codex CLI、Cursor、Windsurf 等——纯网页聊天版不行），然后说：

> 照这个手册，把我这个项目上线。

**方式二：装成 Claude Code skill。** 把整个仓库克隆到 skills 目录：

```sh
git clone https://github.com/rey0905/free-site-deployskill ~/.claude/skills/cloudflare-deploy
```

之后在 Claude Code 里说"帮我把这个项目上线"，skill 会自动触发。

### 你需要准备

- 装了 Node 20 以上的电脑
- 一个免费的 Cloudflare 账号（或 GitHub 账号，纯展示页用）——都不用绑卡
- 中间有两三步（浏览器授权、面板点按钮）AI 会停下来让你自己操作

### 免费额度够用吗

Cloudflare 免费档：静态页面的访问**不限量**；后端接口 10 万次/天；数据库 500 万行读、10 万行写/天。个人项目和小工具远用不满。手册的第一原则就是免费：每一步开工前，AI 会把对应额度报给你；任何只有付费才能做的事，AI 会停下来先问你。

### 仓库里有什么

```
小白教程.md            给人看的手把手教程（不懂代码从这里开始）
PORTABLE.md            给 AI 看的单文件手册（发给你的 AI 用这个）
SKILL.md               Claude Code skill 主文件
references/            免费额度表、常见坑、账号系统代码、GitHub Pages 路线
assets/                模板：安全头、路由回退、后端骨架、数据库初始化
scripts/preflight.sh   一键体检：环境、项目形态、十几类常见问题
```

### 常见问题

**我的代码在私有仓库可以吗？** 可以。默认路线根本不经过 GitHub；接 GitHub 自动部署也支持私有仓库。只有 GitHub Pages 免费版要求公开。

**3D 页面、炫酷效果能上吗？** 能。浏览器渲染的 3D（Three.js 等）对托管来说就是静态文件。单文件超 25 MiB 会被体检脚本提前抓出来。

**AI 给我写的是 Python 后端怎么办？** 推不上去（平台只跑 JS/TS），体检脚本会检测出来并给你两条路：前端照常上线+后端移植，或后端另找托管。

**网站是英文/其他语言的行吗？** 行。托管对语言无感。模板里的报错文案默认中文，手册里写明了要按站点语言改。

---

## English

> **Never touched code?** The step-by-step beginner walkthrough ([小白教程.md](小白教程.md), currently Chinese-only) goes down to "copy this line, paste into Terminal, press Enter" level.

### What is this

A deployment manual written for AI assistants to follow. You've built a web page with an AI (Claude, ChatGPT, Cursor, etc.) but it only exists on your computer — this manual teaches your AI to put it online, entirely on free tiers, no credit card required.

Four levels, pick what you need:

| Level | What you get |
|---|---|
| Static | Your page live on a public URL |
| + API | A same-origin `/api` backend |
| + Database | Data stored server-side, not in browser cache |
| + Accounts | Sign-up/login; data follows users across devices |

For pure showcase pages there is also a simpler GitHub Pages route — the manual asks which one you want first.

### How to use

**Option 1 (recommended): send one file.** Give [`PORTABLE.md`](PORTABLE.md) to any AI that **can run commands on your computer** (Claude Code, Codex CLI, Cursor, Windsurf — a plain chat window won't work), and say:

> Follow this manual and deploy my project.

**Option 2: install as a Claude Code skill.** Clone the repo into your skills directory:

```sh
git clone https://github.com/rey0905/free-site-deployskill ~/.claude/skills/cloudflare-deploy
```

Then ask Claude Code to "deploy this project" and the skill triggers automatically.

### What you need

- A computer with Node 20+
- A free Cloudflare account (or a GitHub account for showcase pages) — no card needed
- Two or three steps (browser OAuth, dashboard clicks) where the AI will stop and hand over to you

### Is the free tier enough?

Cloudflare's free plan: **unlimited** requests and bandwidth for static assets; 100,000 backend requests/day; 5M database rows read and 100K written per day. Personal projects won't come close. Staying free is the manual's first rule: before each level the AI reports the relevant quota to you, and stops to ask before anything that would require a paid plan.

### What's inside

```
PORTABLE.md            Single-file manual (this is what you share)
SKILL.md               Claude Code skill entry point
references/            Free-tier quotas, known pitfalls, auth recipe, GitHub Pages route
assets/                Templates: security headers, SPA fallback, API skeleton, DB schema
scripts/preflight.sh   One-shot checkup: environment, project shape, a dozen common issues
```

### FAQ

**My code is in a private repo — OK?** Yes. The default route never touches GitHub; the Git-integration route supports private repos too. Only GitHub Pages (free) requires a public repo.

**Can it host 3D / fancy pages?** Yes. Browser-rendered 3D (Three.js etc.) is just static files to the host. Files over the 25 MiB per-file limit get caught by the preflight script before deploying.

**My AI wrote a Python backend — what now?** It can't run there (the platform executes JS/TS only). The preflight script detects this and offers two paths: deploy the frontend as-is and port the backend, or host the backend elsewhere.

**My site is in English or another language — fine?** Fine. Hosting is language-agnostic. The template error messages default to Chinese; the manual tells the AI to translate them to your site's language.

---

*Note: free-tier numbers were verified against Cloudflare's official docs in July 2026 and may change — the manual instructs the AI to re-check before relying on them.*

---

## 授权 / License

手册与文档：**CC BY-NC 4.0** —— 使用须署名并附本仓库链接，禁止商用。
**模板**：`assets/`、`scripts/` 及文中供拷贝的代码可自由用于任何项目（含商业项目），条件是**保留文件里指向本仓库的来源注释行**（访客不可见）——限制的是手册本身，不是用它部署的网站。页脚可见署名欢迎但不强制。

Manuals & docs: **CC BY-NC 4.0** — attribution with a link to this repo required; no commercial use.
**Templates**: `assets/`, `scripts/`, and copy-into-your-project code snippets may be used in any project, commercial included, provided the **source-comment line pointing to this repo is retained** (invisible to visitors) — the restriction covers the manual itself, not sites deployed with it. A visible footer credit is welcome but optional.

详见 / Full terms: [LICENSE.md](LICENSE.md)
