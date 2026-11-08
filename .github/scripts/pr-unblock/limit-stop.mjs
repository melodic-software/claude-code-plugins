// Whether an existing pr-unblock check run already handles a head, shared by
// dispatch.mjs and feedback-dispatch.mjs. A check run handles the head unless
// it is the gate's completed neutral skip for an untrusted trigger, a fault
// stop whose model never started, or a run
// the usage limit stopped whose limit has reset: the lane's next trigger then
// dispatches it again, at most `limits.limit-stops-per-head` times on one head.
// A run whose credential was refused (class `auth`, a 401) is a limit stop
// too: the next run on the same credential fails the same way, so the head
// waits `fallback-reset` hours instead of spending its stops at once.
//
// A limit stop is read only from a failed run's lane-outcome record
// (ci-workflows docs/lane-outcome.md), which report-check-run validates and
// writes into output.text from the run job's report-lane-outcome output. Its
// lane and activity must name the run itself. A failed run with no such record
// is no limit stop.

// `limits` is pr-pipeline.yaml's resolved limits leaf. When a limit stop names
// no `resets.at` time, it is taken to reset `fallback-reset` hours after the run
// ended: the shortest plan limit is a five-hour session window
// (https://support.claude.com/en/articles/11145838). After
// `limit-stops-per-head` stops the dispatchers stop re-dispatching the head;
// the next push makes a new one. A fault stop (FAULT_CLASSES) is not counted.
import { LIMIT_DEFAULTS, clampReset } from "../work-resolve-issue/limits.mjs";
import { readRecord } from "../lib/lane-outcome.mjs";
import { laneStop } from "./escalation-routes.mjs";

export { ACTIONS_APP_ID, LANE_STOP, laneStop, retryRung } from "./escalation-routes.mjs";

// The run's lane-outcome record from output.text, or null when it has none,
// names another check run, or is a leg that handed off (its class is not the
// run's).
function laneRecord(run) {
  const record = readRecord(run.output?.text);
  if (!record || record.handoff === true || run.name !== `${record.lane} / ${record.activity}`) {
    return null;
  }
  // Only a usage limit's reset is read; an auth stop always waits
  // fallback-reset.
  return { failureClass: record.class ?? "", resets: record.class === "rate-limit" ? (record.resets?.at ?? "") : "" };
}

// The lane record classes that stop a run until a reset. A credit stop is not
// one: an API key out of credit or at its spend limit does not recover when a
// usage window resets, so its failed run handles the head like any other
// failure, and the morning brief's KEY line names the key to rotate.
const STOP_CLASSES = new Set(["rate-limit", "auth"]);

// The failed `run`'s limit stop as { failureClass, resetsAt } (epoch ms), or
// null when its lane record does not mark it one. The stated reset is held
// within the limits' clamp after the run ended.
export function limitStop(run, limits = LIMIT_DEFAULTS) {
  const ended = Date.parse(run.completed_at ?? "");
  if (!Number.isFinite(ended) || run.conclusion !== "failure") {
    return null;
  }
  const record = laneRecord(run);
  if (!STOP_CLASSES.has(record?.failureClass)) {
    return null;
  }
  // An impossible date (month 13) parses to NaN: treat it as no stated reset.
  const stated = record.resets ? Date.parse(record.resets) : Number.NaN;
  return { failureClass: record.failureClass, resetsAt: clampReset(Number.isFinite(stated) ? stated : null, ended, limits) };
}

// When the limit that stopped the failed `run` resets (epoch ms), or null when
// it is no limit stop.
export const limitResetsAt = (run, limits = LIMIT_DEFAULTS) => limitStop(run, limits)?.resetsAt ?? null;

// The limit stop among `runs` that has not reset by `now` and resets last, or
// null: what a dispatcher names when it skips a head that waits on one.
export function pendingStop(runs, { now, limits = LIMIT_DEFAULTS }) {
  let pending = null;
  for (const run of runs) {
    const stop = limitStop(run, limits);
    if (stop && now < stop.resetsAt && !(pending?.resetsAt >= stop.resetsAt)) {
      pending = stop;
    }
  }
  return pending;
}

// The lane record classes of a run whose model never started
// (ci-workflows docs/lane-outcome.md, Failure classes): the CLI install failed,
// or the sandbox probe kept the run from starting. Such a failure says
// nothing about the head, so it holds: it neither handles the head nor counts
// toward `limit-stops-per-head`, and the next tick dispatches again. Every
// other failure still counts, a red run with no record and `no-credential`
// included: a missing secret fails the same way every tick, like `auth`.
const FAULT_CLASSES = new Set(["install-failed", "sandbox-unavailable"]);
const faultStop = (run) => run?.status === "completed" && run.conclusion === "failure" && FAULT_CLASSES.has(laneRecord(run)?.failureClass);

const untrustedSkip = (run) =>
  run.status === "completed" &&
  run.conclusion === "neutral" &&
  String(run.output?.title ?? "").startsWith("Skipped: untrusted-trigger");

// A run that neither handles the head nor counts toward its cap.
const ignored = (run) => untrustedSkip(run) || faultStop(run);

// The neutral check a run skipped on a held PR posts (report-check-run's
// `Skipped: <reason>` title).
const heldSkip = (run) => run.status === "completed" && run.conclusion === "neutral" && run.output?.title === "Skipped: awaiting-human";

// The gate's head-lag stop (check-trusted-trigger.mjs fetchPull), which
// report-check-run posts as a superseded-sha skip (gate-skip-reasons.json) on
// the head the run read. Every other superseded-sha check lands on a head the
// PR has left (a cancel, a moved tip before the mint or the push), so on the
// head a dispatcher reads, the PR's current one, it is a lag stop that did no
// work there.
export const HEAD_LAG_STOP = "Skipped: superseded-sha";
export const headLagStop = (run) => run?.status === "completed" && run.conclusion === "neutral" && run.output?.title === HEAD_LAG_STOP;

// Three opt-ins, for a dispatcher that checks the PR's holds itself before it
// reads the check runs: with `heldSkipsRelease` a held skip stops handling the
// head, so a head skipped while held is dispatched once the hold is gone; with
// `lagStopsRelease` a head-lag stop on the head read does too, so a round the
// gate stopped on a lagging API read is sent again; with `failuresRetry` a
// failed run of any kind does too. Either way the head is handled once
// `limit-stops-per-head` of them, limit stops included, stand on it, so a
// dispatcher and a run that disagree about a hold stop there. A newer run
// still going handles the head, and a newer finished one decides it, so each
// stop is sent again once.
const released = (run, { heldSkipsRelease = false, lagStopsRelease = false } = {}) =>
  (heldSkipsRelease && heldSkip(run)) || (lagStopsRelease && headLagStop(run)) || killSwitchStop(run);

// The neutral check a run the lanes kill switch stopped posts: its own
// kill-switch step, or the broker refusing its mint for a switch turned on
// after the run read its variables. The dispatchers run only with the switch
// off, so such a run never handles its head, and every dispatcher reads it
// like a held skip: it counts toward `limit-stops-per-head`, so a switch that
// keeps flipping mid-run still ends the head there.
export const KILL_SWITCH_STOP = "Skipped: kill-switch";
export const killSwitchStop = (run) => run?.status === "completed" && run.conclusion === "neutral" && run.output?.title === KILL_SWITCH_STOP;

// Whether an emitter (push, reply or verdict) check releases the head's
// earlier activity checks for a same-head retry: a lane stop, or a
// kill-switch stop, which did no work.
export const releasesHead = (run) => laneStop(run) || killSwitchStop(run);

// Whether `runs` handle the head: any run that is not an untrusted skip, a
// fault stop, a kill-switch stop or a reset limit stop does, and so do
// `limit-stops-per-head` such stops (fault stops aside).
export function anyHandles(runs, { now, limits = LIMIT_DEFAULTS, failuresRetry = false, ...opt }) {
  let stops = 0;
  for (const run of runs) {
    if (ignored(run)) {
      continue;
    }
    if (released(run, opt)) {
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
  // cappedAt needs every finished run retryable, so the two cases are disjoint.
  return done.some((run) => !retryable(run)) || cappedAt(runs, options) > 0;
}

function completedRuns(runs, { limits = LIMIT_DEFAULTS, failuresRetry = false, ...opt }) {
  const done = runs.filter((run) => run.status === "completed" && !ignored(run));
  const retryable = (run) => released(run, opt) || (failuresRetry ? run.conclusion === "failure" : limitResetsAt(run, limits) !== null);
  return { done, retryable };
}

// With an opt-in, the number of finished runs when every one is retryable and
// they reach `limit-stops-per-head`, the head's hard end, else 0: the part of
// permanentlyHandles a dispatcher reports as a stop. A head with any other
// finished run (a success, an escalation) is done, not capped.
export function cappedAt(runs, { limits = LIMIT_DEFAULTS, failuresRetry = false, heldSkipsRelease = false, lagStopsRelease = false } = {}) {
  if (!failuresRetry && !heldSkipsRelease && !lagStopsRelease) {
    return 0;
  }
  const { done, retryable } = completedRuns(runs, { limits, failuresRetry, heldSkipsRelease, lagStopsRelease });
  return done.length >= limits["limit-stops-per-head"] && done.length > 0 && done.every(retryable) ? done.length : 0;
}

const startOf = (run) => Date.parse(run?.started_at ?? "");

// How a head's emitter checks (`stopRuns`, REST shape) release its activity
// checks for a same-head retry: `cut` is the newest emitter check's start
// when that check releases the head (releasesHead) and fewer than `cap` such
// checks stand on it (the dispatcher's own per-head cap), so activity checks
// that started before it stop counting; null otherwise. `stops` counts them.
export function stopRelease(stopRuns, cap) {
  const stops = stopRuns.filter(releasesHead).length;
  const newest = stopRuns.reduce((a, b) => (startOf(b) > startOf(a) ? b : a), stopRuns[0]);
  return { cut: releasesHead(newest) && stops < cap ? startOf(newest) : null, stops };
}

// `runs` without those started before `cut`, a limit stop kept.
export const releasedBy = (runs, cut, limits = LIMIT_DEFAULTS) =>
  cut === null ? runs : runs.filter((run) => limitResetsAt(run, limits) !== null || !(startOf(run) < cut));

