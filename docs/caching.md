# Caching

**Audience:** Rails developers improving SSR throughput and stability for high-traffic pages.
**Topic:** Ruby-side caching (SSR HTML + props inference) and how to choose a cache store.
**Goal:** Enable caching safely, understand keying/TTL behavior, and know how to invalidate caches.

## Overview

ReactiveViews uses a shared cache store for two internal caches:

- **Renderer cache:** SSR HTML fragments for islands
- **Props inference cache:** inferred prop keys for full-page rendering

Both caches are namespaced under `config.cache_namespace`.

## Choose a cache store

By default, ReactiveViews uses an in-process memory cache:

```ruby
ReactiveViews.configure do |config|
  config.cache_store = :memory
end
```

For multi-process or multi-host deployments, prefer a shared store (Redis / Solid Cache):

```ruby
ReactiveViews.configure do |config|
  config.cache_store = [:redis_cache_store, { url: ENV.fetch("REDIS_URL"), namespace: "rv-cache" }]
end
```

## Enable SSR HTML caching

Set `ssr_cache_ttl_seconds` to cache SSR HTML:

```ruby
ReactiveViews.configure do |config|
  config.ssr_cache_ttl_seconds = 30
end
```

### Cache key behavior

The renderer cache key is effectively:

- `"#{component_name}:#{props.to_json}"`

That means:

- **Large props produce large keys** (avoid shipping big arrays/hashes as props when possible)
- **Prop ordering matters** if you build hashes inconsistently

## Props inference caching

Props inference is cached by a digest of the TSX/JSX source:

```ruby
ReactiveViews.configure do |config|
  config.props_inference_cache_ttl_seconds = 300
end
```

## Invalidation

To clear the Ruby-side renderer cache:

```ruby
ReactiveViews::Renderer.clear_cache
```

For the Node-side bundler cache (compiled bundles), restart the SSR process or call `POST /clear-cache` on the SSR server.

## Security considerations

Caching can amplify mistakes:

- If you accidentally include user-specific data in props, caching can leak data across requests.
- Keep cache TTLs conservative for personalized islands, or disable caching for those components.

See [`security.md`](security.md).
