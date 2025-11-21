#!/usr/bin/env node

import http from "http";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import fs from "fs";
import { createRequire } from "module";

// Configuration from environment
const PORT = parseInt(process.env.RV_SSR_PORT || "5175", 10);
const VITE_PORT = parseInt(process.env.RV_VITE_PORT || "5174", 10);
const NODE_ENV = process.env.NODE_ENV || "development";
const IS_DEV = NODE_ENV === "development";

// Determine project root (when run via rake task, cwd should be the Rails app)
const PROJECT_ROOT = process.cwd();

// Create a require function that resolves from the project root
// This allows us to import packages installed in the Rails app's node_modules
const projectRequire = createRequire(join(PROJECT_ROOT, "package.json"));
const esbuild = await import(projectRequire.resolve("esbuild"));

// Resolve React and ReactDOM from the project
const reactPath = projectRequire.resolve("react");
const reactDomServerPath = projectRequire.resolve("react-dom/server");

console.log(`[ReactiveViews SSR] Starting server...`);
console.log(`[ReactiveViews SSR] Project root: ${PROJECT_ROOT}`);
console.log(`[ReactiveViews SSR] Port: ${PORT}`);

const PropsInference = (() => {
  const cache = new Map();
  let cachedTypeScript = null;
  let typescriptMissing = false;

  function loadTypeScript() {
    if (cachedTypeScript) {
      return cachedTypeScript;
    }

    if (typescriptMissing) {
      return null;
    }

    try {
      cachedTypeScript = projectRequire("typescript");
      return cachedTypeScript;
    } catch (error) {
      if (error.code === "MODULE_NOT_FOUND") {
        typescriptMissing = true;
        console.warn(
          "[ReactiveViews SSR] TypeScript not found in the host app. " +
            "Props inference will be skipped. Install it with `yarn add -D typescript` or disable props inference."
        );
        return null;
      }

      throw error;
    }
  }

  function infer(content, contentHash, extension = "tsx") {
    if (contentHash && cache.has(contentHash)) {
      return cache.get(contentHash);
    }

    try {
      const typescript = loadTypeScript();
      if (!typescript) {
        return [];
      }

      const scriptKind =
        extension === "jsx"
          ? typescript.ScriptKind.JSX
          : typescript.ScriptKind.TSX;

      const sourceFile = typescript.createSourceFile(
        `component.${extension}`,
        content,
        typescript.ScriptTarget.Latest,
        true,
        scriptKind
      );

      const keys = [];

      function visit(node) {
        if (
          typescript.isFunctionDeclaration(node) &&
          node.modifiers?.some(
            (m) =>
              m.kind === typescript.SyntaxKind.ExportKeyword ||
              m.kind === typescript.SyntaxKind.DefaultKeyword
          )
        ) {
          extractPropsFromFunction(node);
        }

        if (
          typescript.isExportAssignment(node) &&
          typescript.isIdentifier(node.expression)
        ) {
          const componentName = node.expression.text;
          typescript.forEachChild(sourceFile, (child) => {
            if (
              typescript.isVariableStatement(child) &&
              child.declarationList.declarations.some(
                (d) =>
                  typescript.isIdentifier(d.name) &&
                  d.name.text === componentName
              )
            ) {
              child.declarationList.declarations.forEach((decl) => {
                if (
                  typescript.isIdentifier(decl.name) &&
                  decl.name.text === componentName &&
                  decl.initializer
                ) {
                  if (typescript.isArrowFunction(decl.initializer)) {
                    extractPropsFromArrowFunction(decl.initializer);
                  } else if (
                    typescript.isFunctionExpression(decl.initializer)
                  ) {
                    extractPropsFromFunction(decl.initializer);
                  }
                }
              });
            } else if (
              typescript.isFunctionDeclaration(child) &&
              typescript.isIdentifier(child.name) &&
              child.name.text === componentName
            ) {
              extractPropsFromFunction(child);
            }
          });
        }

        typescript.forEachChild(node, visit);
      }

      function extractPropsFromFunction(node) {
        if (node.parameters.length > 0) {
          const firstParam = node.parameters[0];
          if (typescript.isObjectBindingPattern(firstParam.name)) {
            firstParam.name.elements.forEach((element) => {
              if (
                typescript.isBindingElement(element) &&
                typescript.isIdentifier(element.name)
              ) {
                keys.push(element.name.text);
              }
            });
          }
        }
      }

      function extractPropsFromArrowFunction(node) {
        if (node.parameters.length > 0) {
          const firstParam = node.parameters[0];
          if (typescript.isObjectBindingPattern(firstParam.name)) {
            firstParam.name.elements.forEach((element) => {
              if (
                typescript.isBindingElement(element) &&
                typescript.isIdentifier(element.name)
              ) {
                keys.push(element.name.text);
              }
            });
          }
        }
      }

      visit(sourceFile);

      console.log(`[ReactiveViews SSR] Inferred props: ${keys.join(", ")}`);

      if (contentHash) {
        cache.set(contentHash, keys);
      }

      return keys;
    } catch (error) {
      console.error("[ReactiveViews SSR] Props inference error:", error);
      return [];
    }
  }

  return { infer };
})();

const Bundler = (() => {
  const cache = new Map();
  const pending = new Map();
  const MAX_ENTRIES = parseInt(process.env.RV_SSR_BUNDLE_CACHE || "20", 10);

  function cacheKeyFor(componentPath) {
    const stats = fs.statSync(componentPath);
    return `${componentPath}:${stats.mtimeMs}:${NODE_ENV}`;
  }

  async function loadComponent(componentPath) {
    const key = cacheKeyFor(componentPath);
    const cached = cache.get(key);
    if (cached) {
      cached.lastUsed = Date.now();
      return cached.component;
    }

    if (pending.has(key)) {
      const bundle = await pending.get(key);
      bundle.lastUsed = Date.now();
      return bundle.component;
    }

    const buildPromise = bundleComponent(componentPath, key)
      .then((bundle) => {
        removeExistingEntries(componentPath, key);
        cache.set(key, bundle);
        pruneCache();
        pending.delete(key);
        return bundle;
      })
      .catch((error) => {
        pending.delete(key);
        throw error;
      });

    pending.set(key, buildPromise);
    const bundle = await buildPromise;
    return bundle.component;
  }

  async function bundleComponent(componentPath, cacheKey) {
    const tempDir = join(PROJECT_ROOT, "tmp", "reactive_views_ssr");
    if (!fs.existsSync(tempDir)) {
      fs.mkdirSync(tempDir, { recursive: true });
    }

    const entryFile = join(
      tempDir,
      `entry_${Date.now()}_${Math.random().toString(36).slice(2)}.cjs`
    );
    const outFile = entryFile.replace(".cjs", ".out.cjs");

    const normalizedPath = componentPath.replace(/\\/g, "/");
    const entryContent = `
const React = require('react');
const Component = require('${normalizedPath}').default || require('${normalizedPath}');

exports.default = Component;
`;

    fs.writeFileSync(entryFile, entryContent);

    try {
      await esbuild.build({
        entryPoints: [entryFile],
        bundle: true,
        format: "cjs",
        platform: "node",
        outfile: outFile,
        external: [
          "react",
          "react-dom",
          "react/jsx-runtime",
          "react/jsx-dev-runtime",
        ],
        jsx: "transform",
        jsxFactory: "React.createElement",
        jsxFragment: "React.Fragment",
        loader: {
          ".tsx": "tsx",
          ".ts": "ts",
          ".jsx": "jsx",
          ".js": "jsx",
        },
        logLevel: "warning",
      });

      const React = projectRequire("react");
      global.React = React;
      delete projectRequire.cache[projectRequire.resolve(outFile)];
      const Component = projectRequire(outFile).default;
      delete global.React;

      safeUnlink(entryFile);

      return {
        component: Component,
        componentPath,
        cacheKey,
        bundlePath: outFile,
        lastUsed: Date.now(),
      };
    } catch (error) {
      safeUnlink(entryFile);
      safeUnlink(outFile);
      throw error;
    }
  }

  function removeExistingEntries(componentPath, currentKey) {
    for (const [key, entry] of cache.entries()) {
      if (entry.componentPath === componentPath && key !== currentKey) {
        cleanupBundle(entry);
        cache.delete(key);
      }
    }
  }

  function pruneCache() {
    if (cache.size <= MAX_ENTRIES) {
      return;
    }

    while (cache.size > MAX_ENTRIES) {
      let oldestKey = null;
      let oldestTime = Infinity;

      for (const [key, entry] of cache.entries()) {
        if (entry.lastUsed < oldestTime) {
          oldestKey = key;
          oldestTime = entry.lastUsed;
        }
      }

      if (oldestKey) {
        const entry = cache.get(oldestKey);
        cleanupBundle(entry);
        cache.delete(oldestKey);
      } else {
        break;
      }
    }
  }

  function cleanupBundle(entry) {
    if (entry?.bundlePath && fs.existsSync(entry.bundlePath)) {
      safeUnlink(entry.bundlePath);
    }
  }

  function safeUnlink(path) {
    if (!path) return;
    try {
      if (fs.existsSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (error) {
      // Ignore cleanup errors
    }
  }

  function clear() {
    for (const entry of cache.values()) {
      cleanupBundle(entry);
    }
    cache.clear();
  }

  return { loadComponent, clear };
})();

// Render a component using React's server-side rendering
async function renderComponent(componentPath, props) {
  if (!fs.existsSync(componentPath)) {
    throw new Error(`Component file not found: ${componentPath}`);
  }

  console.log(`[ReactiveViews SSR] Rendering component from ${componentPath}`);

  const Component = await Bundler.loadComponent(componentPath);
  const React = projectRequire("react");
  const { renderToString } = projectRequire("react-dom/server");

  global.React = React;
  try {
    const element = React.createElement(Component, props);
    return renderToString(element);
  } finally {
    delete global.React;
  }
}

// Render a component tree with true React composition
// treeSpec: { componentPath, props, children: [...], htmlChildren: string }
async function renderComponentTree(treeSpec) {
  // Load React from the project
  const React = projectRequire("react");
  const { renderToString } = projectRequire("react-dom/server");

  // Make React available globally
  global.React = React;

  try {
    // Build the React element tree
    const element = await buildReactTree(treeSpec, React);
    
    // Render the entire tree as one
    const html = renderToString(element);
    
    return html;
  } finally {
    // Clean up global
    delete global.React;
  }
}

// Recursively build a React element tree
// treeSpec: { componentPath, props, children: [...], htmlChildren: string }
async function buildReactTree(treeSpec, React) {
  const { componentPath, props, children, htmlChildren } = treeSpec;

  // Verify the component file exists
  if (!fs.existsSync(componentPath)) {
    throw new Error(`Component file not found: ${componentPath}`);
  }

  console.log(`[ReactiveViews SSR] Building tree for ${componentPath}`);

  // Bundle and load the component
  const Component = await Bundler.loadComponent(componentPath);

  // Build child React elements in parallel (siblings render in parallel)
  const childElements = children?.length
    ? await Promise.all(children.map((child) => buildReactTree(child, React)))
    : [];

  // Combine React elements with HTML children
  let allChildren = [...childElements];
  
  // If there's HTML content, add it as a dangerously set inner HTML element
  // This preserves mixed content like <Component><div>foo</div><AnotherComponent /></Component>
  if (htmlChildren && htmlChildren.trim()) {
    // Parse HTML children and create elements
    // For now, we'll use dangerouslySetInnerHTML for HTML content
    allChildren.push(
      React.createElement("div", {
        dangerouslySetInnerHTML: { __html: htmlChildren },
      })
    );
  }

  // Create the React element with all children
  return React.createElement(Component, props || {}, ...allChildren);
}

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function readJsonBody(req, { maxBytes = 1_000_000 } = {}) {
  return new Promise((resolve, reject) => {
    let body = "";
    let received = 0;

    req.on("data", (chunk) => {
      received += chunk.length;
      if (received > maxBytes) {
        reject(new HttpError(413, "Payload too large"));
        req.destroy();
        return;
      }
      body += chunk.toString();
    });

    req.on("end", () => {
      if (!body) {
        resolve({});
        return;
      }

      try {
        resolve(JSON.parse(body));
      } catch {
        reject(new HttpError(400, "Invalid JSON payload"));
      }
    });

    req.on("error", (error) => reject(error));
  });
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, { "Content-Type": "application/json" });
  res.end(JSON.stringify(payload));
}


const Router = {
  async handle(req, res) {
    this.addCors(res);

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    try {
      if (req.method === "GET" && req.url === "/health") {
        sendJson(res, 200, { status: "ok", version: "1.0.0" });
        return;
      }

      if (req.method === "POST" && req.url === "/infer-props") {
        await this.handleInferProps(req, res);
        return;
      }

      if (req.method === "POST" && req.url === "/batch-render") {
        await this.handleBatchRender(req, res);
        return;
      }

      if (req.method === "POST" && req.url === "/render-tree") {
        await this.handleTreeRender(req, res);
        return;
      }

      if (req.method === "POST" && req.url === "/render") {
        await this.handleRender(req, res);
        return;
      }

      sendJson(res, 404, { error: "Not found" });
    } catch (error) {
      this.handleError(res, error);
    }
  },

  addCors(res) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  },

  async handleInferProps(req, res) {
    const { tsxContent, contentHash, extension } = await readJsonBody(req, {
      maxBytes: 256 * 1024,
    });

    if (!tsxContent) {
      throw new HttpError(400, "Missing tsxContent");
    }

    const keys = PropsInference.infer(
      tsxContent,
      contentHash,
      extension || "tsx"
    );

    sendJson(res, 200, { keys });
  },

  async handleBatchRender(req, res) {
    const { components } = await readJsonBody(req);

    if (!Array.isArray(components)) {
      throw new HttpError(400, "Expected components array");
    }

    const results = await Promise.all(
      components.map(async ({ componentPath, props }) => {
        try {
          if (!componentPath) {
            return { error: "Missing componentPath" };
          }

          const html = await renderComponent(componentPath, props || {});
          return { html };
        } catch (error) {
          console.error(
            `[ReactiveViews SSR] Error rendering ${componentPath}:`,
            error
          );
          return {
            error: error.message,
            props: IS_DEV ? props : undefined,
          };
        }
      })
    );

    sendJson(res, 200, { results });
  },

  async handleTreeRender(req, res) {
    const treeSpec = await readJsonBody(req);

    if (!treeSpec.componentPath) {
      throw new HttpError(400, "Missing componentPath");
    }

    const html = await renderComponentTree(treeSpec);
    sendJson(res, 200, { html });
  },

  async handleRender(req, res) {
    const { componentPath, props } = await readJsonBody(req);

    if (!componentPath) {
      throw new HttpError(400, "Missing componentPath");
    }

    const html = await renderComponent(componentPath, props || {});
    sendJson(res, 200, { html });
  },

  handleError(res, error) {
    if (error instanceof HttpError) {
      sendJson(res, error.status, { error: error.message });
      return;
    }

    console.error("[ReactiveViews SSR] Unexpected error:", error);
    sendJson(res, 500, {
      error: error.message,
      stack: IS_DEV ? error.stack : undefined,
    });
  },
};

const server = http.createServer((req, res) => Router.handle(req, res));

server.listen(PORT, () => {
  console.log(
    `[ReactiveViews SSR] Server listening on http://localhost:${PORT}`
  );
  console.log(`[ReactiveViews SSR] Ready to render components!`);
});

// Graceful shutdown
process.on("SIGTERM", () => {
  console.log("[ReactiveViews SSR] Shutting down gracefully...");
  server.close(() => {
    Bundler.clear();
    console.log("[ReactiveViews SSR] Server closed");
    process.exit(0);
  });
});

process.on("SIGINT", () => {
  console.log("[ReactiveViews SSR] Shutting down gracefully...");
  server.close(() => {
    Bundler.clear();
    console.log("[ReactiveViews SSR] Server closed");
    process.exit(0);
  });
});
