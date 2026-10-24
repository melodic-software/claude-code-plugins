// The `limits` leaf of pr-pipeline.yaml (pr-pipeline.schema.json) as the lane
// scripts read it from resolve-config's output: its defaults, in hours and
// counts, and the reset clamp the lanes share. It imports no package and sits
// beside report-outcome.mjs, which runs from a copy of this directory alone.
import { readFileSync } from "node:fs";

const HOUR_MS = 3_600_000;

export const LIMIT_DEFAULTS = Object.freeze({
  "fallback-reset": 5,
  "reset-clamp-min": 1,
  "reset-clamp-max": 168,
  "restarts-per-run": 5,
  "limit-stops-per-head": 3,
  "limit-stops-per-issue": 3,
  "wip-cap": 60,
});

// Every leaf, each set integer within its range over its default.
export const resolveLimits = (limits) =>
  Object.fromEntries(
    Object.entries(LIMIT_DEFAULTS).map(([key, value]) => {
      const set = limits?.[key];
      return [key, Number.isInteger(set) && set >= 1 ? set : value];
    }),
  );

// The limits in resolve-config's output file, the admission leaves included;
// the defaults when it is absent or unreadable.
export function readLimits(path) {
  let limits;
  try {
    limits = JSON.parse(readFileSync(path, "utf8"))?.limits;
  } catch {
    limits = undefined;
  }
  return { ...resolveLimits(limits), ...resolveAdmission(limits) };
}

const positive = (value) => typeof value === "number" && Number.isFinite(value) && value > 0;

// The two `limits` leaves that pace new issue-lane admissions (check-wip-cap's
// queued cap). They are fractions, so resolveLimits, which keeps whole
// numbers only, leaves them out.
export const ADMISSION_DEFAULTS = Object.freeze({
  "admission-factor": 0.8,
  "admission-min-per-hour": 1,
});
const ADMISSION_VALID = {
  "admission-factor": (value) => positive(value) && value <= 1,
  "admission-min-per-hour": (value) => typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 100,
};

// Both admission leaves, each valid set value over its default.
export const resolveAdmission = (limits) =>
  Object.fromEntries(
    Object.entries(ADMISSION_DEFAULTS).map(([key, value]) => [key, ADMISSION_VALID[key](limits?.[key]) ? limits[key] : value]),
  );

// The `wip` leaf of pr-pipeline.yaml: the issue lane's WIP cap derived from
// the lane merge rate, the opened-to-merged ratio, the held-PR buffer and its age
// alarm, and the date from which the lane pauses over the WIP cap. resolve-config
// passes the leaf through as set; this is the one copy of its defaults.
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

// Every wip leaf, each valid set value over its default.
export const resolveWip = (wip) =>
  Object.fromEntries(Object.entries(WIP_DEFAULTS).map(([key, value]) => [key, WIP_VALID[key](wip?.[key]) ? wip[key] : value]));

// The wip leaf in resolve-config's output file; the defaults when it is absent
// or unreadable.
export function readWip(path) {
  try {
    return resolveWip(JSON.parse(readFileSync(path, "utf8"))?.wip);
  } catch {
    return resolveWip(undefined);
  }
}

// When a limit stop at `from` may restart: its stated reset (else the
// fallback), held between the clamp's bounds after the stop, so a reset in the
// past cannot start a tight restart loop and one far off cannot park the work.
export const clampReset = (resets, from, limits = LIMIT_DEFAULTS) =>
  Math.min(
    Math.max(resets ?? from + limits["fallback-reset"] * HOUR_MS, from + limits["reset-clamp-min"] * HOUR_MS),
    from + limits["reset-clamp-max"] * HOUR_MS,
  );
