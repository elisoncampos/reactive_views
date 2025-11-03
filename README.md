# ReactiveViews

Reactive, incremental React for Rails — SSR + hydration islands with optional SPA-like navigation.

- Write React components as islands directly in `.html.erb` using `<PostList />` or `data-react-component="PostList"`.
- Server-render via a Node SSR server, hydrate on the client automatically.
- Optional Vite integration via `vite_rails` for client bundles.

## Disclaimer

This is a work in progress. It is not ready for production use.

## Installation

### Quick Start

1. **Add the gem to your Gemfile:**

```ruby
gem "reactive_views"
```

2. **Install dependencies:**

```bash
bundle install
```

3. **Run the install generator:**

```bash
bundle exec rails generate reactive_views:install
```

The generator will:

- Set up Vite with React plugin (using `vite_rails` dependency)
- Install React dependencies via npm
- Copy the ReactiveViews boot script to `app/javascript/reactive_views/boot.ts`
- Update your Vite entrypoint (`app/javascript/entrypoints/application.js`) to import the boot script
- Create the ReactiveViews initializer
- Add `reactive_views_script_tag` to your application layout (or update existing layout)
- Create `Procfile.dev` for running all services together

4. **Add the script tag to your layout** (if not already added):

The generator automatically adds this to your `app/views/layouts/application.html.erb`, but if you're setting up manually or have a custom layout, add this single line to your `<head>` section:

```erb
<%= reactive_views_script_tag %>
```

That's all you need! This single helper automatically includes:

- Vite client for hot module replacement (HMR) in development
- Your Vite JavaScript entrypoint (which includes the ReactiveViews boot script)

**DX First**: You don't need to worry about `vite_client_tag`, `vite_javascript_tag`, or any other Vite-specific helpers. ReactiveViews abstracts all of that away for you. The boot script is bundled with React via Vite, providing seamless integration with HMR support.

5. **Start the development environment**:

The generator creates `bin/dev` that automatically:

- Cleans up stale processes and PID files
- Starts all services (Rails, Vite, SSR) together using Procfile.dev

```bash
bin/dev
```

The script handles port conflicts automatically, so you can just run `bin/dev` and it works.

Or start services individually:

```bash
# Start SSR server
bundle exec rake reactive_views:ssr

# Start Rails server (separate terminal)
bin/rails server

# Start Vite (separate terminal)
bin/vite dev
```

That's it! You're ready to use React components in your ERB views.

### Generator Options

- `--skip-vite` Skip Vite installation
- `--skip-react` Skip React setup
- `--skip-procfile` Do not create/append `Procfile.dev`
- `--with-example` Generate example component and ERB usage hint

**Note:** The boot script is automatically copied and imported during installation. No manual build step is required.

### Advanced Setup

If you need manual control or want to understand what's happening under the hood:

**Vite Configuration**

The generator sets up `vite.config.ts` with React plugin. If you need to customize it:

```ts
import { defineConfig } from "vite";
import RubyPlugin from "vite-plugin-ruby";
import react from "@vitejs/plugin-react";

export default defineConfig({
  server: {
    port: parseInt(process.env.RV_VITE_PORT || "5174"),
  },
  plugins: [RubyPlugin(), react()],
});
```

**Boot Script**

The generator copies the ReactiveViews boot script source (`boot.ts`) to `app/javascript/reactive_views/` and automatically imports it in your Vite entrypoint. Vite bundles it with React, providing seamless HMR support during development. The boot script handles hydrating React islands on the client side.

**Application Layout**

The generator automatically updates `app/views/layouts/application.html.erb` to include the ReactiveViews script tag:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title>Your App</title>
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= stylesheet_link_tag "application" %>
    <%= javascript_importmap_tags %>
    <%= reactive_views_script_tag %>
  </head>
  <body>
    <%= yield %>
  </body>
</html>
```

**Configuration**

The generator creates `config/initializers/reactive_views.rb` with defaults:

```ruby
ReactiveViews.configure do |c|
  c.enabled = true
  c.ssr_url = ENV.fetch("RV_SSR_URL", "http://localhost:5175")
  c.component_views_paths = ["app/views/components"]
  c.component_js_paths = ["app/javascript/components"]
  # c.ssr_cache_ttl_seconds = 2
end
```

## Usage

### Basic Example

In a normal `.html.erb` view, drop a React island:

```erb
<div class="page-wrap">
  <h1>Posts</h1>
  <PostList props='<%= @posts.as_json(only: [:id, :title]).to_json %>' />
</div>
```

Create your component at `app/views/components/post_list.tsx` (snake_case, following Rails conventions):

```tsx
export default function PostList({
  posts,
}: {
  posts: { id: number; title: string }[];
}) {
  return (
    <ul>
      {posts.map((p) => (
        <li key={p.id}>{p.title}</li>
      ))}
    </ul>
  );
}
```

On render, the gem will SSR this component and hydrate it client-side automatically.

### Component Naming Conventions

ReactiveViews supports multiple file naming conventions to accommodate both Rails and React/JavaScript standards. When you reference a component (e.g., `<PostList />`), the resolver automatically searches for files using all supported conventions:

#### Supported Naming Patterns

1. **PascalCase** (React/TypeScript standard)

   - `PostList.tsx`
   - `UserProfileCard.tsx`

2. **snake_case** (Rails standard)

   - `post_list.tsx`
   - `user_profile_card.tsx`

3. **camelCase** (JavaScript standard)

   - `postList.tsx`
   - `userProfileCard.tsx`

4. **kebab-case** (Web component standard)
   - `post-list.tsx`
   - `user-profile-card.tsx`

All naming conventions work recursively in nested directories:

- `components/PostList.tsx`
- `components/auth/login_form.tsx`
- `components/users/profile/user-avatar.tsx`

#### Search Priority

When resolving a component like `<PostList />`, the resolver searches in this order:

1. Exact match: `PostList.tsx` (original PascalCase)
2. Rails style: `post_list.tsx` (snake_case)
3. JS style: `postList.tsx` (camelCase)
4. Web style: `post-list.tsx` (kebab-case)

Each naming variant is tried with all supported extensions (`.tsx`, `.jsx`, `.ts`, `.js`) across all configured paths (`component_views_paths` and `component_js_paths`).

#### Best Practices

**Recommended:** Use **snake_case** for Rails projects:

```
app/views/components/
  ├── post_list.tsx
  ├── user_profile_card.tsx
  └── auth/
      └── login_form.tsx
```

This follows Rails conventions and integrates naturally with your Ruby codebase. However, you're free to use any supported convention based on your team's preferences.

#### Examples

All of these will be found when using `<HelloWorld />`:

```
app/views/components/HelloWorld.tsx      # PascalCase
app/views/components/hello_world.tsx     # snake_case (recommended for Rails)
app/views/components/helloWorld.tsx      # camelCase
app/views/components/hello-world.tsx     # kebab-case

# Nested directories work too:
app/views/components/auth/login_form.tsx
app/javascript/components/users/UserAvatar.tsx
```

**Note:** If multiple files with different naming conventions exist for the same component, the exact match (PascalCase) takes priority, followed by the search order listed above.

## Development

### Setup

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

### Running the SSR Server

Run the SSR server for development:

```bash
node node/ssr/server.mjs
```

SSR server environment:

```bash
# Port configuration
RV_SSR_PORT=5175        # SSR server HTTP port (default: 5175)
RV_VITE_PORT=5174       # Vite dev server port (default: 5174)
RAILS_PORT=3000         # Rails server port (default: 3000)

# SSR cache configuration
RV_SSR_TTL=2000         # cache TTL (ms) per component+props
```

You can set these in a `.env` file or export them before running `bin/dev`:

```bash
export RV_VITE_PORT=5180
export RV_SSR_PORT=5190
bin/dev
```

Install SSR dependencies in the gem (or host app): `npm i react react-dom`.

## Contributing

Bug reports and pull requests are welcome on GitHub.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
