// Finds the capture for a pr-verify judge job: the pr-verify-capture.yml run
// the same pr-require-checks run started, waited on until it completes or a
// bound passes, and the id of its pr-capture-<pr>-<head-sha> artifact. Both
// workflows start on the same event, so the capture is still running when
// check-intent first asks; the later judge jobs find it done. Every miss (no
// app set, no run, a run still going at the bound, no artifact, an API
// failure) writes no artifact id and exits 0: a missing capture never fails
// a verdict. The capture run is taken only when its record shows it is that
// file, on main, started by workflow_run, in this repository, and its title
// names this upstream run and head (the capture workflow's run-name).
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, detailSuffix } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

export const CAPTURE_PATH = ".github/workflows/pr-verify-capture.yml";
const RUN_ID = /^[1-9][0-9]{0,19}$/;
const PR = /^[1-9][0-9]{0,15}$/;
const SHA = /^[0-9a-f]{40}$/;
const MINUTE = 60_000;
// The capture job's timeout (pr-verify-capture.yml) and five minutes for its
// queue and gates: past this the capture cannot still be running.
export const WAIT_MS = 35 * MINUTE;
// Both runs are created on the same event; one that has not shown up in two
// minutes was not started.
export const APPEAR_MS = 2 * MINUTE;
export const POLL_MS = MINUTE;

// The artifact name, which never starts like a verdict's (`pr-verify-`).
export const artifactName = (pr, headSha) => `pr-capture-${pr}-${headSha}`;
// The capture workflow's run-name, which ties its run to the upstream run.
export const runTitle = (upstreamRunId, headSha) => `pr-verify-capture ${upstreamRunId} ${headSha}`;

const isCaptureRun = (run, { repository, upstreamRunId, headSha }) =>
  run?.path === CAPTURE_PATH &&
  run.event === "workflow_run" &&
  run.head_branch === "main" &&
  run.repository?.full_name === repository &&
  run.display_title === runTitle(upstreamRunId, headSha) &&
  RUN_ID.test(String(run.id));

// { artifactId, runId } once the capture run completed with its artifact,
// else { reason }.
export async function findCapture(github, { repository, upstreamRunId, pr, headSha }, { sleep, now, waitMs = WAIT_MS, appearMs = APPEAR_MS, pollMs = POLL_MS } = {}) {
  if (!RUN_ID.test(String(upstreamRunId)) || !PR.test(String(pr)) || !SHA.test(String(headSha))) {
    return { reason: "the upstream run, pull request or head is malformed" };
  }
  const started = now();
  const runsPath = `/repos/${repository}/actions/workflows/${CAPTURE_PATH.split("/").pop()}/runs?event=workflow_run&branch=main&per_page=50`;
  for (;;) {
    const listed = await github("GET", runsPath);
    const run = (Array.isArray(listed?.workflow_runs) ? listed.workflow_runs : [])
      .filter((candidate) => isCaptureRun(candidate, { repository, upstreamRunId, headSha }))
      .sort((a, b) => b.id - a.id)[0];
    const waited = now() - started;
    if (!run) {
      if (waited >= appearMs) return { reason: "no capture run was started for this head" };
    } else if (run.status === "completed") {
      const name = artifactName(pr, headSha);
      const artifacts = await github("GET", `/repos/${repository}/actions/runs/${run.id}/artifacts?name=${name}&per_page=10`);
      const artifact = (Array.isArray(artifacts?.artifacts) ? artifacts.artifacts : [])
        .filter((candidate) => candidate?.name === name && candidate.expired === false && RUN_ID.test(String(candidate.id)))
        .sort((a, b) => b.id - a.id)[0];
      return artifact ? { artifactId: String(artifact.id), runId: String(run.id) } : { reason: `capture run ${run.id} left no ${name} artifact` };
    } else if (waited >= waitMs) {
      return { reason: `capture run ${run.id} was still running after ${Math.round(waitMs / MINUTE)} minutes` };
    }
    await sleep(pollMs);
  }
}

export async function main(env = process.env, { github, fetchImpl, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)), now = Date.now } = {}) {
  const write = (line) => env.GITHUB_OUTPUT && appendFileSync(env.GITHUB_OUTPUT, `${line}\n`);
  if (!env.CAPTURE_APP) {
    console.log("find-capture: merge.verify-capture.app is unset, so no capture runs; the verdict records no-app");
    return;
  }
  let found;
  try {
    for (const key of ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "UPSTREAM_RUN_ID", "PR_NUMBER", "HEAD_SHA"]) {
      if (!env[key]) throw new Error(`${key} is not set`);
    }
    const client = github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL, fetchImpl });
    found = await findCapture(client, { repository: env.GITHUB_REPOSITORY, upstreamRunId: env.UPSTREAM_RUN_ID, pr: env.PR_NUMBER, headSha: env.HEAD_SHA }, { sleep, now });
  } catch (error) {
    found = { reason: `the capture could not be read: ${error.message}${detailSuffix(error)}` };
  }
  if (found.artifactId) {
    write(`artifact-id=${found.artifactId}`);
    write(`run-id=${found.runId}`);
    console.log(`find-capture: capture run ${found.runId}, artifact ${found.artifactId}`);
  } else {
    console.log(`::notice::no capture for this head (${found.reason}); the judgment goes on without one`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(`::notice::no capture for this head: ${error.message}`);
  });
}
