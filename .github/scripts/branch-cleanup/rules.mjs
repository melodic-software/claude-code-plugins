// The branch-cleanup rule as pure functions: which branches the job never
// touches, which issues a branch is linked to, and whether a closed branch is
// old enough to delete. docs/conventions/pr-pipeline/README.md, "Branch
// cleanup", states the rule; cleanup.mjs reads GitHub and calls these.
import { DIMENSION_STEPS } from "../work-resolve-issue/report-outcome.mjs";

// The `branch-cleanup` leaf of pr-pipeline.yaml (pr-pipeline.schema.json);
// the one copy of its defaults.
export const BRANCH_CLEANUP_DEFAULTS = Object.freeze({
  "min-age-days": 14,
  "max-deletes-per-run": 25,
});

const VALID = {
  "min-age-days": (value) => Number.isInteger(value) && value >= 1 && value <= 365,
  "max-deletes-per-run": (value) => Number.isInteger(value) && value >= 0 && value <= 100,
};

// Every leaf, each valid set value over its default.
export const resolveBranchCleanup = (leaf) =>
  Object.fromEntries(
    Object.entries(BRANCH_CLEANUP_DEFAULTS).map(([key, value]) => [key, VALID[key](leaf?.[key]) ? leaf[key] : value]),
  );

const EXCLUDED_PREFIXES = ["release/", "dependabot/", "gh-readonly-queue/"];

// Why the job never looks at a branch, or null.
export function excluded(name, defaultBranch) {
  if (name === defaultBranch) return "the default branch";
  const prefix = EXCLUDED_PREFIXES.find((p) => name.startsWith(p));
  return prefix ? `a ${prefix}* branch` : null;
}

// {issue, run} for a work-resolve-issue lane branch
// (work-resolve-issue/issue-<n>-<run id>-<attempt>), else null.
const LANE = /^work-resolve-issue\/issue-([1-9][0-9]*)-([1-9][0-9]*)-([1-9][0-9]*)$/;
export function laneBranch(name) {
  const match = LANE.exec(name);
  return match ? { issue: Number(match[1]), run: match[2] } : null;
}

// Issue numbers in this repository a pull request body links with Closes,
// Fixes, Resolves or Refs (any case, optional colon), as `#n`,
// `owner/repo#n` or an issue URL. A link to another repository is ignored.
export function linkedIssues(body, repo) {
  const escaped = repo.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const ref = `(?:#|${escaped}#|https://github\\.com/${escaped}/issues/)([1-9][0-9]*)\\b`;
  const pattern = new RegExp(`\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?)\\b:?\\s+${ref}`, "gi");
  return [...new Set([...String(body ?? "").matchAll(pattern)].map((m) => Number(m[1])))];
}

// Whether a lanes-App outcome marker on the issue records a stopped run
// (needs a human, blocked, limited, funding, turn-cap) whose work may sit on
// this lane branch. A marker naming this run, naming no run, or left by a
// resumed run that kept no branch of its own (its work is on an earlier lane
// branch) counts; a dimension skip ran nothing and does not.
export function stoppedRun(markers, run) {
  return markers.some(
    (m) =>
      !Object.hasOwn(DIMENSION_STEPS, m.outcome) && (m.run === run || m.run === "" || m.run === "0" || m.onResumed),
  );
}

const DAY_MS = 86_400_000;

// Days since the latest of `times` (ISO strings), or null when one is unreadable.
export function ageDays(times, now) {
  const parsed = times.map((t) => Date.parse(t ?? ""));
  if (parsed.length === 0 || parsed.some((t) => !Number.isFinite(t))) return null;
  return (Date.parse(now) - Math.max(...parsed)) / DAY_MS;
}

// The branch's pull request the rule reads: the newest by creation.
export const lastPull = (pulls) => [...pulls].sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))[0] ?? null;
