# Troubleshooting

**Audience:** Rails developers debugging SSR, hydration, and build issues.
**Topic:** Common failures and quick diagnostics.
**Goal:** Get back to a working SSR + hydration setup with minimal guesswork.

## SSR server won’t start

- **Verify Node is installed:** `node --version` (recommended Node 22+).
- **Check the SSR log:** `log/reactive_views_ssr.log` (auto-spawn) or your terminal output (manual run).
- **Confirm SSR script exists:** it should be `node/ssr/server.mjs` (inside the gem).

## Components render blank / show an error overlay

- **Rails logs:** SSR errors are logged with a `[ReactiveViews]` prefix.
- **Development overlay:** in development, ReactiveViews replaces the component with an error overlay containing details.
- **Production behavior:** in production, failed islands are hidden (`data-reactive-views-error="true"`). Check logs.

## Props aren’t reaching the component

- If you pass a JSON blob through a single attribute, ensure it’s valid JSON:

```erb
<MyComponent props="<%= my_hash.to_json %>" />
```

- If you rely on full-page props inference, disable it temporarily to validate:

```ruby
ReactiveViews.configure do |config|
  config.props_inference_enabled = false
end
```

## “Payload too large” (HTTP 413)

The SSR server enforces request size limits.

- Keep props small.
- Pass an identifier and fetch additional data after hydration.
- Split a huge page into multiple islands.

## Changes aren’t picked up

- **Ruby renderer caching:** disable `ssr_cache_ttl_seconds` or call:

```ruby
ReactiveViews::Renderer.clear_cache
```

- **Node bundler cache:** the SSR server caches compiled bundles (LRU). Restart SSR or set `RV_SSR_BUNDLE_CACHE=0` for debugging.

## Hydration mismatch errors

Common causes:

- `Date.now()` / `new Date()` called during render
- `Math.random()` during render
- conditional rendering differences between server and client

Fix by generating non-deterministic values on the server and passing them as props.

## Need help?

- Open an issue at the repository’s issue tracker.
- Include the SSR logs and the minimal component that reproduces the issue.
