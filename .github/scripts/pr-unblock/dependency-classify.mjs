// Sorts an open Dependabot pull request into a review tier, with no model, by
// the rules the pr-merge lane applies: a line-for-line port of
// plugins/source-control/skills/babysit-prs/scripts/babysit_dependabot.py
// (`classify`, `parse_metadata`, `parse_title`, `is_major`, `parse_config`,
// `glob_regex`, `content_refusal`) and its caller's content step
// (`_dependabot_content` in babysit_merge_policy.py). Contract:
// docs/conventions/pr-pipeline/README.md, "Dependabot pull requests".
//
//   auto    every update is non-major (the first numeric version component
//           does not change, and below 1.0 the second does not either), every
//           github_actions update comes from an allowlisted publisher,
//           ci-status is not red, and the diff is only what Dependabot
//           manages. The pr-merge lane merges these.
//   review  anything else, including anything this cannot read, and every
//           update to a dependency the standards Dependabot policy lists under
//           autoMerge.reviewOnly (reviewOnly). The pr-unblock lane's
//           review-dependency activity reviews these.
//
// The updates come from the `updated-dependencies` metadata in Dependabot's
// commits when there is any, and from the title (`bump <name> from <a> to
// <b>`) or a group's body `Updates` lines at the start of a line otherwise
// (release notes are quoted, so they never start one); when both read they
// must name the same dependencies and agree on which are major.

export const DEPENDABOT_LOGIN = "dependabot[bot]";
export const DEPENDABOT_AUTHOR = Object.freeze(["dependabot[bot]", "49699333+dependabot[bot]@users.noreply.github.com"]);
export const ACTIONS_AUTHOR = Object.freeze(["github-actions[bot]", "41898282+github-actions[bot]@users.noreply.github.com"]);
export const ACTIONS_PUBLISHERS = Object.freeze(["actions", "github", "anthropics"]);
const RED = new Set(["failure", "cancelled", "timed_out", "action_required", "startup_failure"]);

const PREFIX = /^[a-z]+(\([^)]*\))?!?:\s*/i;
const SINGLE = /\bbump (\S+) from (\S+) to (\S+?)(?:\s+in\s.*)?$/i;
const GROUP = /\bbump the \S+ group\b.*\bwith (\d+) updates?\s*$/i;
const UPDATE_LINE = /^Updates `([^`\s]+)` from (\S+) to (\S+?)\.?$/gm;
const VERSION = /^v?(\d+)(?:\.(\d+))?(?:\.\d+)*(?:[-+.][0-9A-Za-z.+-]*)?$/;
const ECOSYSTEM = /^dependabot\/([^/]+)\//;
const ENTRY = /^-\s+dependency-name:\s*(\S+)\s*$/;
const FIELD = /^\s+(dependency-version|update-type):\s*(\S+)\s*$/;

function versionParts(version) {
  const found = VERSION.exec(String(version));
  if (!found) {
    return null;
  }
  return [Number(found[1]), found[2] === undefined ? null : Number(found[2])];
}

// true when the first numeric version component changed or, below 1.0, the
// second did; null when either side is not a version (a SHA, a branch).
export function isMajor(from, to) {
  const a = versionParts(from);
  const b = versionParts(to);
  if (a === null || b === null) {
    return null;
  }
  return a[0] !== b[0] || (a[0] === 0 && a[1] !== b[1]);
}

// The `updated-dependencies` entries of one commit message as
// [{ name, major }], or null when it has none. A semver-minor update to a 0.x
// version is major.
export function parseMetadata(message) {
  const lines = String(message ?? "").replace(/\r\n/g, "\n").split("\n");
  const start = lines.findIndex((line) => line.trim() === "updated-dependencies:");
  if (start < 0) {
    return null;
  }
  const entries = [];
  for (const line of lines.slice(start + 1)) {
    if (["...", "---"].includes(line.trim()) || (line && !/^[- ]/.test(line))) {
      break;
    }
    const entry = ENTRY.exec(line);
    const field = FIELD.exec(line);
    if (entry) {
      entries.push({ name: entry[1] });
    } else if (field && entries.length > 0) {
      entries.at(-1)[field[1]] = field[2];
    }
  }
  return entries.map((entry) => {
    const kind = String(entry["update-type"] ?? "").replace(/^version-update:/, "");
    const version = versionParts(entry["dependency-version"] ?? "");
    let major = null;
    if (kind === "semver-major") {
      major = true;
    } else if (kind === "semver-patch") {
      major = false;
    } else if (kind === "semver-minor" && version !== null) {
      major = version[0] === 0;
    }
    return { name: entry.name, major };
  });
}

// The updates the title names, or a group's body `Updates` lines when they add
// up to its count; null when neither reads.
export function parseTitle(title, body) {
  const subject = String(title ?? "").replace(PREFIX, "");
  const group = GROUP.exec(subject);
  if (group) {
    const found = [...String(body ?? "").matchAll(UPDATE_LINE)].map((m) => ({ name: m[1], major: isMajor(m[2], m[3]) }));
    return found.length === Number(group[1]) ? found : null;
  }
  const single = SINGLE.exec(subject);
  return single ? [{ name: single[1], major: isMajor(single[2], single[3]) }] : null;
}

const signed = (item) => [item?.commit?.author?.name, item?.commit?.author?.email];
const isAuthor = (item, author) => signed(item)[0] === author[0] && signed(item)[1] === author[1];
export const isDependabotCommit = (item) => isAuthor(item, DEPENDABOT_AUTHOR);
export const isActionsCommit = (item) => isAuthor(item, ACTIONS_AUTHOR);

// The content rule: every changed path is a manifest or lock file of an
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
// A commit's file listing at this length may be cut short (the pr-merge
// lane's COMMIT_FILES_LIMIT).
export const COMMIT_FILES_LIMIT = 300;

// [ecosystem, directory] for each directory of each `updates` entry of a
// dependabot.yml (`directory` or each `directories` item); null when no entry
// reads.
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
  return pairs.length > 0 ? pairs : null;
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
// rename, sorted per file) the rule does not cover and `extra` (the paths the
// version-bump and lanes App fix commits touched) does not hold, else null.
// `files` is the REST pull-request files listing with patches.
export function contentReason(files, config, extra = new Set()) {
  const pairs = config ?? [];
  for (const file of files) {
    const paths = [...new Set([file.filename, file.previous_filename].filter(Boolean).map(String))].sort();
    for (const path of paths) {
      if (extra.has(path)) {
        continue;
      }
      const name = path.slice(path.lastIndexOf("/") + 1);
      const manifest = pairs.some(([eco, folder]) => MANIFESTS[eco]?.test(name) && inDirectory(path, folder));
      if (!manifest && !(actionsFile(path, pairs) && usesOnly(file.patch))) {
        return `dependabot-content:${path}`;
      }
    }
  }
  return null;
}

// The content step, as the pr-merge lane's _dependabot_content: the paths
// every non-Dependabot commit touched count as checked, a non-version-bump
// commit (a lanes App fix) touching .github/ or a commit whose files cannot be
// read whole is a reason (the pr-merge lane refuses those), an unreadable
// config is dependabot-config-unreadable, and a files listing shorter than
// the PR's changed-file count is dependabot-content:files-incomplete.
// `commitFiles(sha)` returns a commit's paths, or null when unreadable.
export function contentStep({ commits = [], commitFiles = () => null, files, config, changedFiles }) {
  const extra = new Set();
  for (const item of commits) {
    if (isDependabotCommit(item)) {
      continue;
    }
    const sha = String(item?.sha ?? "");
    const touched = commitFiles(sha);
    if (!Array.isArray(touched)) {
      return `dependabot-commit-files-unreadable:${sha.slice(0, 12)}`;
    }
    if (!isActionsCommit(item)) {
      const gated = touched.find((p) => p === ".github" || p.startsWith(".github/"));
      if (gated) {
        return `dependabot-fix-content:${gated}`;
      }
    }
    for (const path of touched) extra.add(path);
  }
  if (config === null || config === undefined) {
    return "dependabot-config-unreadable";
  }
  if (!Number.isInteger(changedFiles) || changedFiles !== files.length) {
    return "dependabot-content:files-incomplete";
  }
  return contentReason(files, config, extra);
}

// The standards-synced Dependabot policy, read at the base.
export const POLICY_PATH = ".github/standards/dependabot-policy/policy.json";
export const POLICY_UNREADABLE = "dependabot-policy-unreadable";
// The head branch's ecosystem segment in dependabot.yml spelling; any other
// segment is the same in both.
const BRANCH_ECOSYSTEMS = Object.freeze({ npm_and_yarn: "npm", github_actions: "github-actions" });
const REVIEW_ONLY_KEYS = ["repository", "ecosystem", "directory", "dependency", "control"];

// As babysit_dependabot.review_only: { reasons, entries } where reasons holds
// `review-only:<dependency>` for each autoMerge.reviewOnly entry of the parsed
// policy that names this repository (any case), the head branch's ecosystem,
// one of `updates`, and the directory of a changed path (any directory when
// `paths` is null), in entry order, and entries the entries that matched;
// reasons is [dependabot-policy-unreadable] when the policy is null, has no
// reviewOnly list, or holds an entry missing a string field.
export function reviewOnly(policy, repository, headRef, updates, paths) {
  const entries = policy?.autoMerge?.reviewOnly;
  if (!Array.isArray(entries) || !entries.every((e) => e !== null && typeof e === "object" && REVIEW_ONLY_KEYS.every((k) => typeof e[k] === "string"))) {
    return { reasons: [POLICY_UNREADABLE], entries: [] };
  }
  const segment = ECOSYSTEM.exec(String(headRef ?? ""))?.[1] ?? "";
  const ecosystem = Object.hasOwn(BRANCH_ECOSYSTEMS, segment) ? BRANCH_ECOSYSTEMS[segment] : segment;
  const names = new Set(updates.map((u) => u.name));
  const folders = paths === null ? null : new Set(paths.map(dirname));
  const reasons = [];
  const matched = [];
  for (const entry of entries) {
    const reason = `review-only:${entry.dependency}`;
    if (
      entry.repository.toLowerCase() === String(repository).toLowerCase() &&
      entry.ecosystem === ecosystem &&
      names.has(entry.dependency) &&
      (folders === null || folders.has(entry.directory.replace(/^\/+|\/+$/g, ""))) &&
      !reasons.includes(reason)
    ) {
      reasons.push(reason);
      matched.push(entry);
    }
  }
  return { reasons, entries: matched };
}

export function isSecurityUpdate({ labels = [], body = "" }) {
  return (
    labels.some((label) => String(label).toLowerCase() === "security") ||
    /\bsecurity advisory\b|\bGHSA(-[0-9a-z]{4}){3}\b|\bCVE-\d{4}-\d{4,}\b/i.test(String(body))
  );
}

// pr: { author, headRef, title, body, labels, ciStatus, commits }, where
// ciStatus is the newest ci-status check run's conclusion (pending or empty
// while none completed) and commits is the REST pull-request commits listing.
// With `files` (the REST files listing, patches included), `config`
// (parseConfig of the base's .github/dependabot.yml), `changedFiles` and
// `commitFiles`, the content step applies too. Returns null for a pull
// request Dependabot did not open.
export function classify(pr) {
  if (pr.author !== DEPENDABOT_LOGIN) {
    return null;
  }
  const ecosystem = ECOSYSTEM.exec(String(pr.headRef ?? ""))?.[1] ?? "";
  let metadata = null;
  for (const item of pr.commits ?? []) {
    if (isDependabotCommit(item)) {
      const entries = parseMetadata(String(item.commit?.message ?? ""));
      if (entries !== null) {
        metadata = [...(metadata ?? []), ...entries];
      }
    }
  }
  const titled = parseTitle(pr.title, pr.body);
  const reasons = [];
  let updates = metadata?.length ? metadata : titled;
  if (!updates?.length) {
    reasons.push("unparsed-updates");
    updates = [];
  } else if (metadata?.length && titled?.length) {
    const byName = new Map(titled.map((u) => [u.name, u.major]));
    const names = new Set(metadata.map((u) => u.name));
    if (names.size !== byName.size || [...names].some((name) => !byName.has(name)) || metadata.some((u) => byName.get(u.name) !== u.major)) {
      reasons.push("sources-disagree");
    }
  }
  for (const update of updates) {
    if (update.major === null) {
      reasons.push(`unparsed-version:${update.name}`);
    } else if (update.major) {
      reasons.push(`major:${update.name}`);
    }
    if (ecosystem === "github_actions" && !ACTIONS_PUBLISHERS.includes(update.name.split("/")[0])) {
      reasons.push(`publisher:${update.name}`);
    }
  }
  if (RED.has(pr.ciStatus)) {
    reasons.push("ci-status-red");
  }
  if (Array.isArray(pr.files)) {
    const content = contentStep(pr);
    if (content) reasons.push(content);
  }
  // With `policy` (parsed policy.json, or null when unreadable) and
  // `repository`, the review-only step applies too, over the changed paths
  // when the config reads and `files` is the whole listing, as the pr-merge
  // lane reads them.
  let listed = null;
  if (pr.policy !== undefined) {
    const whole = Array.isArray(pr.files) && pr.config != null && pr.changedFiles === pr.files.length;
    const paths = whole ? pr.files.flatMap((f) => [f.filename, f.previous_filename].filter(Boolean).map(String)) : null;
    listed = reviewOnly(pr.policy, pr.repository ?? "", pr.headRef, updates, paths);
    reasons.push(...listed.reasons);
  }
  return {
    tier: reasons.length === 0 ? "auto" : "review",
    reasons,
    ecosystem,
    updates,
    security: isSecurityUpdate(pr),
    ...(listed ? { reviewOnly: listed.entries } : {}),
  };
}
