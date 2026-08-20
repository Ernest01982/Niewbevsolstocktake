import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'prompt',
      manifest: {
        name: 'AI Stock Take Control System',
        short_name: 'Stock Take',
        description: 'Offline-first warehouse stock taking',
        display: 'standalone',
        start_url: '/',
        background_color: '#f8fafc',
        theme_color: '#0f172a',
      },
    }),
  ],
});
