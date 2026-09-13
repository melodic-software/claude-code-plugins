import { defineConfig } from '@playwright/test';

// cant-fail-ok: flaky retries accepted, tracked in the dashboard
export default defineConfig({
  testDir: './tests',
  forbidOnly: !!process.env.CI,
  retries: 2,
});
