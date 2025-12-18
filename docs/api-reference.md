# ReactiveViews API Reference

**Audience:** Developers integrating ReactiveViews into Rails apps.
**Topic:** Ruby APIs exposed by the gem (configuration, helpers, controller props).
**Goal:** Provide a copy/pasteable reference for the public surface area.

## Overview

ReactiveViews is mostly “convention over configuration”. The primary public APIs are:

- `ReactiveViews.configure` (configuration)
- `ReactiveViews.config` (read current configuration)
- `reactive_views_script_tag` (view helper)
- `reactive_view_props` (controller helper for full-page templates)
- `ReactiveViews::Renderer` (low-level rendering and cache control)

## Getting started / basic usage

**Introduction:** This example shows the minimal “public API” you’ll use in a typical Rails app.

```ruby
# config/initializers/reactive_views.rb
ReactiveViews.configure do |config|
  # Keep defaults for most apps.
  # You can tune SSR URL, caching, and timeouts here.
  config.enabled = true
end
```

```erb
<!-- app/views/layouts/application.html.erb -->
<head>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>

  <%= reactive_views_script_tag %>
</head>
```

**Explanation:**

1. `ReactiveViews.configure` sets global defaults.
2. `reactive_views_script_tag` injects the client runtime and an SSR URL hint.
3. Once a page contains a ReactiveViews island tag, the gem SSR-renders and hydrates it automatically.

## `ReactiveViews.configure`

Configure the gem globally.

```ruby
ReactiveViews.configure do |config|
  config.enabled = true
end
```

**Parameters:**

| Name     | Type                           | Required | Description               |
| -------- | ------------------------------ | -------: | ------------------------- |
| `config` | `ReactiveViews::Configuration` |      yes | The configuration object. |

**Returns:** The configured `ReactiveViews::Configuration` instance.

See [`configuration.md`](configuration.md) for all options.

## `ReactiveViews.config`

**Purpose:** Read the current configuration instance.

**Returns:** `ReactiveViews::Configuration`.

**Example:**

```ruby
ReactiveViews.config.ssr_timeout # => 5
```

## View helpers (`ReactiveViewsHelper`)

### `reactive_views_script_tag`

**Purpose:** Insert all required tags for ReactiveViews to function (SSR URL meta + Vite entrypoints).

**Usage:**

```erb
<%= reactive_views_script_tag %>
```

**Returns:** An HTML-safe string containing `<meta>` and `<script>`/`<link>` tags.

**Notes:**

- In **development/test**, the `<meta name="reactive-views-ssr-url">` points at the configured SSR URL (default `http://localhost:5175`).
- In **production**, the meta tag points at the **Rails engine proxy** (`/reactive_views`) so the Node SSR server can stay bound to localhost.

### `reactive_views_asset_host`

**Purpose:** Resolve the asset host used for production asset URLs.

Resolution order:

1. `ReactiveViews.config.asset_host`
2. `ENV["ASSET_HOST"]`
3. `Rails.application.config.asset_host`

**Returns:** A string URL or `nil`.

### `reactive_views_boot` (deprecated)

**Purpose:** Legacy helper. Prefer `reactive_views_script_tag`.

## Controller props (`ReactiveViews::ControllerProps`)

### `reactive_view_props(hash = nil)`

**Purpose:** Add explicit props for full-page templates, merged into assigns.

**Behavior:**

- Can be called multiple times.
- Deep-merges hashes.
- Symbolizes keys (`deep_symbolize_keys`).

**Parameters:**

| Name   | Type   | Required | Description                                |
| ------ | ------ | -------: | ------------------------------------------ |
| `hash` | `Hash` |       no | Props to deep-merge into the existing set. |

**Returns:** The current merged props hash.

**Example:**

```ruby
class UsersController < ApplicationController
  before_action -> { reactive_view_props(current_user: current_user) }

  def index
    @users = User.all
    reactive_view_props(page: { title: "Users" })
  end
end
```

### `reactive_props`

Alias for `reactive_view_props`.

## `ReactiveViews::Renderer`

### `render(component_name, props = {})`

**Purpose:** SSR render a component by name.

**Parameters:**

| Name             | Type     | Required | Description                          |
| ---------------- | -------- | -------: | ------------------------------------ |
| `component_name` | `String` |      yes | Component name (e.g. `"UserBadge"`). |
| `props`          | `Hash`   |       no | Props passed to the React component. |

**Returns:** SSR HTML as a string. If `ReactiveViews.config.enabled` is false, returns `""`.

**Errors:** This method does **not raise** on SSR failures. It logs an error (when Rails logger is available) and returns an **error marker string**:

- Prefix: `___REACTIVE_VIEWS_ERROR___`
- Suffix: `___`

**Example (detecting SSR errors):**

```ruby
html = ReactiveViews::Renderer.render("UserBadge", fullName: "Ada")

if html.start_with?("___REACTIVE_VIEWS_ERROR___")
  Rails.logger.warn("SSR failed: #{html}")
end
```

### `render_path(component_path, props = {})`

**Purpose:** SSR render a component by file path (used by full-page pipeline).

### `render_path_with_metadata(component_path, props = {})`

**Purpose:** Render and also return a bundle key for hydration.

**Returns:** `{ html:, bundle_key: }`.

### `batch_render(component_specs)`

**Purpose:** Render many components in one SSR request.

**Input shape:**

```ruby
[
  { component_name: "Counter", props: { initialCount: 0 } },
  { component_name: "UserBadge", props: { fullName: "Ada" } }
]
```

**Returns:** Array of `{ html: }` / `{ error: }` results (one entry per input spec). If batch rendering is disabled or fails, ReactiveViews falls back to individual renders.

### `tree_render(tree_spec)`

**Purpose:** Render nested components as a true React tree.

**Returns:** `{ html: "..." }` on success, or `{ error: "..." }` on failure.

### `clear_cache`

**Purpose:** Clears the Ruby-side renderer cache (SSR HTML fragments for islands).

## Security considerations

- **Props are public.** Anything you pass to a component can be viewed in the browser (it is embedded into HTML).
- **SSR is code execution.** The SSR server executes your React component code. Treat it as part of your trusted backend runtime.
- **Keep SSR private.** Do not expose the SSR server to the public internet. Prefer the production default (localhost + Rails proxy).

See [`security.md`](security.md) for the full guide.

## Error handling

ReactiveViews intentionally tries to avoid breaking your entire Rails response for island rendering failures:

- **Islands:** errors are logged and an error marker is returned so the transformer can swap markup safely.
- **Full-page templates:** SSR errors should be handled via your normal Rails error handling and by inspecting SSR logs.
