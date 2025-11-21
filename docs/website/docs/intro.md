---
sidebar_position: 1
title: Welcome
---

# Meet ReactiveViews

ReactiveViews lets Rails teams drop React components straight into ERB templates—or even ship entire `.tsx.erb` pages—without maintaining a separate frontend project. You get:

- familiar Rails routing + layouts
- Vite dev server with hot reload
- a Node-based SSR server with tree + batch rendering
- automatic hydration islands with zero client boot ceremony
- TypeScript-powered props inference so you only send the data a component needs

If you're a junior developer, think of ReactiveViews as “React on training wheels for Rails”: the generator wires everything up, the defaults are safe, and you can opt into advanced features (tree rendering, caching stores, bundler cache) when you're ready.

## Batteries included

- **Component resolver** scans `app/views/components` or any configured path, memoizing hits by mtime to keep lookup costs tiny.
- **Renderer** talks to the SSR server through a persistent HTTP client, respects the shared cache store, and reports errors via Rails logs/overlays.
- **Full-page pipeline** renders `.tsx.erb`, stores temp files via `TempFileManager`, and reuses `PropsBuilder` so inference rules match partials.
- **SSR server** uses esbuild once per component/mtime/env, caches bundles (LRU), and exposes `/render`, `/batch-render`, `/render-tree`, `/infer-props`, `/health`.

## What you'll build

1. Run `rails g reactive_views:install` to drop in the JS + Vite wiring.
2. Create a component under `app/views/components`.
3. Render it in ERB like `<UserBadge props="<%= @user.as_json.to_json %>" />`.
4. The Node SSR server renders HTML and the browser hydrates it automatically.
5. When you're ready, convert a `.html.erb` page to `.tsx.erb` and let `FullPageRenderer` handle the rest.

## Docs map

| Section | Why read it |
|---------|-------------|
| **Quickstart** | 10-minute walkthrough from install → deployment |
| **Caching & Props Stores** | Configure Redis/Solid Cache + understand TTLs |
| **SSR Architecture** | Learn how the Node server is structured and how to tune it |
| **Troubleshooting** | Copy/paste fixes for the most common issues |

Grab a coffee and let's ship! ☕

