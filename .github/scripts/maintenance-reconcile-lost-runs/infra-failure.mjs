// infra-failure.mjs: whether a failed CI run's failures are all ones an outside
// outage (npm, GitHub, a runner) explains, so a re-run, not a code change, is
// the fix. reconcile.mjs re-runs such a run's failed jobs; pr-unblock's fix-ci
// dispatcher spends no model run on one. Deterministic, no model.
//
// A job is a REST job record of the run's latest attempt
// (GET /repos/{owner}/{repo}/actions/runs/{id}/jobs?filter=latest): its name,
// conclusion, and steps with their names and conclusions. A failed job is
// infra when:
// - it ended cancelled or timed_out: a job past its timeout-minutes ends
//   cancelled inside a run that ends failure (pr-require-checks run
//   39710654665, its check-plugins and test-node jobs). A matrix leg fail-fast
//   cancelled is infra too, but the leg that failed first classifies itself;
// - its first failed step installs a toolchain or dependency, or is the runner's
//   own "Set up job" (action downloads);
// - it failed with no failed step: the runner was lost mid-step.
// Anything else is a real failure. The ci-status aggregate fails whenever a
// lane does, so it is set aside when another job failed; alone, it is real.

export const AGGREGATE_JOBS = new Set(["ci-status"]);
export const INSTALL_STEP = /^(Install |Set up (job|Node|Python)$)/;
const FAILED = new Set(["failure", "cancelled", "timed_out", "startup_failure"]);

// Why the failed job is infra ("time limit", "install", "lost runner"), or "" when it is real.
export function infraCause(job) {
  if (job?.conclusion === "cancelled" || job?.conclusion === "timed_out") {
    return "time limit";
  }
  if (job?.conclusion !== "failure") {
    return "";
  }
  const first = (Array.isArray(job.steps) ? job.steps : []).find((step) => step?.conclusion === "failure");
  if (first === undefined) {
    return "lost runner";
  }
  return INSTALL_STEP.test(String(first.name ?? "")) ? "install" : "";
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
