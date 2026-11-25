// The `limits` leaf of pr-pipeline.yaml (pr-pipeline.schema.json) as the lane
// scripts read it from resolve-config's output: its defaults, in hours and
// counts, and the reset clamp the lanes share. It imports no package and sits
// beside report-outcome.mjs, which runs from a copy of this directory alone.
import { readFileSync } from "node:fs";

const HOUR_MS = 3_600_000;

const overDefaults = (defaults, set, valid) =>
  Object.fromEntries(Object.entries(defaults).map(([key, value]) => [key, valid(set?.[key], key) ? set[key] : value]));

const readConfig = (path) => {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return undefined;
  }
};

export const LIMIT_DEFAULTS = Object.freeze({
  "fallback-reset": 5,
  "reset-clamp-min": 1,
  "reset-clamp-max": 168,
  "restarts-per-run": 5,
  "refire-queue-per-slot": 2,
  "refire-budget-per-slot": 1,
  "stale-queued-minutes": 60,
  "sweep-gap-minutes": 15,
  "readmit-per-run": 20,
  "parent-rescan-per-run": 5,
  "limit-stops-per-head": 3,
  "limit-stops-per-issue": 3,
  "wip-cap": 60,
  "turn-cap-restarts": 0,
  "stop-retries": 2,
});
const ZERO_ALLOWED = new Set(["turn-cap-restarts", "stop-retries", "sweep-gap-minutes"]);

export const resolveLimits = (limits) =>
  overDefaults(LIMIT_DEFAULTS, limits, (set, key) => Number.isInteger(set) && set >= (ZERO_ALLOWED.has(key) ? 0 : 1));

export function readLimits(path) {
  const limits = readConfig(path)?.limits;
  return { ...resolveLimits(limits), ...resolveAdmission(limits), "stranded-backoff-hours": resolveStrandedBackoff(limits?.["stranded-backoff-hours"]) };
}

export const STRANDED_BACKOFF_MAX = 24;
export const STRANDED_BACKOFF_DEFAULTS = Object.freeze({
  "no-run": 3,
  "no-report": 3,
  "failed-again": 3,
  "failed-mint": 3,
  "kill-switch": 3,
});

export const resolveStrandedBackoff = (hours) =>
  overDefaults(STRANDED_BACKOFF_DEFAULTS, hours, (set) => Number.isInteger(set) && set >= 1 && set <= STRANDED_BACKOFF_MAX);

const finite = (value) => typeof value === "number" && Number.isFinite(value);
const positive = (value) => finite(value) && value > 0;

export const ADMISSION_DEFAULTS = Object.freeze({
  "admission-factor": 0.8,
  "admission-min-per-hour": 1,
});
const ADMISSION_VALID = {
  "admission-factor": (value) => positive(value) && value <= 1,
  "admission-min-per-hour": (value) => finite(value) && value >= 0 && value <= 100,
};

export const resolveAdmission = (limits) => overDefaults(ADMISSION_DEFAULTS, limits, (set, key) => ADMISSION_VALID[key](set));

export const WIP_DEFAULTS = Object.freeze({
  "target-lead-time-hours": 2,
  "min-cap": 1,
  "merge-rate-window-hours": 24,
  "opened-to-merged-ratio": 0.8,
  "held-cap": 60,
  "held-alarm-hours": 24,
  "pause-from": "",
});

const WIP_VALID = {
  "target-lead-time-hours": positive,
  "min-cap": (value) => Number.isInteger(value) && value >= 1 && value <= 500,
  "merge-rate-window-hours": (value) => Number.isInteger(value) && value > 0,
  "opened-to-merged-ratio": (value) => positive(value) && value <= 1,
  "held-cap": (value) => Number.isInteger(value) && value > 0,
  "held-alarm-hours": positive,
  "pause-from": (value) => value === "" || (typeof value === "string" && Number.isFinite(Date.parse(value))),
};

export const resolveWip = (wip) => overDefaults(WIP_DEFAULTS, wip, (set, key) => WIP_VALID[key](set));

export function readWip(path) {
  return resolveWip(readConfig(path)?.wip);
}

export const clampReset = (resets, from, limits = LIMIT_DEFAULTS) =>
  Math.min(
    Math.max(resets ?? from + limits["fallback-reset"] * HOUR_MS, from + limits["reset-clamp-min"] * HOUR_MS),
    from + limits["reset-clamp-max"] * HOUR_MS,
  );
