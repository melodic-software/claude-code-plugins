/**
 * Shared manual login fallback for adapters.
 *
 * When automated credentials are unavailable, prompts the user to
 * log in manually in the browser window and press Enter to continue.
 */

import { createInterface } from "node:readline/promises";

import { writeStdout } from "@melodic/video-digestion/shared/terminal";

/**
 * Prompt the user to log in manually and save auth state when done.
 *
 * @param {import('playwright').BrowserContext} context
 * @param {string} storageStatePath
 * @param {string} envPrefix — e.g. "COURSE" or "TEACHABLE"
 */
export async function promptManualLogin(context, storageStatePath, envPrefix) {
  writeStdout(`  Not authenticated. Set ${envPrefix}_EMAIL and ${envPrefix}_PASSWORD,`);
  writeStdout("  or log in manually in the browser window and press Enter.\n");
  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  await rl.question("  Press Enter when logged in: ");
  rl.close();
  await context.storageState({ path: storageStatePath });
  writeStdout("  Saved auth state for future runs.\n");
}
