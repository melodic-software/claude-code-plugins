// Whether a scheduled tick of the lost-run reconciler runs its pass: the one
// that follows each GITHUB_TOKEN window's reset re-runs what a defer gate
// stopped until that reset, wherever the reset has drifted in the hour
// (https://github.com/melodic-software/claude-code-plugins/issues/17460).
// The pass cannot wait for the reset inside its run: check-trusted-trigger
// trusts a reconciler record only for a re-run that starts within WINDOW_MS
// of the reconciler run's start
// (https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/check-trusted-trigger/check-trusted-trigger.mjs),
// so the schedule ticks every 15 minutes and this step decides.
// One GET /rate_limit, which GitHub does not count against the core pool
// (https://docs.github.com/en/rest/rate-limit/rate-limit), names the reset.
// A window that began at most ELIGIBLE_MINUTES ago makes the tick due, once
// GRACE_SECONDS into it, with pass-after naming that moment for recent-pass.mjs,
// which skips the tick when a full pass already started after it; an older
// window makes it due=false. Any other event, or a read that fails, writes
// due=true with no pass-after, so the pass runs as before.

import { appendFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as sleep } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { readingOf } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { WINDOW_SECONDS } from "../../actions/check-kill-switch/projection.mjs";
import { RATE_RESET_GRACE_MS } from "./reconcile.mjs";

export const ELIGIBLE_MINUTES = 30;
const CLOCK_SLACK_SECONDS = 30;
export const GRACE_SECONDS = RATE_RESET_GRACE_MS / 1000 + CLOCK_SLACK_SECONDS;

export function tickPlan(reset, now) {
  const ahead = reset - now;
  if (!Number.isFinite(ahead) || ahead < 0 || ahead > WINDOW_SECONDS) {
    return null;
  }
  const since = WINDOW_SECONDS - ahead;
  if (since > ELIGIBLE_MINUTES * 60) {
    return { due: false, since };
  }
  return { due: true, since, wait: Math.max(0, Math.ceil(GRACE_SECONDS - since)), passAfter: reset - WINDOW_SECONDS + GRACE_SECONDS };
}

export async function main(env = process.env, { fetchImpl = fetch, now = () => Date.now() / 1000, wait = (seconds) => sleep(seconds * 1000) } = {}) {
  const outputs = { due: true, "post-reset": false, "pass-after": "" };
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
      const plan = tickPlan(reading.reset, at);
      if (plan === null) {
        throw new Error(`the reading names no reset inside the next window (reset=${reading.reset} now=${Math.floor(at)})`);
      }
      console.log(`::notice title=reset-tick::reset=${reading.reset} now=${Math.floor(at)} since_window_start=${Math.floor(plan.since)} due=${plan.due} wait_seconds=${plan.wait ?? 0}`);
      if (plan.due) {
        await wait(plan.wait);
        Object.assign(outputs, { "post-reset": true, "pass-after": plan.passAfter });
      } else {
        outputs.due = false;
      }
    } catch (error) {
      console.log(`::warning title=reset-tick::the GITHUB_TOKEN reset was not read (${String(error?.message ?? error).replace(/[\r\n%]/g, " ")}); the pass runs unless one ran in the last hour`);
    }
  }
  appendFileSync(env.GITHUB_OUTPUT, Object.entries(outputs).map(([name, value]) => `${name}=${value}\n`).join(""));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
