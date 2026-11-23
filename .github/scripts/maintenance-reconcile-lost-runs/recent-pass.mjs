// One full pass (one that uploaded SETTLED_ARTIFACT) per token window
// (https://github.com/melodic-software/claude-code-plugins/issues/17460).

import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { countRequests } from "../../actions/log-api-budget/rate-guard.mjs";
import { newestTrustedArtifact, trustedRun } from "../pr-merge/rotation.mjs";
import { SETTLED_ARTIFACT } from "./reconcile.mjs";

const WORKFLOW_PATH = ".github/workflows/maintenance-reconcile-lost-runs.yml";

export async function recentPass({ repo, runId, actions, since, field = "updated_at" }) {
  let found;
  await newestTrustedArtifact({
    repo,
    runId,
    actions,
    name: SETTLED_ARTIFACT,
    workflow: WORKFLOW_PATH,
    trusted: (run) => trustedRun(run, WORKFLOW_PATH) && run.status === "completed" && Date.parse(run[field]) >= since,
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
  const passAfter = /^[1-9][0-9]{8,11}$/.test(env.PASS_AFTER ?? "") ? Number(env.PASS_AFTER) * 1000 : undefined;
  const scheduled = env.EVENT_NAME === "schedule";
  const what = scheduled ? "tick" : "dispatch";
  if ((scheduled || (env.EVENT_NAME === "workflow_dispatch" && env.FORCE !== "true")) && gap > 0) {
    try {
      github ??= createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, fetchImpl: countRequests(fetch) });
      const byWindow = scheduled && passAfter !== undefined;
      const run = await recentPass({
        repo: env.GITHUB_REPOSITORY,
        runId: String(env.GITHUB_RUN_ID),
        actions: github,
        since: byWindow ? passAfter : now() - gap * 60_000,
        field: byWindow ? "run_started_at" : "updated_at",
      });
      if (run !== undefined) {
        skip = true;
        console.log(
          byWindow
            ? `::notice title=recent-pass::run ${run.id} started a full pass at ${run.run_started_at}, after this token window's reset; this tick skips its work`
            : `::notice title=recent-pass::run ${run.id} finished a full pass at ${run.updated_at}, under ${gap} minutes ago; this ${what} skips its work${scheduled ? "" : " (dispatch with force=true to run it)"}`,
        );
      }
    } catch (error) {
      console.log(`::warning::the recent-pass check could not read the last pass (${error.message}); the ${what} runs`);
    }
  }
  appendFileSync(env.GITHUB_OUTPUT, `skip=${skip}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(`::warning::the recent-pass check failed (${error.message}); the pass runs`);
  });
}
