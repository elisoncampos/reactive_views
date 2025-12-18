# Full-page `.tsx.erb` / `.jsx.erb`

**Audience:** Rails developers who want React to render entire pages while keeping Rails routing, controllers, and layouts.
**Topic:** Full-page rendering using ERB → TSX/JSX → SSR, with optional prop inference.
**Goal:** Build a full-page `*.tsx.erb` view, pass props from your controller, and hydrate the page on the client.

## What “full-page” means

With full-page templates, Rails renders a `.tsx.erb` (or `.jsx.erb`) template when the corresponding `.html.erb` is missing.

ReactiveViews:

1. Evaluates ERB to produce TSX/JSX source
2. Writes a temporary component file
3. Builds a props hash from assigns + `reactive_view_props`
4. SSR-renders the page
5. Emits a hydration payload so the browser can hydrate the page

## Minimal full-page example

**Introduction:** This example renders an index page from `index.tsx.erb`, while the controller provides props via instance variables and `reactive_view_props`.

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

## Prop sources and inference

ReactiveViews builds the props hash from:

- **Rails assigns** (instance variables exposed to views)
- **Explicit props** set via `reactive_view_props` (deep-merged)

If prop inference is enabled (`props_inference_enabled = true`), ReactiveViews asks the SSR server to infer the destructured prop keys and filters the props hash to:

- inferred keys ∪ explicit keys

This is a performance feature (smaller payloads), not a security feature.

## Partials inside `.tsx.erb`

Full-page templates can render partials. During ERB evaluation, ReactiveViews temporarily sets the view format to include `:tsx` so lookups like:

```erb
<%= render "users/filters" %>
```

will resolve `_filters.tsx.erb` where applicable.

## Error handling

If SSR fails in development, ReactiveViews renders a fullscreen error overlay with:

- component name
- error message
- file/line when available

In production, island failures are hidden and full-page failures should be handled by your standard Rails error handling and logs.

## Security considerations (full-page)

- **Never render secrets into props.** Full-page props are still shipped to the browser.
- **Avoid server-only APIs in components.** Full-page templates execute in Node during SSR.

See [`security.md`](security.md) for details.
