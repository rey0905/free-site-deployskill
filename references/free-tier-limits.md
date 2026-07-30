# Cloudflare 免费额度

数字核准于 2026-07-30，来源是 developers.cloudflare.com 官方 limits / pricing 页。**额度会变，用之前重新查一遍下面列的链接。**

## Pages（静态托管）

来源：https://developers.cloudflare.com/pages/platform/limits/

| 项目 | 免费额度 |
|---|---|
| 静态资源请求数 | 不限 |
| 带宽 | 不限 |
| 构建次数 | 500 次/月 |
| 并发构建 | 1 个 |
| 构建超时 | 20 分钟 |
| 单次部署文件数 | 20,000 个 |
| 单文件大小 | 25 MiB |
| 项目数 | 100 个/账号 |
| 自定义域名 | 100 个/项目 |
| 预览部署 | 不限 |
| `_headers` 规则 | 100 条 |
| `_redirects` | 2,000 条静态 + 100 条动态 |

**最重要的一条**：静态资源请求不限量，也不计入 Workers 额度。所以前端保持纯静态、页面加载不经过 Functions，是整个架构免费的地基。

## Workers / Pages Functions（后端）

来源：https://developers.cloudflare.com/workers/platform/limits/

| 项目 | 免费额度 |
|---|---|
| 请求数 | 100,000 次/天 |
| CPU 时间 | 10 ms/次调用 |
| 内存 | 128 MB/isolate |
| 子请求（fetch 出站） | 50 个/请求 |
| 脚本大小 | 压缩后 3 MB |
| 环境变量 | 64 个，单个 5 KB |
| Worker 数量 | 100 个/账号 |
| Cron Triggers | 5 个（**Pages Functions 不支持 cron，只有独立 Worker 有**） |

Pages Functions 的请求**计入这 100,000 次/天**，没有独立配额。

超限表现：
- 请求数超了 → `Error 1027`。路由可配 fail open（绕过 Worker，请求当作没这个 Worker）或 fail closed（返回 1027 错误页）。
- CPU 超 10ms → `Error 1102 Worker exceeded resource limits`。单次请求挂掉，不影响其他请求。

## D1（数据库）

来源：https://developers.cloudflare.com/d1/platform/pricing/ 和 /d1/platform/limits/

| 项目 | 免费额度 |
|---|---|
| 行读 | 500 万行/天 |
| 行写 | 10 万行/天 |
| 总存储 | 5 GB/账号 |
| 单库大小 | 500 MB |
| 数据库数量 | 10 个/账号 |
| 单次 Worker 调用的查询数 | 50 条 |
| Time Travel 回滚窗口 | 7 天 |

超限表现：
- 日读写额度用完 → D1 API 直接返回错误，查不了也写不了，等第二天重置。
- 存储满 → 不能再插入、建表、建索引，必须先删数据。

**行读按扫描的行数算，不是按返回的行数算。** 一张 5,000 行的表跑 `SELECT * FROM t`，即使只用到 3 行，也记 5,000 行读。这是最容易无声烧掉免费额度的地方，比请求数危险得多。

一个项目建 production + preview 两个库，10 个的上限意味着最多 5 个项目。

## KV（键值存储）

来源：https://developers.cloudflare.com/kv/platform/limits/

| 项目 | 免费额度 |
|---|---|
| 读 | 100,000 次/天 |
| 写（不同 key） | 1,000 次/天 |
| 写（同一 key） | 1 次/秒 |
| 存储 | 1 GB |
| key 大小 | 512 字节 |
| value 大小 | 25 MiB |

写额度只有 1,000/天，很容易撞。**默认不引入 KV**，能放 D1 就放 D1。

## Workers AI

来源：https://developers.cloudflare.com/workers-ai/platform/pricing/

免费 10,000 Neurons/天。超了直接报错，免费计划**没有超额付费选项**，只能升级到 Workers Paid（超出部分 $0.011 / 1,000 Neurons）。

所以 AI 功能必须做成可降级：有 AI 走 AI，没有或超额就走规则化的兜底逻辑，不能让整个功能挂掉。

## 需要付费或要单独核实的

用之前查文档，别默认能免费：Queues、Hyperdrive、Durable Objects、Workers Paid（$5/月起）、Logpush、Email Routing 的部分能力。

## 省额度四条规则

写代码时的硬约束，不是上线后再优化的事。

**1. 前端保持纯静态。** 页面、JS、CSS、图片全部走 Pages 静态资源，不限量。只有 `/api/*` 计入 Workers 的 10 万次/天。一个日活 50 人、每人 40 次 API 调用的站是 2,000 请求/天，占 2%。

**2. 永远不做全表扫描。** 每张业务表的 `user_id` 建索引，所有查询带 `WHERE user_id = ?`，`SELECT` 明确列出字段。行读按扫描算，一次没有索引的查询能顶掉几千行额度。真正会先爆的是 D1 行读，不是请求数。

**3. 外部 API 一律服务端代理 + 缓存。** 结果落表或用 Cache API，给响应设 `cache-control: public, max-age=N`。别每个前端请求都真去打一次上游 —— 那既烧子请求（50 个/请求上限）也烧对方的额度。

**4. 不要轮询。** 前端别写 `setInterval` 打 `/api`。5 秒一次的心跳，一个用户挂着一天就是 17,000 次请求，六个人就撑爆 10 万。要实时感就用户手动刷新，或者拉长到分钟级并加缓存。
