/**
 * Shared browser infrastructure for course-extraction scripts.
 *
 * Consolidates duplicated browser launch, cookie injection, and auth age
 * checking from extract-course.js and discover-resources.js.
 */

import { existsSync, mkdirSync, statSync } from "node:fs";
import { rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

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
 * Launch a Playwright browser with a fresh temp profile.
 * Returns the context, page, auth dir path, and injected cookie count.
 *
 * @param {object} options
 * @param {boolean} [options.headless=true]
 * @param {string} [options.storageStatePath] — path to .auth-state.json
 * @param {string} [options.profilePrefix="course-extraction"] — temp dir prefix
 * @returns {Promise<{browser: import('playwright').Browser, context: import('playwright').BrowserContext, page: import('playwright').Page, authDir: string, cookieCount: number}>}
 */
export async function launchBrowser({
  headless = true,
  storageStatePath,
  profilePrefix = "course-extraction",
} = {}) {
  const authDir = join(tmpdir(), `${profilePrefix}-${Date.now()}`);
  mkdirSync(authDir, { recursive: true });

  // Use browser.launch + newContext instead of launchPersistentContext.
  // Persistent contexts handle cross-origin iframe events differently —
  // page.on("request"/"response") may not fire for iframe sub-resources.
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

  let cookieCount = 0;
  if (storageStatePath) {
    cookieCount = await injectSavedCookies(context, storageStatePath);
  }

  return { browser, context, page, authDir, cookieCount };
}

/**
 * Close the browser and clean up the temp profile directory.
 * @param {import('playwright').BrowserContext} context
 * @param {string} authDir
 * @param {import('playwright').Browser} [browser]
 */
export async function closeBrowser(context, authDir, browser) {
  await context.close();
  if (browser) await browser.close().catch(() => {});
  rm(authDir, { recursive: true, force: true }).catch(() => {});
}
