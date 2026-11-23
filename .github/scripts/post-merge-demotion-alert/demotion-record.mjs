export const DEMOTION = "babysit-merge-demotion";
export const FAILURE = "post-merge-failure";
export const KINDS = Object.freeze([DEMOTION, FAILURE]);
export const SIGNALS = Object.freeze(["schedule", "dispatch", "canary", "revert", "read-back"]);

const LINE = new RegExp(`^<!-- (${KINDS.join("|")}) sha=([0-9a-f]{40}) signal=(${SIGNALS.join("|")}) -->$`);

export const recordMarker = (kind, sha, signal) => `<!-- ${kind} sha=${sha} signal=${signal} -->`;

export const recordPrefix = (kind, sha) => `<!-- ${kind} sha=${sha} `;

export function parseRecordMarker(line) {
  const match = LINE.exec(String(line ?? ""));
  return match && { kind: match[1], sha: match[2], signal: match[3] };
}
