---
sidebar_position: 6
title: Troubleshooting
---

# Troubleshooting

Common issues and how to debug them quickly.

## SSR server won't start

- Ensure Node 22+ is installed (`node -v`).
- Check the console output—`PROJECT_ROOT` must point at your Rails app (where `package.json` lives).
- Ports already in use? Set `RV_SSR_PORT` / `RV_VITE_PORT` to unused ports.

## Components render blank / show error overlay

1. Open the Rails logs. Errors are prefixed with `[ReactiveViews]`.
2. In development the HTML will include an overlay explaining the stack trace.
3. In production you see an empty `<div data-reactive-views-error>`—check the SSR server logs for the real error.

## Props aren't reaching the component

- Run with `config.props_inference_enabled = false` to confirm inference isn't filtering them out.
- Remember to JSON encode props in ERB: `props="<%= my_hash.to_json %>"`.
- Give each component a unique prop structure; duplicate keys plus caching can make debugging hard.

## Changes aren't picked up

- For Ruby-side caching, either disable `ssr_cache_ttl_seconds` or call `ReactiveViews::Renderer.clear_cache`.
- For Node bundler caching, bump the file's `mtime` (save the file) or disable the cache temporarily via `RV_SSR_BUNDLE_CACHE=0`.

## "Payload too large" errors

Endpoints now guard against huge JSON bodies. Split large props into smaller islands or pass an identifier and fetch data after hydration.

---

## Production Issues

### Assets not found in production

If you see 404 errors for JavaScript or CSS files:

1. **Verify assets are precompiled:**
   ```bash
   ls public/vite/assets/
   ```

2. **Check manifest exists:**
   ```bash
   cat public/vite/.vite/manifest.json
   ```

3. **Ensure static file serving is enabled:**
   ```bash
   RAILS_SERVE_STATIC_FILES=true
   ```

4. **Verify asset host configuration:**
   ```ruby
   # config/environments/production.rb
   config.asset_host = ENV['ASSET_HOST']
   ```

5. **Rebuild assets:**
   ```bash
   NODE_ENV=production npx vite build
   ```

### CSS conflicts between React and Rails

If styles are conflicting between React components and Rails views:

1. **Use CSS Modules for React components:**
   ```tsx
   import styles from './Component.module.css';
   
   export default function Component() {
     return <div className={styles.wrapper}>...</div>;
   }
   ```

2. **Scope Tailwind to React components:**
   ```javascript
   // tailwind.config.js for React
   module.exports = {
     prefix: 'rv-',
     content: ['./app/views/components/**/*.tsx'],
   };
   ```

3. **Use BEM naming with component prefix:**
   ```css
   .Counter__button--primary { }
   ```

4. **Check for common class name conflicts:**
   ```ruby
   conflicts = ReactiveViews::CssStrategy.detect_conflicts(html)
   ```

### Turbo navigation breaks React

If React components don't work after Turbo navigation:

1. **Verify boot script includes Turbo listeners:**
   ```typescript
   document.addEventListener('turbo:load', hydrateAll);
   document.addEventListener('turbo:frame-load', hydrateAll);
   ```

2. **Check before-cache cleanup:**
   ```typescript
   document.addEventListener('turbo:before-cache', () => {
     document.querySelectorAll('[data-reactive-hydrated]').forEach(el => {
       el.removeAttribute('data-reactive-hydrated');
     });
   });
   ```

3. **Ensure components re-hydrate:**
   - After Turbo navigation, `data-reactive-hydrated` should be removed
   - The boot script should re-hydrate on `turbo:load`

4. **Check for JavaScript errors:**
   ```javascript
   // Browser console
   window.__REACTIVE_VIEWS__  // Should be an object
   ```

### SSR server connectivity

If Rails can't connect to the SSR server:

1. **Check SSR server is running:**
   ```bash
   curl http://localhost:5175/health
   ```

2. **Verify URL configuration:**
   ```ruby
   ReactiveViews.config.ssr_url  # Check in Rails console
   ```

3. **Check network connectivity:**
   - In Docker/Kubernetes, ensure services can reach each other
   - Use service names, not localhost

4. **Enable fallback mode:**
   ```ruby
   ReactiveViews.configure do |config|
     config.ssr_fallback_enabled = true
   end
   ```

5. **Review SSR server logs:**
   ```bash
   # In Kamal
   kamal accessory logs ssr
   
   # In Kubernetes
   kubectl logs -l app=reactive-views-ssr
   ```

### Hydration mismatch errors

If you see "Hydration failed" or "Text content does not match":

1. **Check for non-deterministic rendering:**
   - Dates: Use `new Date().toISOString()` on server, pass as prop
   - Random values: Generate on server, pass as prop
   - User-specific data: Ensure same data on server and client

2. **Verify props match:**
   ```javascript
   // Browser console
   document.querySelector('[data-island-uuid]')
     .querySelector('script[type="application/json"]')
     .textContent  // Check props JSON
   ```

3. **Check conditional rendering:**
   - Server and client must render the same initial HTML
   - Use `typeof window === 'undefined'` for server checks

4. **Disable strict mode temporarily:**
   ```tsx
   // Just for debugging
   <React.StrictMode> → remove temporarily
   ```

---

## Need more help?

- Search or open a [GitHub issue](https://github.com/elisoncampos/reactive_views/issues).
- Chat with the team via Discussions for architecture questions.

You're never alone—React + Rails can be fun again!

