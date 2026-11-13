// Whether a sweep a finished work-resolve-issue run started (workflow_run)
// comes too soon after the last full one. A full sweep is a completed sweep
// run of main's work-unblock.yml, whatever it concluded, that uploaded the
// work-unblock-verdicts artifact (verdict-carry.mjs): a held, kill-switch or
// skipped run uploads none, so it never counts. Each full sweep spends about
// 800 lanes App calls, so one finished less than limits.sweep-gap-minutes ago
// writes skip=true and this run requests no lane token. A schedule, an issue
// close, any other event, a gap of 0 or a failed read writes skip=false.
//
//   node sweep-gap.mjs   EVENT_NAME, RESOLVED_CONFIG, ACTIONS_TOKEN,
//                        GITHUB_REPOSITORY, GITHUB_RUN_ID and GITHUB_OUTPUT

import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { countRequests } from "../../actions/log-api-budget/rate-guard.mjs";
import { newestTrustedArtifact } from "../pr-merge/rotation.mjs";
import { readLimits } from "../work-resolve-issue/limits.mjs";
import { anySweepRun, CARRY_ARTIFACT } from "./verdict-carry.mjs";

const WORKFLOW_PATH = ".github/workflows/work-unblock.yml";
// A run the concurrency group replaced, or one whose job never ran, holds no
// artifact; leaving it out saves an artifact listing per run.
const NO_SWEEP = new Set(["cancelled", "skipped"]);

// The newest sweep run, other than `runId`, that finished a full sweep at or
// after `since` (epoch ms), or undefined.
export async function recentSweep({ repo, runId, actions, since }) {
  let found;
  const sweep = anySweepRun(repo);
  await newestTrustedArtifact({
    repo,
    runId,
    actions,
    name: CARRY_ARTIFACT,
    workflow: WORKFLOW_PATH,
    trusted: (run) => sweep(run) && run.status === "completed" && !NO_SWEEP.has(run.conclusion) && Date.parse(run.updated_at) >= since,
    accept: async (run) => {
      found = run;
      return true;
    },
  });
  return found;
}

export async function main(env = process.env, { github, now = () => Date.now() } = {}) {
  let skip = false;
  if (env.EVENT_NAME === "workflow_run") {
    try {
      const gap = readLimits(env.RESOLVED_CONFIG)["sweep-gap-minutes"];
      if (gap > 0) {
        github ??= createGitHub({ token: env.ACTIONS_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, fetchImpl: countRequests(fetch) });
        const run = await recentSweep({ repo: env.GITHUB_REPOSITORY, runId: String(env.GITHUB_RUN_ID), actions: github, since: now() - gap * 60_000 });
        if (run !== undefined) {
          skip = true;
          console.log(
            `::notice title=sweep-gap::run ${run.id} finished a full sweep at ${run.updated_at}, under ${gap} minutes ago (limits.sweep-gap-minutes); this sweep skips its work and the next one covers it`,
          );
        }
      }
    } catch (error) {
      console.log(`::warning::the sweep-gap check could not read the last sweep (${error.message}); the sweep runs`);
    }
  }
  appendFileSync(env.GITHUB_OUTPUT, `skip=${skip}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(`::warning::the sweep-gap check failed (${error.message}); the sweep runs`);
  });
}
