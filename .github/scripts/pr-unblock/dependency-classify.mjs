// Sorts an open Dependabot pull request into a review tier, with no model:
//
//   auto    every update is a patch or minor bump, a github_actions bump comes
//           from an allowlisted publisher, and ci-status is not red. The
//           pr-merge lane merges these.
//   review  anything else: a major bump, a publisher outside the allowlist, a
//           group holding a major, a red ci-status, or a title or version this
//           cannot read. The pr-unblock lane's review-dependency activity
//           reviews these.
//
// It reads only what Dependabot wrote: the title, the head branch and, for a
// group, the body's `Updates` lines at the start of a line (release notes are
// quoted, so they never start one). A group whose lines do not add up to its
// title's count is review, so text in the body can only make a PR stricter.
// The same rules hold wherever a lane sorts Dependabot PRs; the contract is in
// docs/conventions/pr-pipeline/pr-run-activity.md, "prepare: dependency-review".

export const DEPENDABOT_LOGIN = "dependabot[bot]";
// The publishers pr-automerge-dependabot.yml and the dependabot.yml
// vendor-actions group allow.
export const ACTIONS_PUBLISHERS = Object.freeze(["actions", "github", "anthropics"]);
const RED = new Set(["failure", "cancelled", "timed_out", "action_required", "startup_failure"]);

const SINGLE = /\bbump (\S+) from (\S+) to (\S+?)(?:\s+in\s.*)?$/i;
const GROUP = /\bbump the \S+ group\b.*\bwith (\d+) updates?\s*$/i;
const UPDATE_LINE = /^Updates `([^`\s]+)` from (\S+) to (\S+?)\.?$/gm;
const VERSION = /^v?(\d+)(\.\d+)*([-+.][0-9A-Za-z.+-]*)?$/;

// true when the first numeric component changed, false when it did not, null
// when either side is not a version (a SHA, a branch name).
export function isMajor(from, to) {
  const a = VERSION.exec(String(from));
  const b = VERSION.exec(String(to));
  if (!a || !b) {
    return null;
  }
  return Number(a[1]) !== Number(b[1]);
}

export function isSecurityUpdate({ labels = [], body = "" }) {
  return (
    labels.some((label) => String(label).toLowerCase() === "security") ||
    /\bsecurity advisory\b|\bGHSA(-[0-9a-z]{4}){3}\b|\bCVE-\d{4}-\d{4,}\b/i.test(String(body))
  );
}

function parseUpdates(title, body) {
  const subject = String(title).replace(/^[a-z]+(\([^)]*\))?!?:\s*/i, "");
  const group = GROUP.exec(subject);
  if (group) {
    const updates = [...String(body).matchAll(UPDATE_LINE)].map((match) => ({
      name: match[1],
      from: match[2],
      to: match[3],
    }));
    return updates.length === Number(group[1]) ? { updates } : { updates, problem: "unparsed-group" };
  }
  const single = SINGLE.exec(subject);
  if (!single) {
    return { updates: [], problem: "unparsed-title" };
  }
  return { updates: [{ name: single[1], from: single[2], to: single[3] }] };
}

// pr: { author, headRef, title, body, labels, ciStatus }, where ciStatus is
// the newest ci-status check run's conclusion, or pending or empty.
// Returns null for a pull request Dependabot did not open.
export function classify(pr) {
  if (pr.author !== DEPENDABOT_LOGIN) {
    return null;
  }
  const ecosystem = /^dependabot\/([^/]+)\//.exec(String(pr.headRef))?.[1] ?? "";
  const { updates, problem } = parseUpdates(pr.title, pr.body);
  const reasons = problem ? [problem] : [];
  if (!problem) {
    for (const update of updates) {
      const major = isMajor(update.from, update.to);
      if (major === null) {
        reasons.push(`unparsed-version:${update.name}`);
      } else if (major) {
        reasons.push(`major:${update.name}`);
      }
      if (ecosystem === "github_actions" && !ACTIONS_PUBLISHERS.includes(update.name.split("/")[0])) {
        reasons.push(`publisher:${update.name}`);
      }
    }
  }
  if (RED.has(pr.ciStatus)) {
    reasons.push("ci-status-red");
  }
  return {
    tier: reasons.length === 0 ? "auto" : "review",
    reasons,
    ecosystem,
    updates,
    security: isSecurityUpdate(pr),
  };
}
