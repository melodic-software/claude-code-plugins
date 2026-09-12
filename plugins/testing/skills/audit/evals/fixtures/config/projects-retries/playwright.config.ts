import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  forbidOnly: true,
  projects: [
    {
      name: 'chromium',
      retries: 2,
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      retries: 2,
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      retries: 2,
      use: { ...devices['Desktop Safari'] },
    },
  ],
});
