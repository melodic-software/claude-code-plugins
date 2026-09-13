import { defineConfig } from '@playwright/test';

export default defineConfig({
  forbidOnly: true,
  projects: [{ name: 'chromium' }],
  webServer
    : { env: { retries: 3 } },
});
