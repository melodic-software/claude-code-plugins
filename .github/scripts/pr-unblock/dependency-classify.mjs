// Sorts an open Dependabot pull request into a review tier, with no model, by
// the rules the pr-merge lane applies: a line-for-line port of
// plugins/source-control/skills/babysit-prs/scripts/babysit_dependabot.py
// (`classify`, `parse_metadata`, `parse_title`, `is_major`, `commit_refusal`,
// `commits_refusal`, `parse_config`, `glob_regex`, `content_refusal`, and the
// fix rule `in_fix_scope`, `is_fix_file`, `is_semver_range`,
// `fix_content_refusal` and `fix_refusal`) and its
// caller's commit and content steps (`dependabot_eligibility` and
// `_dependabot_content` in babysit_merge_policy.py). Contract:
// docs/conventions/pr-pipeline/README.md, "Dependabot pull requests".
//
//   auto    every update is non-major (the first numeric version component
//           does not change, and below 1.0 the second does not either), every
//           github_actions update comes from an allowlisted publisher,
//           ci-status is not red, and the diff is only what Dependabot
//           manages. The pr-merge lane merges these.
//   review  anything else, including anything this cannot read, every
//           update to a dependency the standards Dependabot policy lists under
//           autoMerge.reviewOnly (reviewOnly), and an npm or pip update whose
//           registry provenance changed (withProvenance). The pr-unblock
//           lane's review-dependency activity reviews these.
//
// The updates come from the `updated-dependencies` metadata in Dependabot's
// commits when there is any, and from the title (`bump <name> from <a> to
// <b>`) or a group's body `Updates` lines at the start of a line otherwise
// (release notes are quoted, so they never start one); when both read they
// must name the same dependencies and agree on which are major. A commit the
// pr-merge lane refuses (not GitHub-verified, not committed by GitHub, or
// neither Dependabot's nor the version-bump commit) is a review reason here,
// so the AI review owns the pull request; it never sorts `auto`.

export const DEPENDABOT_LOGIN = "dependabot[bot]";
// Dependabot's account id. GraphQL names the Bot "dependabot" and REST
// "dependabot[bot]", so a GraphQL listing matches it by id.
export const DEPENDABOT_ID = 49699333;
export const DEPENDABOT_AUTHOR = Object.freeze(["dependabot[bot]", "49699333+dependabot[bot]@users.noreply.github.com"]);
export const ACTIONS_AUTHOR = Object.freeze(["github-actions[bot]", "41898282+github-actions[bot]@users.noreply.github.com"]);
export const ACTIONS_PUBLISHERS = Object.freeze(["actions", "github", "anthropics"]);
export const GITHUB_COMMITTER_EMAIL = "noreply@github.com";
export const SKIP_MARKER = "[dependabot skip]";
const BUMP_PATH = /^plugins\/[A-Za-z0-9._-]+\/(\.claude-plugin\/plugin\.json|CHANGELOG\.md)$/;
export const RED = new Set(["failure", "cancelled", "timed_out", "action_required", "startup_failure"]);

const PREFIX = /^[a-z]+(\([^)]*\))?!?:\s*/i;
const SINGLE = /\bbump (\S+) from (\S+) to (\S+?)(?:\s+in\s.*)?$/i;
const GROUP = /\bbump the \S+ group\b.*\bwith (\d+) updates?\s*$/i;
const UPDATE_LINE = /^Updates `([^`\s]+)` from (\S+) to (\S+?)\.?$/gm;
const VERSION = /^v?(\d+)(?:\.(\d+))?(?:\.\d+)*(?:[-+.][0-9A-Za-z.+-]*)?$/;
const ECOSYSTEM = /^dependabot\/([^/]+)\//;
// Dependabot quotes a value YAML would misread, such as a scoped npm name.
const ENTRY = /^-\s+dependency-name:\s*(["']?)([^"'\s]+)\1\s*$/;
const FIELD = /^\s+(dependency-version|update-type):\s*(["']?)([^"'\s]+)\2\s*$/;

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
      entries.push({ name: entry[2] });
    } else if (field && entries.length > 0) {
      entries.at(-1)[field[1]] = field[3];
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
    return { name: entry.name, major, version: entry["dependency-version"] ?? null };
  });
}

// The jump a metadata entry with no `update-type` (a security update writes
// none) reads from its own Dependabot commit's subject, never the editable PR
// title: only when the subject opens with `Bump <pkg> from <a> to <b>` for the
// same package and the entry's version is `<b>`; null otherwise, a group
// subject included.
export function subjectMajor(message, update) {
  const subject = String(message ?? "").split("\n", 1)[0].replace(PREFIX, "");
  if (update.version === null || update.version === undefined || GROUP.test(subject)) {
    return null;
  }
  const single = SINGLE.exec(subject);
  if (!single || single.index !== 0 || single[1] !== update.name || single[3] !== update.version) {
    return null;
  }
  return isMajor(single[2], single[3]);
}

// The updates the title names, or a group's body `Updates` lines when they add
// up to its count; null when neither reads.
export function parseTitle(title, body) {
  const subject = String(title ?? "").replace(PREFIX, "");
  const group = GROUP.exec(subject);
  if (group) {
    const found = [...String(body ?? "").matchAll(UPDATE_LINE)].map((m) => ({ name: m[1], major: isMajor(m[2], m[3]), version: m[3] }));
    return found.length === Number(group[1]) ? found : null;
  }
  const single = SINGLE.exec(subject);
  return single ? [{ name: single[1], major: isMajor(single[2], single[3]), version: single[3] }] : null;
}

const signed = (item) => [item?.commit?.author?.name, item?.commit?.author?.email];
const isAuthor = (item, author) => signed(item)[0] === author[0] && signed(item)[1] === author[1];
export const isDependabotCommit = (item) => isAuthor(item, DEPENDABOT_AUTHOR);
export const isActionsCommit = (item) => isAuthor(item, ACTIONS_AUTHOR);

// Why one REST pull-request commit may not merge, or null: it is
// GitHub-verified, committed by GitHub, and Dependabot's or the repository's
// `[dependabot skip]` version-bump commit (github-actions[bot], touching only a
// plugin's plugin.json or CHANGELOG.md). `files(sha)` lists a commit's paths,
// or null when unreadable. The pr-merge lane's lanes App admission is left
// out: a lanes App fix commit keeps the pull request `review`, which pr-merge
// merges only on a round marker.
export function commitRefusal(item, files) {
  const commit = item?.commit ?? {};
  const sha = String(item?.sha || "?").slice(0, 12);
  if (commit.verification?.verified !== true) {
    return `commit-unverified:${sha}`;
  }
  if (commit.committer?.email !== GITHUB_COMMITTER_EMAIL) {
    return `commit-not-committed-by-github:${sha}`;
  }
  if (isDependabotCommit(item)) {
    return null;
  }
  if (!isActionsCommit(item) || !String(commit.message ?? "").includes(SKIP_MARKER)) {
    return `commit-not-dependabot:${sha}`;
  }
  const paths = files(String(item?.sha ?? ""));
  if (!paths?.length || paths.some((path) => !BUMP_PATH.test(path))) {
    return `commit-not-version-bump:${sha}`;
  }
  return null;
}

// The first commit that may not merge, or `commits-missing`.
export function commitsRefusal(commits, files) {
  if (!commits.length) {
    return "commits-missing";
  }
  for (const item of commits) {
    const refusal = commitRefusal(item, files);
    if (refusal) return refusal;
  }
  return null;
}

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
// A pinned `uses:` line: its indent and key, the action path, the full SHA.
const PINNED_USES = /^[+-](\s*(?:-\s+)?uses:\s*)([^\s#@]+)@([0-9a-f]{40})(?:\s+#.*)?\s*$/;

// Why a Dependabot change to a workflow or action file (either side of a
// rename) is not a pin swap, or null. Each change block in its patch must
// remove and add the same number of lines, and each removed line pairs in
// order with an added `uses:` line that keeps its indent and action path,
// both pinned to a full SHA: only the SHA and the trailing comment differ.
// `files` is the REST pull-request files listing with patches.
export function pinSwapRefusal(files) {
  const isWorkflow = (path) => /^\.github\/workflows\//i.test(path) || ACTION.test(path);
  for (const file of files) {
    const paths = [file.filename, file.previous_filename].filter(Boolean).map(String);
    if (!paths.some(isWorkflow)) continue;
    const where = paths.find(isWorkflow);
    if (!["modified", "renamed"].includes(file.status) || typeof file.patch !== "string") return `${where}:not-a-modification`;
    const blocks = [];
    let block = null;
    for (const line of file.patch.split("\n")) {
      if (/^[+-]/.test(line)) {
        block ??= { removed: [], added: [] };
        if (line[0] === "-" && block.added.length) return `${where}:interleaved`;
        (line[0] === "-" ? block.removed : block.added).push(line);
      } else if (!line.startsWith("\\")) {
        if (block) blocks.push(block);
        block = null;
      }
    }
    if (block) blocks.push(block);
    if (blocks.length === 0) return `${where}:no-pin-change`;
    for (const { removed, added } of blocks) {
      if (removed.length !== added.length) return `${where}:lines-added-or-removed`;
      for (const [i, before] of removed.entries()) {
        const after = added[i];
        if (!USES_LINE.test(before) || !USES_LINE.test(after)) return `${where}:not-a-uses-line`;
        const [, oldKey, oldPath, oldSha] = PINNED_USES.exec(before) ?? [];
        const [, newKey, newPath, newSha] = PINNED_USES.exec(after) ?? [];
        if (!oldSha || !newSha) return `${where}:not-a-full-sha`;
        if (oldKey !== newKey || oldPath !== newPath) return `${where}:action-changed`;
      }
    }
  }
  return null;
}
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

// What the lanes App's fix on a reviewed Dependabot pull request may change:
// npm and pip manifests and lock files only, narrower than MANIFESTS (no
// setup.py, pyproject.toml or other file a build runs).
const FIX_MANIFESTS = Object.freeze({
  npm: /^(package\.json|package-lock\.json|npm-shrinkwrap\.json)$/,
  pip: /^requirements[^/]*\.(txt|in)$/,
});

// Whether a fix may change `path`: one of FIX_MANIFESTS in a directory of
// its ecosystem in `config` (the base dependabot.yml's [ecosystem, directory]
// pairs), never under .github/. A fix that changes anything else does not
// land, and the pull request goes to a person. No config admits nothing.
// The pr-merge lane's twin is `in_fix_scope` in babysit_dependabot.py, as
// for every fix rule below.
export function inFixScope(path, config) {
  const text = String(path ?? "");
  const name = text.slice(text.lastIndexOf("/") + 1);
  return (
    !/^\.github(\/|$)/i.test(text) &&
    Array.isArray(config) &&
    config.some((pair) => Array.isArray(pair) && FIX_MANIFESTS[pair[0]]?.test(name) && typeof pair[1] === "string" && inDirectory(text, pair[1]))
  );
}

// web-flow, the committer GitHub records on the commits it signs.
export const WEB_FLOW_ID = 19864447;

// A commit Dependabot authored and GitHub committed and signed for it: the
// account ids as well as the name and email, so a fix commit is never taken
// for Dependabot's on its author text alone.
export const isDependabotSigned = (item) =>
  isDependabotCommit(item) &&
  item?.author?.id === DEPENDABOT_ID &&
  item?.committer?.id === WEB_FLOW_ID &&
  item?.commit?.verification?.verified === true &&
  item.commit.verification.reason === "valid";

// A fix changes only regular, non-executable files: no symbolic link
// (120000), submodule (160000) or executable (100755). `entry` is the GraphQL
// tree entry at the fix's tip.
export const FIX_MODE = 0o100644;
export const isFixFile = (entry) => entry?.type === "blob" && entry.mode === FIX_MODE;

const DEPENDENCY_SECTIONS = Object.freeze(["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"]);
const RANGE_VERSION = /^v?([0-9]+|[xX*])(\.([0-9]+|[xX*])){0,2}(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/;
const COMPARATOR = /^(\^|~|[<>]=?|=)?v?([0-9]+|[xX*])(\.([0-9]+|[xX*])){0,2}(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/;
export const NPM_REGISTRY_TARBALL = "https://registry.npmjs.org/";
const REQUIREMENT = /^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?(\[[A-Za-z0-9._,-]+\])?==[0-9][0-9A-Za-z.+!-]*(\s*;\s*[A-Za-z0-9_.'"<>=!~ ()]+?)?(\s+\\)?$/;
const HASH_LINE = /^\s+--hash=sha256:[0-9a-f]{64}(\s+\\)?$/;

// A plain semver range: comparators (`^1.2.3`, `>=1 <2`, `1.x`), a hyphen
// range, or `||` of either. No dist-tag, alias, URL, path, git or GitHub
// shorthand, or workspace protocol.
// Every set is bounded: no wildcard major (`*`, `x`) and no set of lower
// bounds alone (`>=0`, `>1.2`).
const WILD_MAJOR = /^(\^|~|[<>]=?|=)?v?[xX*]/;
export function isSemverRange(value) {
  if (typeof value !== "string" || value.length === 0 || value.length > 200) return false;
  return value.split("||").every((part) => {
    const set = part.trim();
    const hyphen = /^(\S+) - (\S+)$/.exec(set);
    if (hyphen) return [hyphen[1], hyphen[2]].every((v) => RANGE_VERSION.test(v) && !WILD_MAJOR.test(v));
    const comparators = set.split(/\s+/);
    return (
      set !== "" &&
      comparators.every((comparator) => COMPARATOR.test(comparator) && !WILD_MAJOR.test(comparator)) &&
      !comparators.every((comparator) => /^>/.test(comparator))
    );
  });
}

const parseJson = (text) => {
  try {
    const value = JSON.parse(String(text));
    return value !== null && typeof value === "object" && !Array.isArray(value) ? value : null;
  } catch {
    return null;
  }
};
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const canonical = (value) =>
  Array.isArray(value)
    ? `[${value.map(canonical).join(",")}]`
    : isObject(value)
      ? `{${Object.keys(value)
          .sort()
          .map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`)
          .join(",")}}`
      : JSON.stringify(value);

// package.json: only the version range of a dependency already listed in a
// dependency section changes, to a plain semver range. Any other key
// (scripts, overrides, resolutions, bin, ...) stays as it was.
export function packageJsonRefusal(before, after) {
  const old = parseJson(before);
  const now = parseJson(after);
  if (!old || !now) return "package-json-unreadable";
  for (const key of [...new Set([...Object.keys(old), ...Object.keys(now)])].sort()) {
    if (!DEPENDENCY_SECTIONS.includes(key)) {
      if (canonical(old[key]) !== canonical(now[key])) return `package-json-key:${key}`;
      continue;
    }
    const was = old[key];
    const is = now[key];
    if (!isObject(was) || !isObject(is)) return `package-json-key:${key}`;
    const names = Object.keys(was).sort();
    if (canonical(names) !== canonical(Object.keys(is).sort())) return `package-json-entries:${key}`;
    for (const name of names) {
      if (canonical(was[name]) !== canonical(is[name]) && !isSemverRange(is[name])) return `package-json-range:${key}:${name}`;
    }
  }
  return null;
}

// The package a lock key installs: the last `node_modules/<name>` of the
// path, or the entry's `name` for an alias.
const LOCK_KEY = /^(?:node_modules\/(?:@[^/]+\/)?[^/@][^/]*\/)*node_modules\/((?:@[^/]+\/)?[^/@][^/]*)$/;
const PACKAGE_NAME = /^(@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*$/;
const LOCK_VERSION = /^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$/;
const INTEGRITY = /^sha512-[A-Za-z0-9+/]+={0,2}$/;

// Why one `packages` entry is not a registry tarball of its own name and
// version, or null. Its alias `name` is the before side's (`was`): a fix
// never adds, drops or changes one, so it cannot repoint a key.
function lockEntryRefusal(key, entry, was) {
  const at = LOCK_KEY.exec(key);
  if (!at || !isObject(entry)) return `lock-key:${key}`;
  if (canonical(isObject(was) ? was.name : undefined) !== canonical(entry.name)) return `lock-name:${key}`;
  const name = entry.name ?? at[1];
  if (typeof name !== "string" || !PACKAGE_NAME.test(name) || typeof entry.version !== "string" || !LOCK_VERSION.test(entry.version)) {
    return `lock-entry:${key}`;
  }
  const tarball = `${NPM_REGISTRY_TARBALL}${name}/-/${name.slice(name.lastIndexOf("/") + 1)}-${entry.version}.tgz`;
  if (entry.link !== undefined || entry.resolved !== tarball) return `lock-resolved:${key}`;
  if (typeof entry.integrity !== "string" || !INTEGRITY.test(entry.integrity)) return `lock-integrity:${key}`;
  return null;
}

// package-lock.json and npm-shrinkwrap.json: every `packages` entry but the
// root is the registry tarball its key and version name, with a sha512
// integrity; the fix adds and removes no package (the before side is the
// Dependabot commit's lock, so its own additions stand); every other
// `resolved` is a registry tarball; and no package gains or loses an
// install script.
export function lockRefusal(before, after) {
  const old = parseJson(before);
  const now = parseJson(after);
  if (!old || !now) return "lock-unreadable";
  if (!isObject(old.packages) || !isObject(now.packages)) return "lock-packages";
  const keys = Object.keys(now.packages).sort();
  if (canonical(keys) !== canonical(Object.keys(old.packages).sort())) return "lock-packages-changed";
  for (const key of keys) {
    const why = key === "" ? null : lockEntryRefusal(key, now.packages[key], old.packages[key]);
    if (why) return why;
  }
  const stack = [now];
  while (stack.length) {
    const node = stack.pop();
    for (const [key, value] of Object.entries(node)) {
      if (key === "resolved" && !(typeof value === "string" && value.startsWith(NPM_REGISTRY_TARBALL))) return "lock-resolved";
      if (value !== null && typeof value === "object") stack.push(value);
    }
  }
  const was = isObject(old.packages) ? old.packages : {};
  const is = isObject(now.packages) ? now.packages : {};
  for (const name of [...new Set([...Object.keys(was), ...Object.keys(is)])].sort()) {
    if ((was[name]?.hasInstallScript === true) !== (is[name]?.hasInstallScript === true)) return `lock-install-script:${name}`;
  }
  return null;
}

// requirements*.txt and .in: every line the fix adds is blank, a comment, a
// `name==version` pin (extras and an environment marker allowed), or an
// indented `--hash=sha256:` continuation. No option line (`--index-url`,
// `--extra-index-url`, `-e`, `-r`, `-c`, ...), URL or VCS requirement.
// A requirement line's project name, normalized (PEP 503), or null.
const PROJECT = /^([A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)/;
const projectOf = (line) => {
  const name = /^[A-Za-z0-9]/.test(line) ? PROJECT.exec(line)?.[1] : null;
  return name ? name.toLowerCase().replace(/[-_.]+/g, "-") : null;
};

// Every pin the fix adds names a project a line it removed named: a fix
// repins, it adds no package.
export function requirementsRefusal(before, after) {
  if (typeof before !== "string" || typeof after !== "string") return "requirements-unreadable";
  const kept = new Map();
  for (const line of before.split("\n")) kept.set(line, (kept.get(line) ?? 0) + 1);
  const added = [];
  for (const line of after.split("\n")) {
    if (kept.get(line)) {
      kept.set(line, kept.get(line) - 1);
      continue;
    }
    const text = line.replace(/\r$/, "");
    if (!/^\s*(#.*)?$/.test(text) && !REQUIREMENT.test(text) && !HASH_LINE.test(text)) return "requirements-line";
    if (REQUIREMENT.test(text)) added.push(projectOf(text));
  }
  const removed = new Set([...kept].filter(([, count]) => count > 0).map(([line]) => projectOf(line.replace(/\r$/, ""))));
  const fresh = added.find((name) => !removed.has(name));
  return fresh === undefined ? null : `requirements-new-package:${fresh}`;
}

// Why the fix's change to `path` from `before` to `after` (the file's text on
// each side) is not a version change, or null.
export function fixContentRefusal(path, before, after) {
  const name = String(path ?? "").slice(String(path ?? "").lastIndexOf("/") + 1);
  if (name === "package.json") return packageJsonRefusal(before, after);
  if (name === "package-lock.json" || name === "npm-shrinkwrap.json") return lockRefusal(before, after);
  if (/^requirements[^/]*\.(txt|in)$/.test(name)) return requirementsRefusal(before, after);
  return "content-unchecked";
}

// The first reason a fix's changed files (a REST compare or commit `files`
// listing) are not a lane fix, or null: each file only modified in place,
// in fix scope for `config`, a regular file at the tip (`entry(path)`, read
// before any content, since a contents read follows a symbolic link), and a
// version change from `text("before", path)` to `text("after", path)`.
export async function fixRefusal(files, config, { entry, text }) {
  for (const file of files) {
    const path = String(file?.filename ?? "");
    if (file?.status !== "modified" || file.previous_filename) return `fix-status:${path}`;
    if (!inFixScope(path, config)) return `fix-scope:${path}`;
    if (!isFixFile(await entry(path))) return `fix-mode:${path}`;
    const why = fixContentRefusal(path, await text("before", path), await text("after", path));
    if (why) return `fix-content:${path}:${why}`;
  }
  return null;
}

// The version-bump commit's plugin.json: only `version` changes, to a
// plain version; every other key stays as it was.
export function pluginJsonRefusal(before, after) {
  const old = parseJson(before);
  const now = parseJson(after);
  if (!old || !now) return "plugin-json-unreadable";
  if (typeof now.version !== "string" || !LOCK_VERSION.test(now.version)) return "plugin-json-version";
  const rest = ({ version, ...other }) => canonical(other);
  return rest(old) === rest(now) ? null : "plugin-json-key";
}

// The first reason the repository's version-bump commit (its files, as in
// fixRefusal) is more than a version bump, or null: each file a plugin's
// plugin.json or CHANGELOG.md, modified in place as a regular file, and a
// plugin.json changing only its `version`. CHANGELOG.md is text.
export async function bumpRefusal(files, { entry, text }) {
  if (!files.length) return "bump-empty";
  for (const file of files) {
    const path = String(file?.filename ?? "");
    if (file?.status !== "modified" || file.previous_filename) return `bump-status:${path}`;
    if (!BUMP_PATH.test(path)) return `bump-path:${path}`;
    if (!isFixFile(await entry(path))) return `bump-mode:${path}`;
    if (path.endsWith("/plugin.json")) {
      const why = pluginJsonRefusal(await text("before", path), await text("after", path));
      if (why) return `bump-content:${path}:${why}`;
    }
  }
  return null;
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

// Whether a review-only entry covers a changed path: the path sits in the
// entry's directory (glob-aware), or the entry is github-actions and the path
// is a workflow or action file it covers, as the content rule reads them.
function entryCovers(entry, path) {
  return inDirectory(path, entry.directory) || (entry.ecosystem === "github-actions" && actionsFile(path, [[entry.ecosystem, entry.directory]]));
}

// As babysit_dependabot.review_only: { reasons, entries } where reasons holds
// `review-only:<dependency>` for each autoMerge.reviewOnly entry of the parsed
// policy that names this repository (any case), the head branch's ecosystem,
// one of `updates`, and a changed path the entry covers (entryCovers; any
// path when `paths` is null), in entry order, and entries the entries that
// matched; reasons is [dependabot-policy-unreadable] when the policy is null
// or undefined, has no reviewOnly list, or holds an entry missing a string
// field.
export function reviewOnly(policy, repository, headRef, updates, paths) {
  const entries = policy?.autoMerge?.reviewOnly;
  if (!Array.isArray(entries) || !entries.every((e) => e !== null && typeof e === "object" && REVIEW_ONLY_KEYS.every((k) => typeof e[k] === "string"))) {
    return { reasons: [POLICY_UNREADABLE], entries: [] };
  }
  const segment = ECOSYSTEM.exec(String(headRef ?? ""))?.[1] ?? "";
  const ecosystem = Object.hasOwn(BRANCH_ECOSYSTEMS, segment) ? BRANCH_ECOSYSTEMS[segment] : segment;
  const names = new Set(updates.map((u) => u.name));
  const reasons = [];
  const matched = [];
  for (const entry of entries) {
    const reason = `review-only:${entry.dependency}`;
    if (
      entry.repository.toLowerCase() === String(repository).toLowerCase() &&
      entry.ecosystem === ecosystem &&
      names.has(entry.dependency) &&
      (paths === null || paths.some((path) => entryCovers(entry, path))) &&
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
// With `files` (the REST files listing, patches included), `totalCommits`
// (the pull request's own commit count), `config`
// (parseConfig of the base's .github/dependabot.yml), `changedFiles` and
// `commitFiles`, the commit and content steps apply too. Returns null for a pull
// request Dependabot did not open.
export function classify(pr) {
  if (pr.author !== DEPENDABOT_LOGIN) {
    return null;
  }
  const ecosystem = ECOSYSTEM.exec(String(pr.headRef ?? ""))?.[1] ?? "";
  let metadata = null;
  for (const item of pr.commits ?? []) {
    if (isDependabotCommit(item)) {
      const message = String(item.commit?.message ?? "");
      const entries = parseMetadata(message);
      if (entries !== null) {
        metadata = [...(metadata ?? []), ...entries.map((u) => (u.major === null ? { ...u, major: subjectMajor(message, u) } : u))];
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
    // The commits listing stops at 250, so a prefix is never read as all.
    const listed = (pr.commits ?? []).length;
    if (!Number.isInteger(pr.totalCommits) || pr.totalCommits !== listed) {
      reasons.push(`commits-listed:${listed}-of:${pr.totalCommits}`);
    }
    const refusal = commitsRefusal(pr.commits ?? [], pr.commitFiles ?? (() => null));
    if (refusal) reasons.push(refusal);
    const content = contentStep(pr);
    if (content) reasons.push(content);
  }
  // The review-only step over `policy` (parsed policy.json; null or absent is
  // unreadable) and `repository`, over the changed paths when the config
  // reads and `files` is the whole listing, as the pr-merge lane reads them.
  const whole = Array.isArray(pr.files) && pr.config != null && pr.changedFiles === pr.files.length;
  const paths = whole ? pr.files.flatMap((f) => [f.filename, f.previous_filename].filter(Boolean).map(String)) : null;
  const listed = reviewOnly(pr.policy ?? null, pr.repository ?? "", pr.headRef, updates, paths);
  reasons.push(...listed.reasons);
  return {
    tier: reasons.length === 0 ? "auto" : "review",
    reasons,
    ecosystem,
    updates,
    security: isSecurityUpdate(pr),
    reviewOnly: listed.entries,
  };
}

// The provenance gate, as babysit_dependabot.provenance_reasons: each npm or
// pip update's publisher identity against the newest earlier stable version
// that has one. Rule: README, "Registry provenance".
export const PROVENANCE_TIMEOUT_MS = 10_000;
export const PROVENANCE_CALL_CAP = 20;
const PROVENANCE_ECOSYSTEMS = Object.freeze({ npm_and_yarn: "npm", pip: "pip" });
const NPM_REGISTRY = "https://registry.npmjs.org";
const PYPI = "https://pypi.org";
const SIMPLE_JSON = "application/vnd.pypi.simple.v1+json";
const INTEGRITY_JSON = "application/vnd.pypi.integrity.v1+json";
const SLSA = /^https:\/\/slsa\.dev\/provenance\/v/;
const NPM_STABLE = /^\d+\.\d+\.\d+$/;
const PIP_STABLE = /^\d+(\.\d+)*(\.post\d+)?$/;

class Unreadable extends Error {}

// The registry's JSON at `url`; throws on a non-2xx answer, a timeout or a
// body that is not JSON.
export async function registryFetch(url, accept) {
  const response = await fetch(url, { headers: { accept }, signal: AbortSignal.timeout(PROVENANCE_TIMEOUT_MS) });
  if (!response.ok) {
    throw new Unreadable(`HTTP ${response.status}`);
  }
  return response.json();
}

const repoName = (url) =>
  String(url)
    .replace(/^git\+/, "")
    .replace(/^https:\/\/github\.com\//i, "")
    .replace(/\.git$/, "")
    .toLowerCase();
const npmPath = (name) => (name.startsWith("@") ? `@${encodeURIComponent(name.slice(1))}` : encodeURIComponent(name));
const changed = (name, before, now) => (now === null ? `provenance-missing:${name}` : now === before ? null : `provenance-changed:${name}`);

// One npm version's identity: the SLSA provenance's workflow repository and
// path (never the ref), else the trusted publisher's oidcConfigId without any
// `oidc:` prefix, else null.
async function npmIdentity(name, version, manifest, get) {
  if (manifest?.dist?.attestations?.url) {
    const body = await get(`${NPM_REGISTRY}/-/npm/v1/attestations/${npmPath(name)}@${encodeURIComponent(version)}`, "application/json");
    const slsa = (body?.attestations ?? []).find((item) => SLSA.test(String(item?.predicateType)));
    const payload = slsa?.bundle?.dsseEnvelope?.payload;
    if (typeof payload !== "string") {
      throw new Unreadable("no SLSA provenance");
    }
    const predicate = JSON.parse(Buffer.from(payload, "base64").toString("utf8"))?.predicate;
    const workflow = predicate?.buildDefinition?.externalParameters?.workflow;
    if (typeof workflow?.repository === "string" && typeof workflow?.path === "string") {
      return `workflow:${repoName(workflow.repository)}:${workflow.path}`;
    }
    // SLSA v0.2, which npm wrote before v1: the ref follows the last `@`.
    const source = predicate?.invocation?.configSource;
    if (typeof source?.uri === "string" && typeof source?.entryPoint === "string") {
      return `workflow:${repoName(source.uri.replace(/@[^@]*$/, ""))}:${source.entryPoint}`;
    }
    throw new Unreadable("no workflow in the provenance");
  }
  const trusted = manifest?._npmUser?.trustedPublisher;
  return typeof trusted?.oidcConfigId === "string" ? `trusted-publisher:${trusted.id ?? ""}:${trusted.oidcConfigId.replace(/^oidc:/, "")}` : null;
}

async function npmReason({ name, version }, get) {
  const doc = await get(`${NPM_REGISTRY}/${npmPath(name)}`, "application/json");
  const versions = doc?.versions;
  const time = doc?.time;
  const at = Date.parse(time?.[version]);
  if (!versions?.[version] || Number.isNaN(at)) {
    throw new Unreadable("the new version is not in the packument");
  }
  const now = await npmIdentity(name, version, versions[version], get);
  const earlier = Object.keys(versions)
    .filter((v) => NPM_STABLE.test(v) && Date.parse(time[v]) < at)
    .sort((a, b) => Date.parse(time[b]) - Date.parse(time[a]));
  for (const v of earlier) {
    const before = await npmIdentity(name, v, versions[v], get);
    if (before !== null) {
      return changed(name, before, now);
    }
  }
  return null;
}

// A distribution file's version: a wheel's second `-` field, an sdist's text
// after its last `-`.
function pipVersion(filename) {
  const wheel = /^[^-]+-([^-]+)-.+\.whl$/.exec(filename);
  const sdist = /^.+-([^-]+)\.(tar\.gz|zip)$/.exec(filename);
  return (wheel?.[1] ?? sdist?.[1])?.toLowerCase() ?? null;
}

// One PyPI version's identity: the PEP 740 publisher kind, repository and
// workflow of its first file (by name) with provenance, else null.
async function pipIdentity(entry, get) {
  // Code-unit order, as Python's sorted().
  const url = entry.provenance.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))[0]?.[1];
  if (url === undefined) {
    return null;
  }
  if (!url.startsWith(`${PYPI}/integrity/`)) {
    throw new Unreadable("a provenance URL off PyPI");
  }
  const publisher = (await get(url, INTEGRITY_JSON))?.attestation_bundles?.[0]?.publisher;
  if (![publisher?.kind, publisher?.repository, publisher?.workflow].every((field) => typeof field === "string")) {
    throw new Unreadable("no publisher in the provenance");
  }
  return `${publisher.kind}:${publisher.repository.toLowerCase()}:${publisher.workflow}`;
}

async function pipReason({ name, version }, get) {
  const doc = await get(`${PYPI}/simple/${name.toLowerCase().replace(/[-_.]+/g, "-")}/`, SIMPLE_JSON);
  if (!Array.isArray(doc?.files)) {
    throw new Unreadable("no files in the simple index");
  }
  const byVersion = new Map();
  for (const file of doc.files) {
    const v = pipVersion(String(file?.filename ?? ""));
    if (v === null || file.yanked) {
      continue;
    }
    const entry = byVersion.get(v) ?? { at: Number.POSITIVE_INFINITY, provenance: [] };
    entry.at = Math.min(entry.at, Date.parse(file["upload-time"]));
    if (typeof file.provenance === "string") {
      entry.provenance.push([String(file.filename), file.provenance]);
    }
    byVersion.set(v, entry);
  }
  const current = byVersion.get(String(version).toLowerCase());
  if (!current || !Number.isFinite(current.at)) {
    throw new Unreadable("the new version is not in the simple index");
  }
  const now = await pipIdentity(current, get);
  const earlier = [...byVersion]
    .filter(([v, entry]) => PIP_STABLE.test(v) && entry.at < current.at)
    .sort((a, b) => b[1].at - a[1].at);
  for (const [, entry] of earlier) {
    const before = await pipIdentity(entry, get);
    if (before !== null) {
      return changed(name, before, now);
    }
  }
  return null;
}

// `provenance-changed:<pkg>`, `provenance-missing:<pkg>` or
// `provenance-unreadable:<pkg>` for each update on an npm_and_yarn or pip
// branch (`segment`), in update order. `get(url, accept)` reads the registry
// and throws on failure; past `cap` reads in all, the rest are unreadable.
export async function provenanceReasons(updates, segment, get = registryFetch, cap = PROVENANCE_CALL_CAP) {
  if (!Object.hasOwn(PROVENANCE_ECOSYSTEMS, segment)) {
    return [];
  }
  const reason = PROVENANCE_ECOSYSTEMS[segment] === "npm" ? npmReason : pipReason;
  let calls = 0;
  const counted = (url, accept) => {
    calls += 1;
    if (calls > cap) {
      throw new Unreadable("past the call cap");
    }
    return get(url, accept);
  };
  const reasons = [];
  for (const update of updates) {
    try {
      if (typeof update.version !== "string" || update.version === "") {
        throw new Unreadable("no version");
      }
      const found = await reason(update, counted);
      if (found) reasons.push(found);
    } catch {
      reasons.push(`provenance-unreadable:${update.name}`);
    }
  }
  return reasons;
}

// The classification with the provenance gate applied. Only a tier `auto`
// one spends registry reads; any other is already reviewed.
// `reasonsOf(updates, segment)` is provenanceReasons over the live registry
// unless a test passes its own.
export async function withProvenance(classification, reasonsOf = provenanceReasons) {
  if (classification?.tier !== "auto") {
    return classification;
  }
  const reasons = await reasonsOf(classification.updates, classification.ecosystem);
  return reasons.length ? { ...classification, tier: "review", reasons } : classification;
}

// The reasons a pull request goes to review only because the classifier
// could not read something: a parse gap, not a risk. Empty when any other
// reason holds.
export const CLASSIFIER_GAPS = Object.freeze(["unparsed-updates", "sources-disagree", "dependabot-config-unreadable", POLICY_UNREADABLE]);
export function classifierGaps(reasons) {
  const gap = (r) => CLASSIFIER_GAPS.includes(r) || r.startsWith("provenance-unreadable:");
  return reasons.length > 0 && reasons.every(gap) ? [...reasons] : [];
}
