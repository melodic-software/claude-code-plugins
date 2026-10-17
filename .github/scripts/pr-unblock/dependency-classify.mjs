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
// A major bump changes the first numeric version component, or for a 0.x
// version the second. It reads only what Dependabot wrote: the
// `updated-dependencies` metadata in the head commit's message when that
// commit is Dependabot's and verified, the title, the head branch and, for a
// group, the body's `Updates` lines at the start of a line (release notes are
// quoted, so they never start one). A group whose lines do not add up to its
// title's count, or metadata that disagrees with the title, is review, so
// text in the body can only make a PR stricter.
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

const parts = (version) => String(version).replace(/^v/, "").split(/[-+]/)[0].split(".").map(Number);

// true when the first numeric component changed, or for a 0.x version the
// second, false when it did not, null when either side is not a version (a
// SHA, a branch name).
export function isMajor(from, to) {
  if (!VERSION.test(String(from)) || !VERSION.test(String(to))) {
    return null;
  }
  const [a, b] = [parts(from), parts(to)];
  return a[0] !== b[0] || (a[0] === 0 && (a[1] ?? 0) !== (b[1] ?? 0));
}

// The `updated-dependencies` YAML block Dependabot writes into its commit
// message: name, version and semver update type per dependency, or null when
// the message holds no such block.
export function parseMetadata(message) {
  const block = /^updated-dependencies:\s*$([\s\S]*?)^\.\.\.\s*$/m.exec(String(message ?? ""));
  if (!block) {
    return null;
  }
  const rows = [];
  for (const line of block[1].split("\n")) {
    const field = /^(- )?\s*(dependency-name|dependency-version|update-type):\s*(\S+)\s*$/.exec(line);
    if (!field) {
      continue;
    }
    if (field[1]) {
      rows.push({});
    }
    const row = rows.at(-1);
    if (!row) {
      return null;
    }
    if (field[2] === "dependency-name") row.name = field[3];
    if (field[2] === "dependency-version") row.to = field[3];
    if (field[2] === "update-type") row.type = /^version-update:semver-(major|minor|patch)$/.exec(field[3])?.[1] ?? "unknown";
  }
  return rows.length > 0 && rows.every((row) => row.name) ? rows : null;
}

const bare = (version) => String(version ?? "").replace(/^v/, "");

function agrees(updates, metadata) {
  const byName = new Map(metadata.map((row) => [row.name, row]));
  return (
    updates.length === metadata.length &&
    updates.every((update) => byName.has(update.name) && (byName.get(update.name).to === undefined || bare(byName.get(update.name).to) === bare(update.to)))
  );
}

// From metadata alone, with no `from` version: a 0.x minor is major too.
function isMajorFromType(update) {
  if (update.type === "major") return true;
  if (update.type === "minor") return parts(update.to)[0] === 0;
  if (update.type === "patch") return false;
  return null;
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

// pr: { author, headRef, title, body, labels, ciStatus, commitMessage },
// where ciStatus is the newest ci-status check run's conclusion, or pending
// or empty, and commitMessage is the head commit's message, passed only when
// Dependabot authored it and GitHub verified its signature.
// Returns null for a pull request Dependabot did not open.
export function classify(pr) {
  if (pr.author !== DEPENDABOT_LOGIN) {
    return null;
  }
  const ecosystem = /^dependabot\/([^/]+)\//.exec(String(pr.headRef))?.[1] ?? "";
  const metadata = parseMetadata(pr.commitMessage);
  let { updates, problem } = parseUpdates(pr.title, pr.body);
  if (metadata && problem) {
    updates = metadata.map((row) => ({ name: row.name, from: null, to: row.to ?? null, type: row.type ?? "unknown" }));
    problem = undefined;
  } else if (metadata && !agrees(updates, metadata)) {
    problem = "metadata-disagrees";
  } else if (metadata) {
    const types = new Map(metadata.map((row) => [row.name, row.type ?? "unknown"]));
    updates = updates.map((update) => ({ ...update, type: types.get(update.name) }));
  }
  const reasons = problem ? [problem] : [];
  if (!problem) {
    for (const update of updates) {
      const computed = update.from === null ? isMajorFromType(update) : isMajor(update.from, update.to);
      const major = computed === null ? null : computed || update.type === "major";
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
