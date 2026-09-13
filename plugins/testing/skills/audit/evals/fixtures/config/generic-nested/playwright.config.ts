import { defineConfig } from '@playwright/test';

export default defineConfig<Options<Extra>>({ retries: 2 });
