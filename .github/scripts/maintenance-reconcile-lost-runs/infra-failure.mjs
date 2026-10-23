// infra-failure.mjs: whether a failed CI run's failures are all ones an outside
// outage (npm, GitHub, a runner) explains, so a re-run, not a code change, is
// the fix. reconcile.mjs re-runs such a run's failed jobs, and any other failed
// run's once (firstFailure); pr-unblock's fix-ci dispatcher spends no model run
// on a run the reconciler still re-runs (reconcilerOwns). Deterministic, no model.
//
// A job is a REST job record of the run's latest attempt
// (GET /repos/{owner}/{repo}/actions/runs/{id}/jobs?filter=latest): its name,
// conclusion, and steps with their names and conclusions. A failed job is
// infra when:
// - it ended cancelled or timed_out: a job past its timeout-minutes ends
//   cancelled inside a run that ends failure (pr-require-checks run
//   39710654665, its check-plugins and test-node jobs). A matrix leg fail-fast
//   cancelled is infra too, but the leg that failed first classifies itself;
// - its first stopped step (cancelled or timed_out) installs a toolchain or
//   dependency, or is the runner's own "Set up job" (action downloads). An
//   install step that concluded failure exited non-zero, as `npm ci` does on a
//   stale lockfile, so it is real;
// - it failed with no failed step: the runner was lost mid-step.
// Anything else is a real failure. The ci-status aggregate fails whenever a
// lane does, so it is set aside when another job failed; alone, it is real.

export const AGGREGATE_JOBS = new Set(["ci-status"]);
export const INSTALL_STEP = /^(Install |Set up (job|Node|Python)$)/;
const FAILED = new Set(["failure", "cancelled", "timed_out", "startup_failure"]);
const STOPPED = new Set(["cancelled", "timed_out"]);
// Minutes after attempt N of an infra-only run ended before the reconciler
// re-runs its failed jobs; past the last entry it is left red, and fix-ci takes
// it. Two re-runs per head at most.
export const INFRA_BACKOFF_MINUTES = [15, 30];
// An outage loss is re-run within a day; an older one is left to a person (judgment).
export const LOOKBACK_HOURS = 24;

// True for a failed run whose failed jobs the reconciler re-runs, once its
// backoff has passed, when its failures are infra only; fix-ci leaves exactly
// these heads to it.
export const reconcilerRetries = (run, now) =>
  run?.status === "completed" &&
  run.conclusion === "failure" &&
  Number.isInteger(run.run_attempt) &&
  run.run_attempt >= 1 &&
  run.run_attempt <= INFRA_BACKOFF_MINUTES.length &&
  Date.parse(run.created_at) >= now - LOOKBACK_HOURS * 3_600_000;

// True for a failed run at attempt 1 inside the lookback: when its failures are
// not infra only, the reconciler re-runs its failed jobs once, whatever the
// status pages show, so a flaky test the diff did not cause spends no model
// run. The attempt number is the cap: one re-run per run and head.
export const firstFailure = (run, now) =>
  run?.status === "completed" &&
  run.conclusion === "failure" &&
  run.run_attempt === 1 &&
  Date.parse(run.created_at) >= now - LOOKBACK_HOURS * 3_600_000;

// Why the reconciler still owns a tested run ({ run, jobs } from testedRun),
// or "" when it re-runs it no more and fix-ci may take it.
export function reconcilerOwns({ run, jobs }, now) {
  if (infraOnly(jobs)) {
    return reconcilerRetries(run, now) ? "infra failure, re-run job owns it" : "";
  }
  return firstFailure(run, now) ? "first failure, re-run job re-runs it once" : "";
}

// Why the failed job is infra ("time limit", "install", "lost runner"), or "" when it is real.
export function infraCause(job) {
  if (job?.conclusion === "cancelled" || job?.conclusion === "timed_out") {
    return "time limit";
  }
  if (job?.conclusion !== "failure") {
    return "";
  }
  const steps = Array.isArray(job.steps) ? job.steps : [];
  const first = steps.find((step) => step?.conclusion === "failure" || STOPPED.has(step?.conclusion));
  if (first === undefined) {
    return "lost runner";
  }
  if (STOPPED.has(first.conclusion) && INSTALL_STEP.test(String(first.name ?? ""))) {
    return "install";
  }
  return steps.some((step) => step?.conclusion === "failure") ? "" : "lost runner";
}

// True for a contract-only run, which a label or edit event starts: every lane
// skipped and the aggregate alone ran (pr-require-checks run 39716948399).
export function contractOnly(jobs) {
  if (!Array.isArray(jobs)) {
    return false;
  }
  const lanes = jobs.filter((job) => !AGGREGATE_JOBS.has(job?.name));
  return lanes.length > 0 && lanes.length < jobs.length && lanes.every((job) => job?.conclusion === "skipped");
}

// A failed contract-only run can land on the head seconds after the run that
// tested it, so the run whose failures count is the newest one that is not a
// failed contract-only run. runs is one workflow's runs on the head, newest
// first; readJobs(run) reads a run's latest jobs. Returns { run, jobs } (jobs
// read only for a run that ended failure, else null), or undefined when the
// STEP_BACK newest runs are all failed contract-only runs.
export const STEP_BACK = 5;
export async function testedRun(runs, readJobs) {
  for (const run of runs.slice(0, STEP_BACK)) {
    if (run?.status !== "completed" || run.conclusion !== "failure") {
      return { run, jobs: null };
    }
    const jobs = await readJobs(run);
    if (!contractOnly(jobs)) {
      return { run, jobs };
    }
  }
  return undefined;
}

// True when the run's failed jobs exist and every one is infra.
export function infraOnly(jobs) {
  if (!Array.isArray(jobs)) {
    return false;
  }
  const failed = jobs.filter((job) => FAILED.has(job?.conclusion));
  const lanes = failed.filter((job) => !AGGREGATE_JOBS.has(job.name));
  return lanes.length > 0 && lanes.every((job) => infraCause(job) !== "");
}
