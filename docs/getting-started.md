# Getting Started

**Audience:** Rails developers adding React to a Rails app (monolith) without a separate frontend deployment.
**Topic:** Installing ReactiveViews and rendering your first React component.
**Goal:** Install the gem, run the generator, render an island from ERB, and understand the dev workflow.

## Overview

ReactiveViews lets you write React components and use them directly in Rails views:

- **Islands:** write `<MyComponent />` inside `.html.erb` and get SSR + hydration.
- **Full-page TSX/JSX:** write `index.tsx.erb` (or `.jsx.erb`) and let Rails render the entire page through SSR.

## Prerequisites

- **Ruby/Rails:** any version supported by your app.
- **Node.js:** recommended **Node 22+** (this repo’s CI runs on 22).
- **Vite:** installed and wired by the generator (via `vite_rails`).

## 1) Install the gem

```ruby
# Gemfile
gem "reactive_views"
```

```bash
bundle install
```

## 2) Run the installer

```bash
bundle exec rails g reactive_views:install
```

This generator wires the Rails + Vite integration and creates a boot file used to hydrate islands.

## 3) Add the script tag to your layout

In your main layout:

```erb
<!-- app/views/layouts/application.html.erb -->
<head>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>

  <%= reactive_views_script_tag %>
</head>
```

## 4) Create a component

**Introduction:** This example creates a minimal island component that accepts a string prop.

```tsx
// app/views/components/user_badge.tsx
type Props = { fullName: string };

export default function UserBadge({ fullName }: Props) {
  return <strong className="UserBadge">{fullName}</strong>;
}
```

## 5) Render it from ERB

```erb
<!-- app/views/users/show.html.erb -->
<section class="profile">
  <UserBadge props="<%= { fullName: @user.name }.to_json %>" />
</section>
```

**Explanation:**

1. Rails renders your ERB as usual.
2. ReactiveViews finds PascalCase tags (like `<UserBadge />`) in the HTML response.
3. The SSR server renders the component and returns HTML.
4. The client boot script hydrates the island using the embedded props.

## 6) Run the dev workflow

```bash
bin/dev
```

This typically runs:

- Rails server
- Vite dev server (HMR)
- Node SSR server

If you prefer to run the SSR server separately for debugging, see [`ssr.md`](ssr.md).

## Before you ship (production notes)

ReactiveViews can run in production without a separate frontend deployment, but there are a couple of “don’t learn this the hard way” details.

- **Props are public:** props are embedded into the HTML response (as JSON). Don’t put secrets in props.
- **Keep SSR private:** don’t expose the Node SSR server to the public internet. The production default uses a Rails proxy route so the SSR server can stay bound to localhost.
- **Watch SSR logs:** auto-spawn writes to `log/reactive_views_ssr.log`.

Read next:

- [`security.md`](security.md)
- [`production-deployment.md`](production-deployment.md)
- [`ssr.md`](ssr.md)

## Next steps

- If you’re primarily embedding islands in existing ERB pages: [`islands.md`](islands.md)
- If you want full-page rendering: [`full-page-tsx-erb.md`](full-page-tsx-erb.md)
- If you want to tune behavior: [`configuration.md`](configuration.md)
