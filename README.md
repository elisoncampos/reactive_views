# ReactiveViews

[![CI](https://github.com/elisoncampos/reactive_views/actions/workflows/ci.yml/badge.svg)](https://github.com/elisoncampos/reactive_views/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/reactive_views)](https://rubygems.org/gems/reactive_views)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

ReactiveViews brings React components to Rails with server-side rendering (SSR) and client-side hydration islands. Write React components directly in your ERB templates or build full pages with `.tsx.erb` templates, all with seamless Rails integration.

## Disclaimer

**⚠️ This gem is currently in development and is not ready for production use.** We're actively working on stability, performance, and feature completeness. Use at your own risk.

## Motivation

Integrating React into Rails applications has traditionally involved several approaches, each with its own trade-offs:

### Current Solutions

**react-rails**: Provides basic SSR and component mounting, but offers limited flexibility and lacks advanced performance optimizations. Setup is straightforward but features are minimal.

**react_on_rails**: Comprehensive integration with SSR and client-side hydration, but requires complex setup and can introduce performance overhead. Managing JavaScript dependencies separately adds complexity.

**Webpacker / Shakapacker**: Modern JavaScript toolchain within Rails, but requires manual dependency management and adds significant configuration overhead. The learning curve can be steep for teams not familiar with Webpack.

**Separate Frontend/Backend**: Clear separation of concerns with Rails as an API and a separate React application. However, this approach increases deployment complexity, requires maintaining two codebases, and can lead to code duplication.

### Why ReactiveViews?

ReactiveViews aims to provide a better developer experience than current alternatives by focusing on:

**Features**: Advanced SSR with batch and tree rendering, automatic props inference via TypeScript AST parsing, full-page `.tsx.erb` templates, and component caching with configurable TTL.

**Developer Experience**: One-command setup via generator, convention over configuration, seamless Rails integration. Write React components in ERB using familiar Rails conventions, or use TypeScript/TSX for full pages.

**Performance**: Batch rendering consolidates multiple components into a single SSR request, tree rendering enables true React composition, and intelligent caching reduces redundant rendering. Optimized hydration ensures minimal overhead.

**Ease of Use**: Generator-based setup handles all configuration automatically. Minimal boilerplate, flexible component naming (supports PascalCase, snake_case, camelCase, kebab-case), and automatic component resolution.

**Ease of Deployment**: Single application deployment, integrated tooling with Vite, no separate services required. Works seamlessly with Rails' asset pipeline and existing deployment workflows.

## Features

- **Server-Side Rendering (SSR)**: Render React components on the server via Node.js for improved initial load times and SEO
- **Client-Side Hydration Islands**: Automatic hydration of React components on the client with minimal overhead
- **Batch Rendering**: Render multiple components in a single SSR request for improved performance
- **Tree Rendering**: Support for nested component composition with true React component trees
- **Full-Page TSX.ERB Rendering**: Write entire pages in TypeScript/JSX with ERB evaluation and Rails partials
- **Automatic Props Inference**: TypeScript AST parsing extracts required props from component signatures, ensuring only necessary data is sent to SSR
- **Component Caching**: Configurable TTL-based caching for rendered components
- **Flexible Component Naming**: Supports PascalCase, snake_case, camelCase, and kebab-case naming conventions
- **ERB Partial Composition**: Compose multiple TSX components using standard Rails partial syntax
- **Vite Integration**: Seamless integration with Vite for development (HMR) and production builds
- **TypeScript Support**: Full TypeScript support for type-safe component development

## Roadmap

Our vision is to evolve ReactiveViews into a Rails counterpart of Next.js, bringing modern React features and optimizations to the Rails ecosystem.

### Performance Optimizations

- **Adaptive Hydration**: Prioritize or defer component hydration based on device capabilities and network conditions
- **Modular Rendering**: Render components in isolation to reduce bundle size and improve load times
- **Code Splitting Improvements**: Automatic route-based and component-based code splitting
- **Concurrent Rendering Enhancements**: Leverage React's concurrent features for smoother interactions

### Infrastructure

- **HERB Integration**: Transition from Nokogiri to HERB for HTML parsing and manipulation. HERB offers better performance, a more Ruby-centric API, and improved maintainability
- **Adapter Architecture**: Develop adapter system to support other frontend frameworks (Vue.js, Svelte, etc.), allowing flexibility in frontend rendering engines
- **Enhanced Error Boundaries**: Better error handling and recovery mechanisms for SSR failures

### Developer Experience

- **Visual Studio Code Extension**: Syntax highlighting and IntelliSense for `.tsx.erb` files
- **Enhanced Debugging Tools**: Better error messages, stack traces, and development-time warnings
- **Documentation**: Comprehensive guides, API reference, and best practices

## Usage

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

The generator will set up Vite, install React dependencies, create the necessary configuration files, and add the required script tags to your layout.

4. **Start the development environment:**

```bash
bin/dev
```

This starts Rails, Vite, and the SSR server together. You're ready to use React components in your Rails views!

## Example

### Island Architecture (Components in ERB)

Write React components directly in your ERB templates:

```erb
<!-- app/views/posts/index.html.erb -->
<div class="page-wrap">
  <h1>Posts</h1>
  <PostList props='<%= @posts.as_json(only: [:id, :title]).to_json %>' />
</div>
```

Create your component:

```tsx
// app/views/components/post_list.tsx
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

The component will be server-rendered and automatically hydrated on the client.

### Full-Page TSX.ERB Rendering

Write entire pages in TypeScript/JSX:

```ruby
# app/controllers/users_controller.rb
class UsersController < ApplicationController
  def index
    @users = User.all
    reactive_view_props(
      page_title: "User Directory",
      current_user: current_user
    )
  end
end
```

```tsx
// app/views/users/index.tsx.erb
interface Props {
  users: User[];
  page_title: string;
  current_user: User;
}

export default function UsersPage({ users, page_title, current_user }: Props) {
  return (
    <main>
      <h1>{page_title}</h1>
      <p>Welcome, {current_user.name}</p>
      <ul>
        {users.map(user => (
          <li key={user.id}>{user.name}</li>
        ))}
      </ul>
    </main>
  );
}
```

Rails automatically detects the missing `.html.erb` template and renders the `.tsx.erb` template instead. Props are automatically inferred from the TypeScript component signature.

## Contributing

At this time, we are only accepting bug reports. If you encounter any issues or have suggestions, please open an issue on our [GitHub repository](https://github.com/elisoncampos/reactive_views/issues).

We appreciate your feedback and contributions to help improve ReactiveViews!

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
