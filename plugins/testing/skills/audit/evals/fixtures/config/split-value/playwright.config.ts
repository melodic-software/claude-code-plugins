import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  forbidOnly: true,
  retries: process.env.CI
    ? 2 : 0,
});
