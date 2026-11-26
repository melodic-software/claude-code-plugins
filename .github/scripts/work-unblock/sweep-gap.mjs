// https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-work-unblock-sweep

import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { countRequests } from "../../actions/log-api-budget/rate-guard.mjs";
import { newestTrustedArtifact } from "../pr-merge/rotation.mjs";
import { readLimits } from "../work-resolve-issue/limits.mjs";
import { anySweepRun, CARRY_ARTIFACT } from "./verdict-carry.mjs";

const WORKFLOW_PATH = ".github/workflows/work-unblock.yml";
const NO_SWEEP = new Set(["cancelled", "skipped"]);

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
