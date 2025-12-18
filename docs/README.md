# ReactiveViews Documentation

**Audience:** Rails developers who want to use React components inside server-rendered Rails views.
**Topic:** How to install, configure, render, and deploy ReactiveViews.
**Goal:** Help you ship React “islands” and full-page `.tsx.erb` templates with SSR (server-side rendering) and client hydration.

## Where to start

- **New to ReactiveViews:** Read [`getting-started.md`](getting-started.md)
- **Rendering components from ERB:** Read [`islands.md`](islands.md)
- **Rendering full pages from `.tsx.erb`:** Read [`full-page-tsx-erb.md`](full-page-tsx-erb.md)

## Guides

- [`configuration.md`](configuration.md): all configuration options and defaults
- [`ssr.md`](ssr.md): SSR server runtime, auto-spawn behavior, and endpoints
- [`caching.md`](caching.md): cache stores, TTLs, and invalidation
- [`production-deployment.md`](production-deployment.md): deploy with a standard Rails workflow
- [`troubleshooting.md`](troubleshooting.md): common issues and how to debug quickly
- [`security.md`](security.md): boundaries, best practices, and insecure patterns to avoid
- [`api-reference.md`](api-reference.md): Ruby helpers, configuration API, and return values

## Project status

ReactiveViews is **beta**. Expect iteration (and occasional breaking changes) as defaults and APIs settle.
