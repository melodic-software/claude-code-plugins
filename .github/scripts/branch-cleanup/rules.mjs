// The branch-cleanup rule as pure functions: which branches the job never
// touches and which issues a branch is linked to.
// docs/conventions/pr-pipeline/README.md, "Branch cleanup", states the rule;
// cleanup.mjs reads GitHub and calls these.

// The `branch-cleanup` leaf of pr-pipeline.yaml (pr-pipeline.schema.json);
// the one copy of its defaults.
export const BRANCH_CLEANUP_DEFAULTS = Object.freeze({
  "max-deletes-per-run": 25,
});

const VALID = {
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

// The issue number of a work-resolve-issue lane branch
// (work-resolve-issue/issue-<n>-<run id>-<attempt>), else null.
const LANE = /^work-resolve-issue\/issue-([1-9][0-9]*)-[1-9][0-9]*-[1-9][0-9]*$/;
export function laneIssue(name) {
  const match = LANE.exec(name);
  return match ? Number(match[1]) : null;
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

// The branch's pull request the rule reads: the newest by creation.
export const lastPull = (pulls) => [...pulls].sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))[0] ?? null;
