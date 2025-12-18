# Production Deployment

**Audience:** Rails developers deploying ReactiveViews with standard Rails infrastructure.
**Topic:** Building assets, running SSR in production, and safe network boundaries.
**Goal:** Deploy ReactiveViews without a separate frontend app, and understand what to monitor.

## Overview

A production ReactiveViews deployment includes:

- **Your Rails app** serving HTML
- **Vite-built assets** served from `public/vite/...`
- **A Node SSR server** that renders components and serves full-page hydration bundles

ReactiveViews is designed so SSR can run **inside the same container/VM** as Rails.

## Build assets

ReactiveViews hooks into `assets:precompile` and runs a Vite build automatically:

```bash
bin/rails assets:precompile
```

This should produce a Vite manifest at one of:

- `public/vite/.vite/manifest.json`
- `public/vite/manifest.json`

## Start the app

Start Rails normally:

```bash
bin/rails server -e production
```

When Rails renders a page containing a React island or a full-page TSX template, the gem will ensure an SSR server is running.

## SSR process strategy

You have two supported strategies:

### Strategy A: auto-spawn (default)

- Ruby spawns `node/ssr/server.mjs` on localhost when needed.
- SSR logs are written to `log/reactive_views_ssr.log`.

### Strategy B: external SSR (advanced)

If you want to run SSR as a separate service, set:

```bash
RV_SSR_URL=https://your-ssr.internal:5175
```

When `RV_SSR_URL` is set, ReactiveViews will not auto-spawn SSR.

## CDN / asset host

If you serve Vite assets from a CDN, set `ASSET_HOST`:

```bash
ASSET_HOST=https://cdn.example.com
```

ReactiveViews will prefix asset URLs accordingly.

## Health and monitoring

- **Rails health:** your normal Rails health checks
- **SSR health:** `GET /health` on the SSR server (when reachable internally)
- **Logs:** `log/reactive_views_ssr.log` (auto-spawn) and Rails logs (`[ReactiveViews]` prefix)

## Security checklist

- Keep the SSR server **private** (localhost or internal network).
- Do not pass **secrets** in props (they are embedded into HTML).
- Keep props small to reduce SSR latency and avoid payload limits.

See [`security.md`](security.md).
