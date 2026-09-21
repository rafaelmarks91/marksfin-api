import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['test/**/*.test.ts'],
    globals: false,
    env: {
      NODE_ENV: 'test',
      DATABASE_URL: 'mysql://marksfin:marksfin@localhost:3306/marksfin_test',
      SESSION_SECRET: 'test-only-session-secret-please-change',
    },
  },
});
