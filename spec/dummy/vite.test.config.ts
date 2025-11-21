import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

const port = parseInt(process.env.RV_VITE_PORT || '5174');

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
    rollupOptions: {
      input: {
        boot: path.resolve(__dirname, 'app/javascript/boot.tsx'),
      },
    },
  },
});
