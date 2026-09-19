import { defineConfig } from '@playwright/test';
import { overrides } from './overrides';

export default defineConfig({ testDir: 'e2e' }, overrides);
