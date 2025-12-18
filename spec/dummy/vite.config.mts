import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

const port = parseInt(process.env.RV_VITE_PORT || '5174');

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  const isProduction = mode === 'production';

  return {
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
        '@components': path.resolve(import.meta.dirname, 'app/views/components'),
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

      // Output directory relative to public/
      outDir: 'public/vite',

      // Clean output directory before build
      emptyOutDir: true,

      rollupOptions: {
        input: {
          application: path.resolve(import.meta.dirname, 'app/javascript/entrypoints/application.js'),
        },
        output: {
          // Consistent naming with content hashes for cache busting
          entryFileNames: 'assets/[name]-[hash].js',
          chunkFileNames: 'assets/[name]-[hash].js',
          assetFileNames: 'assets/[name]-[hash][extname]',
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

