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

// The content rule, the same as the pr-merge lane's (babysit_dependabot.py,
// content_refusal): every changed path is a manifest or lock file of an
// ecosystem and directory .github/dependabot.yml lists at the base, or a
// workflow or action file a github-actions entry covers whose diff changes
// only `uses:` lines.
export const MANIFESTS = Object.freeze({
  npm: /^(package\.json|package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml)$/,
  pip: /^(requirements[^/]*\.(txt|in)|pyproject\.toml|uv\.lock|setup\.cfg|setup\.py|Pipfile|Pipfile\.lock|poetry\.lock|pdm\.lock)$/,
});
const WORKFLOW = /^\.github\/workflows\/[^/]+\.ya?ml$/;
const ACTION = /^(.+\/)?action\.ya?ml$/;
const USES_LINE = /^[+-]\s*(-\s+)?uses:\s*[^\s#]+(\s+#.*)?\s*$/;
const CONFIG_ENTRY = /^\s*-\s+package-ecosystem:\s*["']?([A-Za-z0-9_-]+)/;
const CONFIG_DIR = /^\s+directory:\s*["']?([^"'#\s]+)/;
const CONFIG_DIRS = /^\s+directories:\s*$/;
const CONFIG_ITEM = /^\s+-\s+["']?([^"'#\s]+)/;

// [ecosystem, directory] per `updates` entry of a dependabot.yml, one pair
// per directory: [] for an `updates:` key with no entry, null when the text
// has no top-level `updates:` key (not a dependabot.yml it can read).
export function parseConfig(text) {
  const pairs = [];
  let ecosystem = null;
  let inDirs = false;
  for (const line of String(text ?? "").replace(/\r\n/g, "\n").split("\n")) {
    const entry = CONFIG_ENTRY.exec(line);
    const dir = CONFIG_DIR.exec(line);
    const item = CONFIG_ITEM.exec(line);
    if (entry) {
      ecosystem = entry[1];
      inDirs = false;
    } else if (ecosystem && dir) {
      pairs.push([ecosystem, dir[1]]);
      inDirs = false;
    } else if (ecosystem && CONFIG_DIRS.test(line)) {
      inDirs = true;
    } else if (inDirs && item) {
      pairs.push([ecosystem, item[1]]);
    } else if (line.trim() && !line.trimStart().startsWith("#")) {
      inDirs = false;
    }
  }
  return /^updates:\s*(\[\s*\])?\s*(#.*)?$/m.test(String(text ?? "").replace(/\r\n/g, "\n")) ? pairs : null;
}

const dirname = (path) => (path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : "");
// A `directories` glob (docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference,
// "directories or directory", and the "Defining multiple locations for
// manifest files" examples `/lib-*` and the globstar `**/*`, "all
// directories from the current layer and below recursively", as of
// 2026-10-17; recheck when either page changes its glob wording): `*` and
// `?` stay inside one path segment, `**/` is zero or more whole segments,
// and any other `**` crosses segments. Everything else is literal.
export function globRegex(pattern) {
  let out = "";
  for (let i = 0; i < pattern.length; i += 1) {
    if (pattern.startsWith("**/", i)) {
      out += "(?:[^/]*/)*";
      i += 2;
    } else if (pattern.startsWith("**", i)) {
      out += ".*";
      i += 1;
    } else if (pattern[i] === "*") {
      out += "[^/]*";
    } else if (pattern[i] === "?") {
      out += "[^/]";
    } else {
      out += pattern[i].replace(/[.+^${}()|[\]\\]/g, "\\$&");
    }
  }
  return new RegExp(`^${out}$`);
}

function inDirectory(path, directory) {
  const want = directory.replace(/^\/+|\/+$/g, "");
  return /[*?]/.test(want) ? globRegex(want).test(dirname(path)) : dirname(path) === want;
}

function actionsFile(path, config) {
  return config.some(([eco, folder]) => {
    if (eco !== "github-actions") return false;
    if (folder.replace(/^\/+|\/+$/g, "") === "") {
      return WORKFLOW.test(path) || (path.startsWith(".github/actions/") && ACTION.test(path));
    }
    return ACTION.test(path) && inDirectory(path, folder);
  });
}

// Whether a unified diff changes only `uses:` lines (an action repin).
export function usesOnly(patch) {
  const changed = String(patch ?? "")
    .split("\n")
    .filter((line) => /^[+-]/.test(line) && !/^(\+\+\+|---)/.test(line));
  return changed.length > 0 && changed.every((line) => USES_LINE.test(line));
}

// `dependabot-content:<path>` for the first changed path (either side of a
// rename, sorted per file) the rule does not cover, else null. `files` is the
// REST pull-request files listing with patches; `config` is parseConfig's
// result, where null covers nothing.
export function contentReason(files, config) {
  const pairs = config ?? [];
  for (const file of files) {
    const paths = [...new Set([file.filename, file.previous_filename].filter(Boolean).map(String))].sort();
    for (const path of paths) {
      const name = path.slice(path.lastIndexOf("/") + 1);
      const manifest = pairs.some(([eco, folder]) => MANIFESTS[eco]?.test(name) && inDirectory(path, folder));
      if (!manifest && !(actionsFile(path, pairs) && usesOnly(file.patch))) {
        return `dependabot-content:${path}`;
      }
    }
  }
  return null;
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
// Dependabot authored it and GitHub verified its signature. With `files` (the
// REST files listing, patches included) and `config` (parseConfig of the
// base's .github/dependabot.yml), the content rule applies too.
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
  if (Array.isArray(pr.files)) {
    // A config that could not be read or parsed is its own reason: it keeps
    // the PR in review, and the verdict job never posts a merge on it.
    const content = Array.isArray(pr.config) ? contentReason(pr.files, pr.config) : "dependabot-config-unreadable";
    if (content) reasons.push(content);
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
