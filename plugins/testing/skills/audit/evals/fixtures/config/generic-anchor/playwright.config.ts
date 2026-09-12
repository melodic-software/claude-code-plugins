import { defineConfig } from '@playwright/test';
import type { PlaywrightTestConfig } from '@playwright/test';

export default defineConfig<MyOptions>({ retries: 2 }) satisfies PlaywrightTestConfig;
