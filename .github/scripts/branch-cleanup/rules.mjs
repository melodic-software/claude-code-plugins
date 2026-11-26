import { parseLaneBranch } from "../lib/lane-branch.mjs";

export const BRANCH_CLEANUP_DEFAULTS = Object.freeze({
  "max-deletes-per-run": 25,
});

const VALID = {
  "max-deletes-per-run": (value) => Number.isInteger(value) && value >= 0 && value <= 100,
};

export const resolveBranchCleanup = (leaf) =>
  Object.fromEntries(
    Object.entries(BRANCH_CLEANUP_DEFAULTS).map(([key, value]) => [key, VALID[key](leaf?.[key]) ? leaf[key] : value]),
  );

const EXCLUDED_PREFIXES = ["release/", "dependabot/", "gh-readonly-queue/"];

export function excluded(name, defaultBranch) {
  if (name === defaultBranch) return "the default branch";
  const prefix = EXCLUDED_PREFIXES.find((p) => name.startsWith(p));
  return prefix ? `a ${prefix}* branch` : null;
}

export function laneIssue(name) {
  const match = parseLaneBranch(name);
  return match ? Number(match.issue) : null;
}

export function linkedIssues(body, repo) {
  const escaped = repo.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const ref = `(?:#|${escaped}#|https://github\\.com/${escaped}/issues/)([1-9][0-9]*)\\b`;
  const pattern = new RegExp(`\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?)\\b:?\\s+${ref}`, "gi");
  return [...new Set([...String(body ?? "").matchAll(pattern)].map((m) => Number(m[1])))];
}

export const lastPull = (pulls) => [...pulls].sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))[0] ?? null;
