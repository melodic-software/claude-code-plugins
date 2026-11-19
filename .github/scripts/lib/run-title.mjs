export const PREFIXES = Object.freeze({
  "pr-merge.yml": Object.freeze(["pr-merge", "PR Merge"]),
  "pr-rate-merge-risk.yml": Object.freeze(["merge-risk", "PR Rate Merge Risk"]),
  "pr-refine.yml": Object.freeze(["pr-refine", "PR Refine"]),
  "pr-unblock.yml": Object.freeze(["pr-unblock", "PR Unblock"]),
  "pr-verify-capture.yml": Object.freeze(["pr-verify-capture", "PR Verify Capture"]),
});

const each = (workflow, rest) => PREFIXES[workflow].map((prefix) => `${prefix}${rest}`);
const anchored = (workflow, rest, flags = "") => new RegExp(`^(?:${PREFIXES[workflow].join("|")})${rest}$`, flags);

export const prMergeTitle = (pr) => each("pr-merge.yml", `: arm #${pr}`)[0];
export const PR_MERGE_TITLE = anchored("pr-merge.yml", ": arm #(.*)", "s");

export const mergeRiskTitle = (pr, head) => each("pr-rate-merge-risk.yml", ` #${pr} ${head}`)[0];
export const isMergeRiskTitle = (title, pr, head) => each("pr-rate-merge-risk.yml", ` #${pr} ${head}`).includes(title);

export const prRefineTitle = (activity, number) => each("pr-refine.yml", ` ${activity} #${number}`)[0];
export const isPrRefineTitle = (title, activity, number) => each("pr-refine.yml", ` ${activity} #${number}`).includes(title);

export const prUnblockTitle = (activity, number) => each("pr-unblock.yml", ` ${activity} #${number}`)[0];
export const isPrUnblockTitle = (title, activity, number) => each("pr-unblock.yml", ` ${activity} #${number}`).includes(title);
export const PR_UNBLOCK_TITLE = anchored("pr-unblock.yml", " ([a-z]+(?:-[a-z]+)*) #([1-9][0-9]{0,9})");

export const prVerifyCaptureTitle = (upstreamRunId, headSha) => each("pr-verify-capture.yml", ` ${upstreamRunId} ${headSha}`)[0];
export const isPrVerifyCaptureTitle = (title, upstreamRunId, headSha) =>
  each("pr-verify-capture.yml", ` ${upstreamRunId} ${headSha}`).includes(title);
export const PR_VERIFY_CAPTURE_TITLE = anchored("pr-verify-capture.yml", " ([1-9][0-9]{0,19}) ([0-9a-f]{40})");
