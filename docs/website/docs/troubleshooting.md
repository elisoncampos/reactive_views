---
sidebar_position: 5
title: Troubleshooting
---

# Troubleshooting

Common issues and how to debug them quickly.

## SSR server won't start

- Ensure Node 18+ is installed (`node -v`).
- Check the console output—`PROJECT_ROOT` must point at your Rails app (where `package.json` lives).
- Ports already in use? Set `RV_SSR_PORT` / `RV_VITE_PORT` to unused ports.

## Components render blank / show error overlay

1. Open the Rails logs. Errors are prefixed with `[ReactiveViews]`.
2. In development the HTML will include an overlay explaining the stack trace.
3. In production you see an empty `<div data-reactive-views-error>`—check the SSR server logs for the real error.

## Props aren't reaching the component

- Run with `config.props_inference_enabled = false` to confirm inference isn't filtering them out.
- Remember to JSON encode props in ERB: `props="<%= my_hash.to_json %>"`.
- Give each component a unique prop structure; duplicate keys plus caching can make debugging hard.

## Changes aren't picked up

- For Ruby-side caching, either disable `ssr_cache_ttl_seconds` or call `ReactiveViews::Renderer.clear_cache`.
- For Node bundler caching, bump the file's `mtime` (save the file) or disable the cache temporarily via `RV_SSR_BUNDLE_CACHE=0`.

## "Payload too large" errors

Endpoints now guard against huge JSON bodies. Split large props into smaller islands or pass an identifier and fetch data after hydration.

## Need more help?

- Search or open a [GitHub issue](https://github.com/elisoncampos/reactive_views/issues).
- Chat with the team via Discussions for architecture questions.

You're never alone—React + Rails can be fun again!

