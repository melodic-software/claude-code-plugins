// The read-floor gate for maintenance lanes. It reads the GITHUB_TOKEN pool
// once, from the x-ratelimit-* headers of a counted GET /repos/<repo> (GET
// /rate_limit reports a different bucket from the one a job spends:
// log-api-budget/action.yml), and writes skip=true when the pool is under
// limits.api github-token read-floor of its planned budget (planOf with
// limit-cap: pr-pipeline.yaml, handed over as RESOLVED_CONFIG, over
// rate-limits.json), the margin the rate guard warns at. A reading it cannot
// take, a refused answer or any error also writes skip=true: a rate budget
// is a safety limit, so the gate never runs the work blind.
//
//   node check-read-floor.mjs   GITHUB_TOKEN, GITHUB_REPOSITORY and
//                               GITHUB_OUTPUT; RESOLVED_CONFIG optional

import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { apiLimitsOrBuiltIn, countRequests, planOf } from "../log-api-budget/rate-guard.mjs";

// { skip, reason, left, planned } for one reading against github-token's
// margins: reason is below-floor, ok or unreadable.
export function floorDecision({ limit, remaining } = {}, margins = {}) {
  const floor = margins["read-floor"];
  const cap = margins["limit-cap"] ?? null;
  if (![limit, remaining].every(Number.isInteger) || limit <= 0 || remaining < 0 || remaining > limit || !Number.isFinite(floor)) {
    return { skip: true, reason: "unreadable", left: null, planned: null };
  }
  const { planned, left } = planOf({ limit, remaining }, cap);
  const below = left < floor * planned;
  return { skip: below, reason: below ? "below-floor" : "ok", left, planned };
}

export async function main(env = process.env, { fetchImpl = fetch } = {}) {
  let decision = { skip: true, reason: "unreadable", left: null, planned: null };
  let floor = null;
  try {
    const margins = apiLimitsOrBuiltIn({ resolvedPath: env.RESOLVED_CONFIG })["github-token"];
    floor = margins["read-floor"];
    // Counted for the job-end api-calls notice like any guarded call.
    const response = await countRequests(fetchImpl)(`${env.GITHUB_API_URL ?? "https://api.github.com"}/repos/${env.GITHUB_REPOSITORY}`, {
      headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${env.GITHUB_TOKEN}`, "X-GitHub-Api-Version": "2022-11-28" },
    });
    const header = (name) => (/^\d{1,12}$/.test(response.headers.get(name) ?? "") ? Number(response.headers.get(name)) : Number.NaN);
    if (response.ok) {
      decision = floorDecision({ limit: header("x-ratelimit-limit"), remaining: header("x-ratelimit-remaining") }, margins);
    }
  } catch (error) {
    console.log(`::warning::the read-floor gate could not read the GITHUB_TOKEN pool (${error.message})`);
  }
  const pool = decision.left === null ? "unreadable" : `left=${decision.left} of planned ${decision.planned}`;
  const why = decision.skip ? "this run skips its work" : "the run proceeds";
  console.log(`::notice title=api-read-floor::github-token ${pool}, read-floor=${floor ?? "na"} skip=${decision.skip} reason=${decision.reason}; ${why}`);
  appendFileSync(env.GITHUB_OUTPUT, `skip=${decision.skip}\nreason=${decision.reason}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(`::warning::the read-floor gate failed (${error.message}); the run skips its work`);
    try {
      appendFileSync(process.env.GITHUB_OUTPUT, "skip=true\nreason=unreadable\n");
    } catch {
      // No output: the caller's `skip == 'false'` gate still stops the work.
    }
  });
}
