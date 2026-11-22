// Holds a scheduled tick of the lost-run reconciler until just after the
// GITHUB_TOKEN window resets, so each hourly pass re-runs what a defer gate
// stopped until that reset at the start of the next window, wherever the
// reset has drifted to in the hour
// (https://github.com/melodic-software/claude-code-plugins/issues/17460).
// One GET /rate_limit, which GitHub does not count against the core pool
// (https://docs.github.com/en/rest/rate-limit/rate-limit#get-rate-limit-status-for-the-authenticated-user),
// names the reset. A window that began at most RUN_NOW_MINUTES ago runs the
// pass now; any other waits until GRACE_SECONDS past the reset ahead. Either
// way post-reset=true, so the pacer is skipped: the pass spends the fresh
// window. Any other event, or a read that fails, waits for nothing and writes
// post-reset=false, so the tick runs as before.

import { appendFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as sleep } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { readingOf } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { WINDOW_SECONDS } from "../../actions/check-kill-switch/projection.mjs";
import { RATE_RESET_GRACE_MS } from "./reconcile.mjs";

export const RUN_NOW_MINUTES = 11;
const CLOCK_SLACK_SECONDS = 30;
export const GRACE_SECONDS = RATE_RESET_GRACE_MS / 1000 + CLOCK_SLACK_SECONDS;

export function resetWait(reset, now) {
  const ahead = reset - now;
  if (!Number.isFinite(ahead) || ahead < 0 || ahead > WINDOW_SECONDS) {
    return null;
  }
  const since = WINDOW_SECONDS - ahead;
  return since <= RUN_NOW_MINUTES * 60 ? Math.max(0, Math.ceil(GRACE_SECONDS - since)) : Math.ceil(ahead + GRACE_SECONDS);
}

export async function main(env = process.env, { fetchImpl = fetch, now = () => Date.now() / 1000, wait = (seconds) => sleep(seconds * 1000) } = {}) {
  let postReset = false;
  if (env.EVENT_NAME === "schedule") {
    try {
      const response = await fetchImpl(`${env.GITHUB_API_URL || "https://api.github.com"}/rate_limit`, {
        headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${env.GITHUB_TOKEN}`, "X-GitHub-Api-Version": "2022-11-28" },
        signal: AbortSignal.timeout(10_000),
      });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      const { reading } = readingOf(response.headers, await response.json().catch(() => null));
      const at = now();
      const seconds = resetWait(reading.reset, at);
      if (seconds === null) {
        throw new Error(`the reading names no reset inside the next window (reset=${reading.reset} now=${Math.floor(at)})`);
      }
      console.log(`::notice title=reset-wait::reset=${reading.reset} (${new Date(reading.reset * 1000).toISOString()}) now=${Math.floor(at)} wait_seconds=${seconds}`);
      await wait(seconds);
      postReset = true;
    } catch (error) {
      console.log(`::warning title=reset-wait::the GITHUB_TOKEN reset was not read (${String(error?.message ?? error).replace(/[\r\n%]/g, " ")}); the pass runs now, paced as before`);
    }
  }
  appendFileSync(env.GITHUB_OUTPUT, `post-reset=${postReset}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
