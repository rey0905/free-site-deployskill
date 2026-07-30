/**
 * Cloudflare Pages Functions —— /api/* 的全部入口
 *
 * 位置必须是项目根的 functions/api/[[path]].ts。
 * [[path]] 是多层通配，[path] 只匹配一层。
 *
 * 免费额度相关的硬约束（细节见 references/free-tier-limits.md）：
 *   - 请求数 100,000/天，和 Workers 共用配额。静态资源不计入，所以别让页面加载走这里。
 *   - CPU 10ms/次调用。超了是 Error 1102。
 *   - 出站 fetch 50 个/请求。别在循环里打外部 API。
 *   - D1 查询 50 条/次调用。N+1 查询用 env.DB.batch 合并。
 *   - D1 行读按扫描行数算。所有查询带 WHERE user_id = ? 且该列有索引，SELECT 明确列字段。
 */

type Env = {
  DB: D1Database;
  // AI?: AiBinding;
  // ENABLE_WORKERS_AI?: string;
};

// 手写最小 D1 类型。绑定变多时可以改成 npx wrangler types 生成。
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
  // 剥掉 /api 前缀，路由里只写业务路径。前端调 /api/xxx，这里匹配 /xxx。
  const path = url.pathname.replace(/^\/api\/?/, '/');
  const method = request.method.toUpperCase();

  try {
    if (method === 'GET' && path === '/health') {
      return json({ ok: true });
    }

    // ── 业务路由往下加 ────────────────────────────────────────────
    //
    // if (method === 'GET' && path === '/items') {
    //   const user = await requireUser(request, env);
    //   const { results } = await env.DB.prepare(
    //     'SELECT id, title, created_at FROM items WHERE user_id = ? ORDER BY created_at DESC'
    //   ).bind(user.id).all<ItemRow>();
    //   return json({ items: results.map(mapItemRow) });
    // }
    //
    // 带路径参数的写法：
    // const itemMatch = /^\/items\/([^/]+)$/.exec(path);
    // if (method === 'DELETE' && itemMatch) {
    //   const user = await requireUser(request, env);
    //   await env.DB.prepare('DELETE FROM items WHERE id = ? AND user_id = ?')
    //     .bind(decodeURIComponent(itemMatch[1]), user.id).run();
    //   return json({ ok: true });
    // }
    //
    // 认证路由见 references/auth-recipe.md，整段抄过来。

    throw new HttpError('接口不存在', 404);
  } catch (error) {
    if (error instanceof HttpError) {
      return json({ error: error.message }, error.status);
    }
    // 内部错误不把细节返回给前端。调试看 npx wrangler pages deployment tail。
    console.error(error);
    return json({ error: '服务器出错了，请稍后再试' }, 500);
  }
};

/**
 * 统一 JSON 响应。
 * _headers 里的 CSP 和 HSTS 不会落到 Functions 响应上，所以这里自己带一份安全头。
 * 默认 no-store：接口数据别被 CDN 或浏览器缓存。可缓存的接口显式传 cache-control 覆盖。
 */
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

/** 截断字符串。所有写库的用户输入都要过一遍，否则一条超长 body 就能吃掉存储额度。 */
function text(value: unknown, maxLength: number): string {
  return String(value ?? '').slice(0, maxLength);
}

function nullableText(value: unknown, maxLength: number): string | null {
  const result = text(value, maxLength).trim();
  return result ? result : null;
}

/**
 * 外部 API 代理的模板。前端直连会被 connect-src 'self' 拦，而且会暴露 key。
 * 一定要缓存：既省自己的子请求额度，也省上游的额度。
 */
// async function proxyUpstream(env: Env, key: string): Promise<unknown> {
//   const cacheKey = new Request(`https://internal.cache/upstream/${encodeURIComponent(key)}`);
//   const cache = await caches.open('upstream');
//   const hit = await cache.match(cacheKey);
//   if (hit) return await hit.json();
//
//   const response = await fetch(`https://example.com/api?q=${encodeURIComponent(key)}`);
//   if (!response.ok) throw new HttpError('上游数据暂时取不到', 502);
//   const data = await response.json();
//
//   await cache.put(cacheKey, new Response(JSON.stringify(data), {
//     headers: { 'content-type': 'application/json', 'cache-control': 'public, max-age=300' }
//   }));
//   return data;
// }

// 消掉未使用告警，用到就删掉这行。
void readJson; void nullableText;
