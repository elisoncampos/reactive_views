import React from 'react';
import { hydrateRoot } from 'react-dom/client';

type IslandSpec = {
  id: string;
  component: string;
  el: Element;
};

type ReactiveViewsGlobal = {
  react?: typeof React;
  hydrateRoot?: typeof hydrateRoot;
  ssrUrl?: string;
  hydratedPages?: string[];
  lastPageError?: string;
};

declare global {
  interface Window {
    __REACTIVE_VIEWS__?: ReactiveViewsGlobal;
  }
}

const globalRV: ReactiveViewsGlobal = (window.__REACTIVE_VIEWS__ ||= {});
globalRV.react = React;
globalRV.hydrateRoot = hydrateRoot;
globalRV.hydratedPages ||= [];

function readProps(uuid: string) {
  const script = document.querySelector(`script[type="application/json"][data-island-uuid="${uuid}"]`);
  if (!script) return {};
  try {
    return JSON.parse(script.textContent || '{}');
  } catch (_e) {
    return {};
  }
}

type PageMetadata = {
  props?: Record<string, unknown>;
  bundle?: string;
};

function readPageMetadata(uuid: string): PageMetadata {
  const script = document.querySelector(`script[type="application/json"][data-page-uuid="${uuid}"]`);
  if (!script) return {};
  try {
    return JSON.parse(script.textContent || '{}');
  } catch (_e) {
    return {};
  }
}

function toPath(name: string): string {
  // Convert PascalCase and dot notation to snake_case path
  const parts = name.split('.');
  const snake = (s: string) => s.replace(/([A-Z]+)([A-Z][a-z])/g, '$1_$2').replace(/([a-z\d])([A-Z])/g, '$1_$2').replace(/-/g, '_').toLowerCase();
  return parts.map(snake).join('/');
}

// Import all components eagerly so they are available for hydration
const rawComponentsFromViews = import.meta.glob('../../views/components/**/*.{tsx,jsx,ts,js}', { 
  eager: true,
});
const rawComponentsFromJs = import.meta.glob('../components/**/*.{tsx,jsx,ts,js}', { 
  eager: true,
});

// Normalize paths to match the absolute aliased paths that loadComponent expects
const componentsFromViews: Record<string, any> = {};
const componentsFromJs: Record<string, any> = {};

for (const [path, module] of Object.entries(rawComponentsFromViews)) {
  const normalized = path.replace('../../views/components/', '/app/views/components/');
  componentsFromViews[normalized] = (module as any).default;
}

for (const [path, module] of Object.entries(rawComponentsFromJs)) {
  const normalized = path.replace('../components/', '/app/javascript/components/');
  componentsFromJs[normalized] = (module as any).default;
}

async function loadComponent(name: string) {
  // Attempt both conventional locations; try multiple filename shapes and extensions
  const rel = toPath(name);
  const leaf = rel.split('/').pop() as string;
  const bases = ['/app/views/components', '/app/javascript/components'];
  const exts = ['.tsx', '.jsx', '.ts', '.js'];

  // Combine both glob maps
  const allComponents = { ...componentsFromViews, ...componentsFromJs };

  // Try both the original name (e.g., "InteractiveCounter") and snake_case ("interactive_counter")
  const nameVariants = [name, rel];
  const leafVariants = [name, leaf];

  for (const base of bases) {
    for (let i = 0; i < nameVariants.length; i++) {
      const nameVar = nameVariants[i];
      const leafVar = leafVariants[i];
      
      for (const ext of exts) {
        const candidates = [
          `${base}/${nameVar}${ext}`,
          `${base}/${nameVar}/index${ext}`,
          `${base}/${nameVar}/${leafVar}${ext}`,
        ];
        for (const path of candidates) {
          // Check if this path exists in our glob imports
          if (allComponents[path]) {
            // Component is already loaded with eager: true
            // The .default was already extracted during normalization
            return allComponents[path];
          }
        }
      }
    }
  }

  throw new Error(`Component not found on client: ${name}`);
}

function resolveSsrUrl() {
  if (globalRV.ssrUrl) return globalRV.ssrUrl.replace(/\/$/, '');
  const meta = document.querySelector('meta[name="reactive-views-ssr-url"]');
  if (meta?.getAttribute('content')) {
    return meta.getAttribute('content')!.replace(/\/$/, '');
  }
  return 'http://localhost:5175';
}

async function hydrateFullPages() {
  const nodes = Array.from(document.querySelectorAll<HTMLElement>('[data-reactive-page="true"]'));
  for (const node of nodes) {
    const uuid = node.dataset.pageUuid;
    if (!uuid) continue;

    const metadata = readPageMetadata(uuid);
    if (!metadata.bundle) continue;

    const ssrUrl = resolveSsrUrl();
    const moduleUrl = `${ssrUrl}/full-page-bundles/${metadata.bundle}.js`;

    try {
      if (import.meta.env?.DEV) {
        console.log(`[reactive_views] Hydrating full page bundle: ${metadata.bundle}`);
      }
      const mod = await import(/* @vite-ignore */ moduleUrl);
      const Comp = mod.default || mod.Component || mod;
      hydrateRoot(node, React.createElement(Comp, metadata.props || {}));
      if (import.meta.env?.DEV) {
        console.log(`[reactive_views] Hydrated full page bundle ${metadata.bundle}`);
      }
      globalRV.hydratedPages!.push(uuid);
      node.dataset.reactiveHydrated = "true";
    } catch (e) {
      if (import.meta.env?.DEV) {
        console.error(`[reactive_views] Failed to hydrate full page bundle: ${metadata.bundle}`, e);
      }
      globalRV.lastPageError = e instanceof Error ? e.stack : String(e);
    }
  }
}

async function hydrateIslands() {
  const nodes = Array.from(document.querySelectorAll('[data-island-uuid][data-component]'));
  for (const node of nodes) {
    const el = node as HTMLElement;
    const uuid = el.dataset.islandUuid!;
    const component = el.dataset.component!;
    try {
      const Comp = await loadComponent(component);
      const props = readProps(uuid);
      hydrateRoot(el, React.createElement(Comp, props));
    } catch (e) {
      if (import.meta.env?.DEV) {
        console.error(`[reactive_views] Failed to hydrate component: ${component}`, e);
        console.error(`[reactive_views] Make sure vite.config.ts has resolve.alias configured for /app/views/components and /app/javascript/components`);
      }
    }
  }
}

async function hydrateAll() {
  await hydrateFullPages();
  await hydrateIslands();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', hydrateAll);
} else {
  hydrateAll();
}
