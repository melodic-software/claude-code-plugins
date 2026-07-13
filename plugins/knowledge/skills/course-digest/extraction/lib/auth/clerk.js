/**
 * Clerk authentication flow.
 *
 * Two-step Clerk login: identifier input → Continue → password input → Continue.
 * Used by Dometrain and any future platform using Clerk for auth.
 */

import {
  CONTINUE_OR_SUBMIT_BUTTON,
  IDENTIFIER_INPUT_SELECTOR,
  PASSWORD_INPUT_SELECTOR,
} from "../playwright-selectors.js";

/**
 * Perform Clerk two-step login.
 *
 * @param {import('playwright').Page} page
 * @param {string} email
 * @param {string} password
 * @param {string} loginUrl
 */
export async function login(page, email, password, loginUrl) {
  await page.goto(loginUrl, { waitUntil: "networkidle", timeout: 15000 });
  await page.waitForTimeout(2000);

  await page.locator(IDENTIFIER_INPUT_SELECTOR).fill(email);
  await page.locator(CONTINUE_OR_SUBMIT_BUTTON).first().click();
  await page.waitForTimeout(2000);

  await page.locator(PASSWORD_INPUT_SELECTOR).fill(password);
  await page.locator(CONTINUE_OR_SUBMIT_BUTTON).first().click();
  await page.waitForLoadState("networkidle", { timeout: 15000 });
  await page.waitForTimeout(3000);
}
