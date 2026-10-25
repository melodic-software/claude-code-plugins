// Whether an existing pr-unblock check run already handles a head, shared by
// dispatch.mjs and feedback-dispatch.mjs. A check run handles the head unless
// it is the gate's completed neutral skip for an untrusted trigger, or a run
// the usage limit stopped whose limit has reset: the lane's next trigger then
// dispatches it again, at most `limits.limit-stops-per-head` times on one head.
//
// A limit stop is read only from a failed run's lane record, which
// report-check-run writes from runner-computed outputs. The record is the first
// line of the run's output.summary, matched whole: `lane=<lane>
// activity=<activity>` naming the run itself, then class, resets, turns,
// max-turns, models and profile in that order, each optional. A failed run with no such line is
// no limit stop.

// `limits` is pr-pipeline.yaml's resolved limits leaf. When a limit stop names
// no `resets=` time, it is taken to reset `fallback-reset` hours after the run
// ended: the shortest plan limit is a five-hour session window
// (https://support.claude.com/en/articles/11145838). After
// `limit-stops-per-head` stops the dispatchers stop re-dispatching the head;
// the next push makes a new one.
import { LIMIT_DEFAULTS, clampReset } from "../work-resolve-issue/limits.mjs";

const ISO = String.raw`\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?Z`;
const NAME = "[a-z][a-z0-9]*(?:-[a-z0-9]+)*";
const MODEL = String.raw`[A-Za-z0-9][A-Za-z0-9._[\]-]{0,63}`;
const SUMMARY_RECORD = new RegExp(
  `^lane=(${NAME}) activity=(${NAME})(?: class=([a-z-]+))?(?: resets=(${ISO}))?` +
    "(?: turns=(?:0|[1-9][0-9]{0,5}))?(?: max-turns=(?:0|[1-9][0-9]{0,5}))?" +
    `(?: models=${MODEL}(?:,${MODEL}){0,7})?(?: profile=${NAME})?$`,
);

// The lane record on the first line of `run`'s output.summary, or null when
// that line is not one or names another check run.
function summaryRecord(run) {
  const match = SUMMARY_RECORD.exec(String(run.output?.summary ?? "").split("\n")[0]);
  if (!match || run.name !== `${match[1]} / ${match[2]}`) {
    return null;
  }
  return { failureClass: match[3] ?? "", resets: match[4] ?? "" };
}

// When the limit that stopped the failed `run` resets (epoch ms), or null when
// its lane record does not mark it a limit stop. The stated reset is held
// within the limits' clamp after the run ended.
export function limitResetsAt(run, limits = LIMIT_DEFAULTS) {
  const ended = Date.parse(run.completed_at ?? "");
  if (!Number.isFinite(ended) || run.conclusion !== "failure") {
    return null;
  }
  const summary = summaryRecord(run);
  if (summary?.failureClass !== "rate-limit") {
    return null;
  }
  return clampReset(summary.resets ? Date.parse(summary.resets) : null, ended, limits);
}

const untrustedSkip = (run) =>
  run.status === "completed" &&
  run.conclusion === "neutral" &&
  String(run.output?.title ?? "").startsWith("Skipped: untrusted-trigger");

// The neutral check a run skipped on a held PR posts (report-check-run's
// `Skipped: <reason>` title).
const heldSkip = (run) => run.status === "completed" && run.conclusion === "neutral" && run.output?.title === "Skipped: awaiting-human";

// Two opt-ins, for a dispatcher that checks the PR's holds itself before it
// reads the check runs: with `heldSkipsRelease` a held skip stops handling the
// head, so a head skipped while held is dispatched once the hold is gone; with
// `failuresRetry` a failed run of any kind does too. Either way the head is
// handled once `limit-stops-per-head` of them, limit stops included, stand on
// it, so a dispatcher and a run that disagree about a hold stop there.
const released = (run, heldSkipsRelease) => heldSkipsRelease && heldSkip(run);

// Whether `runs` handle the head: any run that is not an untrusted skip or a
// reset limit stop does, and so do `limit-stops-per-head` limit stops.
export function anyHandles(runs, { now, limits = LIMIT_DEFAULTS, failuresRetry = false, heldSkipsRelease = false }) {
  let stops = 0;
  for (const run of runs) {
    if (untrustedSkip(run)) {
      continue;
    }
    if (released(run, heldSkipsRelease)) {
      stops += 1;
      continue;
    }
    if (run.status !== "completed" || run.conclusion !== "failure") {
      return true;
    }
    const resets = limitResetsAt(run, limits);
    if ((resets === null && !failuresRetry) || now < resets) {
      return true;
    }
    stops += 1;
  }
  return stops >= limits["limit-stops-per-head"];
}

// Whether `runs` hold a run that handles the head for good: completed, not an
// untrusted skip, and not a limit stop (with failuresRetry: not a failure, or
// the cap of failures). anyHandles is true then whatever `now` is, so a
// dispatcher may record the head and skip reading its check runs again.
// Without an opt-in, limit stops never handle the head for good, however many:
// anyHandles holds it at the cap, and a head recorded at one cap would stay
// recorded under a higher one.
export function permanentlyHandles(runs, options = {}) {
  const { done, retryable } = completedRuns(runs, options);
  return done.some((run) => !retryable(run)) || cappedAt(runs, options) > 0;
}

function completedRuns(runs, { limits = LIMIT_DEFAULTS, failuresRetry = false, heldSkipsRelease = false }) {
  const done = runs.filter((run) => run.status === "completed" && !untrustedSkip(run));
  const retryable = (run) => released(run, heldSkipsRelease) || (failuresRetry ? run.conclusion === "failure" : limitResetsAt(run, limits) !== null);
  return { done, retryable };
}

// With an opt-in, the number of retryable runs when they reach
// `limit-stops-per-head`, the head's hard end, else 0: the part of
// permanentlyHandles a dispatcher reports as a stop.
export function cappedAt(runs, { limits = LIMIT_DEFAULTS, failuresRetry = false, heldSkipsRelease = false } = {}) {
  if (!failuresRetry && !heldSkipsRelease) {
    return 0;
  }
  const { done, retryable } = completedRuns(runs, { limits, failuresRetry, heldSkipsRelease });
  const stops = done.filter(retryable).length;
  return stops >= limits["limit-stops-per-head"] ? stops : 0;
}
