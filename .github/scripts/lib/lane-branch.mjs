const NUMBER = "[1-9][0-9]*";

export const WORK_RESOLVE_ISSUE = "work-resolve-issue";

export const laneBranch = (lane, issue, run, attempt) => `${lane}/issue-${issue}-${run}-${attempt}`;

export const laneBranchPrefix = (lane, issue) => `${lane}/issue-${issue}-`;

export const laneBranchPattern = (lane, issue) => new RegExp(`^${laneBranchPrefix(lane, issue)}(?<run>${NUMBER})-(?<attempt>${NUMBER})$`);

export function parseLaneBranch(name, { lanePattern = WORK_RESOLVE_ISSUE, runPattern = NUMBER } = {}) {
  const match = new RegExp(`^(?<lane>${lanePattern})/issue-(?<issue>${NUMBER})-(?<run>${runPattern})-(?<attempt>${NUMBER})$`).exec(String(name ?? ""));
  return match ? { ...match.groups } : null;
}
