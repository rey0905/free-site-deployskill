# 纯展示站走 GitHub Pages

只适用于：**永远静态、不要后端、代码可以公开**。三条有一条不满足就回 Cloudflare 路线。

## 先向用户确认两件事

1. **仓库会是公开的**。GitHub Pages 免费版只对 public 仓库开放，全世界都能看到源码。用户不同意就停，改走 Cloudflare（支持私有仓库）。
2. URL 形态是 `https://<用户名>.github.io/<仓库名>/`，带仓库名后缀。想要根域名得把仓库命名为 `<用户名>.github.io`。

## 免费额度（软限制，来源 GitHub 文档，数字可能变，用前可再查）

- 站点大小 ≤ 1 GB
- 带宽约 100 GB/月（软限制，超了不是断站是收到通知）
- 构建约 10 次/小时
- public 仓库的 GitHub Actions 免费不限分钟

个人展示页远碰不到这些线。

## 最大的坑：子路径

站点部署在 `/<仓库名>/` 下，**所有以 `/` 开头的绝对路径引用全部 404**。

- 纯 HTML 项目：资源引用一律用相对路径（`./style.css` 而不是 `/style.css`）
- Vite 项目：`vite.config` 里设 `base: '/<仓库名>/'`
- 客户端路由：GitHub Pages 没有 rewrite 规则，SPA fallback 的通行 hack 是**把构建出的 index.html 复制一份改名 404.html** 放进部署目录

另外 GitHub Pages 不支持自定义响应头（没有 `_headers` 等价物），CSP 那套安全头加不了。展示页无所谓，这也是"要认真做产品就走 Cloudflare"的理由之一。

## 步骤

前置：`gh auth status` 不通过就**停下来**让用户跑 `gh auth login`（浏览器 OAuth，AI 代不了）。

### 1. 建仓库并推上去

```sh
git init && git add -A && git commit -m "init"
gh repo create <仓库名> --public --source=. --push   # public 这步必须已经获得用户同意
```

### 2a. 无构建项目（HTML 直接在仓库根）

```sh
gh api repos/{owner}/<仓库名>/pages -X POST \
  -f "source[branch]=main" -f "source[path]=/"
```

失败就给用户面板路径：仓库 → Settings → Pages → Source 选 "Deploy from a branch" → main / root。

### 2b. 有构建项目（Vite 等）

先设 `base: '/<仓库名>/'`，然后加官方 Actions workflow `.github/workflows/pages.yml`：

```yaml
name: Deploy Pages
on:
  push: { branches: [main] }
permissions: { contents: read, pages: write, id-token: write }
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: { name: github-pages }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci && npm run build
      - run: cp dist/index.html dist/404.html   # 只有 SPA 才要这行
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with: { path: dist }
      - uses: actions/deploy-pages@v4
```

再把 Pages source 设为 GitHub Actions：

```sh
gh api repos/{owner}/<仓库名>/pages -X POST -f "build_type=workflow"
```

（已存在 Pages 配置时用 `-X PUT` 更新。）然后 push 触发部署。

### 3. 验证

首次发布可能要等一两分钟：

```sh
gh api repos/{owner}/<仓库名>/pages --jq '.html_url,.status'
curl -sI https://<用户名>.github.io/<仓库名>/ | head -1     # 200
```

浏览器打开检查资源没有 404（子路径坑的症状就是页面在、样式图片全裂）。最后把 URL 发给用户，让用户手机上开一次。

## 以后想加后端了怎么办

GitHub Pages 上永远加不了。迁移路径：同一个仓库直接接 Cloudflare Pages（Git 集成分支），把 `base` 改回 `'/'`，回到主流程的 L1 往上走。前端代码本身不用改。
