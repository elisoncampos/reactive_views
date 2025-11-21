---
sidebar_position: 3
title: Caching & Props Stores
---

# Caching & Props Stores

ReactiveViews now ships with a pluggable cache layer shared by:

- `ReactiveViews::Renderer` (SSR fragment cache)
- `ReactiveViews::PropsInference` (AST results)

By default we use a thread-safe in-memory store. Swap in Redis, Solid Cache, or any `ActiveSupport::Cache::Store` to share entries across Puma workers or servers.

## Configuring the cache store

```ruby title="config/initializers/reactive_views.rb"
ReactiveViews.configure do |config|
  # The simple option (process-local memory)
  config.cache_store = :memory

  # Solid Cache (Rails 7.1+)
  # config.cache_store = :solid_cache_store

  # Redis with custom namespace + URL
  # config.cache_store = [
  #   :redis_cache_store,
  #   { url: ENV["REDIS_URL"], namespace: "rv:ssr" }
  # ]

  # Optional: change the namespace used for renderer/props keys
  config.cache_namespace = "reactive_views"

  # TTLs
  config.ssr_cache_ttl_seconds = 30      # rendered HTML
  config.props_inference_cache_ttl_seconds = 5.minutes
end
```

Under the hood we wrap the provided store with lightweight namespaces:

- `reactive_views:renderer:*`
- `reactive_views:props_inference:*`

So you can wipe just one portion (`ReactiveViews::Renderer.clear_cache`) without blowing away your entire cache.

Need the raw store? Use `ReactiveViews.config.cache_for(:renderer)` or `cache_for(:props_inference)`—each returns a namespaced store that still honors `read`, `write(ttl:)`, `clear`, etc.

## When does caching kick in?

| Feature                | Cache key                                               | TTL source                               |
|------------------------|----------------------------------------------------------|------------------------------------------|
| SSR fragments          | `component_name + props JSON`                           | `config.ssr_cache_ttl_seconds`           |
| Props inference (AST)  | SHA256 of TSX/JSX content                               | `config.props_inference_cache_ttl_seconds` |
| Temp file pool         | `TempFileManager` writes under `tmp/reactive_views_full_page`; `prune` removes stale files older than 30 min (configurable) | `TempFileManager.prune(max_age:)` |
| SSR bundler (Node)     | `componentPath + mtime + NODE_ENV` (see SSR section)    | LRU (default 20 entries)                 |

Tips:

- **Dev mode**: keep TTLs low or nil so changes show up instantly.
- **Jobs/workers**: point `cache_store` at Redis or Memcached to avoid duplicating work in background jobs that invoke ReactiveViews.
- **Multi-app deployments**: set `cache_namespace` to avoid key collisions if Redis is shared.

## Manual cache busting

```ruby
ReactiveViews::Renderer.clear_cache      # erase SSR fragment cache
ReactiveViews.config.cache_for(:renderer).clear
ReactiveViews.config.cache_for(:props_inference).clear
```

or just blow away keys in your external store using the namespace prefix.

## Temp file hygiene

`ReactiveViews::TempFileManager` now powers `FullPageRenderer`. It:

- writes TSX content using `TempFileManager.write(content, identifier:, extension:)`
- periodically purges old files when `write` is called (every 5 minutes by default)
- exposes `TempFileManager.prune(max_age_seconds: 600)` for cron jobs

If you want even stricter control, schedule a job:

```ruby
# config/schedule.rb (whenever) or a simple ActiveJob
ReactiveViews::TempFileManager.prune(max_age_seconds: 5.minutes)
```

That’s it—no custom middleware required. Pick the store that matches your infrastructure and keep your SSR server focused on fresh work.

