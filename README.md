# ReactiveViews

[![CI](https://github.com/elisoncampos/reactive_views/actions/workflows/ci.yml/badge.svg)](https://github.com/elisoncampos/reactive_views/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/reactive_views)](https://rubygems.org/gems/reactive_views)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

ReactiveViews lets you write React components and use them directly inside Rails views — with **server-side rendering (SSR)**, **client hydration**, and an optional **full-page `.tsx.erb` / `.jsx.erb`** pipeline. No separate frontend app required.

## Disclaimer

**⚠️ ReactiveViews is in beta.** Expect some breaking changes as the API and defaults settle. If you run it in production, treat the Node SSR runtime as part of your app (monitor it, capture logs, and load test SSR-heavy pages).

## What you get

- **React islands in ERB**: write `<UserBadge />` in `.html.erb` and get SSR + hydration.
- **Full-page React templates**: render entire Rails pages from `.tsx.erb` / `.jsx.erb` while keeping Rails controllers, routes, and layouts.
- **Fast SSR**: batch rendering for flat pages, tree rendering for nested component composition.
- **Less prop plumbing**: optional TypeScript-based prop key inference for full-page pages (reduces payload size).
- **Caching knobs**: SSR HTML caching + inference caching with pluggable cache stores.
- **Vite-native**: dev HMR + production builds via `vite_rails`.

## A quick taste

### Islands inside ERB

```tsx
// app/views/components/user_badge.tsx
type Props = { fullName: string };

export default function UserBadge({ fullName }: Props) {
  return <strong className="UserBadge">{fullName}</strong>;
}
```

```erb
<!-- app/views/users/show.html.erb -->
<UserBadge fullName="<%= @user.name %>" />
```

### Full-page `.tsx.erb`

```ruby
# app/controllers/users_controller.rb
class UsersController < ApplicationController
  def index
    @users = User.select(:id, :name).order(:name)
    reactive_view_props(current_user: current_user)
  end
end
```

```tsx
// app/views/users/index.tsx.erb
interface Props {
  users: Array<{ id: number; name: string }>;
  current_user: { name: string } | null;
}

export default function UsersIndex({ users, current_user }: Props) {
  return (
    <main>
      <h1>Users</h1>
      {current_user ? (
        <p>Signed in as {current_user.name}</p>
      ) : (
        <p>Not signed in</p>
      )}
      <ul>
        {users.map((u) => (
          <li key={u.id}>{u.name}</li>
        ))}
      </ul>
    </main>
  );
}
```

## Install (5 minutes)

1. Add the gem + install:

```ruby
gem "reactive_views"
```

```bash
bundle install
```

2. Run the installer:

```bash
bundle exec rails generate reactive_views:install
```

3. Start dev:

```bash
bin/dev
```

That runs Rails + Vite + the SSR server together.

For the layout helper and a full walkthrough, see [`docs/getting-started.md`](docs/getting-started.md).

## Documentation

Start at [`docs/README.md`](docs/README.md). Handy links:

- **Quick start:** [`docs/getting-started.md`](docs/getting-started.md)
- **Islands in ERB:** [`docs/islands.md`](docs/islands.md)
- **Full-page `.tsx.erb` / `.jsx.erb`:** [`docs/full-page-tsx-erb.md`](docs/full-page-tsx-erb.md)
- **Configuration:** [`docs/configuration.md`](docs/configuration.md)
- **SSR runtime & process management:** [`docs/ssr.md`](docs/ssr.md)
- **Caching:** [`docs/caching.md`](docs/caching.md)
- **Production deployment:** [`docs/production-deployment.md`](docs/production-deployment.md)
- **Troubleshooting:** [`docs/troubleshooting.md`](docs/troubleshooting.md)
- **Security considerations:** [`docs/security.md`](docs/security.md)
- **API reference:** [`docs/api-reference.md`](docs/api-reference.md)

## Before you ship

- Read [`docs/security.md`](docs/security.md) (props are public; SSR should stay private).
- Read [`docs/production-deployment.md`](docs/production-deployment.md) (assets, SSR process strategy, what to monitor).

## Contributing

At this time, we are only accepting bug reports. If you encounter any issues or have suggestions, please open an issue on our [GitHub repository](https://github.com/elisoncampos/reactive_views/issues).

We appreciate your feedback and contributions to help improve ReactiveViews!

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
