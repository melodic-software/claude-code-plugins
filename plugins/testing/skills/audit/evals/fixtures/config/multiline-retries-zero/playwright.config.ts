import { defineConfig } from '@playwright/test';

export default defineConfig({
  failOnFlakyTests: true,
  forbidOnly: true,
  retries:
    0,
});
