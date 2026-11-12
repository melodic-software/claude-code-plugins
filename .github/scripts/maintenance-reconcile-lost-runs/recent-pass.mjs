// Whether a hand-started (workflow_dispatch) pass comes too soon after the
// last full one. A full pass is one that uploaded its SETTLED_ARTIFACT: a
// paced tick, a kill-switch tick and a status-idle tick upload none, so they
// never count. A dispatch whose trusted predecessor finished such a pass less
// than MIN_GAP_MINUTES ago writes skip=true and the pass is skipped; the next
// scheduled tick reads the same runs. FORCE=true, any other event, a gap of 0,
// or a failed read writes skip=false. Only whether this pass runs changes:
// nothing here reads or writes a re-run record.
//
//   node recent-pass.mjs   EVENT_NAME, FORCE, MIN_GAP_MINUTES, GITHUB_TOKEN,
//                          GITHUB_REPOSITORY, GITHUB_RUN_ID and GITHUB_OUTPUT

import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { countRequests } from "../../actions/log-api-budget/rate-guard.mjs";
import { newestTrustedArtifact, trustedRun } from "../pr-merge/rotation.mjs";
import { SETTLED_ARTIFACT } from "./reconcile.mjs";

const WORKFLOW_PATH = ".github/workflows/maintenance-reconcile-lost-runs.yml";

// The newest trusted run, other than `runId`, that finished a full pass at or
// after `since` (epoch ms), or undefined.
export async function recentPass({ repo, runId, actions, since }) {
  let found;
  await newestTrustedArtifact({
    repo,
    runId,
    actions,
    name: SETTLED_ARTIFACT,
    workflow: WORKFLOW_PATH,
    trusted: (run) => trustedRun(run, WORKFLOW_PATH) && run.status === "completed" && Date.parse(run.updated_at) >= since,
    accept: async (run) => {
      found = run;
      return true;
    },
  });
  return found;
}

export async function main(env = process.env, { github, now = () => Date.now() } = {}) {
  let skip = false;
  const gap = Number(env.MIN_GAP_MINUTES);
  if (env.EVENT_NAME === "workflow_dispatch" && env.FORCE !== "true" && gap > 0) {
    try {
      github ??= createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, fetchImpl: countRequests(fetch) });
      const run = await recentPass({ repo: env.GITHUB_REPOSITORY, runId: String(env.GITHUB_RUN_ID), actions: github, since: now() - gap * 60_000 });
      if (run !== undefined) {
        skip = true;
        console.log(
          `::notice title=recent-pass::run ${run.id} finished a full pass at ${run.updated_at}, under ${gap} minutes ago; this dispatch skips its work (dispatch with force=true to run it)`,
        );
      }
    } catch (error) {
      console.log(`::warning::the recent-pass check could not read the last pass (${error.message}); the dispatch runs`);
    }
  }
  appendFileSync(env.GITHUB_OUTPUT, `skip=${skip}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(`::warning::the recent-pass check failed (${error.message}); the dispatch runs`);
  });
}
