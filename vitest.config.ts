import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['test/**/*.test.ts'],
    globals: false,
    env: {
      NODE_ENV: 'test',
      DB_HOST: 'localhost',
      DB_PORT: '3306',
      DB_USER: 'marksfin',
      DB_PASSWORD: 'marksfin',
      DB_NAME: 'marksfin_test',
      SESSION_SECRET: 'test-only-session-secret-please-change',
    },
  },
});
