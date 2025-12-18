# Islands (React components inside ERB)

**Audience:** Rails developers who want to sprinkle React into existing ERB pages.
**Topic:** Rendering “islands” by writing React component tags in HTML and passing props safely.
**Goal:** Render SSR’d islands, pass props reliably, and understand the performance trade-offs (batch vs tree rendering).

## How islands work

When an action returns an HTML response, ReactiveViews scans the rendered HTML and looks for **PascalCase tags** like:

```html
<UserBadge />
```

It replaces each component tag with:

- A **container element** with metadata (`data-island-uuid`, `data-component`)
- The **SSR HTML** inside that container
- A **JSON props `<script type="application/json">`** that the client reads during hydration

## Basic usage

**Introduction:** This example shows a component rendered from ERB, with props encoded as JSON.

```tsx
// app/views/components/counter.tsx
import { useState } from "react";

type Props = { initialCount: number };

export default function Counter({ initialCount }: Props) {
  const [count, setCount] = useState(initialCount);

  return (
    <button type="button" onClick={() => setCount((c) => c + 1)}>
      Count: {count}
    </button>
  );
}
```

```erb
<!-- app/views/home/index.html.erb -->
<Counter initialCount={0} />
```

### Prop parsing rules (important)

ReactiveViews parses attribute values using pragmatic rules:

- **JSX-style `{...}`** values are interpreted (booleans, numbers, JSON, null)
- Plain strings are preserved (with some coercions for `"true"`, `"false"`, numbers)

Examples:

```erb
<UserBadge fullName="Ada Lovelace" />
<Counter initialCount={10} />
<FeatureFlag enabled={true} />
<ProductList products="<%= @products.as_json.to_json %>" />
```

## Nested components: batch vs tree rendering

ReactiveViews has two strategies:

- **Batch rendering (fast for flat pages):** renders many components with one SSR request.
- **Tree rendering (correct for nested components):** sends the component tree to SSR so children are rendered as real React children.

Tree rendering is used when nesting is detected and `tree_rendering_enabled` is true.

## Security considerations (islands)

- **Do not pass secrets in props.** Props are embedded in the HTML response and are readable by the browser.
- **Treat props as untrusted input.** React escapes strings by default, but you can still create XSS if you use `dangerouslySetInnerHTML`.
- **Avoid exposing the SSR server publicly.** The Node server enables permissive CORS and should be bound to localhost in production.

For the full security guide, see [`security.md`](security.md).
