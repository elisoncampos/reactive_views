---
sidebar_position: 2
title: Quickstart
---

# Quickstart (10‑minute tour)

> **Goal:** render your first React component from a Rails view, then graduate to full-page `.tsx.erb`.

## 1. Install the gem

```ruby title="Gemfile"
gem "reactive_views"
```

```bash
bundle install
```

## 2. Run the installer

```bash
bundle exec rails g reactive_views:install
```

What you get:

- Vite config + dev server wiring
- `app/frontend/reactive_views/boot.ts` hydrated on every page
- sample component + SSR Node server script
- `config/initializers/reactive_views.rb` with sensible defaults

## 3. Create a component

```tsx title="app/views/components/user_badge.tsx"
type Props = { fullName: string; avatarUrl?: string };

export default function UserBadge({ fullName, avatarUrl }: Props) {
  return (
    <div className="UserBadge">
      <img src={avatarUrl ?? "/avatar.svg"} alt="" />
      <strong>{fullName}</strong>
    </div>
  );
}
```

## 4. Render it from ERB

```erb title="app/views/users/show.html.erb"
<section class="profile">
  <UserBadge props="<%= { fullName: @user.name, avatarUrl: @user.avatar_url }.to_json %>" />
</section>
```

When the view renders:

1. Rails finds `UserBadge` via the resolver (PascalCase, snake_case, or kebab-case all work).
2. The Node SSR server bundles only that component, pulls props, and returns HTML.
3. The browser boot file hydrates it so interactivity works instantly.

## 5. Full‑page `.tsx.erb`

Convert `app/views/users/index.html.erb` → `app/views/users/index.tsx.erb`:

```tsx title="app/views/users/index.tsx.erb"
interface Props {
  users: Array<{ id: number; name: string }>;
  currentUser: { name: string };
}

export default function UsersPage({ users, currentUser }: Props) {
  return (
    <main>
      <h1>Hello {currentUser.name}</h1>
      <ul>
        {users.map((user) => (
          <li key={user.id}>{user.name}</li>
        ))}
      </ul>
    </main>
  );
}
```

In the controller:

```ruby
def index
  @users = User.all
  reactive_view_props(current_user: current_user)
end
```

`FullPageRenderer` renders the ERB portion to TSX, writes it via `TempFileManager`, infers props, and calls the renderer just like your islands.

## 6. Dev workflow

```bash
bin/dev
```

This runs:

- Rails server
- Vite dev server (HMR for `.tsx`)
- SSR Node server (port `5175` by default)

Make changes to a component—your browser reloads automatically.

## 7. Production checklist

- Set `RV_SSR_URL` to the SSR server URL (e.g., `http://127.0.0.1:5175` via env var).
- Choose a cache store (memory, Redis, Solid Cache) for the Ruby helpers (see [Caching](./caching.md)).
- Deploy the Node SSR server alongside your Rails app (Procfile entry, systemd unit, Kubernetes sidecar, etc.).
- For CI/CD, add a step to run `node node/ssr/server.mjs` (or wrap it via `foreman`) and ensure the `tmp/reactive_views_ssr` directory is writable.

That’s it! Dive into the next sections for caching, SSR architecture, and troubleshooting tips.

