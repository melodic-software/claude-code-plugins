import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  forbidOnly: true,
  reporter: [['./r', { retries: 5 }]],
});
