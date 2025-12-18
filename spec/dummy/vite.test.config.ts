import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

const port = parseInt(process.env.RV_VITE_PORT || '5174');
const dummyRoot = __dirname;
const sourceRoot = path.resolve(dummyRoot, 'app/javascript');

// Test configuration - simplified for running specs
export default defineConfig({
  // Align with vite-ruby test config (publicOutputDir = vite-test, sourceCodeDir = app/javascript)
  root: sourceRoot,
  base: '/vite-test/',
  plugins: [react()],

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
    manifest: true,
    rollupOptions: {
      input: {
        application: path.resolve(sourceRoot, 'entrypoints/application.js'),
      },
    },
  },

  optimizeDeps: {
    include: ['react', 'react-dom', '@hotwired/turbo-rails', '@hotwired/stimulus'],
  },
});
