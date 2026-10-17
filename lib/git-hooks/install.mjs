#!/usr/bin/env node
// Register a plugin's git-hook entries with the repository's hook manager.
// The contract is the check-placement convention: the entry manifest, the
// HookManager port (detect, list, plan, copy, decline) and verify's drift states.
//
//   install.mjs detect   [common]
//   install.mjs list     [common]
//   install.mjs plan     --scope local|shared [--manager <m>] [common]
//   install.mjs copy     --scope local|shared [--entry <name>]... [--manager <m>] [--force] [common]
//   install.mjs decline  --entry <name> [--undo] [--global] [common]
//   install.mjs verify   [--quiet] [common]
//   common: [--repo <dir>] [--plugin-root <dir>]
//
// The plugin root defaults to two directories up from this file, where the
// vendored copy sits (plugins/<plugin>/lib/git-hooks/install.mjs).
//
// Scripts decide nothing that needs judgment (rule D1). copy writes only files
// the plugin owns outright: the copied check scripts and check lib, the plain
// dispatcher and its <event>.d/ markers, a new .gitattributes, and the
// `git config --local` decline key. Everything else (edits to lefthook or husky
// config, a foreign hook, a manager conflict, an exclude line, a migration, a
// missing tool) comes back from plan as a decisions[] item for the setup agent.
//
// Exit 0 done; 1 verify found drift, or copy refused a locally modified copy or
// a target that is or passes through a symlink;
// 2 usage, a bad manifest, or not a git repository (verify --quiet exits 0).
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  closeSync,
  constants,
  existsSync,
  fstatSync,
  lstatSync,
  mkdirSync,
  openSync,
  readdirSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

export const EVENTS = ["pre-commit", "pre-push", "commit-msg"];
export const MANAGERS = ["lefthook", "husky", "plain"];
const NAME_RE = /^[a-z0-9][a-z0-9-]*$/;
const SCRIPT_RE = /^[A-Za-z0-9._-]+\.sh$/;
const STAMP_RE = /^# (\S+) (\S+) sha256:([0-9a-f]{64})$/;
const SENTINEL = "# checks-dispatcher v1";
const SHARED_DIR = ".githooks";
const ATTRIBUTES_LINE = ".githooks/** text eol=lf";
const LIB_NAME = "check-lib.sh";

const LEFTHOOK_NAMES = ["yml", "yaml", "toml", "json", "jsonc"].flatMap((ext) => [
  `lefthook.${ext}`,
  `.lefthook.${ext}`,
  `.config/lefthook.${ext}`,
]);

// Hook managers this installer does not drive; finding one is a manager-conflict decision.
const FOREIGN = [
  { manager: "pre-commit", files: [".pre-commit-config.yaml", ".pre-commit-config.yml"] },
  {
    manager: "simple-git-hooks",
    files: [".simple-git-hooks.json", ".simple-git-hooks.js", ".simple-git-hooks.cjs", "simple-git-hooks.json"],
    packageKey: "simple-git-hooks",
  },
  { manager: "overcommit", files: [".overcommit.yml"] },
  { manager: "husky-v4", files: [".huskyrc", ".huskyrc.json", ".huskyrc.js", "husky.config.js"], packageKey: "husky" },
];

// The plain dispatcher: one file per event, POSIX sh. It runs a chained
// pre-existing hook first, then every entry registered in <event>.d/ and in the
// clone-only local/<event>.d/, each under bash, and fails if any failed. A
// marker's first line is its script's path relative to the marker's base.
export const DISPATCHER = `#!/bin/sh
${SENTINEL}
# Runs every check registered for this git hook event: <event>.d/ (this
# directory) and local/<event>.d/ (this clone only). Written by a plugin's
# git-hooks installer; a pre-existing hook kept as <event>.pre-checks runs first.
dir=$(dirname "$0")
event=$(basename "$0")
input=""
if [ "$event" = pre-push ]; then
  input=$(mktemp) || exit 1
  trap 'rm -f "$input"' EXIT
  cat >"$input"
fi
feed() {
  if [ -n "$input" ]; then "$@" <"$input"; else "$@"; fi
}
status=0
if [ -f "$dir/$event.pre-checks" ]; then
  feed "$dir/$event.pre-checks" "$@" || status=1
fi
for base in "$dir" "$dir/local"; do
  for marker in "$base/$event.d"/*; do
    [ -f "$marker" ] || continue
    rel=""
    IFS= read -r rel <"$marker" || [ -n "$rel" ] || continue
    if [ ! -f "$base/$rel" ]; then
      echo "checks: $base/$rel is registered but missing" >&2
      status=1
      continue
    fi
    feed bash "$base/$rel" "$@" || status=1
  done
done
exit $status
`;

class UsageError extends Error {}

const lf = (text) => text.replace(/\r\n/g, "\n");
const posix = (p) => p.split(path.sep).join("/");

function git(cwd, args) {
  const r = spawnSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  return { ok: !r.error && r.status === 0, status: r.status, out: (r.stdout ?? "").trim() };
}

// readText(file) -> the text of a regular file of at most MAX_READ bytes, else
// null. Repository contents are untrusted: a symlink as the last component, a
// device, a FIFO or an oversize file reads as absent rather than being followed,
// blocked on, or read whole.
const MAX_READ = 1024 * 1024;
const READ_FLAGS = constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0) | (constants.O_NONBLOCK ?? 0);

function readText(file) {
  let fd;
  try {
    fd = openSync(file, READ_FLAGS);
    const st = fstatSync(fd);
    return st.isFile() && st.size <= MAX_READ ? readFileSync(fd, "utf8") : null;
  } catch {
    return null;
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

// repoInfo(dir) -> the paths every action needs, or null outside a work tree.
export function repoInfo(dir) {
  const top = git(dir, ["rev-parse", "--show-toplevel"]);
  if (!top.ok || !top.out) return null;
  const root = top.out;
  const abs = (p) => path.resolve(root, p);
  return {
    top: root,
    hooksDir: abs(git(root, ["rev-parse", "--git-path", "hooks"]).out),
    excludeFile: abs(git(root, ["rev-parse", "--git-path", "info/exclude"]).out),
    hooksPath: git(root, ["config", "--get", "core.hooksPath"]).out,
  };
}

function entryErrors(entry, i) {
  const where = `entries[${i}]`;
  const errors = [];
  if (!NAME_RE.test(entry?.name ?? "")) errors.push(`${where}.name must match ${NAME_RE.source}`);
  if (!EVENTS.includes(entry?.event)) errors.push(`${where}.event must be one of ${EVENTS.join(", ")}`);
  if (!SCRIPT_RE.test(entry?.script ?? "")) errors.push(`${where}.script must be a .sh file name`);
  if (!Array.isArray(entry?.tools) || !entry.tools.every((t) => NAME_RE.test(t))) {
    errors.push(`${where}.tools must be a list of tool names`);
  }
  if (typeof entry?.rewrites !== "boolean") errors.push(`${where}.rewrites must be true or false`);
  if (entry?.rewrites === true && entry.event === "pre-push") errors.push(`${where}: a pre-push entry cannot rewrite`);
  return [...errors, ...assetErrors(entry?.assets, where)];
}

// assets: optional plugin-relative files copied beside the script under their
// base names, so the names must be distinct and none may be the lib or the script.
function assetErrors(assets, where) {
  if (assets === undefined) return [];
  if (!Array.isArray(assets)) return [`${where}.assets must be a list of paths`];
  const bad = assets.filter((a) => typeof a !== "string" || !a || path.isAbsolute(a) || a.split(/[\\/]/).includes(".."));
  if (bad.length) return [`${where}.assets must be relative paths inside the plugin`];
  const names = assets.map((a) => path.posix.basename(a.replace(/\\/g, "/")));
  if (new Set(names).size !== names.length || names.includes(LIB_NAME)) {
    return [`${where}.assets need distinct base names other than ${LIB_NAME}`];
  }
  return [];
}

const assetName = (asset) => path.posix.basename(asset.replace(/\\/g, "/"));

// validateEntries(manifest) -> list of errors; empty means valid.
export function validateEntries(manifest) {
  if (!Array.isArray(manifest?.entries) || manifest.entries.length === 0) {
    return ["entries.json needs a non-empty entries list"];
  }
  const errors = manifest.entries.flatMap(entryErrors);
  const names = manifest.entries.map((e) => e?.name);
  if (new Set(names).size !== names.length) errors.push("entries.json names an entry twice");
  return errors;
}

function installHint(root, tool) {
  try {
    const req = JSON.parse(readFileSync(path.join(root, "prerequisites.json"), "utf8")).requires ?? [];
    const found = req.find((r) => r.id === tool);
    return found ? Object.values(found.install).join("; ") : null;
  } catch {
    return null;
  }
}

// loadPlugin(root) -> { name, root, entries, libText }; throws UsageError on a bad manifest.
export function loadPlugin(root) {
  let name = path.basename(path.resolve(root));
  try {
    name = JSON.parse(readFileSync(path.join(root, ".claude-plugin", "plugin.json"), "utf8")).name || name;
  } catch {
    // The directory name stands in when plugin.json is absent.
  }
  const file = path.join(root, "git-hooks", "entries.json");
  const text = readText(file);
  if (text === null) throw new UsageError(`${name}: no git-hooks/entries.json`);
  let manifest;
  try {
    manifest = JSON.parse(text);
  } catch (err) {
    throw new UsageError(`${name}: entries.json is not valid JSON: ${err.message}`);
  }
  const errors = validateEntries(manifest);
  if (errors.length) throw new UsageError(`${name}: ${errors.join("; ")}`);
  const libText = readText(path.join(root, "lib", "git-hooks", LIB_NAME));
  if (libText === null) throw new UsageError(`${name}: lib/git-hooks/${LIB_NAME} is missing`);
  return { name, root, entries: manifest.entries, libText };
}

// stampHash(script, lib, assets): sha256 over the LF-normalized script, a NUL,
// the LF-normalized lib, then for each asset in manifest order a NUL and its
// LF-normalized text.
export function stampHash(scriptText, libText, assetTexts = []) {
  const h = createHash("sha256").update(lf(scriptText)).update("\0").update(lf(libText));
  for (const text of assetTexts) h.update("\0").update(lf(text));
  return h.digest("hex");
}

function sourceScript(plugin, entry) {
  const text = readText(path.join(plugin.root, "git-hooks", entry.script));
  if (text === null) throw new UsageError(`${plugin.name}: git-hooks/${entry.script} is missing`);
  return text;
}

function sourceAssets(plugin, entry) {
  return (entry.assets ?? []).map((asset) => {
    const text = readText(path.join(plugin.root, asset));
    if (text === null) throw new UsageError(`${plugin.name}: asset ${asset} is missing`);
    return { name: assetName(asset), text };
  });
}

const sourceHash = (plugin, entry) =>
  stampHash(
    sourceScript(plugin, entry),
    plugin.libText,
    sourceAssets(plugin, entry).map((a) => a.text),
  );

// The installed copy: the source with `# <plugin> <name> sha256:<hex>` as line 2.
export function renderCopy(plugin, entry, scriptText) {
  const lines = lf(scriptText).split("\n");
  const stamp = `# ${plugin.name} ${entry.name} sha256:${sourceHash(plugin, entry)}`;
  return [lines[0], stamp, ...lines.slice(1)].join("\n");
}

// readStamp(copyText) -> { plugin, name, hash, body } or null; body is the copy without its stamp line.
export function readStamp(copyText) {
  const lines = lf(copyText).split("\n");
  const m = STAMP_RE.exec(lines[1] ?? "");
  if (!m) return null;
  return { plugin: m[1], name: m[2], hash: m[3], body: [lines[0], ...lines.slice(2)].join("\n") };
}

function packageKeys(top) {
  try {
    return Object.keys(JSON.parse(readText(path.join(top, "package.json"))) ?? {});
  } catch {
    return [];
  }
}

function foreignEvidence(top) {
  const keys = packageKeys(top);
  return FOREIGN.flatMap((f) => {
    const hits = f.files.filter((file) => existsSync(path.join(top, file)));
    if (f.packageKey && keys.includes(f.packageKey)) hits.push(`package.json "${f.packageKey}"`);
    return hits.map((hit) => ({ manager: f.manager, evidence: hit }));
  });
}

const isHuskyPath = (p) => /^\.husky(\/_)?\/?$/.test(p);

function managerEvidence(info) {
  const found = [];
  const config = LEFTHOOK_NAMES.find((n) => existsSync(path.join(info.top, n)));
  if (config) found.push({ manager: "lefthook", evidence: config });
  if (isHuskyPath(info.hooksPath)) found.push({ manager: "husky", evidence: `core.hooksPath=${info.hooksPath}` });
  else if (existsSync(path.join(info.top, ".husky"))) found.push({ manager: "husky", evidence: ".husky/" });
  if (info.hooksPath === SHARED_DIR) found.push({ manager: "plain", evidence: `core.hooksPath=${SHARED_DIR}` });
  else if (info.hooksPath && !isHuskyPath(info.hooksPath)) {
    found.push({ manager: "unknown", evidence: `core.hooksPath=${info.hooksPath}` });
  }
  return found;
}

// detect(info) -> { manager: lefthook|husky|plain|conflict, evidence[] }
export function detect(info) {
  const evidence = [...managerEvidence(info), ...foreignEvidence(info.top)];
  if (evidence.length === 0) return { manager: "plain", evidence };
  const managers = new Set(evidence.map((e) => e.manager));
  const only = [...managers][0];
  if (managers.size === 1 && MANAGERS.includes(only)) return { manager: only, evidence };
  return { manager: "conflict", evidence };
}

// The directory a scope's copies live in, and the dispatcher directory for plain.
function layout(info, scope, manager) {
  const shared = path.join(info.top, SHARED_DIR);
  if (scope === "shared") return { root: shared, dispatchDir: shared };
  if (manager === "plain" && info.hooksPath === SHARED_DIR) {
    return { root: path.join(shared, "local"), dispatchDir: shared };
  }
  return { root: info.hooksDir, dispatchDir: info.hooksDir };
}

// anchor: the directory trusted as is. Inside the work tree that is its top
// level, since a clone can commit a symlink anywhere below it; a hooks dir under
// the git directory holds nothing committed, so it is its own anchor.
function entryPaths(info, plugin, entry, scope, manager) {
  const { root, dispatchDir } = layout(info, scope, manager);
  const dir = path.join(root, plugin.name);
  return {
    root,
    anchor: root === info.hooksDir ? root : info.top,
    script: path.join(dir, entry.script),
    lib: path.join(dir, LIB_NAME),
    marker: path.join(root, `${entry.event}.d`, `${plugin.name}.${entry.name}`),
    dispatcher: path.join(dispatchDir, entry.event),
  };
}

// The path a hook-manager config names: repo-relative inside the work tree,
// absolute outside it (a local copy under the git directory of a linked worktree).
const configPath = (info, file) => {
  const rel = posix(path.relative(info.top, file));
  return rel.startsWith("..") ? posix(file) : rel;
};
const runLine = (info, file) => {
  const p = configPath(info, file);
  return p === posix(file) ? `bash "${p}"` : `bash ${p}`;
};

function lefthookSnippet(info, plugin, entry, file) {
  const lines = [`${entry.event}:`, "  jobs:", `    - name: ${plugin.name}-${entry.name}`];
  const args = entry.event === "pre-commit" ? "" : " {0}";
  lines.push(`      run: ${runLine(info, file)}${args}`);
  if (entry.event === "pre-push") lines.push("      use_stdin: true");
  return lines.join("\n");
}

function lefthookFile(info, scope) {
  const main = LEFTHOOK_NAMES.find((n) => existsSync(path.join(info.top, n))) ?? "lefthook.yml";
  if (scope === "shared") return main;
  const dir = path.posix.dirname(main);
  const base = path.posix.basename(main).replace(/^(\.?)lefthook\./, "$1lefthook-local.");
  return dir === "." ? base : `${dir}/${base}`;
}

// wiring(info, plugin, entry, scope, manager) -> { wired, decision? }: whether
// the manager runs the copy, and the edit the agent makes when it does not.
function wiring(info, plugin, entry, scope, manager) {
  const p = entryPaths(info, plugin, entry, scope, manager);
  if (manager === "plain") {
    const wired = isDispatcher(readText(p.dispatcher)) && lf(readText(p.marker) ?? "") === markerText(plugin, entry);
    return { wired: wired && (scope === "local" || info.hooksPath === SHARED_DIR) };
  }
  const file = manager === "lefthook" ? lefthookFile(info, scope) : `.husky/${entry.event}`;
  const run = runLine(info, p.script);
  const wired = Boolean(readText(path.join(info.top, file))?.includes(configPath(info, p.script)));
  if (wired) return { wired };
  const snippet =
    manager === "lefthook" ? lefthookSnippet(info, plugin, entry, p.script) : `${run}${entry.event === "pre-commit" ? "" : ' "$@"'}`;
  const kind = manager === "lefthook" ? "lefthook-config" : "husky-config";
  return { wired, decision: { kind, entry: entry.name, file, snippet } };
}

// isDeclined: the entry's key at any git config scope (git's precedence, so a
// local false beats a global true); unset, the master key declines every entry.
// A value that is not a boolean reads as not declined, never as unset.
const MASTER_DECLINE_KEY = "checks.git-hooks.declined";
const declineKey = (plugin, entry) => `checks.${plugin.name}.${entry.name}.declined`;
function configBool(info, key) {
  const r = git(info.top, ["config", "--type=bool", "--get", key]);
  return r.ok ? r.out : r.status === 1 ? "" : "invalid";
}
const isDeclined = (info, plugin, entry) =>
  (configBool(info, declineKey(plugin, entry)) || configBool(info, MASTER_DECLINE_KEY)) === "true";

// copyState(file, entry, current) -> missing | modified | stale | ok, for one
// installed script, its lib and its assets beside it.
function copyState(file, entry, currentHash) {
  const text = readText(file);
  if (text === null) return "missing";
  const stamp = readStamp(text);
  const dir = path.dirname(file);
  const lib = readText(path.join(dir, LIB_NAME));
  const assets = (entry.assets ?? []).map((a) => readText(path.join(dir, assetName(a))));
  if (!stamp || lib === null || assets.includes(null) || stampHash(stamp.body, lib, assets) !== stamp.hash) {
    return "modified";
  }
  return stamp.hash === currentHash ? "ok" : "stale";
}

function whichTool(tool) {
  const exts = process.platform === "win32" ? ["", ".exe", ".cmd", ".bat"] : [""];
  for (const dir of (process.env.PATH ?? "").split(path.delimiter)) {
    if (dir && exts.some((ext) => existsSync(path.join(dir, tool + ext)))) return true;
  }
  return false;
}

function ciMentions(top, tool) {
  const files = [".gitlab-ci.yml", "azure-pipelines.yml", ".circleci/config.yml"].map((f) => path.join(top, f));
  const wf = path.join(top, ".github", "workflows");
  if (existsSync(wf)) files.push(...readdirSync(wf).map((f) => path.join(wf, f)));
  return files.some((f) => readText(f)?.includes(tool));
}

function toolDecisions(info, plugin, entry) {
  return entry.tools.flatMap((tool) => {
    const out = [];
    if (!whichTool(tool)) {
      out.push({ kind: "missing-tool", entry: entry.name, tool, install: installHint(plugin.root, tool) });
    }
    if (!ciMentions(info.top, tool)) out.push({ kind: "no-ci-rerun", entry: entry.name, tool });
    return out;
  });
}

function entryPlan(info, plugin, entry, scope, manager) {
  const decisions = [];
  if (manager === "husky" && scope === "local") {
    decisions.push({ kind: "husky-shared-only", entry: entry.name, detail: "husky has no per-clone hooks; use scope shared" });
    return { actions: [], decisions };
  }
  if (isDeclined(info, plugin, entry)) decisions.push({ kind: "declined", entry: entry.name });
  const p = entryPaths(info, plugin, entry, scope, manager);
  const unsafe = unsafeTarget(info, plugin, entry, scope, manager);
  if (unsafe) decisions.push({ kind: "unsafe-path", entry: entry.name, file: unsafe });
  const state = copyState(p.script, entry, sourceHash(plugin, entry));
  if (state === "modified") decisions.push({ kind: "modified", entry: entry.name, file: p.script });
  if (manager === "plain" && dispatcherState(p.dispatcher) === "modified") {
    decisions.push({ kind: "modified", entry: entry.name, file: p.dispatcher });
  }
  const assets = (entry.assets ?? []).map((a) => path.join(path.dirname(p.script), assetName(a)));
  const action = { op: "copy", entry: entry.name, scope, manager, state, files: [p.script, p.lib, ...assets] };
  if (manager === "plain") action.files.push(p.marker);
  const wire = wiring(info, plugin, entry, scope, manager);
  if (wire.decision) decisions.push(wire.decision);
  decisions.push(...toolDecisions(info, plugin, entry));
  return { actions: [action], decisions };
}

function attributesStep(info) {
  const file = path.join(info.top, ".gitattributes");
  const text = readText(file);
  if (text === null) return { action: { op: "gitattributes", file, line: ATTRIBUTES_LINE } };
  if (text.split(/\r?\n/).includes(ATTRIBUTES_LINE)) return {};
  return { decision: { kind: "gitattributes", file, line: ATTRIBUTES_LINE } };
}

const ignored = (info, rel) => git(info.top, ["check-ignore", "-q", "--no-index", rel]).ok;

function excludeDecision(info, rel) {
  if (ignored(info, rel)) return [];
  return [{ kind: "exclude", file: info.excludeFile, line: `/${rel}` }];
}

function plainDecisions(info, plugin, scope) {
  const out = [];
  const events = [...new Set(plugin.entries.map((e) => e.event))];
  for (const event of events) {
    const { dispatchDir } = layout(info, scope, "plain");
    const file = path.join(dispatchDir, event);
    if (dispatcherState(file) === "foreign") {
      out.push({ kind: "foreign-hook", file, chainAs: `${file}.pre-checks` });
    }
  }
  if (scope === "shared" && info.hooksPath !== SHARED_DIR) {
    out.push({ kind: "hooks-path", command: `git config core.hooksPath ${SHARED_DIR}`, perClone: true });
  }
  if (scope === "local" && info.hooksPath === SHARED_DIR) out.push(...excludeDecision(info, `${SHARED_DIR}/local/`));
  return out;
}

function managerDecisions(info, plugin, scope, manager) {
  if (manager === "plain") return plainDecisions(info, plugin, scope);
  if (manager === "husky") {
    return isHuskyPath(info.hooksPath)
      ? []
      : [{ kind: "husky-install", detail: "core.hooksPath is not .husky/_ in this clone; run the project's husky install" }];
  }
  const out = [];
  const installed = plugin.entries.some((e) => readText(path.join(info.hooksDir, e.event))?.includes("lefthook"));
  if (!installed) out.push({ kind: "lefthook-install", command: "lefthook install" });
  if (scope === "local") out.push(...excludeDecision(info, lefthookFile(info, "local")));
  return out;
}

// Local copies that a shared install would leave behind, for the agent to remove.
function migrateDecision(info, plugin, scope, manager) {
  if (scope !== "shared") return [];
  const files = plugin.entries
    .map((e) => entryPaths(info, plugin, e, "local", manager).script)
    .filter((f) => existsSync(f));
  return files.length ? [{ kind: "migrate", from: "local", files }] : [];
}

// plan(info, plugin, scope, manager?) -> { manager, actions[], decisions[] }
// A local install writes into `git rev-parse --git-path hooks`. With
// core.hooksPath set to anything but the plain shared .githooks, that directory
// belongs to whatever set it (husky's .husky/_, or a foreign tool), so a local
// copy there would either be ignored or overwrite that tool's files.
function hooksDirOwned(info, scope, manager) {
  if (scope !== "local" || manager === "husky" || !info.hooksPath) return null;
  if (manager === "plain" && info.hooksPath === SHARED_DIR) return null;
  return { kind: "hooks-path-owned", hooksPath: info.hooksPath, dir: info.hooksDir };
}

export function plan(info, plugin, scope, override) {
  const found = detect(info);
  const manager = override ?? found.manager;
  if (manager === "conflict") {
    return { manager, actions: [], decisions: [{ kind: "manager-conflict", evidence: found.evidence }] };
  }
  const owned = hooksDirOwned(info, scope, manager);
  if (owned) return { manager, actions: [], decisions: [owned] };
  const actions = [];
  const decisions = [...managerDecisions(info, plugin, scope, manager), ...migrateDecision(info, plugin, scope, manager)];
  for (const entry of plugin.entries) {
    const step = entryPlan(info, plugin, entry, scope, manager);
    actions.push(...step.actions);
    decisions.push(...step.decisions);
  }
  if (scope === "shared" && actions.length) {
    const step = attributesStep(info);
    if (step.action) actions.push(step.action);
    if (step.decision) decisions.push(step.decision);
  }
  return { manager, actions, decisions };
}

// Every file copy writes for one entry, the dispatcher and .gitattributes included.
function copyTargets(info, plugin, entry, scope, manager) {
  const p = entryPaths(info, plugin, entry, scope, manager);
  const dir = path.dirname(p.script);
  const files = [p.lib, ...(entry.assets ?? []).map((a) => path.join(dir, assetName(a))), p.script];
  if (manager === "plain") files.push(p.marker, p.dispatcher);
  if (scope === "shared") files.push(path.join(info.top, ".gitattributes"));
  return { anchor: p.anchor, files };
}

// symlinkOnPath(anchor, file) -> the first path below anchor, down to and
// including file, that is a symbolic link (or file itself when it is not below
// anchor), else null. A write through such a path could land outside the repository.
function symlinkOnPath(anchor, file) {
  const rel = path.relative(anchor, file);
  if (!rel || rel.startsWith("..") || path.isAbsolute(rel)) return file;
  let at = anchor;
  for (const part of rel.split(path.sep)) {
    at = path.join(at, part);
    try {
      if (lstatSync(at).isSymbolicLink()) return at;
    } catch {
      return null; // absent from here down: copy creates it
    }
  }
  return null;
}

function unsafeTarget(info, plugin, entry, scope, manager) {
  const { anchor, files } = copyTargets(info, plugin, entry, scope, manager);
  for (const file of files) {
    const link = symlinkOnPath(anchor, file);
    if (link) return link;
  }
  return null;
}

// Written beside the target and renamed over it, so a link planted after the
// check is replaced rather than followed; the mode is set on that new file only.
function writeIfChanged(file, text, mode) {
  if (readText(file) === text) return false;
  mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  try {
    writeFileSync(tmp, text, { flag: "wx" });
    if (mode) chmodSync(tmp, mode);
    renameSync(tmp, file);
  } finally {
    rmSync(tmp, { force: true });
  }
  return true;
}

// Only the exact dispatcher is ours; any other text at the path, even one that
// carries the sentinel, belongs to someone else.
const isDispatcher = (text) => text !== null && lf(text) === DISPATCHER;

// dispatcherState(file) -> absent | ours | modified (carries the sentinel, but
// edited) | foreign (some other hook, or a file too odd to read).
function dispatcherState(file) {
  const text = readText(file);
  if (isDispatcher(text)) return "ours";
  if (text?.includes(SENTINEL)) return "modified";
  try {
    lstatSync(file);
    return "foreign";
  } catch {
    return "absent";
  }
}

// The marker names the script the dispatcher runs; anything else is drift.
const markerText = (plugin, entry) => `${plugin.name}/${entry.script}\n`;

// stage(info, files, executable) -> whether git add staged every file.
function stage(info, files, executable) {
  if (!files.length) return true;
  const rel = files.map((f) => path.relative(info.top, f));
  return git(info.top, ["add", ...(executable ? ["--chmod=+x"] : []), "--", ...rel]).ok;
}

// copy(info, plugin, entry, scope, manager, force) -> installed | refreshed | unchanged | refused | blocked | unsafe-path | stage-failed
// (blocked: a local install whose hooks dir another manager owns; unsafe-path: a
// target is or passes through a symlink; nothing is written for either.
// stage-failed: a shared install wrote its files but git add failed, so the
// team would not receive them)
export function copy(info, plugin, entry, scope, manager, force = false) {
  if (manager === "husky" && scope === "local") throw new UsageError("husky has no local scope; use --scope shared");
  if (hooksDirOwned(info, scope, manager)) return "blocked";
  if (unsafeTarget(info, plugin, entry, scope, manager)) return "unsafe-path";
  const p = entryPaths(info, plugin, entry, scope, manager);
  const source = sourceScript(plugin, entry);
  const before = copyState(p.script, entry, sourceHash(plugin, entry));
  const hook = manager === "plain" ? dispatcherState(p.dispatcher) : null;
  if ((before === "modified" || hook === "modified") && !force) return "refused";
  let changed = writeIfChanged(p.lib, plugin.libText);
  const assetFiles = [];
  for (const asset of sourceAssets(plugin, entry)) {
    const file = path.join(path.dirname(p.script), asset.name);
    changed = writeIfChanged(file, asset.text) || changed;
    assetFiles.push(file);
  }
  changed = writeIfChanged(p.script, renderCopy(plugin, entry, source), 0o755) || changed;
  const exec = [p.script];
  const plainFiles = [...assetFiles]; // staged without the exec bit at shared scope
  if (manager === "plain") {
    changed = writeIfChanged(p.marker, markerText(plugin, entry)) || changed;
    if (hook !== "foreign" && writeIfChanged(p.dispatcher, DISPATCHER, 0o755)) exec.push(p.dispatcher);
    plainFiles.push(p.marker);
  }
  if (scope === "shared") {
    const attributes = attributesStep(info).action;
    if (attributes) writeIfChanged(attributes.file, `${ATTRIBUTES_LINE}\n`);
    const staged = stage(info, exec, true) && stage(info, [p.lib, ...plainFiles, ...(attributes ? [attributes.file] : [])], false);
    if (!staged) return "stage-failed";
  }
  git(info.top, ["config", "--local", "--unset", declineKey(plugin, entry)]);
  // An install opts this clone back in over a global or master decline.
  if (isDeclined(info, plugin, entry)) git(info.top, ["config", "--local", declineKey(plugin, entry), "false"]);
  if (before === "missing") return "installed";
  return changed ? "refreshed" : "unchanged";
}

// decline(info, plugin, entry, undo, global) -> sets or clears the entry's
// decline key in this clone, or with global in the user's global config.
export function decline(info, plugin, entry, undo = false, global = false) {
  const scope = global ? "--global" : "--local";
  const key = declineKey(plugin, entry);
  const args = undo ? ["config", scope, "--unset", key] : ["config", scope, key, "true"];
  const r = git(info.top, args);
  return r.ok || (undo && r.status === 5); // 5: the key was not set
}

function scopesFor(info) {
  const scopes = [{ scope: "shared", manager: "lefthook" }, { scope: "local", manager: "lefthook" }];
  if (info.hooksPath === SHARED_DIR) scopes.push({ scope: "local", manager: "plain" });
  return scopes;
}

// list(info, plugin) -> [{ entryId, event, scope, file, stamp }] for every installed copy.
export function list(info, plugin) {
  const out = [];
  for (const entry of plugin.entries) {
    const seen = new Set();
    for (const { scope, manager } of scopesFor(info)) {
      const file = entryPaths(info, plugin, entry, scope, manager).script;
      const text = seen.has(file) ? null : readText(file);
      seen.add(file);
      if (text === null) continue;
      out.push({ entryId: entry.name, event: entry.event, scope, file, stamp: readStamp(text)?.hash ?? null });
    }
  }
  return out;
}

function entryVerdict(info, plugin, entry, manager) {
  if (isDeclined(info, plugin, entry)) return { state: "declined" };
  const current = sourceHash(plugin, entry);
  const copies = list(info, plugin).filter((c) => c.entryId === entry.name);
  if (copies.length === 0) return { state: "missing", detail: "not installed" };
  const states = copies.map((c) => copyState(c.file, entry, current));
  if (states.includes("modified")) return { state: "modified", detail: copies[states.indexOf("modified")].file };
  if (states.includes("stale")) return { state: "stale", detail: copies[states.indexOf("stale")].file };
  const wired = copies.some((c) => manager !== "conflict" && wiring(info, plugin, entry, c.scope, manager).wired);
  return wired ? { state: "ok" } : { state: "missing", detail: "installed but not wired into the hook manager" };
}

// verify(info, plugin) -> [{ entry, state, detail?, missingTools[] }]
export function verify(info, plugin) {
  const { manager } = detect(info);
  return plugin.entries.map((entry) => ({
    entry: entry.name,
    ...entryVerdict(info, plugin, entry, manager),
    missingTools: entry.tools.filter((t) => !whichTool(t)),
  }));
}

export const DRIFT = ["stale", "modified", "missing"];

export function driftLine(plugin, row) {
  return `${plugin.name}: git hook ${row.entry} ${row.state}; run /${plugin.name}:setup apply install-git-hooks`;
}

const USAGE = [
  "usage: install.mjs detect|list [--repo <dir>] [--plugin-root <dir>]",
  "       install.mjs plan --scope local|shared [--manager lefthook|husky|plain]",
  "       install.mjs copy --scope local|shared [--entry <name>]... [--manager <m>] [--force]",
  "       install.mjs decline --entry <name> [--undo] [--global]",
  "       install.mjs verify [--quiet]",
].join("\n");

const VALUE_FLAGS = { "--repo": "repo", "--plugin-root": "pluginRoot", "--scope": "scope", "--manager": "manager" };
const BOOL_FLAGS = { "--force": "force", "--quiet": "quiet", "--undo": "undo", "--global": "global" };
const ACTIONS = ["detect", "list", "plan", "copy", "decline", "verify"];

function parseArgs(argv, defaults) {
  const [action, ...rest] = argv;
  if (!ACTIONS.includes(action)) throw new UsageError(action ? `unknown action: ${action}` : "no action given");
  const opts = { action, entries: [], ...defaults };
  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i];
    if (BOOL_FLAGS[arg]) opts[BOOL_FLAGS[arg]] = true;
    else if (VALUE_FLAGS[arg] && rest[i + 1]) opts[VALUE_FLAGS[arg]] = rest[++i];
    else if (arg === "--entry" && rest[i + 1]) opts.entries.push(rest[++i]);
    else throw new UsageError(`unexpected argument: ${arg}`);
  }
  if (["plan", "copy"].includes(action) && !["local", "shared"].includes(opts.scope)) {
    throw new UsageError(`${action} needs --scope local or --scope shared`);
  }
  if (opts.manager && !MANAGERS.includes(opts.manager)) throw new UsageError(`unknown manager: ${opts.manager}`);
  if (action === "decline" && opts.entries.length !== 1) throw new UsageError("decline needs one --entry");
  return opts;
}

function pickEntries(plugin, names) {
  if (names.length === 0) return plugin.entries;
  return names.map((n) => {
    const found = plugin.entries.find((e) => e.name === n);
    if (!found) throw new UsageError(`${plugin.name} has no entry named ${n}`);
    return found;
  });
}

function runVerify(info, plugin, opts, io) {
  const rows = verify(info, plugin);
  const drift = rows.filter((r) => DRIFT.includes(r.state));
  if (opts.quiet) {
    for (const row of drift) io.stdout(driftLine(plugin, row));
    return 0;
  }
  for (const row of rows) {
    io.stdout([row.state, row.entry, row.detail ?? ""].join("\t").trimEnd());
    for (const tool of row.state === "declined" ? [] : row.missingTools) io.stdout(`tool\t${tool}\tmissing`);
  }
  return drift.length ? 1 : 0;
}

function runCopy(info, plugin, opts, io) {
  const manager = opts.manager ?? detect(info).manager;
  if (manager === "conflict") throw new UsageError("hook managers conflict; run plan and pass --manager");
  const owned = hooksDirOwned(info, opts.scope, manager);
  if (owned) {
    io.stdout(JSON.stringify({ installed: [], decisions: [owned] }));
    return 1;
  }
  const results = pickEntries(plugin, opts.entries).map((entry) => ({
    entry: entry.name,
    status: copy(info, plugin, entry, opts.scope, manager, opts.force),
  }));
  io.stdout(JSON.stringify(results));
  return results.some((r) => ["refused", "unsafe-path", "stage-failed"].includes(r.status)) ? 1 : 0;
}

function dispatch(info, plugin, opts, io) {
  switch (opts.action) {
    case "detect":
      io.stdout(JSON.stringify(detect(info)));
      return 0;
    case "list":
      io.stdout(JSON.stringify(list(info, plugin)));
      return 0;
    case "plan":
      io.stdout(JSON.stringify(plan(info, plugin, opts.scope, opts.manager)));
      return 0;
    case "copy":
      return runCopy(info, plugin, opts, io);
    case "decline":
      return decline(info, plugin, pickEntries(plugin, opts.entries)[0], opts.undo, opts.global) ? 0 : 2;
    default:
      return runVerify(info, plugin, opts, io);
  }
}

// main(argv, ctx, out) -> exit code. ctx and out are injectable for tests.
export function main(argv, ctx = {}, out = {}) {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const io = { stdout: out.stdout ?? ((s) => console.log(s)), stderr: out.stderr ?? ((s) => console.error(s)) };
  let opts;
  try {
    opts = parseArgs(argv, { repo: ctx.cwd ?? process.cwd(), pluginRoot: path.resolve(here, "..", "..") });
    const info = repoInfo(opts.repo);
    if (!info) {
      if (opts.quiet) return 0;
      throw new UsageError(`not inside a git work tree: ${opts.repo}`);
    }
    return dispatch(info, loadPlugin(opts.pluginRoot), opts, io);
  } catch (err) {
    if (!(err instanceof UsageError)) throw err;
    if (opts?.quiet) return 0;
    io.stderr(`install.mjs: ${err.message}\n${USAGE}`);
    return 2;
  }
}

function realPath(p) {
  try {
    return realpathSync(p);
  } catch {
    return path.resolve(p);
  }
}

if (process.argv[1] && realPath(process.argv[1]) === realPath(fileURLToPath(import.meta.url))) {
  process.exitCode = main(process.argv.slice(2));
}
