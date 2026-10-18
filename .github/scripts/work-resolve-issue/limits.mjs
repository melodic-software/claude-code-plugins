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

// Every leaf, each set positive integer over its default.
export const resolveLimits = (limits) =>
  Object.fromEntries(
    Object.entries(LIMIT_DEFAULTS).map(([key, value]) => {
      const set = limits?.[key];
      return [key, Number.isInteger(set) && set > 0 ? set : value];
    }),
  );

// The limits in resolve-config's output file; the defaults when it is absent
// or unreadable.
export function readLimits(path) {
  try {
    return resolveLimits(JSON.parse(readFileSync(path, "utf8"))?.limits);
  } catch {
    return resolveLimits(undefined);
  }
}

// The `wip` leaf of pr-pipeline.yaml: the issue lane's WIP cap derived from
// the lane merge rate, the admission factor, the held-PR buffer and its age
// alarm, and the date from which the lane pauses over a cap. resolve-config
// passes the leaf through as set; this is the one copy of its defaults.
export const WIP_DEFAULTS = Object.freeze({
  "target-lead-time-hours": 2,
  "merge-rate-window-hours": 24,
  "admission-factor": 0.8,
  "held-cap": 60,
  "held-alarm-hours": 24,
  "pause-from": "",
});

const positive = (value) => typeof value === "number" && Number.isFinite(value) && value > 0;
const WIP_VALID = {
  "target-lead-time-hours": positive,
  "merge-rate-window-hours": (value) => Number.isInteger(value) && value > 0,
  "admission-factor": (value) => positive(value) && value <= 1,
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
