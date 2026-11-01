// The burn-rate pacer for timer-driven lanes. A budget trip (the breaker
// share of the header's limit left, rate-limits.json) turns the kill switch
// on and stops every lane; this slows the timer-driven ones first. On a
// schedule tick it reads the GITHUB_TOKEN pool once, projects the remaining
// at the window's reset from the burn rate the window has shown so far, and
// writes paced=true when that falls under `pace` of the header's limit
// (limits.api github-token pace: pr-pipeline.yaml, which each paced workflow
// hands over as RESOLVED_CONFIG, over rate-limits.json; 0 is off). Only an
// even-numbered tick is paced, so a paced lane runs at half its cadence
// rather than stopping: the lost-run reconciler, which re-runs the runs a
// breaker trip stops, keeps working while the pool recovers. A paced tick
// skips its work and ends green. Any other event, a reading that cannot
// project, a run number that is no number, or a failed read is
// paced=false: the breaker stays the backstop.
//
//   node pace.mjs   EVENT_NAME, RUN_NUMBER, GITHUB_TOKEN, GITHUB_REPOSITORY
//                   and GITHUB_OUTPUT; RESOLVED_CONFIG optional

import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { apiLimitsOrBuiltIn, countRequests } from "./rate-guard.mjs";

// GitHub's primary rate-limit window.
const WINDOW_SECONDS = 3600;
// Before this much of the window has passed, the burn rate is too short to project.
const MIN_ELAPSED_SECONDS = 60;

const round = (value) => Math.round(value * 100) / 100;

// { paced, projected } for one reading at `now` (epoch seconds): projected is
// the share of the header's limit left at the reset, at the window's burn
// rate so far, clamped to 0..1.
export function paceDecision({ limit, remaining, reset } = {}, share, now) {
  const left = reset - now;
  if (![limit, remaining, reset].every(Number.isFinite) || limit <= 0 || remaining < 0 || remaining > limit || left < 0 || !(share > 0)) {
    return { paced: false, projected: null };
  }
  const elapsed = WINDOW_SECONDS - Math.min(left, WINDOW_SECONDS);
  const used = limit - remaining;
  const atReset = elapsed < MIN_ELAPSED_SECONDS ? remaining : remaining - (used * left) / elapsed;
  const projected = Math.max(0, atReset) / limit;
  return { paced: projected < share, projected: round(projected) };
}

export async function main(env = process.env, { fetchImpl = fetch, now = () => Date.now() / 1000 } = {}) {
  let paced = false;
  if (env.EVENT_NAME === "schedule") {
    try {
      const share = apiLimitsOrBuiltIn({ resolvedPath: env.RESOLVED_CONFIG })["github-token"].pace;
      // Counted for the job-end api-calls notice like any guarded call.
      const response = await countRequests(fetchImpl)(`${env.GITHUB_API_URL ?? "https://api.github.com"}/repos/${env.GITHUB_REPOSITORY}`, {
        headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${env.GITHUB_TOKEN}`, "X-GitHub-Api-Version": "2022-11-28" },
      });
      const header = (name) => (response.headers.has(name) ? Number(response.headers.get(name)) : Number.NaN);
      const reading = { limit: header("x-ratelimit-limit"), remaining: header("x-ratelimit-remaining"), reset: header("x-ratelimit-reset") };
      const decision = response.ok ? paceDecision(reading, share, now()) : { paced: false, projected: null };
      const even = /^[0-9]+$/.test(env.RUN_NUMBER ?? "") && Number(env.RUN_NUMBER) % 2 === 0;
      paced = decision.paced && even;
      const why = paced ? "; this tick skips its work" : decision.paced ? "; an odd tick runs at half cadence" : "";
      if (decision.projected !== null) {
        console.log(`::notice title=api-pace::github-token projected=${decision.projected} pace=${share} paced=${paced}${why}`);
      }
    } catch (error) {
      console.log(`::warning::the pacer could not read the GITHUB_TOKEN pool (${error.message}); the tick runs`);
      paced = false;
    }
  }
  appendFileSync(env.GITHUB_OUTPUT, `paced=${paced}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(`::warning::the pacer failed (${error.message}); the tick runs`);
  });
}
