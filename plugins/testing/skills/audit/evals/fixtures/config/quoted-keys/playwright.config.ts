import { defineConfig } from '@playwright/test';

export default defineConfig({
  'forbidOnly': true,
  "failOnFlakyTests": true,
  retries: 1,
});
