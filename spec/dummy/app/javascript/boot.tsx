import React from 'react';
import { hydrateRoot } from 'react-dom/client';

// Import Turbo and Stimulus for Rails 8 compatibility testing
import "@hotwired/turbo-rails";
import { Application } from "@hotwired/stimulus";

// Import Stimulus controllers
import HelloController from "./controllers/hello_controller";
import CounterController from "./controllers/counter_controller";

// Initialize Stimulus
const application = Application.start();
application.register("hello", HelloController);
application.register("counter", CounterController);

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
const rawComponentsFromViews = import.meta.glob('../views/components/**/*.{tsx,jsx,ts,js}', { 
  eager: true,
});

// Normalize paths to match the absolute aliased paths that loadComponent expects
const componentsFromViews: Record<string, any> = {};

console.log('[reactive_views] Raw components:', Object.keys(rawComponentsFromViews));

for (const [path, module] of Object.entries(rawComponentsFromViews)) {
  const normalized = path.replace('../views/components/', '/app/views/components/');
  componentsFromViews[normalized] = (module as any).default;
  console.log(`[reactive_views] Loaded component: ${normalized}`);
}

async function loadComponent(name: string) {
  // Attempt both conventional locations; try multiple filename shapes and extensions
  const rel = toPath(name);
  const leaf = rel.split('/').pop() as string;
  const bases = ['/app/views/components'];
  const exts = ['.tsx', '.jsx', '.ts', '.js'];

  const allComponents = componentsFromViews;

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

    // Skip if already hydrated
    if (node.dataset.reactiveHydrated === 'true') continue;

    const metadata = readPageMetadata(uuid);
    if (!metadata.bundle) continue;

    const ssrUrl = resolveSsrUrl();
    const moduleUrl = `${ssrUrl}/full-page-bundles/${metadata.bundle}.js`;

    try {
      console.log(`[reactive_views] Hydrating full page bundle: ${metadata.bundle}`);
      const mod = await import(/* @vite-ignore */ moduleUrl);
      const Comp = mod.default || mod.Component || mod;
      hydrateRoot(node, React.createElement(Comp, metadata.props || {}));
      console.log(`[reactive_views] Hydrated full page bundle ${metadata.bundle}`);
      globalRV.hydratedPages!.push(uuid);
      node.dataset.reactiveHydrated = 'true';
    } catch (e) {
      console.error(`[reactive_views] Failed to hydrate full page bundle: ${metadata.bundle}`, e);
      globalRV.lastPageError = e instanceof Error ? e.stack : String(e);
    }
  }
}

async function hydrateIslands() {
  const nodes = Array.from(document.querySelectorAll('[data-island-uuid][data-component]'));
  console.log(`[reactive_views] Found ${nodes.length} islands to hydrate`);
  
  for (const node of nodes) {
    const el = node as HTMLElement;
    
    // Skip if already hydrated
    if (el.dataset.reactiveHydrated === 'true') continue;
    
    const uuid = el.dataset.islandUuid!;
    const component = el.dataset.component!;
    console.log(`[reactive_views] Hydrating component: ${component} (uuid: ${uuid})`);
    
    try {
      const Comp = await loadComponent(component);
      const props = readProps(uuid);
      console.log(`[reactive_views] Props for ${component}:`, props);
      hydrateRoot(el, React.createElement(Comp, props));
      el.dataset.reactiveHydrated = 'true';
      console.log(`[reactive_views] Successfully hydrated: ${component}`);
    } catch (e) {
      console.error(`[reactive_views] Failed to hydrate component: ${component}`, e);
      console.error(`[reactive_views] Available components:`, Object.keys(componentsFromViews));
    }
  }
}

async function hydrateAll() {
  await hydrateFullPages();
  await hydrateIslands();
}

// Initial hydration
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', hydrateAll);
} else {
  hydrateAll();
}

// Turbo integration: re-hydrate after Turbo navigations
// This ensures React components work correctly with Turbo Drive and Turbo Frames
document.addEventListener('turbo:load', hydrateAll);
document.addEventListener('turbo:frame-load', hydrateAll);

