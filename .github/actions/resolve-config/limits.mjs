// The `limits` leaf of pr-pipeline.yaml: the resolved object holds every key,
// each missing one at its default. Durations are hours. The lane scripts read
// the resolved file through .github/scripts/work-resolve-issue/limits.mjs,
// which repeats these defaults (limits.test.mjs checks the two agree), because
// some workflows check out resolve-config without the scripts directory.

export const DEFAULT_LIMITS = Object.freeze({
  "fallback-reset": 5,
  "reset-clamp-min": 1,
  "reset-clamp-max": 168,
  "restarts-per-run": 5,
  "limit-stops-per-head": 3,
  "limit-stops-per-issue": 3,
});

// The schema has already checked `value`.
export function withLimitDefaults(value) {
  return { ...DEFAULT_LIMITS, ...value };
}
