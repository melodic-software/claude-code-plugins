import { LIMIT_DEFAULTS, clampReset } from "../work-resolve-issue/limits.mjs";
import { readRecord } from "../lib/lane-outcome.mjs";
import { laneStop } from "./escalation-routes.mjs";

export { ACTIONS_APP_ID, LANE_STOP, laneStop, retryRung } from "./escalation-routes.mjs";

function laneRecord(run) {
  const record = readRecord(run.output?.text);
  if (!record || record.handoff === true || run.name !== `${record.lane} / ${record.activity}`) {
    return null;
  }
  return { failureClass: record.class ?? "", resets: record.class === "rate-limit" ? (record.resets?.at ?? "") : "" };
}

const STOP_CLASSES = new Set(["rate-limit", "auth"]);

export function limitStop(run, limits = LIMIT_DEFAULTS) {
  const ended = Date.parse(run.completed_at ?? "");
  if (!Number.isFinite(ended) || run.conclusion !== "failure") {
    return null;
  }
  const record = laneRecord(run);
  if (!STOP_CLASSES.has(record?.failureClass)) {
    return null;
  }
  const stated = record.resets ? Date.parse(record.resets) : Number.NaN;
  return { failureClass: record.failureClass, resetsAt: clampReset(Number.isFinite(stated) ? stated : null, ended, limits) };
}

export const limitResetsAt = (run, limits = LIMIT_DEFAULTS) => limitStop(run, limits)?.resetsAt ?? null;

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

const FAULT_CLASSES = new Set(["install-failed", "sandbox-unavailable"]);
const faultStop = (run) => run?.status === "completed" && run.conclusion === "failure" && FAULT_CLASSES.has(laneRecord(run)?.failureClass);

const untrustedSkip = (run) =>
  run.status === "completed" &&
  run.conclusion === "neutral" &&
  String(run.output?.title ?? "").startsWith("Skipped: untrusted-trigger");

const ignored = (run) => untrustedSkip(run) || faultStop(run);

const neutralTitled = (run, title) => run?.status === "completed" && run.conclusion === "neutral" && run.output?.title === title;

const heldSkip = (run) => neutralTitled(run, "Skipped: awaiting-human");

export const HEAD_LAG_STOP = "Skipped: superseded-sha";
export const headLagStop = (run) => neutralTitled(run, HEAD_LAG_STOP);

const released = (run, { heldSkipsRelease = false, lagStopsRelease = false } = {}) =>
  (heldSkipsRelease && heldSkip(run)) || (lagStopsRelease && headLagStop(run)) || killSwitchStop(run);

export const KILL_SWITCH_STOP = "Skipped: kill-switch";
export const killSwitchStop = (run) => neutralTitled(run, KILL_SWITCH_STOP);

export const releasesHead = (run) => laneStop(run) || killSwitchStop(run);

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

export function permanentlyHandles(runs, options = {}) {
  const { done, retryable } = completedRuns(runs, options);
  return done.some((run) => !retryable(run)) || cappedAt(runs, options) > 0;
}

function completedRuns(runs, { limits = LIMIT_DEFAULTS, failuresRetry = false, ...opt }) {
  const done = runs.filter((run) => run.status === "completed" && !ignored(run));
  const retryable = (run) => released(run, opt) || (failuresRetry ? run.conclusion === "failure" : limitResetsAt(run, limits) !== null);
  return { done, retryable };
}

export function cappedAt(runs, { limits = LIMIT_DEFAULTS, failuresRetry = false, heldSkipsRelease = false, lagStopsRelease = false } = {}) {
  if (!failuresRetry && !heldSkipsRelease && !lagStopsRelease) {
    return 0;
  }
  const { done, retryable } = completedRuns(runs, { limits, failuresRetry, heldSkipsRelease, lagStopsRelease });
  return done.length >= limits["limit-stops-per-head"] && done.length > 0 && done.every(retryable) ? done.length : 0;
}

const startOf = (run) => Date.parse(run?.started_at ?? "");

export function stopRelease(stopRuns, cap) {
  const stops = stopRuns.filter(releasesHead).length;
  const newest = stopRuns.reduce((a, b) => (startOf(b) > startOf(a) ? b : a), stopRuns[0]);
  return { cut: releasesHead(newest) && stops < cap ? startOf(newest) : null, stops, newest };
}

export const releasedBy = (runs, cut, limits = LIMIT_DEFAULTS) =>
  cut === null ? runs : runs.filter((run) => limitResetsAt(run, limits) !== null || !(startOf(run) < cut));

