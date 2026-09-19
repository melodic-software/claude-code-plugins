import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  retries: 2,
  failOnFlakyTests:
    false,
  forbidOnly:
    false,
});
