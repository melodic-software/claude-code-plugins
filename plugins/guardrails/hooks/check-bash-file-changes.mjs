// Bash and PowerShell hooks: run the Write/Edit content guards on the repository
// files a shell command changed.
//
//   node check-bash-file-changes.mjs snapshot   PreToolUse   (Bash|PowerShell)
//   node check-bash-file-changes.mjs check      PostToolUse and PostToolUseFailure
//
// block-hook-bypass.sh judges a command by its shape, so a script FILE run by
// an interpreter (`node x.js`, `python3 x.py`) writes repository files that no
// Write/Edit guard sees (#6674). This gates the outcome instead: `snapshot`
// records `git status`, the HEAD commit, and the size and mtime of every dirty
// path before the command, and `check` lists the paths that are new to
// `git status` or whose size or mtime moved, plus the paths that commits the
// command made added or modified. Each one goes through
// the guards of the PreToolUse Write|Edit row of hooks.json, read from that row
// so the two cannot drift, as the Write or Edit Claude would have made: a new
// file as a Write of its whole content, a tracked file as an Edit whose new
// text is the lines it adds against the HEAD commit from before the command,
// staged or not (hook-precision rule 1). A guard that blocks reports
// its own message to Claude, naming the file. The command already ran, so this
// reports rather than denies.
//
// Cheap and fail-open by design. The repository is the one holding the call's
// cwd, found by walking up to a `.git` entry with no process; outside one, both
// modes exit 0 having started nothing. A fire costs one `git status`, and a
// check that finds changes adds, per file and at most MAX_FILES, one `git diff`
// for a tracked file and one guard process. Git runs with GIT_OPTIONAL_LOCKS=0,
// so it never takes the index lock a concurrent git command needs, and with
// fsmonitor and textconv off, so a repository config the command wrote starts
// no program outside the sandbox. Snapshots live only under CLAUDE_PLUGIN_DATA;
// without it both modes do nothing. Every error exits 0. A skip that leaves a
// change unexamined is reported as a note, never a block: a missing snapshot, a
// failed or oversized git status, a symbolic link, files past the first
// MAX_FILES in path order or past the time budget, and a run_in_background
// command, whose later writes are not checked.
//
// Scope residuals, not reported: a file outside the cwd's repository, a
// gitignored file (hook-precision rule 6), a change inside a submodule, a file
// that was already dirty and whose size and mtime did not change, an oversized
// or binary file, and a file the command wrote and then deleted. A file dirty
// before the command is judged on every line it adds against that HEAD, not
// only this command's. A
// HEAD moved by a checkout, pull, merge or reset brings in others' content and
// adds no paths, and with the HEAD reflog off (core.logAllRefUpdates=false)
// a commit is not seen.
//
// Kill switch: the bash_file_change_check_enabled userConfig option set to
// false.

import { spawnSync } from "node:child_process";
import {
  mkdirSync,
  readdirSync,
  readFileSync,
  realpathSync,
  lstatSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { readStdin, resolveBash, stdinIdleMs } from "./exec-bash.mjs";

const HOOK_DIR = path.dirname(fileURLToPath(import.meta.url));
const MAX_FILES = 20;
const MAX_FILE_BYTES = 1024 * 1024;
const MAX_STATUS_ENTRIES = 10000;
const GIT_TIMEOUT_MS = 5000;
const GUARD_TIMEOUT_MS = 10000;
// Under the 60-second hooks.json timeout, with room for one last guard run.
const CHECK_BUDGET_MS = 40000;
const STALE_MS = 24 * 60 * 60 * 1000;

function enabled(env) {
  return env.CLAUDE_PLUGIN_OPTION_BASH_FILE_CHANGE_CHECK_ENABLED !== "false";
}

// The directory holding the nearest `.git` entry (a directory, or a file in a
// linked worktree or submodule) at or above dir, or null.
export function repoRoot(dir) {
  let current = path.resolve(dir);
  for (;;) {
    try {
      statSync(path.join(current, ".git"));
      return current;
    } catch {
      const parent = path.dirname(current);
      if (parent === current) return null;
      current = parent;
    }
  }
}

function gitEnv() {
  const env = { ...process.env, GIT_OPTIONAL_LOCKS: "0" };
  for (const key of ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"]) delete env[key];
  return env;
}

function git(root, args) {
  // No fsmonitor: the hook runs outside the Bash sandbox, so a repository
  // config the command wrote must not name a program for it to start.
  const result = spawnSync("git", ["-C", root, "-c", "core.fsmonitor=false", ...args], {
    env: gitEnv(),
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    timeout: GIT_TIMEOUT_MS,
    windowsHide: true,
  });
  return result.status === 0 ? result.stdout : null;
}

// git status as {relativePath: code}, or null when git fails or the list is
// too long to be worth snapshotting.
// With porcelain v2 the same call also names the HEAD commit, so a commit made
// inside the command is seen without a second git process.
export function gitStatus(root) {
  const out = git(root, [
    "status",
    "--porcelain=v2",
    "--branch",
    "-z",
    "--untracked-files=all",
    "--no-renames",
    "--ignore-submodules=all",
  ]);
  if (out === null) return null;
  const entries = {};
  let head = null;
  let count = 0;
  for (const record of out.split("\0")) {
    if (record.startsWith("# branch.oid ")) {
      const oid = record.slice(13);
      head = /^[0-9a-f]{40,64}$/.test(oid) ? oid : null;
      continue;
    }
    // `1 XY sub mH mI mW hH hI path`, `u XY sub m1 m2 m3 mW h1 h2 h3 path`, `? path`
    const fields = { 1: 8, u: 10, "?": 1 }[record[0]];
    if (fields === undefined) continue;
    if (++count > MAX_STATUS_ENTRIES) return null;
    const parts = record.split(" ");
    const rel = parts.slice(fields).join(" ");
    if (rel) entries[rel] = record[0] === "?" ? "??" : parts[1];
  }
  return { head, entries };
}

// The HEAD reflog file of the repository at root (per worktree), or null.
export function headLog(root) {
  const dotGit = path.join(root, ".git");
  try {
    if (lstatSync(dotGit).isDirectory()) return path.join(dotGit, "logs", "HEAD");
    const match = /^gitdir:\s*(.+?)\s*$/m.exec(readFileSync(dotGit, "utf8"));
    return match ? path.join(path.resolve(root, match[1]), "logs", "HEAD") : null;
  } catch {
    return null;
  }
}

export function fileSize(file) {
  try {
    return file ? statSync(file).size : 0;
  } catch {
    return 0;
  }
}

// The commits the command made: the `commit` entries (`commit:`,
// `commit (amend):`, ...) appended to the HEAD reflog since its size at the
// snapshot. Reading only the appended bytes needs no process and cannot be
// confused by HEAD revisiting an earlier commit. A checkout, pull, merge or
// reset entry brings in others' content and names no commit here. A command
// can still write its own reflog subject (`git update-ref -m`); like
// block-hook-bypass, this is friction for an agent, not a sandbox.
export function commitsMade(log, offset) {
  let text;
  try {
    const buffer = readFileSync(log);
    if (buffer.length < offset) return [];
    text = buffer.subarray(offset).toString("utf8");
  } catch {
    return [];
  }
  const commits = [];
  for (const line of text.split("\n")) {
    const tab = line.indexOf("\t");
    if (tab < 0 || !line.slice(tab + 1).startsWith("commit")) continue;
    const sha = line.split(" ")[1];
    if (/^[0-9a-f]{40,64}$/.test(sha ?? "")) commits.push(sha);
  }
  return commits;
}

// Paths the given commits added or modified, from one git process.
export function committedFiles(root, commits) {
  if (commits.length === 0) return [];
  const out = git(root, [
    "log",
    "--no-walk=unsorted",
    // A merge commit lists the paths whose result differs from every parent,
    // the ones the command resolved, not what the merge brought in.
    "--cc",
    "--format=",
    "--name-only",
    "-z",
    "--no-renames",
    "--diff-filter=AM",
    ...commits.slice(-MAX_FILES),
    "--",
  ]);
  return out === null ? [] : [...new Set(out.split("\0").map((p) => p.trim()).filter(Boolean))];
}

// [size, mtime, isLink] of a file or symbolic link, or null.
function stamp(file) {
  try {
    // lstat: a symbolic link is not followed, so a link to a file outside the
    // repository never has that file's content read and quoted back.
    const s = lstatSync(file);
    return s.isFile() || s.isSymbolicLink() ? [s.size, s.mtimeMs, s.isSymbolicLink()] : null;
  } catch {
    return null;
  }
}

function snapshotDir(env) {
  // No shared-temp fallback: a predictable path there is one another local
  // user could plant a symbolic link at. Without a data directory, no-op.
  return env.CLAUDE_PLUGIN_DATA ? path.join(env.CLAUDE_PLUGIN_DATA, "bash-file-snapshots") : null;
}

function snapshotFile(env, payload) {
  const id = `${payload.session_id ?? ""}-${payload.tool_use_id}`.replace(/[^A-Za-z0-9_-]/g, "_");
  return path.join(snapshotDir(env), `${id}.json`);
}

function pruneStale(dir, now) {
  try {
    for (const name of readdirSync(dir)) {
      const file = path.join(dir, name);
      try {
        if (now - statSync(file).mtimeMs > STALE_MS) unlinkSync(file);
      } catch {}
    }
  } catch {}
}

export function snapshot(payload, env) {
  const root = repoRoot(payload.cwd);
  if (!root) return;
  const status = gitStatus(root);
  const stamps = {};
  for (const rel of Object.keys(status?.entries ?? {})) stamps[rel] = stamp(path.join(root, rel));
  const dir = snapshotDir(env);
  mkdirSync(dir, { recursive: true });
  pruneStale(dir, Date.now());
  // A failed git status still leaves a snapshot, so the check can say why it
  // examined nothing.
  writeFileSync(
    snapshotFile(env, payload),
    JSON.stringify(
      status
        ? { root, head: status.head, log: fileSize(headLog(root)), status: status.entries, stamps }
        : { root, failed: true },
    ),
  );
}

// The paths that are dirty now and were clean before, or whose size or mtime
// moved, plus the paths commits made inside the command added or modified, as
// [{rel, abs, untracked, size, link}].
export function changedFiles(before, after, committed = []) {
  const changed = new Map();
  for (const [rel, code] of Object.entries(after.status)) {
    const abs = path.join(before.root, rel);
    const now = stamp(abs);
    if (!now) continue;
    const then = before.stamps[rel];
    if (rel in before.status && then && then[0] === now[0] && then[1] === now[1]) continue;
    changed.set(rel, { rel, abs, untracked: code === "??", size: now[0], link: now[2] });
  }
  for (const rel of committed) {
    const abs = path.join(before.root, rel);
    const now = stamp(abs);
    if (now && !changed.has(rel)) {
      changed.set(rel, { rel, abs, untracked: false, size: now[0], link: now[2] });
    }
  }
  return [...changed.values()].sort((a, b) => a.rel.localeCompare(b.rel));
}

// The lines one tracked path adds against `base`, the HEAD commit before the
// command, so a write the command also staged or committed is still judged
// (hook-precision rule 1). null when there is no base to diff against. One diff
// per file, keyed by the name asked for, so no header is parsed for a name: a
// quoted, tab-suffixed or content-forged `+++` header cannot redirect lines.
// A `+` line counts only after the first `@@`.
export function addedLines(root, rel, base) {
  if (!base) return null;
  const out = git(root, [
    "--literal-pathspecs",
    "diff",
    "--no-color",
    "--no-ext-diff",
    "--no-textconv",
    "--no-renames",
    // --text: a .gitattributes `-diff` or a NUL byte would otherwise turn the
    // diff into "Binary files differ" and hide every added line.
    "--text",
    "-U0",
    base,
    "--",
    rel,
  ]);
  if (out === null) return null;
  const added = [];
  let inHunk = false;
  for (const line of out.split("\n")) {
    if (line.startsWith("@@")) inHunk = true;
    else if (inHunk && line.startsWith("+")) added.push(line.slice(1));
  }
  return added;
}

// The guard scripts of the PreToolUse Write|Edit row, so this runs exactly the
// checks a Write or Edit runs.
export function writeGuards() {
  const hooks = JSON.parse(readFileSync(path.join(HOOK_DIR, "hooks.json"), "utf8"));
  for (const row of hooks.hooks.PreToolUse ?? []) {
    if (!/\bWrite\b/.test(row.matcher ?? "")) continue;
    for (const handler of row.hooks ?? []) {
      const args = handler.args ?? [];
      const at = args.findIndex((arg) => arg.endsWith("/run-guards.sh"));
      if (at >= 0) return args.slice(at + 1);
    }
  }
  return [];
}

// A NUL byte becomes a line break, so the text either side of it is still
// scanned and none is joined across it (the guards refuse a NUL outright).
function readContent(abs, size) {
  if (size > MAX_FILE_BYTES) return null;
  try {
    return readFileSync(abs).toString("utf8").replaceAll("\0", "\n");
  } catch {
    return null;
  }
}

// The stderr of a guard run that blocked the Write or Edit, or null.
function runGuards(bash, guards, toolPayload, env) {
  const result = spawnSync(bash, [path.join(HOOK_DIR, "run-guards.sh"), ...guards], {
    input: JSON.stringify(toolPayload),
    env: { ...env, CLAUDE_PLUGIN_ROOT: env.CLAUDE_PLUGIN_ROOT || path.dirname(HOOK_DIR) },
    encoding: "utf8",
    timeout: GUARD_TIMEOUT_MS,
    windowsHide: true,
  });
  return result.status === 2 ? (result.stderr || "").trim() : null;
}

function isFile(p) {
  try {
    return statSync(p).isFile();
  } catch {
    return false;
  }
}

function notExamined(count, reason) {
  const files = count === null ? "" : `${count} changed ${count === 1 ? "file" : "files"}`;
  return `guardrails: ${files || "changed files"} not examined: ${reason}.`;
}

// The findings for one call, as {rel, message} rows, and a note for each
// skip or truncation, so an unexamined change is never read as a clean one.
export function check(payload, env) {
  const findings = [];
  const notes = [];
  const result = { findings, notes };
  const file = snapshotFile(env, payload);
  let before;
  try {
    before = JSON.parse(readFileSync(file, "utf8"));
  } catch {
    if (repoRoot(payload.cwd)) {
      notes.push(notExamined(null, "no git status snapshot was recorded before the command"));
    }
    return result;
  }
  try {
    unlinkSync(file);
  } catch {}
  if (payload.tool_input?.run_in_background === true) {
    notes.push(notExamined(null, "the command runs in the background, so what it writes later is not checked"));
  }
  const status = before.failed ? null : gitStatus(before.root);
  if (!status) {
    notes.push(notExamined(null, `git status failed or listed more than ${MAX_STATUS_ENTRIES} paths`));
    return result;
  }
  const log = headLog(before.root);
  const commits = log && fileSize(log) > before.log ? commitsMade(log, before.log) : [];
  if (commits.length > MAX_FILES) {
    const dropped = commits.length - MAX_FILES;
    notes.push(
      notExamined(
        null,
        `the command made ${commits.length} commits and the check reads only the last ${MAX_FILES}, so ${dropped} earlier ${dropped === 1 ? "commit is" : "commits are"} not checked`,
      ),
    );
  }
  const committed = committedFiles(before.root, commits);
  const all = changedFiles(before, { status: status.entries }, committed);
  const links = all.filter((f) => f.link).length;
  if (links) notes.push(notExamined(links, "a symbolic link is not followed"));
  const files = all.filter((f) => !f.link);
  if (files.length > MAX_FILES) {
    notes.push(
      notExamined(files.length - MAX_FILES, `the check stops after the first ${MAX_FILES} in path order`),
    );
  }
  const changed = files.slice(0, MAX_FILES);
  if (changed.length === 0) return result;
  const guards = writeGuards();
  const bash = resolveBash(env, process.platform, isFile);
  if (guards.length === 0 || !bash) {
    notes.push(notExamined(changed.length, "no bash was found to run the guards"));
    return result;
  }
  const deadline = Date.now() + CHECK_BUDGET_MS;
  let late = 0;
  let unread = 0;
  changed.forEach((f, n) => {
    if (Date.now() > deadline) {
      late++;
      return;
    }
    // A tracked file is judged by the lines it adds, whatever its size. One
    // with no commit to diff against (an unborn branch) is judged whole, like
    // a new file.
    const added = f.untracked ? null : addedLines(before.root, f.rel, before.head);
    const whole = added === null;
    if (!whole && added.length === 0) return;
    const content = whole ? readContent(f.abs, f.size) : null;
    if (whole && content === null) {
      unread++;
      return;
    }
    const toolInput = whole
      ? { file_path: f.abs, content }
      : { file_path: f.abs, old_string: "", new_string: added.join("\n") };
    const message = runGuards(
      bash,
      guards,
      {
        session_id: payload.session_id,
        transcript_path: payload.transcript_path,
        cwd: payload.cwd,
        hook_event_name: "PreToolUse",
        tool_name: whole ? "Write" : "Edit",
        tool_input: toolInput,
        tool_use_id: `${payload.tool_use_id}-${n}`,
      },
      env,
    );
    if (message) findings.push({ rel: f.rel, message });
  });
  if (unread) notes.push(notExamined(unread, "a new file over 1 MiB is not read"));
  if (late) notes.push(notExamined(late, "the check ran out of time"));
  return result;
}

// A finding blocks; notes alone reach Claude as context.
export function report(event, tool, { findings, notes }) {
  const reason = [
    ...findings.map(
      (f) =>
        `guardrails: this ${tool} command changed ${JSON.stringify(f.rel)}, and the check a Write or Edit of ` +
        `that file runs reports:\n${f.message}\nThe change is already on disk: fix the file ` +
        "with Edit, or revert it.",
    ),
    ...notes,
  ].join("\n\n");
  if (event === "PostToolUseFailure" || findings.length === 0) {
    return { hookSpecificOutput: { hookEventName: event, additionalContext: reason } };
  }
  return { decision: "block", reason };
}

async function main() {
  const mode = process.argv[2];
  if (!enabled(process.env) || (mode !== "snapshot" && mode !== "check")) return;
  if (!snapshotDir(process.env)) return;
  const input = await readStdin(stdinIdleMs(process.env));
  if (input === null) return;
  let payload;
  try {
    payload = JSON.parse(input.toString("utf8"));
  } catch {
    return;
  }
  if (!payload || typeof payload.cwd !== "string" || !payload.tool_use_id) return;
  if (mode === "snapshot") {
    snapshot(payload, process.env);
    return;
  }
  const result = check(payload, process.env);
  if (result.findings.length === 0 && result.notes.length === 0) return;
  const event = payload.hook_event_name ?? "PostToolUse";
  process.stdout.write(`${JSON.stringify(report(event, payload.tool_name ?? "Bash", result))}\n`);
}

// Node realpaths the main entry, so compare real paths (see exec-bash.mjs).
function realPath(p) {
  try {
    return realpathSync(p);
  } catch {
    return path.resolve(p);
  }
}

function invokedDirectly() {
  const arg = process.argv[1];
  return Boolean(arg) && realPath(arg) === realPath(fileURLToPath(import.meta.url));
}

if (invokedDirectly()) main().catch(() => {});
