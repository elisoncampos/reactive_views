import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

const port = parseInt(process.env.RV_VITE_PORT || '5174');
const dummyRoot = import.meta.dirname;
const sourceRoot = path.resolve(dummyRoot, 'app/javascript');

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  const isProduction = mode === 'production';

  return {
    // Align with vite-ruby (sourceCodeDir = app/javascript)
    // so manifest keys are like "entrypoints/application.js" (not "app/javascript/...").
    root: sourceRoot,
    plugins: [react()],

    // Base path for assets - can be overridden via ASSET_HOST env var for CDN
    base: env.ASSET_HOST ? `${env.ASSET_HOST}/vite/` : '/vite/',

    server: {
      port,
      strictPort: true,
      host: 'localhost',
    },

    resolve: {
      alias: {
        '@components': path.resolve(dummyRoot, 'app/views/components'),
      },
    },

    build: {
      // Modern browsers only in production for smaller bundles
      target: isProduction ? 'es2022' : 'esnext',

      // Generate manifest for Rails integration
      manifest: true,

      // Single CSS file for simpler loading order
      cssCodeSplit: false,

      // Source maps in production for debugging (can be disabled)
      sourcemap: env.VITE_SOURCEMAP !== 'false',

      // Output directory relative to root (app/javascript)
      outDir: path.resolve(dummyRoot, 'public/vite'),

      // Clean output directory before build
      emptyOutDir: true,

      rollupOptions: {
        input: {
          application: path.resolve(sourceRoot, 'entrypoints/application.js'),
        },
        output: {
          // Consistent naming with content hashes for cache busting
          entryFileNames: 'assets/[name]-[hash].js',
          chunkFileNames: 'assets/[name]-[hash].js',
          assetFileNames: 'assets/[name]-[hash][extname]',
          // Keep hashes hex so production specs can validate fingerprints deterministically
          hashCharacters: 'hex',
        },
      },

      // Increase chunk size warning threshold
      chunkSizeWarningLimit: 1000,
    },

    // CSS configuration
    css: {
      // Enable CSS modules for .module.css files
      modules: {
        localsConvention: 'camelCase',
      },
      // PostCSS configuration
      postcss: './postcss.config.js',
    },

    // Optimize deps for faster dev server startup
    optimizeDeps: {
      include: ['react', 'react-dom', '@hotwired/turbo-rails', '@hotwired/stimulus'],
    },
  };
});

