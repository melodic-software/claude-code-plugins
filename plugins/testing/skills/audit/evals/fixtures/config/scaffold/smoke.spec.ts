import { expect, test } from '@playwright/test';

test('home page states its own title', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveTitle('Example Domain');
});
