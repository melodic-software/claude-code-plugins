// Finds the capture for a pr-verify judge job: the pr-verify-capture.yml run
// the same pr-require-checks run started, waited on until it completes or a
// bound passes, and the id of its pr-capture-<pr>-<head-sha> artifact. Both
// workflows start on the same event, so the capture is still running when
// check-intent first asks. The runs are listed only until the capture run
// shows up; after that only its own record is read. A later judge job takes
// what the job before it found (FOUND_CAPTURE, a job output written only
// here: `<run id>:<artifact id>`, or a miss code that cannot change) and
// reads nothing; it looks for itself when that job wrote neither. The listing starts at the
// upstream run's creation, before which no capture run of it exists, and is
// read page by page. Every miss with the app set (no run, a run that ended
// other than success, a run still going at the bound, no artifact, an API
// failure) writes no artifact id but a blocked reason the verdict records
// (write-verdict.mjs CAPTURE_BLOCKED), and exits 0: a missing capture never
// fails a verdict. Each reason is built here from a fixed code, a run id and
// a run conclusion, each pattern-checked, so a carried miss gives the same
// reason and no API text reaches an output. The capture run is taken only
// when its record shows it is that file, on main, started by workflow_run,
// in this repository, and its title names this upstream run and head (the
// capture workflow's run-name).
import { appendFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub, detailSuffix } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

export const CAPTURE_PATH = ".github/workflows/pr-verify-capture.yml";
// A run or artifact id, and a run conclusion (GitHub's lowercase enum:
// failure, cancelled, timed_out, ...).
const ID = "[1-9][0-9]{0,19}";
const ENDED_AS = "[a-z_]{1,32}";
const RUN_ID = new RegExp(`^${ID}$`);
const PR = /^[1-9][0-9]{0,15}$/;
const SHA = /^[0-9a-f]{40}$/;
const CREATED = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const CARRIED = new RegExp(`^(${ID}):(${ID})$`);
// A miss: a code alone, a code and the run id, or `ended`, the run id and its
// conclusion.
const MISS = new RegExp(`^(?:(not-started|malformed|unreadable)|(running|no-artifact|mismatch):(${ID})|ended:(${ID}):(${ENDED_AS}))$`);
// The misses that cannot change, which alone are carried to the later jobs:
// a malformed input, and a completed run's outcome. A run not yet started,
// still running, or an API read that failed can change by the time a later
// job asks (at least one 22-minute judge step later), so that job searches
// again under the same bound. That costs it little: the capture job's own
// 30-minute timeout has mostly run out by then, so its wait is short, and a
// run that never started is given up on in two minutes.
const PERMANENT = new RegExp(`^(?:malformed|(?:no-artifact|mismatch):${ID}|ended:${ID}:${ENDED_AS})$`);
const CONCLUSION = new RegExp(`^${ENDED_AS}$`);
const MINUTE = 60_000;
// The capture job's timeout (pr-verify-capture.yml) and five minutes for its
// queue and gates: past this the capture cannot still be running.
export const WAIT_MS = 35 * MINUTE;
// Both runs are created on the same event; one that has not shown up in two
// minutes was not started.
export const APPEAR_MS = 2 * MINUTE;
// The listing's interval while the run has yet to show up.
export const POLL_MS = MINUTE;
// The found run's own record, read first this long after it showed up and
// then at this interval, the last read at the bound. A capture that drives
// the app runs its gates, a reach-probe session of up to 7 minutes and a
// driver of up to 16 (pr-verify-capture.yml), so a sooner read finds it still
// running; 3 minutes of added wait is small beside the judge steps' 22 each,
// and the 35-minute bound costs 13 calls where a listing each minute took 36.
export const RUN_POLL_MS = 3 * MINUTE;
export const PER_PAGE = 50;
// Capture runs started since the upstream run, one per pull request run:
// ten pages is 500, more than the lanes start in the judges' longest wait.
export const MAX_PAGES = 10;

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

// The highest-id entry of a listed array that passes keep, if any.
const newest = (listed, keep) => (Array.isArray(listed) ? listed : []).filter(keep).sort((a, b) => b.id - a.id)[0];

// The newest matching run in the listing since `createdAt`, page by page.
async function captureRun(github, ids, createdAt) {
  const since = CREATED.test(String(createdAt)) ? `&created=${encodeURIComponent(`>=${createdAt}`)}` : "";
  const runsPath = `/repos/${ids.repository}/actions/workflows/${CAPTURE_PATH.split("/").pop()}/runs?event=workflow_run&branch=main${since}&per_page=${PER_PAGE}`;
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const listed = await github("GET", `${runsPath}&page=${page}`);
    const runs = Array.isArray(listed?.workflow_runs) ? listed.workflow_runs : [];
    const run = newest(runs, (candidate) => isCaptureRun(candidate, ids));
    if (run) return run;
    if (runs.length < PER_PAGE) return undefined;
  }
  return undefined;
}

// The verdict's reason for a miss code, or undefined for anything else.
export function missReason(miss) {
  const match = MISS.exec(String(miss ?? ""));
  if (!match) return undefined;
  const [, bare, code, runId, endedId, conclusion] = match;
  if (bare === "not-started") return "no capture run was started for this head";
  if (bare === "malformed") return "the upstream run, pull request or head is malformed";
  if (bare === "unreadable") return "the capture run or its artifact could not be read";
  if (code === "running") return `capture run ${runId} was still running after ${Math.round(WAIT_MS / MINUTE)} minutes`;
  if (code === "no-artifact") return `capture run ${runId} left no capture artifact for this head`;
  if (code === "mismatch") return `capture run ${runId}'s record no longer names this upstream run and head`;
  return `capture run ${endedId} ended ${conclusion}`;
}

const miss = (code) => ({ miss: code, reason: missReason(code) });

// A completed run's outcome: its artifact when it succeeded, else a miss. A
// run that ended other than success may still have uploaded a summary (the
// capture's collect and upload steps run always()), but it is not taken.
async function completed(github, { repository, pr, headSha }, run) {
  if (run.conclusion !== "success") {
    return miss(typeof run.conclusion === "string" && CONCLUSION.test(run.conclusion) ? `ended:${run.id}:${run.conclusion}` : "unreadable");
  }
  const name = artifactName(pr, headSha);
  const artifacts = await github("GET", `/repos/${repository}/actions/runs/${run.id}/artifacts?name=${name}&per_page=10`);
  const artifact = newest(
    artifacts?.artifacts,
    (candidate) => candidate?.name === name && candidate.expired === false && RUN_ID.test(String(candidate.id)),
  );
  return artifact ? { artifactId: String(artifact.id), runId: String(run.id) } : miss(`no-artifact:${run.id}`);
}

// { artifactId, runId } once the capture run completed with its artifact,
// else { miss, reason }: the runs are listed until the capture run shows up,
// then its own record is read until it completes or the bound passes.
export async function findCapture(github, { repository, upstreamRunId, pr, headSha, createdAt }, { sleep, now, waitMs = WAIT_MS, appearMs = APPEAR_MS, pollMs = POLL_MS, runPollMs = RUN_POLL_MS } = {}) {
  if (!RUN_ID.test(String(upstreamRunId)) || !PR.test(String(pr)) || !SHA.test(String(headSha))) {
    return miss("malformed");
  }
  const ids = { repository, upstreamRunId, headSha };
  const started = now();
  let run;
  for (;;) {
    run = await captureRun(github, ids, createdAt);
    if (run) break;
    if (now() - started >= appearMs) return miss("not-started");
    await sleep(pollMs);
  }
  for (;;) {
    if (run.status === "completed") return completed(github, { repository, pr, headSha }, run);
    const waited = now() - started;
    if (waited >= waitMs) return miss(`running:${run.id}`);
    await sleep(Math.min(runPollMs, waitMs - waited));
    const record = await github("GET", `/repos/${repository}/actions/runs/${run.id}`);
    if (!isCaptureRun(record, ids) || String(record.id) !== String(run.id)) return miss(`mismatch:${run.id}`);
    run = record;
  }
}

export async function main(env = process.env, { github, fetchImpl, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)), now = Date.now } = {}) {
  const write = (line) => env.GITHUB_OUTPUT && appendFileSync(env.GITHUB_OUTPUT, `${line}\n`);
  if (!env.CAPTURE_APP) {
    console.log("find-capture: merge.verify-capture.app is unset, so no capture runs; the verdict records no-app");
    return;
  }
  let found;
  const carried = CARRIED.exec(env.FOUND_CAPTURE ?? "");
  if (carried) {
    found = { runId: carried[1], artifactId: carried[2] };
    console.log("find-capture: the capture the earlier judge job found");
  } else if (PERMANENT.test(env.FOUND_CAPTURE ?? "")) {
    found = miss(env.FOUND_CAPTURE);
    console.log("find-capture: the miss the earlier judge job found");
  } else {
    try {
      for (const key of ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "UPSTREAM_RUN_ID", "PR_NUMBER", "HEAD_SHA"]) {
        if (!env[key]) throw new Error(`${key} is not set`);
      }
      const client = github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL, fetchImpl });
      found = await findCapture(
        client,
        { repository: env.GITHUB_REPOSITORY, upstreamRunId: env.UPSTREAM_RUN_ID, pr: env.PR_NUMBER, headSha: env.HEAD_SHA, createdAt: env.UPSTREAM_CREATED_AT },
        { sleep, now },
      );
    } catch (error) {
      // The detail goes to the log alone; the verdict gets the fixed reason.
      console.log(`::notice::the capture could not be read: ${error.message}${detailSuffix(error)}`);
      found = miss("unreadable");
    }
  }
  if (found.artifactId) {
    write(`artifact-id=${found.artifactId}`);
    write(`run-id=${found.runId}`);
    write(`carry=${found.runId}:${found.artifactId}`);
    // Recorded only when the download leaves no summary to read instead.
    write(`blocked-reason=capture run ${found.runId}'s artifact ${found.artifactId} did not download a summary`);
    console.log(`find-capture: capture run ${found.runId}, artifact ${found.artifactId}`);
  } else {
    if (PERMANENT.test(found.miss)) write(`carry=${found.miss}`);
    write(`blocked-reason=${found.reason}`);
    console.log(`::notice::no capture for this head (${found.reason}); the verdict records it blocked and the judgment goes on`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.log(`::notice::no capture for this head: ${error.message}`);
  });
}
