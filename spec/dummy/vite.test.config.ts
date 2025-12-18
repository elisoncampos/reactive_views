import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

const port = parseInt(process.env.RV_VITE_PORT || '5174');

// Test configuration - simplified for running specs
export default defineConfig({
  plugins: [react()],

  server: {
    port,
    strictPort: true,
    host: 'localhost',
  },

  resolve: {
    alias: {
      '@components': path.resolve(__dirname, 'app/views/components'),
    },
  },

  build: {
    manifest: true,
    rollupOptions: {
      input: {
        application: path.resolve(__dirname, 'app/javascript/entrypoints/application.js'),
      },
    },
  },

  optimizeDeps: {
    include: ['react', 'react-dom', '@hotwired/turbo-rails', '@hotwired/stimulus'],
  },
});
