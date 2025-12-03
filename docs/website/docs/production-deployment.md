---
sidebar_position: 5
title: Production Deployment
---

# Production Deployment

This guide covers deploying ReactiveViews to production, including asset precompilation, SSR server deployment, and monitoring.

## Overview

A production ReactiveViews deployment consists of:

1. **Rails Application** - Your main application serving HTML
2. **Precompiled Assets** - Vite-built JavaScript and CSS bundles
3. **SSR Server** - Node.js server for server-side rendering

## Asset Precompilation

### Building for Production

Build your production assets using Vite:

```bash
# Set environment
export NODE_ENV=production
export RAILS_ENV=production

# Build assets
npx vite build
```

This creates:
- Fingerprinted JavaScript bundles in `public/vite/assets/`
- Extracted CSS files
- A manifest file at `public/vite/.vite/manifest.json`

### Vite Configuration

Ensure your `vite.config.ts` includes production settings:

```typescript
export default defineConfig(({ mode }) => {
  const isProduction = mode === 'production';
  
  return {
    build: {
      target: isProduction ? 'es2022' : 'esnext',
      manifest: true,
      cssCodeSplit: false, // Single CSS file
      sourcemap: process.env.VITE_SOURCEMAP !== 'false',
    },
  };
});
```

### CDN Configuration

For CDN deployments, set the `ASSET_HOST` environment variable:

```bash
ASSET_HOST=https://cdn.example.com
```

ReactiveViews will automatically prefix asset URLs with your CDN host.

## SSR Server Deployment

The SSR server must run alongside your Rails application. Choose one of these deployment options:

### Option 1: Kamal 2 (Recommended)

Generate Kamal configuration:

```bash
rails generate reactive_views:kamal
```

This creates:
- `Dockerfile.ssr` - Docker image for SSR server
- `package.ssr.json` - SSR dependencies
- Kamal accessory configuration

Add to your `config/deploy.yml`:

```yaml
accessories:
  ssr:
    image: your-registry/reactive-views-ssr:latest
    host: your-server
    port: 5175
    env:
      clear:
        RV_SSR_PORT: "5175"
        NODE_ENV: production
        PROJECT_ROOT: /rails
    volumes:
      - /rails/app:/rails/app:ro
    healthcheck:
      path: /health
      interval: 10s
```

Deploy:

```bash
# Build and push SSR image
docker build -f Dockerfile.ssr -t your-registry/reactive-views-ssr .
docker push your-registry/reactive-views-ssr

# Deploy with Kamal
kamal deploy
```

### Option 2: Kubernetes

Generate Kubernetes manifests:

```bash
rails generate reactive_views:kubernetes --namespace=production
```

This creates in `k8s/`:
- `deployment.yaml` - SSR Deployment with health checks
- `service.yaml` - ClusterIP Service
- `configmap.yaml` - Environment configuration
- `hpa.yaml` - Horizontal Pod Autoscaler
- `kustomization.yaml` - Kustomize configuration

Apply:

```bash
kubectl apply -k k8s/
```

Configure Rails to use the SSR service:

```yaml
env:
  - name: REACTIVE_VIEWS_SSR_URL
    value: http://reactive-views-ssr:5175
```

### Option 3: Standalone Process

Run the SSR server as a separate process using your process manager:

```bash
# systemd, supervisord, or similar
NODE_ENV=production \
RV_SSR_PORT=5175 \
PROJECT_ROOT=/var/www/myapp \
node /path/to/reactive_views/node/ssr/server.mjs
```

## Environment Variables

### Rails Application

| Variable | Description | Default |
|----------|-------------|---------|
| `REACTIVE_VIEWS_SSR_URL` | SSR server URL | `http://localhost:5175` |
| `REACTIVE_VIEWS_SSR_TIMEOUT` | SSR request timeout (seconds) | `5` |
| `REACTIVE_VIEWS_SSR_FALLBACK` | Enable client-only fallback | `true` |
| `ASSET_HOST` | CDN URL for assets | - |

### SSR Server

| Variable | Description | Default |
|----------|-------------|---------|
| `RV_SSR_PORT` | HTTP port | `5175` |
| `NODE_ENV` | Node environment | `development` |
| `PROJECT_ROOT` | Rails app root path | Current directory |
| `RV_SSR_BUNDLE_CACHE` | Component cache size | `20` |

## Configuration

Configure ReactiveViews in `config/initializers/reactive_views.rb`:

```ruby
ReactiveViews.configure do |config|
  # SSR server configuration
  config.ssr_url = ENV.fetch("REACTIVE_VIEWS_SSR_URL", "http://localhost:5175")
  config.ssr_timeout = ENV.fetch("REACTIVE_VIEWS_SSR_TIMEOUT", 5).to_i
  
  # Enable fallback to client-only rendering if SSR fails
  config.ssr_fallback_enabled = true
  
  # SSR health check interval (seconds)
  config.ssr_health_check_interval = 30
  
  # Retry configuration
  config.ssr_retry_count = 2
  config.ssr_retry_delay = 0.1
  
  # Asset host for CDN
  config.asset_host = ENV["ASSET_HOST"]
  
  # Caching
  config.cache_store = :redis_cache_store, { url: ENV["REDIS_URL"] }
  config.ssr_cache_ttl_seconds = 60
end
```

## Health Checks

### SSR Server Health

The SSR server exposes a health endpoint:

```bash
curl http://localhost:5175/health
# {"status":"ok","version":"1.0.0"}
```

### Rails Health Check

Include SSR status in your Rails health check:

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def show
    checks = {
      database: database_healthy?,
      ssr: ssr_healthy?
    }
    
    status = checks.values.all? ? :ok : :service_unavailable
    render json: checks, status: status
  end
  
  private
  
  def ssr_healthy?
    uri = URI.parse("#{ReactiveViews.config.ssr_url}/health")
    response = Net::HTTP.get_response(uri)
    response.code == "200"
  rescue StandardError
    false
  end
end
```

## Monitoring

### Metrics to Track

1. **SSR Response Time** - Average time for SSR renders
2. **SSR Error Rate** - Failed SSR requests
3. **Bundle Cache Hit Rate** - Percentage of cached component renders
4. **Asset Load Time** - Time to load JavaScript and CSS
5. **Hydration Time** - Client-side React hydration duration

### Logging

Configure structured logging for the SSR server:

```bash
LOG_LEVEL=info node node/ssr/server.mjs
```

The SSR server logs:
- Component render requests
- Bundle compilation events
- Cache hits/misses
- Errors with stack traces

## Performance Optimization

### Bundle Size

Keep your production bundles small:

```bash
# Check bundle size after build
du -sh public/vite/assets/*
```

Targets:
- Total JavaScript: < 500KB (gzipped)
- Total CSS: < 100KB (gzipped)

### SSR Caching

Enable component caching to reduce SSR load:

```ruby
ReactiveViews.configure do |config|
  config.cache_store = :redis_cache_store, { url: ENV["REDIS_URL"] }
  config.ssr_cache_ttl_seconds = 60
end
```

### SSR Server Scaling

The SSR server is stateless and can be horizontally scaled:

```yaml
# Kubernetes HPA
spec:
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

## Troubleshooting

### Assets Not Found

1. Verify `public/vite/` directory exists
2. Check manifest file is present
3. Ensure `RAILS_SERVE_STATIC_FILES=true` in production
4. Verify asset host configuration

### SSR Connection Failed

1. Check SSR server is running: `curl http://ssr:5175/health`
2. Verify network connectivity between Rails and SSR
3. Check `REACTIVE_VIEWS_SSR_URL` is correct
4. Review SSR server logs for errors

### Hydration Mismatch

1. Ensure server and client render the same HTML
2. Check for non-deterministic rendering (dates, random values)
3. Verify props are serialized consistently
4. Check for conditional rendering differences

See [Troubleshooting](/docs/troubleshooting) for more solutions.


