import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';

const basePath = process.env.VITE_BASE_PATH ?? '/';

export default defineConfig({
  base: basePath,
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      manifest: {
        name: 'AI Stock Take Control System',
        short_name: 'Stock Take',
        description: 'Offline-first warehouse stock taking',
        display: 'standalone',
        start_url: basePath,
        scope: basePath,
        background_color: '#f8fafc',
        theme_color: '#0f172a',
      },
    }),
  ],
});
