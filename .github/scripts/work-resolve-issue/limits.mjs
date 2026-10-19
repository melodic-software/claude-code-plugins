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

// When a limit stop at `from` may restart: its stated reset (else the
// fallback), held between the clamp's bounds after the stop, so a reset in the
// past cannot start a tight restart loop and one far off cannot park the work.
export const clampReset = (resets, from, limits = LIMIT_DEFAULTS) =>
  Math.min(
    Math.max(resets ?? from + limits["fallback-reset"] * HOUR_MS, from + limits["reset-clamp-min"] * HOUR_MS),
    from + limits["reset-clamp-max"] * HOUR_MS,
  );
