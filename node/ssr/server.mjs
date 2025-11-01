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
