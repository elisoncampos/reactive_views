# Configuration

**Audience:** Rails developers configuring ReactiveViews for different environments.
**Topic:** All supported configuration options, defaults, and common setups.
**Goal:** Configure SSR connectivity, caching, rendering strategies, and asset hosting safely.

## Overview

ReactiveViews is configured via `ReactiveViews.configure` (typically in `config/initializers/reactive_views.rb`).

```ruby
ReactiveViews.configure do |config|
  # config.enabled = true
end
```

## Configuration reference

> Defaults below are taken from `ReactiveViews::Configuration`.

| Option                              |            Type |                                                                             Default | What it controls                                                                                                       |
| ----------------------------------- | --------------: | ----------------------------------------------------------------------------------: | ---------------------------------------------------------------------------------------------------------------------- |
| `enabled`                           |       `Boolean` |                                                                              `true` | Enables/disables all ReactiveViews behavior (tag transform, SSR calls).                                                |
| `ssr_url`                           |        `String` | `ENV["RV_SSR_URL"]` or `ENV["REACTIVE_VIEWS_SSR_URL"]` or `"http://localhost:5175"` | Base URL used by Ruby to call the SSR server. If `RV_SSR_URL`/`REACTIVE_VIEWS_SSR_URL` is set, auto-spawn is disabled. |
| `component_views_paths`             | `Array<String>` |                                                          `["app/views/components"]` | Where to look for components referenced from ERB tags.                                                                 |
| `component_js_paths`                | `Array<String>` |                                                     `["app/javascript/components"]` | Additional component lookup paths (JS/TS).                                                                             |
| `ssr_cache_ttl_seconds`             | `Integer`/`nil` |                                                                               `nil` | Enables SSR HTML caching for islands when set.                                                                         |
| `boot_module_path`                  |  `String`/`nil` |                                                                               `nil` | Legacy/override path for the boot module (most apps should use `reactive_views_script_tag`).                           |
| `ssr_timeout`                       |       `Integer` |               `ENV["RV_SSR_TIMEOUT"]` or `ENV["REACTIVE_VIEWS_SSR_TIMEOUT"]` or `5` | Timeout (seconds) for SSR and props inference requests.                                                                |
| `batch_rendering_enabled`           |       `Boolean` |                                                                              `true` | Enables `/batch-render` usage for flat pages.                                                                          |
| `batch_timeout`                     |       `Integer` |                                                                                `10` | Read timeout (seconds) for batch/tree SSR requests.                                                                    |
| `tree_rendering_enabled`            |       `Boolean` |                                                                              `true` | Enables tree rendering for nested components.                                                                          |
| `max_nesting_depth_warning`         |       `Integer` |                                                                                 `3` | Warns in logs when nesting depth exceeds this value.                                                                   |
| `props_inference_enabled`           |       `Boolean` |                                                                              `true` | Enables TypeScript-based prop key inference (used for full-page props filtering).                                      |
| `props_inference_cache_ttl_seconds` |       `Integer` |                                                                               `300` | Cache TTL for inferred prop keys (Ruby-side).                                                                          |
| `full_page_enabled`                 |       `Boolean` |                                                                              `true` | Enables full-page `.tsx/.jsx` template handler pipeline.                                                               |
| `cache_namespace`                   |        `String` |                                                                  `"reactive_views"` | Prefix used for namespacing keys in the configured cache store.                                                        |
| `cache_store`                       |      store spec |                                                                           `:memory` | Cache store adapter used for renderer and props inference caches.                                                      |
| `asset_host`                        |  `String`/`nil` |                                                                 `ENV["ASSET_HOST"]` | CDN host for Vite assets when generating production tags.                                                              |

### `cache_store`

Set `config.cache_store` to either:

- `:memory` (default)
- An `ActiveSupport::Cache` store spec, e.g. `[:redis_cache_store, {...}]`

See [`caching.md`](caching.md).

## Common configurations

### Production with Redis caching

```ruby
# config/initializers/reactive_views.rb
ReactiveViews.configure do |config|
  config.cache_store = [:redis_cache_store, { url: ENV.fetch("REDIS_URL"), namespace: "rv-cache" }]
  config.cache_namespace = "reactive_views"

  config.ssr_cache_ttl_seconds = 60
  config.props_inference_cache_ttl_seconds = 300

  config.asset_host = ENV["ASSET_HOST"]
end
```

### Disable prop inference (debugging)

```ruby
ReactiveViews.configure do |config|
  config.props_inference_enabled = false
end
```

### Disable tree rendering

```ruby
ReactiveViews.configure do |config|
  config.tree_rendering_enabled = false
end
```
