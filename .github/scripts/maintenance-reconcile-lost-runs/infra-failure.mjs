export const GATE_CHECK = "CI Status";
export const GATE_ALIAS = "ci-status";
export const AGGREGATE_JOBS = new Set([GATE_CHECK, GATE_ALIAS]);
export const gateEntries = (entries) => {
  const list = Array.isArray(entries) ? entries : [];
  const gate = list.filter((entry) => entry?.name === GATE_CHECK);
  return gate.length > 0 ? gate : list.filter((entry) => entry?.name === GATE_ALIAS);
};
export const INSTALL_STEP = /^(Install |Set up (job|Node|Python)$)/;
export const FAILED = new Set(["failure", "cancelled", "timed_out", "startup_failure"]);
export const LOST = new Set(["cancelled", "timed_out", "startup_failure"]);
const STOPPED = new Set(["cancelled", "timed_out"]);
export const INFRA_BACKOFF_MINUTES = 15;
export const LOOKBACK_HOURS = 24;
const inLookback = (run, now) => Date.parse(run.created_at) >= now - LOOKBACK_HOURS * 3_600_000;

export const reconcilerRetries = (run, now) =>
  run?.status === "completed" && run.conclusion === "failure" && run.run_attempt === 1 && inLookback(run, now);

export const firstFailure = (run, jobs, now) =>
  reconcilerRetries(run, now) && Array.isArray(jobs) && jobs.some((job) => FAILED.has(job?.conclusion) && !AGGREGATE_JOBS.has(job.name));

const IN_FLIGHT = new Set(["queued", "in_progress", "waiting", "requested", "pending"]);
const RECONCILER_TICK_MINUTES = 60;
export const RERUN_DUE_MINUTES = INFRA_BACKOFF_MINUTES + 2 * RECONCILER_TICK_MINUTES;

export function reconcilerOwns({ run, jobs }, now) {
  if (IN_FLIGHT.has(run?.status) && inLookback(run, now)) {
    return `run ${run.id} attempt ${run.run_attempt} is ${run.status}; its result decides`;
  }
  const due = Date.parse(run?.updated_at) + RERUN_DUE_MINUTES * 60_000;
  if (!(now < due)) {
    return "";
  }
  if (run.status === "completed" && LOST.has(run.conclusion) && run.run_attempt === 1 && inLookback(run, now)) {
    return `run ${run.id} attempt 1 ended ${run.conclusion}, re-run job re-runs it once`;
  }
  if (!reconcilerRetries(run, now)) {
    return "";
  }
  if (stepsUnread(jobs)) {
    return "its failed jobs' steps did not list, re-run job reads them again";
  }
  return infraOnly(jobs) ? "infra failure, re-run job re-runs it once" : "";
}

export function stepsKnown(job) {
  const steps = job?.steps;
  if (!Array.isArray(steps) || steps.length === 0) {
    return Array.isArray(steps) && !job.runner_id;
  }
  if (steps[0]?.name !== "Set up job") {
    return false;
  }
  if (job.status === "completed" && (steps.at(-1)?.name !== "Complete job" || steps.some((step) => step?.status !== "completed"))) {
    return false;
  }
  const gap = steps.findIndex((step, i) => step?.number != null && step.number !== i + 1);
  return gap === -1 || steps.slice(gap).every((step) => /^(Post |Complete job$)/.test(String(step?.name ?? "")));
}

export function setupFailed(job) {
  const steps = job?.steps;
  return (
    job?.status === "completed" &&
    job.conclusion === "failure" &&
    Array.isArray(steps) &&
    steps.length === 1 &&
    steps[0]?.name === "Set up job" &&
    steps[0].conclusion === "failure"
  );
}

const LOST_RUNNER = /lost communication with the server|runner has received a shutdown signal/i;
const failureNoted = (annotations, pattern) =>
  Array.isArray(annotations) && annotations.some((a) => a?.annotation_level === "failure" && pattern.test(String(a.message ?? "")));
export const lostRunnerNoted = (job) => failureNoted(job?.annotations, LOST_RUNNER);

const TIME_LIMIT = /^The job has exceeded the maximum execution time of /;
export const timeLimitNoted = (annotations) => failureNoted(annotations, TIME_LIMIT);

export const stepsUnread = (jobs) =>
  Array.isArray(jobs) && jobs.some((job) => job?.conclusion === "failure" && !AGGREGATE_JOBS.has(job.name) && !stepsKnown(job));

export function infraCause(job) {
  if (STOPPED.has(job?.conclusion)) {
    return "time limit";
  }
  if (job?.conclusion !== "failure") {
    return "";
  }
  if (lostRunnerNoted(job)) {
    return "lost runner";
  }
  if (!stepsKnown(job)) {
    return "";
  }
  const { steps } = job;
  const first = steps.find((step) => step?.conclusion === "failure" || STOPPED.has(step?.conclusion));
  if (first === undefined) {
    return "lost runner";
  }
  if (STOPPED.has(first.conclusion) && INSTALL_STEP.test(String(first.name ?? ""))) {
    return "install";
  }
  return steps.some((step) => step?.conclusion === "failure") ? "" : "lost runner";
}

export function contractOnly(jobs) {
  if (!Array.isArray(jobs)) {
    return false;
  }
  const lanes = jobs.filter((job) => !AGGREGATE_JOBS.has(job?.name));
  return lanes.length > 0 && lanes.length < jobs.length && lanes.every((job) => job?.conclusion === "skipped");
}

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

export function infraOnly(jobs) {
  if (!Array.isArray(jobs)) {
    return false;
  }
  const lanes = jobs.filter((job) => FAILED.has(job?.conclusion) && !AGGREGATE_JOBS.has(job.name));
  return lanes.length > 0 && lanes.every((job) => infraCause(job) !== "");
}
