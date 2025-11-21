---
sidebar_position: 4
title: SSR Architecture
---

# SSR Architecture

The Node SSR server (at `node/ssr/server.mjs`) is intentionally simple yet production-ready. Here's what matters:

## Entry points

| Endpoint        | Description                                  |
|-----------------|----------------------------------------------|
| `POST /render`  | Render a single component                    |
| `POST /batch-render` | Render N components in one HTTP call    |
| `POST /render-tree`  | Render nested React trees (children/props work exactly like client-side React) |
| `POST /infer-props`  | Parse TSX/JSX to detect prop names      |
| `GET /health`   | Basic health probe                           |

All endpoints accept JSON and now enforce payload limits + better error messages via a shared router module.

## Bundler cache (per component)

Every render used to invoke esbuild and throw away the result. The new bundler cache keeps hot components ready-to-render:

```text
Cache key: "#{componentPath}:#{mtimeMs}:#{NODE_ENV}"
Eviction : LRU (default 20 entries, configurable via RV_SSR_BUNDLE_CACHE)
Cleanup  : cached bundles deleted on eviction + on server shutdown
```

Each cache entry stores:

1. The compiled CommonJS file (under `tmp/reactive_views_ssr`)
2. The evaluated component function
3. `lastUsed` timestamp for LRU pruning

The first request compiles with esbuild; subsequent renders skip straight to `renderToString`.

### Configure the cache

```bash
RV_SSR_BUNDLE_CACHE=40   # keep up to 40 components hot
RV_SSR_PORT=5175         # HTTP port
RV_VITE_PORT=5174        # dev-only Vite proxy
NODE_ENV=production      # becomes part of the bundle cache key
```

## Router modules

To make the upcoming TypeScript rewrite easier, the server is already split into logical modules:

- `PropsInference` – wraps TypeScript AST parsing + memoization
- `Bundler` – esbuild wrapper, bundle cache, cleanup helpers
- `Router` – CORS handling, JSON parsing, payload guards, restful responses

Take a look at `Router.handle` to see how each endpoint consumes helpers like `readJsonBody` and `HttpError`.

## Deployment tips

- The server is just a Node script; run it with `node node/ssr/server.mjs`.
- Use the provided GitHub Actions workflow (see `/docs/website`) or your own CI step to run `npm install` before packaging.
- Remember to expose the SSR URL to Rails (`ReactiveViews.config.ssr_url` or `RV_SSR_URL` env var).
- For multi-tenant apps, run multiple instances behind a load balancer—the bundle cache lives in-process.

With the bundler cache + modular router in place, the final step is translating this file to TypeScript. The boundaries are already there.

