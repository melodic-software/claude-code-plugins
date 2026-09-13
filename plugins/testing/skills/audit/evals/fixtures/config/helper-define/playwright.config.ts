import { defineConfig } from '@playwright/test';

const base = defineConfig({ retries: 2 });

export default defineConfig({ ...base, forbidOnly: true });
