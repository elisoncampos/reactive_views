#!/usr/bin/env node

import http from "http";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import fs from "fs";
import { createRequire } from "module";

// Configuration from environment
const PORT = parseInt(process.env.RV_SSR_PORT || "5175", 10);
const VITE_PORT = parseInt(process.env.RV_VITE_PORT || "5174", 10);

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

// Props inference cache (keyed by content hash)
const propsInferenceCache = new Map();

// Lazy-load TypeScript compiler for props inference
let ts = null;
async function getTypeScript() {
  if (!ts) {
    ts = await import(projectRequire.resolve("typescript"));
  }
  return ts;
}

/**
 * Infer prop keys from TSX component signature
 * Supports: export default function Component({ a, b }: Props) {}
 * Supports: const Component = ({ a, b }: Props) => {}; export default Component
 */
function inferPropsFromTSX(tsxContent, contentHash) {
  // Check cache first
  if (propsInferenceCache.has(contentHash)) {
    console.log(`[ReactiveViews SSR] Props inference cache hit for ${contentHash}`);
    return propsInferenceCache.get(contentHash);
  }

  try {
    // Use synchronous import for typescript
    const typescript = projectRequire("typescript");
    
    // Parse TSX source
    const sourceFile = typescript.createSourceFile(
      "component.tsx",
      tsxContent,
      typescript.ScriptTarget.Latest,
      true,
      typescript.ScriptKind.TSX
    );

    const keys = [];

    // Find default export and extract prop destructuring
    function visit(node) {
      // Case 1: export default function Component({ a, b }: Props) {}
      if (
        typescript.isFunctionDeclaration(node) &&
        node.modifiers?.some(
          (m) => m.kind === typescript.SyntaxKind.ExportKeyword ||
                 m.kind === typescript.SyntaxKind.DefaultKeyword
        )
      ) {
        extractPropsFromFunction(node);
      }

      // Case 2: export default Component (find Component declaration)
      if (
        typescript.isExportAssignment(node) &&
        typescript.isIdentifier(node.expression)
      ) {
        const componentName = node.expression.text;
        // Find the variable/function declaration
        typescript.forEachChild(sourceFile, (child) => {
          if (
            typescript.isVariableStatement(child) &&
            child.declarationList.declarations.some(
              (d) => typescript.isIdentifier(d.name) && d.name.text === componentName
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
                } else if (typescript.isFunctionExpression(decl.initializer)) {
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
            if (typescript.isBindingElement(element) && typescript.isIdentifier(element.name)) {
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
            if (typescript.isBindingElement(element) && typescript.isIdentifier(element.name)) {
              keys.push(element.name.text);
            }
          });
        }
      }
    }

    visit(sourceFile);

    console.log(`[ReactiveViews SSR] Inferred props: ${keys.join(", ")}`);
    
    // Cache the result
    propsInferenceCache.set(contentHash, keys);
    
    return keys;
  } catch (error) {
    console.error(`[ReactiveViews SSR] Props inference error:`, error);
    return [];
  }
}

// Render a component using React's server-side rendering
async function renderComponent(componentPath, props) {
  // Verify the component file exists
  if (!fs.existsSync(componentPath)) {
    throw new Error(`Component file not found: ${componentPath}`);
  }

  console.log(`[ReactiveViews SSR] Rendering component from ${componentPath}`);

  // Create a temporary entry file that imports React and the component
  const tempDir = join(PROJECT_ROOT, "tmp", "reactive_views_ssr");
  if (!fs.existsSync(tempDir)) {
    fs.mkdirSync(tempDir, { recursive: true });
  }

  const entryFile = join(
    tempDir,
    `entry_${Date.now()}_${Math.random().toString(36).slice(2)}.cjs`
  );
  const outFile = entryFile.replace(".cjs", ".out.cjs");

  // Create entry file that imports React and the component
  // React is marked external so it won't be bundled
  const entryContent = `
const React = require('react');
const Component = require('${componentPath.replace(
    /\\/g,
    "/"
  )}').default || require('${componentPath.replace(/\\/g, "/")}');

exports.default = Component;
`;

  fs.writeFileSync(entryFile, entryContent);

  try {
    // Bundle the component with esbuild
    // Keep React external and load it at runtime
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

    // Load React from the project
    const React = projectRequire("react");
    const { renderToString } = projectRequire("react-dom/server");

    // Make React available globally for the bundled component
    global.React = React;

    // Clear cache and load the bundled component
    delete projectRequire.cache[projectRequire.resolve(outFile)];
    const Component = projectRequire(outFile).default;

    const element = React.createElement(Component, props);
    const html = renderToString(element);

    // Clean up global
    delete global.React;

    // Cleanup
    try {
      fs.unlinkSync(entryFile);
      fs.unlinkSync(outFile);
    } catch (e) {
      // Ignore cleanup errors
    }

    return html;
  } catch (error) {
    // Cleanup on error
    try {
      fs.unlinkSync(entryFile);
      if (fs.existsSync(outFile)) {
        fs.unlinkSync(outFile);
      }
    } catch (e) {
      // Ignore cleanup errors
    }
    throw error;
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
  const Component = await loadComponent(componentPath);

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

// Load and bundle a component, returning the Component function
async function loadComponent(componentPath) {
  const tempDir = join(PROJECT_ROOT, "tmp", "reactive_views_ssr");
  if (!fs.existsSync(tempDir)) {
    fs.mkdirSync(tempDir, { recursive: true });
  }

  const entryFile = join(
    tempDir,
    `entry_${Date.now()}_${Math.random().toString(36).slice(2)}.cjs`
  );
  const outFile = entryFile.replace(".cjs", ".out.cjs");

  // Create entry file that imports React and the component
  const entryContent = `
const React = require('react');
const Component = require('${componentPath.replace(
    /\\/g,
    "/"
  )}').default || require('${componentPath.replace(/\\/g, "/")}');

exports.default = Component;
`;

  fs.writeFileSync(entryFile, entryContent);

  try {
    // Bundle the component with esbuild
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

    // Clear cache and load the bundled component
    delete projectRequire.cache[projectRequire.resolve(outFile)];
    const Component = projectRequire(outFile).default;

    // Cleanup
    try {
      fs.unlinkSync(entryFile);
      fs.unlinkSync(outFile);
    } catch (e) {
      // Ignore cleanup errors
    }

    return Component;
  } catch (error) {
    // Cleanup on error
    try {
      fs.unlinkSync(entryFile);
      if (fs.existsSync(outFile)) {
        fs.unlinkSync(outFile);
      }
    } catch (e) {
      // Ignore cleanup errors
    }
    throw error;
  }
}

// HTTP server
const server = http.createServer(async (req, res) => {
  // Enable CORS for development
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  // Handle OPTIONS preflight
  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  // Health check endpoint
  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok", version: "1.0.0" }));
    return;
  }

  // Props inference endpoint
  // Request: { tsxContent, contentHash }
  // Response: { keys: [...] }
  if (req.method === "POST" && req.url === "/infer-props") {
    let body = "";

    req.on("data", (chunk) => {
      body += chunk.toString();
    });

    req.on("end", async () => {
      try {
        const { tsxContent, contentHash } = JSON.parse(body);

        if (!tsxContent) {
          res.writeHead(400, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Missing tsxContent" }));
          return;
        }

        const keys = inferPropsFromTSX(tsxContent, contentHash);

        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ keys }));
      } catch (error) {
        console.error("[ReactiveViews SSR] Props inference error:", error);

        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(
          JSON.stringify({
            error: error.message,
            stack:
              process.env.NODE_ENV === "development" ? error.stack : undefined,
          })
        );
      }
    });

    return;
  }

  // Batch render endpoint - renders multiple components in parallel
  // Request: { components: [{ componentPath, props }, ...] }
  // Response: { results: [{ html } | { error }, ...] }
  //
  // This endpoint significantly improves performance by:
  // - Reducing HTTP overhead (N requests -> 1 request)
  // - Enabling parallel component rendering with Promise.all
  // - Maintaining order of results to match input order
  if (req.method === "POST" && req.url === "/batch-render") {
    let body = "";

    req.on("data", (chunk) => {
      body += chunk.toString();
    });

    req.on("end", async () => {
      try {
        const { components } = JSON.parse(body);

        if (!Array.isArray(components)) {
          res.writeHead(400, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Expected components array" }));
          return;
        }

        // Render all components in parallel using Promise.all
        // Individual component failures don't fail the entire batch
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
                props:
                  process.env.NODE_ENV === "development" ? props : undefined,
              };
            }
          })
        );

        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ results }));
      } catch (error) {
        console.error("[ReactiveViews SSR] Batch render error:", error);

        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(
          JSON.stringify({
            error: error.message,
            stack:
              process.env.NODE_ENV === "development" ? error.stack : undefined,
          })
        );
      }
    });

    return;
  }

  // Tree render endpoint - renders a component tree with true React composition
  // Request: { componentPath, props, children: [...], htmlChildren: string }
  // Response: { html } | { error }
  //
  // This endpoint enables true React composition by:
  // - Building a complete React element tree
  // - Importing all components in parallel (siblings)
  // - Rendering as a single React tree (children prop works naturally)
  if (req.method === "POST" && req.url === "/render-tree") {
    let body = "";

    req.on("data", (chunk) => {
      body += chunk.toString();
    });

    req.on("end", async () => {
      try {
        const treeSpec = JSON.parse(body);

        if (!treeSpec.componentPath) {
          res.writeHead(400, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Missing componentPath" }));
          return;
        }

        // Build React element tree recursively
        const html = await renderComponentTree(treeSpec);

        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ html }));
      } catch (error) {
        console.error("[ReactiveViews SSR] Tree render error:", error);

        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(
          JSON.stringify({
            error: error.message,
            stack:
              process.env.NODE_ENV === "development" ? error.stack : undefined,
          })
        );
      }
    });

    return;
  }

  // Render endpoint
  if (req.method === "POST" && req.url === "/render") {
    let body = "";

    req.on("data", (chunk) => {
      body += chunk.toString();
    });

    req.on("end", async () => {
      try {
        const { componentPath, props } = JSON.parse(body);

        if (!componentPath) {
          res.writeHead(400, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Missing componentPath" }));
          return;
        }

        const html = await renderComponent(componentPath, props || {});

        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ html }));
      } catch (error) {
        console.error("[ReactiveViews SSR] Render error:", error);

        // Parse request to get props for error reporting
        let errorProps = {};
        try {
          const { props } = JSON.parse(body);
          errorProps = props;
        } catch (e) {
          // Ignore parse errors in error handler
        }

        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(
          JSON.stringify({
            error: error.message,
            props:
              process.env.NODE_ENV === "development" ? errorProps : undefined,
            stack:
              process.env.NODE_ENV === "development" ? error.stack : undefined,
          })
        );
      }
    });

    return;
  }

  // 404 for other routes
  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "Not found" }));
});

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
    console.log("[ReactiveViews SSR] Server closed");
    process.exit(0);
  });
});

process.on("SIGINT", () => {
  console.log("[ReactiveViews SSR] Shutting down gracefully...");
  server.close(() => {
    console.log("[ReactiveViews SSR] Server closed");
    process.exit(0);
  });
});
