import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  retries: 2,
  projects: [
    {
      name: 'chromium',
      forbidOnly: true,
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
