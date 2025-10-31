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

async function loadComponent(name: string) {
  // Attempt both conventional locations; Vite should alias these as needed in the host app
  const rel = toPath(name);
  try {
    return (await import(/* @vite-ignore */ `/app/views/components/${rel}.tsx`)).default;
  } catch (_e) {
    return (await import(/* @vite-ignore */ `/app/javascript/components/${rel}.tsx`)).default;
  }
}

async function hydrateAll() {
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
        console.error('[reactive_views] Hydration error', e);
      }
    }
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', hydrateAll);
} else {
  hydrateAll();
}


