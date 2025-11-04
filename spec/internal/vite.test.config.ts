import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

const port = parseInt(process.env.RV_VITE_PORT || '5174');

export default defineConfig({
  plugins: [react()],
  root: __dirname,
  server: {
    port,
    strictPort: true,
    host: '0.0.0.0',  // Allow connections from test environment
  },
  resolve: {
    alias: {
      '@components': path.resolve(__dirname, 'app/views/components'),
    },
  },
});

