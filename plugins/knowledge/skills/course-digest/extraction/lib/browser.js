/**
 * Shared browser infrastructure for course-extraction scripts: browser
 * launch, cookie injection, and auth age checking.
 */

import { existsSync, statSync } from "node:fs";

import { writeStdout } from "@melodic/video-digestion/shared/terminal";
import { chromium } from "playwright";

import { injectSavedCookies } from "../utils.js";

const DEFAULT_AUTH_WARN_DAYS = 6;

/**
 * Check auth state freshness and warn if stale.
 * @param {string} storageStatePath
 * @param {object} platformCfg
 */
export function checkAuthAge(storageStatePath, platformCfg) {
  if (!existsSync(storageStatePath)) return;
  const stat = statSync(storageStatePath);
  const ageDays = (Date.now() - stat.mtimeMs) / (1000 * 60 * 60 * 24);
  const warnDays = platformCfg.authWarnDays ?? DEFAULT_AUTH_WARN_DAYS;
  if (ageDays > warnDays) {
    const provider = platformCfg.authProvider ?? "platform";
    writeStdout(
      `  ⚠ Auth state is ${Math.round(ageDays)} days old (${provider} sessions may have expired).`,
    );
    writeStdout("  Re-authentication may be needed.\n");
  }
}

/**
 * Launch a Playwright browser.
 * Returns the browser, context, page, and injected cookie count.
 *
 * @param {object} options
 * @param {boolean} [options.headless=true]
 * @param {string} [options.storageStatePath] - path to .auth-state.json
 * @returns {Promise<{browser: import('playwright').Browser, context: import('playwright').BrowserContext, page: import('playwright').Page, cookieCount: number}>}
 */
export async function launchBrowser({ headless = true, storageStatePath } = {}) {
  // Not launchPersistentContext: persistent contexts may not fire
  // page.on("request"/"response") for cross-origin iframe sub-resources.
  const browser = await chromium.launch({
    headless,
    timeout: 60000,
    args: [
      "--disable-blink-features=AutomationControlled",
      "--autoplay-policy=no-user-gesture-required",
    ],
  });
  const context = await browser.newContext();
  const page = await context.newPage();

  const cookieCount = storageStatePath ? await injectSavedCookies(context, storageStatePath) : 0;

  return { browser, context, page, cookieCount };
}

/**
 * Close the browser context and the browser.
 * @param {import('playwright').BrowserContext} context
 * @param {import('playwright').Browser} [browser]
 */
export async function closeBrowser(context, browser) {
  await context.close();
  if (browser) await browser.close().catch(() => {});
}
