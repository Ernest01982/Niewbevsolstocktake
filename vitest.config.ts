import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      enabled: false,
      provider: 'v8',
    },
    environment: 'node',
    include: ['apps/**/*.test.ts', 'apps/**/*.test.tsx'],
  },
});
