import React from 'react';
import { hydrateRoot } from 'react-dom/client';

type IslandSpec = {
  id: string;
  component: string;
  el: Element;
};

function readProps(uuid: string) {
  const script = document.querySelector(`script[type="application/json"][data-island-uuid="${uuid}"]`);
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

async function hydrateAll() {
  const nodes = Array.from(document.querySelectorAll('[data-island-uuid][data-component]'));
  console.log(`[reactive_views] Found ${nodes.length} islands to hydrate`);
  
  for (const node of nodes) {
    const el = node as HTMLElement;
    const uuid = el.dataset.islandUuid!;
    const component = el.dataset.component!;
    console.log(`[reactive_views] Hydrating component: ${component} (uuid: ${uuid})`);
    
    try {
      const Comp = await loadComponent(component);
      const props = readProps(uuid);
      console.log(`[reactive_views] Props for ${component}:`, props);
      hydrateRoot(el, React.createElement(Comp, props));
      console.log(`[reactive_views] Successfully hydrated: ${component}`);
    } catch (e) {
      console.error(`[reactive_views] Failed to hydrate component: ${component}`, e);
      console.error(`[reactive_views] Available components:`, Object.keys(componentsFromViews));
    }
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', hydrateAll);
} else {
  hydrateAll();
}

