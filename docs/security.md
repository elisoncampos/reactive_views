# Security Considerations

**Audience:** Rails developers shipping ReactiveViews to production.
**Topic:** Security boundaries and common risks (XSS, data exposure, SSR server network exposure).
**Goal:** Use ReactiveViews safely by understanding what data is public, what code runs where, and what to avoid.

## Security model (what runs where)

ReactiveViews has two execution environments:

- **Rails:** renders ERB, transforms HTML, and injects hydration payloads.
- **Node SSR:** executes your React component code to generate HTML (and for full-page templates, it also emits a browser bundle key).

Your browser receives:

- SSR HTML
- JSON props embedded in the response
- JavaScript assets needed to hydrate

## Do not ship secrets in props

Props are embedded into the HTML response (as JSON inside `<script type="application/json">`).

That means:

- Any prop is visible to anyone who can load the page.
- Props can leak via “View Source”, browser devtools, and caching layers.

**Rule:** If you wouldn’t put it in the HTML, don’t put it in props.

## XSS (Cross-Site Scripting)

React escapes interpolated strings by default, which is good. You can still create XSS if you:

- Render untrusted HTML via `dangerouslySetInnerHTML`
- Build HTML strings on the server and inject them without sanitizing

**Prefer:** pass plain strings and render them as text.

If you must render HTML from untrusted sources, sanitize it server-side (e.g., Rails sanitizers) before passing it to React.

## SSR server exposure

The SSR server:

- Accepts JSON requests to render arbitrary component paths
- Responds with permissive CORS headers

In production, you should treat SSR as an **internal service**:

- Bind to `127.0.0.1` when co-located with Rails (recommended)
- Or restrict SSR to a private network and firewall it

If you set `RV_SSR_URL` to an external address, ensure:

- It is not publicly reachable
- You have rate limiting and monitoring
- You have a clear trust boundary between Rails and SSR

## Denial of service (DoS) and large props

SSR work scales with:

- the number of islands on the page
- the size/shape of props
- component render complexity

Reduce risk:

- Avoid passing large arrays/hashes as props
- Cache SSR output where safe
- Prefer IDs + client fetch for large datasets

## Caching and user-specific data

SSR caching can leak data across users if the cache key does not fully capture user-specific differences.

- Avoid caching personalized components, or keep TTLs very short.
- Never cache SSR HTML that contains sensitive or private user information.

## Reporting vulnerabilities

If you discover a security issue in ReactiveViews, report it privately (if a security contact is available) before opening a public issue.
