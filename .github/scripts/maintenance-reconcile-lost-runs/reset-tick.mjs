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
  const passAfter = reset - WINDOW_SECONDS;
  if (since > ELIGIBLE_MINUTES * 60) {
    return { due: false, since, passAfter };
  }
  return { due: true, since, wait: Math.max(0, Math.ceil(GRACE_SECONDS - since)), passAfter };
}

export async function main(env = process.env, { fetchImpl = fetch, now = () => Date.now() / 1000, wait = (seconds) => sleep(seconds * 1000) } = {}) {
  const outputs = { due: true, "post-reset": false, "pass-after": "" };
  if (env.EVENT_NAME === "schedule") {
    try {
      // GET /rate_limit does not count against the rate limit: https://docs.github.com/en/rest/rate-limit/rate-limit
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
        Object.assign(outputs, { due: false, "pass-after": plan.passAfter });
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
