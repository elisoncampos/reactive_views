# SSR (Server-Side Rendering)

**Audience:** Rails developers operating ReactiveViews in development and production.
**Topic:** How the Node SSR server is started, how Ruby talks to it, and what endpoints exist.
**Goal:** Understand SSR connectivity, auto-spawn behavior, environment variables, and operational debugging.

## Overview

ReactiveViews uses a Node server (`node/ssr/server.mjs`) to:

- SSR render components (`/render`, `/batch-render`, `/render-tree`)
- Infer prop keys from TSX/JSX (`/infer-props`)
- Serve full-page hydration bundles (`/full-page-bundles/:bundleKey.js`)

Ruby calls the SSR server over HTTP.

## Auto-spawn behavior (production default)

Ruby will **auto-start** the SSR server as a child process when it needs to render, unless you explicitly configure an SSR URL via environment variables:

- If `RV_SSR_URL` (or `REACTIVE_VIEWS_SSR_URL`) is set: **no auto-spawn** (you manage SSR externally).
- Otherwise: ReactiveViews starts Node on `127.0.0.1` and chooses a port (or uses `RV_SSR_PORT`).

Logs for the auto-spawned SSR process are written to:

- `log/reactive_views_ssr.log`

## Development: running SSR manually

You can run the SSR server yourself:

```bash
bundle exec rake reactive_views:ssr
```

This can help when debugging SSR logs independently of `bin/dev`.

## Engine route: full-page bundle proxy

In production, the client is expected to fetch full-page hydration bundles via the Rails engine mount:

- `GET /reactive_views/full-page-bundles/:bundle_key.js`

The engine proxies that request to the local SSR server, so you can keep SSR bound to localhost.

## Environment variables

| Variable                 | Used by     | Meaning                                                                     |
| ------------------------ | ----------- | --------------------------------------------------------------------------- |
| `RV_SSR_URL`             | Ruby        | SSR base URL. If set, disables auto-spawn.                                  |
| `REACTIVE_VIEWS_SSR_URL` | Ruby        | Backward-compatible SSR base URL.                                           |
| `RV_SSR_PORT`            | Ruby + Node | Port to bind the SSR server when auto-spawned (Ruby) / when started (Node). |
| `RV_SSR_TIMEOUT`         | Ruby        | Timeout (seconds) for SSR and inference HTTP requests.                      |
| `RV_VITE_PORT`           | Node        | Vite port used by the SSR runtime (dev tooling).                            |
| `PROJECT_ROOT`           | Node        | Path to the Rails app (where `package.json` lives).                         |
| `RV_SSR_BUNDLE_CACHE`    | Node        | Max number of bundled components to keep (LRU). Default `20`.               |

## SSR endpoints (reference)

- `GET /health` → `{ status: "ok", version: "1.0.0" }`
- `POST /render` → `{ html }` (optionally returns `{ html, bundleKey }` when metadata header is set)
- `POST /batch-render` → `{ results: [{ html } | { error }] }`
- `POST /render-tree` → `{ html }` or `{ error }`
- `POST /infer-props` → `{ keys: string[] }`
- `GET /full-page-bundles/:bundleKey(.js)` → JavaScript bundle
- `POST /clear-cache` → clears SSR bundler/inference caches

## Operational notes

- **Payload size limits:** SSR endpoints reject very large JSON bodies (HTTP 413). Keep props small and pass IDs when possible.
- **CORS:** SSR responses include permissive CORS headers. In production, do not expose the SSR server directly to the public internet.
