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

// Whether `runs` handle the head: any run that is not an untrusted skip or a
// reset limit stop does, and so do `limit-stops-per-head` limit stops.
export function anyHandles(runs, { now, limits = LIMIT_DEFAULTS }) {
  let stops = 0;
  for (const run of runs) {
    if (untrustedSkip(run)) {
      continue;
    }
    if (run.status !== "completed" || run.conclusion !== "failure") {
      return true;
    }
    const resets = limitResetsAt(run, limits);
    if (resets === null || now < resets) {
      return true;
    }
    stops += 1;
  }
  return stops >= limits["limit-stops-per-head"];
}

// Whether `runs` hold a run that handles the head for good: completed, not an
// untrusted skip, and not a limit stop. anyHandles is true for such a run
// whatever `now` and `limits` are, so a dispatcher may record the head and
// skip reading its check runs again.
export const permanentlyHandles = (runs) =>
  runs.some((run) => run.status === "completed" && !untrustedSkip(run) && limitResetsAt(run) === null);
