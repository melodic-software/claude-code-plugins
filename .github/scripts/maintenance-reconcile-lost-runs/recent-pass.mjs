import { appendFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";
import { countRequests } from "../../actions/log-api-budget/rate-guard.mjs";
import { escapeCommand, ghDownloadArtifact, newestTrustedArtifact, trustedRun } from "../pr-merge/rotation.mjs";
import { parseSettled, SETTLED_ARTIFACT, SETTLED_FILE } from "./reconcile.mjs";

const WORKFLOW_PATH = ".github/workflows/maintenance-reconcile-lost-runs.yml";

export async function recentPass({ repo, runId, actions, since, field = "updated_at" }) {
  let found;
  const hit = await newestTrustedArtifact({
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
  return found === undefined ? undefined : { ...found, artifactId: hit?.artifactId };
}

function queueFollowUp(env, run, download) {
  if (!env.FOLLOWUP_PATH) {
    return false;
  }
  try {
    if (run.artifactId === undefined) {
      throw new Error(`run ${run.id}'s ${SETTLED_ARTIFACT} artifact has no id`);
    }
    download ??= ghDownloadArtifact({ repo: env.GITHUB_REPOSITORY, token: env.GITHUB_TOKEN, dir: env.RUNNER_TEMP, name: SETTLED_ARTIFACT, file: SETTLED_FILE });
    const { waiting } = parseSettled(download(run.artifactId), env.GITHUB_REPOSITORY);
    if (waiting.length === 0) {
      return false;
    }
    writeFileSync(env.FOLLOWUP_PATH, JSON.stringify({ run_id: run.id, waiting_reviews: waiting }));
    console.log(`::notice title=recent-pass::run ${run.id} left ${waiting.length} reviews waiting on a checks run; this tick follows them up`);
    return true;
  } catch (error) {
    console.log(`::warning::the full pass's waiting reviews were not read (${escapeCommand(error?.message ?? error)}); this tick follows up nothing`);
    return false;
  }
}

export async function main(env = process.env, { github, now = () => Date.now(), download } = {}) {
  let skip = false;
  let followup = false;
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
        followup = byWindow && queueFollowUp(env, run, download);
      }
    } catch (error) {
      console.log(`::warning::the recent-pass check could not read the last pass (${error.message}); the ${what} runs`);
    }
  }
  appendFileSync(env.GITHUB_OUTPUT, `skip=${skip}\n${followup ? "followup=true\n" : ""}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(`::warning::the recent-pass check failed (${error.message}); the pass runs`);
  });
}
