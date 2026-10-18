// The lane limit settings: the `limits` leaf of pr-pipeline.yaml, each value an
// integer. Durations are hours. The lane scripts read them from a resolved
// config file here. It sits beside report-outcome.mjs, which runs from a copy
// of its own directory; resolve-config repeats the defaults in its own
// limits.mjs, and limits.test.mjs checks the two agree.

import { readFileSync } from "node:fs";

export const HOUR_MS = 3_600_000;

export const DEFAULT_LIMITS = Object.freeze({
  "fallback-reset": 5,
  "reset-clamp-min": 1,
  "reset-clamp-max": 168,
  "restarts-per-run": 5,
  "limit-stops-per-head": 3,
  "limit-stops-per-issue": 3,
});

const positive = (value) => Number.isSafeInteger(value) && value >= 1;

// The limits of a resolved-config object, for a script that cannot trust the
// file: a key that is not a positive integer, or a clamp whose minimum
// exceeds its maximum, falls back to the default.
export function limitsFrom(resolved) {
  const given = resolved?.limits ?? {};
  const limits = { ...DEFAULT_LIMITS };
  for (const key of Object.keys(DEFAULT_LIMITS)) {
    if (positive(given[key])) {
      limits[key] = given[key];
    }
  }
  if (limits["reset-clamp-min"] > limits["reset-clamp-max"]) {
    limits["reset-clamp-min"] = DEFAULT_LIMITS["reset-clamp-min"];
    limits["reset-clamp-max"] = DEFAULT_LIMITS["reset-clamp-max"];
  }
  return limits;
}

// The limits of the resolved-config file at `path`; the defaults when the file
// is missing or unreadable.
export function readLimits(path) {
  try {
    return limitsFrom(JSON.parse(readFileSync(path, "utf8")));
  } catch {
    return { ...DEFAULT_LIMITS };
  }
}
