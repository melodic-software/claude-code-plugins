/**
 * Teachable SSO authentication flow.
 *
 * Simple form: email input + password input + submit button.
 * Used by Teachable-hosted course platforms.
 */

import {
  EMAIL_INPUT_SELECTOR,
  PASSWORD_INPUT_SELECTOR,
  SUBMIT_BUTTON_SELECTOR,
} from "../playwright-selectors.js";

/**
 * Perform Teachable SSO login.
 *
 * @param {import('playwright').Page} page
 * @param {string} email
 * @param {string} password
 * @param {string} loginUrl
 */
export async function login(page, email, password, loginUrl) {
  await page.goto(loginUrl, { waitUntil: "networkidle", timeout: 15000 });
  await page.waitForTimeout(2000);

  await page.locator(EMAIL_INPUT_SELECTOR).fill(email);
  await page.locator(PASSWORD_INPUT_SELECTOR).fill(password);

  await page.locator(SUBMIT_BUTTON_SELECTOR).first().click();
  await page.waitForLoadState("networkidle", { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(3000);
}
