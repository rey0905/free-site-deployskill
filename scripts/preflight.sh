#!/usr/bin/env bash
# 上线前环境检查 + 项目探测。只读，不改任何东西。
# 用法：bash scripts/preflight.sh [项目目录]   （默认当前目录）

set -u
DIR="${1:-.}"
cd "$DIR" || { echo "目录不存在: $DIR"; exit 1; }

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }

echo
echo "项目目录: $(pwd)"

echo
echo "── 环境 ─────────────────────────────────────────────"

if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  if [ "$NODE_MAJOR" -ge 20 ] 2>/dev/null; then
    ok "node $(node -v)"
  else
    warn "node $(node -v) —— wrangler 需要 20 以上，先升级"
  fi
else
  bad "没有 node"
fi

if command -v npx >/dev/null 2>&1; then
  WRANGLER_VERSION="$(npx --no-install wrangler --version 2>/dev/null | tail -1)"
  if [ -n "$WRANGLER_VERSION" ]; then
    ok "wrangler $WRANGLER_VERSION"
  else
    warn "本地没装 wrangler，命令会走 npx 临时下载（可用，只是慢）"
  fi
else
  bad "没有 npx"
fi

# 登录状态。这一步失败必须停下来让用户自己跑 npx wrangler login，skill 代不了。
WHOAMI="$(npx --no-install wrangler whoami 2>&1)"
if printf '%s' "$WHOAMI" | grep -qiE 'You are logged in|associated with the email'; then
  ok "已登录 Cloudflare：$(printf '%s' "$WHOAMI" | grep -oiE '[a-z0-9._%+-]+@[a-z0-9.-]+' | head -1)"
else
  bad "未登录 Cloudflare —— 停下来让用户执行: npx wrangler login"
fi

echo
echo "── 项目 ─────────────────────────────────────────────"

NOBUILD=0
if [ ! -f package.json ]; then
  NOBUILD=1
  if ls ./*.html >/dev/null 2>&1; then
    ok "无构建项目（没有 package.json，有 HTML）—— 目录本身就是部署目录，_headers 直接放 index.html 旁边"
    [ -d node_modules ] && warn "目录里有 node_modules —— deploy . 会把它一起推上去（2 万文件上限），先清理"
  else
    bad "既没有 package.json 也没有 HTML 文件 —— 先确认这是不是前端项目目录"
  fi
fi

# 非 JS 后端 —— Workers 只跑 JS/TS/WASM，这是硬边界
if [ -f requirements.txt ] || [ -f app.py ] || [ -f main.py ] || [ -f manage.py ] || [ -f Pipfile ] || [ -f pyproject.toml ]; then
  if grep -qsiE 'flask|fastapi|django|streamlit|gradio|uvicorn' requirements.txt Pipfile pyproject.toml 2>/dev/null || [ -f manage.py ]; then
    bad "检测到 Python 后端 —— 推不上 Pages Functions。停下来向用户说明：前端照常上线+后端移植成 Functions，或后端另找托管（见 gotchas「后端语言」）"
  else
    warn "有 Python 文件 —— 确认它们不是后端（只是数据脚本就没事）"
  fi
fi

if [ -f package.json ]; then
  ok "package.json 存在"
  echo "    scripts:"
  node -e 'const s=require("./package.json").scripts||{};for(const k of Object.keys(s))console.log("      "+k+": "+s[k])' 2>/dev/null

  has_dep() {
    node -e 'const p=require("./package.json");const d={...p.dependencies,...p.devDependencies};process.exit(d[process.argv[1]]?0:1)' "$1" 2>/dev/null
  }

  FRAMEWORK=""
  for dep in next astro nuxt @sveltejs/kit vite react vue svelte; do
    if has_dep "$dep"; then
      FRAMEWORK="${FRAMEWORK} ${dep}"
    fi
  done
  [ -n "$FRAMEWORK" ] && echo "    检测到:$FRAMEWORK"

  if printf '%s' "$FRAMEWORK" | grep -q 'next'; then
    warn "Next.js 项目：SSR 走 Pages 需要 @cloudflare/next-on-pages，和本 skill 的 Functions 路径冲突。先问用户是否导出纯静态"
  fi

  for dep in react-router-dom vue-router @tanstack/react-router; do
    if has_dep "$dep"; then
      ok "有客户端路由 ${dep} —— 需要 _redirects 做 SPA fallback"
    fi
  done
fi

# 构建输出目录 / 静态资源目录
OUTDIR=""
if [ "$NOBUILD" = "1" ]; then
  OUTDIR="."
  [ -f _headers ] && ok "_headers 已存在" || warn "缺 _headers（无构建项目直接放 index.html 旁边）"
  [ -f _redirects ] && ok "_redirects 已存在"
else
  for d in dist build out .output/public .svelte-kit/cloudflare; do
    [ -d "$d" ] && OUTDIR="$d" && break
  done
  if [ -n "$OUTDIR" ]; then
    ok "构建输出目录（已存在）: $OUTDIR"
  else
    warn "还没构建过，输出目录待确认（Vite=dist，CRA=build，Astro=dist，Next static=out）"
  fi

  STATICDIR=""
  for d in public static; do
    [ -d "$d" ] && STATICDIR="$d" && break
  done
  if [ -n "$STATICDIR" ]; then
    ok "静态资源目录: $STATICDIR/ —— _headers 和 _redirects 放这里"
    [ -f "$STATICDIR/_headers" ] && ok "_headers 已存在" || warn "缺 _headers"
    [ -f "$STATICDIR/_redirects" ] && ok "_redirects 已存在"
  else
    warn "没有 public/ 或 static/ —— 需要新建，_headers 放项目根不生效"
  fi
fi

echo
echo "── Cloudflare 相关文件 ───────────────────────────────"

if [ -f wrangler.toml ] || [ -f wrangler.jsonc ] || [ -f wrangler.json ]; then
  ok "wrangler 配置已存在 → 二次运行，走增量路径，不要重新初始化"
  grep -nE '^(name|pages_build_output_dir|compatibility_date)' wrangler.toml 2>/dev/null | sed 's/^/    /'
  if grep -q 'preview_database_id' wrangler.toml 2>/dev/null; then
    PROD_ID="$(grep -E '^database_id' wrangler.toml | head -1 | cut -d'"' -f2)"
    PREV_ID="$(grep -E '^preview_database_id' wrangler.toml | head -1 | cut -d'"' -f2)"
    if [ -n "$PROD_ID" ] && [ "$PROD_ID" = "$PREV_ID" ]; then
      bad "database_id 和 preview_database_id 相同 —— 预览分支会写生产库"
    else
      ok "production / preview 用了不同的 database_id"
    fi
  fi
  if grep -qiE '^[[:space:]]*[A-Z_]*(KEY|SECRET|TOKEN|PASSWORD)[A-Z_]*[[:space:]]*=' wrangler.toml 2>/dev/null; then
    bad "wrangler.toml 里疑似有密钥 —— 这个文件进 git，改用 wrangler pages secret put"
  fi
else
  warn "没有 wrangler 配置 → 首次初始化"
fi

if [ -d functions ]; then
  ok "functions/ 存在"
  find functions -name '*.ts' -o -name '*.js' | sed 's/^/    /'
else
  warn "没有 functions/ —— L1 起需要，且必须在项目根"
fi

[ -d migrations ] && ok "migrations/ 存在: $(ls migrations | tr '\n' ' ')" || warn "没有 migrations/ —— L2 起需要"

if [ -d .git ]; then
  ok "是 git 仓库（GitHub 集成分支需要）"
  for p in dist build out node_modules .wrangler; do
    grep -q "^${p}/\?$" .gitignore 2>/dev/null || warn ".gitignore 里没有 $p"
  done
else
  warn "不是 git 仓库 —— GitHub 集成分支不可用，只能 CLI 直推"
fi

echo
echo "── CSP 风险扫描 ──────────────────────────────────────"
# CSP 默认 'self'，外部引用和内联脚本都会被拦
HTML_FILES="$(find . -maxdepth 2 -name '*.html' -not -path './node_modules/*' -not -path "./$OUTDIR/*" 2>/dev/null)"
if [ -n "$HTML_FILES" ]; then
  HITS="$(grep -hoE '(src|href)="https?://[^"]+"' $HTML_FILES 2>/dev/null | sort -u)"
  if [ -n "$HITS" ]; then
    bad "HTML 里有外部资源，CSP 会拦掉，上线前先本地化或放宽对应指令："
    printf '%s\n' "$HITS" | sed 's/^/    /'
  else
    ok "HTML 里没有外部资源引用"
  fi
  INLINE_JS="$(grep -hcE '<script(>| [^>]*>)' $HTML_FILES 2>/dev/null | paste -sd+ - | bc 2>/dev/null || echo 0)"
  INLINE_JS_SRC="$(grep -hcE '<script[^>]*src=' $HTML_FILES 2>/dev/null | paste -sd+ - | bc 2>/dev/null || echo 0)"
  if [ "${INLINE_JS:-0}" -gt "${INLINE_JS_SRC:-0}" ] 2>/dev/null; then
    bad "HTML 里有内联 <script>，会被 script-src 'self' 拦掉白屏 —— 抽成 .js 文件，或放宽 CSP 并告知用户"
  fi
  if grep -hqE '<style(>| [^>]*>)' $HTML_FILES 2>/dev/null; then
    warn "HTML 里有内联 <style> —— style-src 需要 'unsafe-inline'，或抽成 .css 文件"
  fi
fi

echo
echo "── 重资源检查（Pages 单文件上限 25 MiB）──────────────"
BIG="$(find . -type f -size +25M -not -path './node_modules/*' -not -path './.git/*' 2>/dev/null)"
if [ -n "$BIG" ]; then
  bad "有超过 25 MiB 的文件，部署会失败 —— 压缩/拆分，或放 R2："
  printf '%s\n' "$BIG" | while read -r f; do
    printf '    %8s  %s\n' "$(du -h "$f" | cut -f1)" "$f"
  done
else
  ok "没有超过 25 MiB 的文件"
fi
if find . -name '*.wasm' -not -path './node_modules/*' 2>/dev/null | grep -q .; then
  warn "有 WASM —— CSP 的 script-src 需要加 'wasm-unsafe-eval'；Unity/Godot 包另见 gotchas 的 3D 一节"
fi

echo
echo "提醒：Pages Functions 的请求计入 Workers 100,000 次/天；"
echo "      D1 免费 500 万行读、10 万行写/天，行读按扫描行数算。"
echo "      完整额度见 references/free-tier-limits.md"
echo
