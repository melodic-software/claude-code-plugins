#!/usr/bin/env node
// GENERATED from lib/exec-bash.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// Exec-form entry for a bash-scripted hook (#3686).
//
// hooks.json spells `"command": "node"` and puts this file, then optional
// launch flags, then the shell script and that script's own arguments, in
// `args`. Each flag takes one value and sits before the script. Every flag
// must pass (AND); a failed one exits 0 without resolving or spawning bash.
//
//   --require-true NAME          run only when CLAUDE_PLUGIN_OPTION_NAME is
//                                exactly `true` (a default-off option).
//   --run-if-unset-or-true NAME  run unless that variable is set to something
//                                other than `true` (a default-on option).
//   --skip-if-all-false A,B,...  skip only when every named variable is
//                                exactly `false`. Unset, empty, `true` or any
//                                other value runs, so a row whose script holds
//                                several default-on switches skips only when
//                                all of them are provably off.
//   --skip-unless-stdin-contains TEXT
//                                buffer stdin; skip when the payload lacks
//                                TEXT, else write the same bytes to the script.
//   --run-if-any-set A,B,...     run when any named variable is non-empty.
//   --run-if-settings-mention TEXT
//                                run when TEXT appears in the user settings.json
//                                of a plugins/cache install (found from the
//                                script's own path, never from the environment)
//                                or in a managed-settings.json or one of its
//                                managed-settings.d/*.json drop-ins. These two
//                                --run-if-* flags form ONE any-of gate: it opens
//                                when either does, and every other gate must
//                                open too.
//   --skip-unless-marker SUBDIR  buffer stdin, read the payload's session_id,
//                                and skip only when <marker-root>/SUBDIR exists
//                                and neither it nor the tmp fallback
//                                disk-hygiene-SUBDIR holds <session>.launched.
//                                No session id, no such directory, or a stall
//                                runs the script (fail closed).
//   --marker-root DIR            the root for --skip-unless-marker, passed
//                                explicitly. Empty or a literal
//                                ${CLAUDE_PLUGIN_DATA} means none.
//
// Option flags are decided first, before stdin is touched. A stdin flag reads
// stdin to EOF with an idle bound (2 s, or the stdin_read_timeout option read
// the way hook-utils.sh reads it). On a stall --skip-unless-stdin-contains
// exits 0 without running the script. That fails OPEN, so that flag is for
// advisory rows only: the shared library treats a stalled payload as
// fail-closed for a blocking guard, which must not use the flag as written.
// On a stall --skip-unless-marker runs the script with the bytes that arrived.
// A row without a stdin flag keeps stdin inherited.
//
// Bare `bash` is not a legal exec-form command: on Windows it resolves to the
// WSL relay and a failed hook launch does not block. This process finds a
// real bash and spawns it with the script path as argv, stdin inherited (or
// written from the buffer), and the child's exit code forwarded. `shell` is
// not used.
//
// On Windows the candidates, in order, are CLAUDE_CODE_GIT_BASH_PATH
// (accepted only when the file is named bash.exe, sh.exe, bash, or sh),
// Git\bin\bash.exe / Git\usr\bin\bash.exe under Program Files, then
// bash.exe in each absolute PATH entry. System32, Sysnative and WindowsApps
// are never accepted, PATH hits included. On other platforms the candidates
// are bash in each absolute PATH entry, then /bin/bash and /usr/bin/bash.
// Empty and relative PATH entries are skipped, so the working directory
// never supplies a bash.
//
// A launcher failure (no bash, spawn error, wrong usage, child killed by a
// signal) exits 1 after one stderr line that names the script and what the
// failure means for the hook, built by failureLine. Nothing goes to stdout:
// Claude Code ignores the exit code when stdout holds a JSON object, and
// the hook would no longer be reported as an error. Exit 1 is a hook error,
// not a guard block. A guard's own exit 2 passes through.

import { spawn } from "node:child_process";
import { readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const SHELL_NAMES = new Set(["bash.exe", "sh.exe", "bash", "sh"]);

function pathApi(platform) {
  return platform === "win32" ? path.win32 : path.posix;
}

function isWslRelay(p) {
  const n = p.replaceAll("/", "\\").toLowerCase();
  return (
    n.endsWith("\\system32\\bash.exe") ||
    n.endsWith("\\sysnative\\bash.exe") ||
    n.includes("\\windowsapps\\")
  );
}

function shellBase(p, platform) {
  return pathApi(platform).basename(p).toLowerCase();
}

function acceptBash(p, platform, exists) {
  if (!p || !exists(p)) return false;
  if (!SHELL_NAMES.has(shellBase(p, platform))) return false;
  if (platform === "win32" && isWslRelay(p)) return false;
  return true;
}

function firstExisting(candidates, platform, exists) {
  for (const candidate of candidates) {
    if (acceptBash(candidate, platform, exists)) return candidate;
  }
  return null;
}

const OPTION_NAME = /^[A-Z0-9_]+$/;
const ONE_NAME = "needs the CLAUDE_PLUGIN_OPTION_ suffix (A-Z, digits, underscore)";
const NAME_LIST = "needs a comma-separated list of CLAUDE_PLUGIN_OPTION_ suffixes (A-Z, digits, underscore)";

function oneName(value) {
  return value && !value.startsWith("-") && OPTION_NAME.test(value) ? [value] : null;
}

function nameList(value) {
  if (!value || value.startsWith("-")) return null;
  const names = value.split(",");
  return names.every((name) => OPTION_NAME.test(name)) ? names : null;
}

function literal(value) {
  return value ? value : null;
}

// A directory may be empty (an unset ${CLAUDE_PLUGIN_DATA}), but never a flag.
function directory(value) {
  return value === undefined || value.startsWith("-") ? null : value;
}

const optionValues = (names, env) => names.map((name) => env[`CLAUDE_PLUGIN_OPTION_${name}`]);
const unsetOrTrue = (v) => v === undefined || v === "" || v === "true";

// The launch flags. `env` and `any` flags read only the environment and files
// on disk and are decided before stdin is touched; the `any` flags together are
// one any-of gate. A `stdin` flag reads the buffered payload, and `onStall` is
// its verdict when stdin stalls. A `config` flag only supplies a value. `parse`
// returns the flag's value or null for a usage error; `open` says whether the
// script runs.
const FLAGS = {
  "--require-true": {
    phase: "env",
    parse: oneName,
    problem: ONE_NAME,
    open: (names, env) => optionValues(names, env)[0] === "true",
  },
  "--run-if-unset-or-true": {
    phase: "env",
    parse: oneName,
    problem: ONE_NAME,
    open: (names, env) => unsetOrTrue(optionValues(names, env)[0]),
  },
  "--skip-if-all-false": {
    phase: "env",
    parse: nameList,
    problem: NAME_LIST,
    open: (names, env) => !optionValues(names, env).every((v) => v === "false"),
  },
  "--run-if-any-set": {
    phase: "any",
    parse: nameList,
    problem: NAME_LIST,
    open: (names, env) => optionValues(names, env).some((v) => v !== undefined && v !== ""),
  },
  "--run-if-settings-mention": {
    phase: "any",
    parse: literal,
    problem: "needs non-empty text to look for in settings files",
    open: (text, env, ctx) => settingsMention(text, { ...ctx, env }),
  },
  // Advisory rows only: never put this on a blocking guard row. A stdin stall
  // exits 0 without running the script, so a guard behind it would fail open.
  "--skip-unless-stdin-contains": {
    phase: "stdin",
    parse: literal,
    problem: "needs non-empty text to look for in stdin",
    onStall: false,
    open: (text, input) => input.includes(text),
  },
  "--skip-unless-marker": {
    phase: "stdin",
    parse: literal,
    problem: "needs the marker subdirectory name",
    onStall: true,
    open: (subdir, input, ctx) => !markerSkips(subdir, input, ctx),
  },
  "--marker-root": {
    phase: "config",
    parse: directory,
    problem: "needs a directory (empty means none)",
  },
};

const USAGE = "usage: node exec-bash.mjs [--FLAG VALUE]... <script> [args...] (flags: header of exec-bash.mjs)";

export function parseLaunchArgs(argv) {
  const gates = [];
  let i = 0;
  while (i < argv.length && Object.hasOwn(FLAGS, argv[i])) {
    const flag = argv[i];
    const value = FLAGS[flag].parse(argv[i + 1]);
    if (value === null) return { error: `usage: ${flag} ${FLAGS[flag].problem}` };
    gates.push({ flag, value });
    i += 2;
  }
  const script = argv[i];
  if (!script) return { error: USAGE };
  return { gates, script, args: argv.slice(i + 1) };
}

const ofPhase = (gates, phase) => gates.filter((gate) => FLAGS[gate.flag].phase === phase);

function withDefaults(gates, ctx) {
  const markerRoot = gates.find((gate) => gate.flag === "--marker-root")?.value ?? "";
  return { env: process.env, platform: process.platform, script: "", fs: DISK, markerRoot, ...ctx };
}

// The option flags. A closed gate exits 0 before stdin is read or bash is
// resolved. ctx carries the script path, platform and file access.
export function optionGateOpen(gates, env, ctx = {}) {
  const c = withDefaults(gates, { ...ctx, env });
  const any = ofPhase(gates, "any");
  return (
    ofPhase(gates, "env").every((gate) => FLAGS[gate.flag].open(gate.value, env, c)) &&
    (any.length === 0 || any.some((gate) => FLAGS[gate.flag].open(gate.value, env, c)))
  );
}

export function needsStdin(gates) {
  return ofPhase(gates, "stdin").length > 0;
}

// The stdin flags, over the buffered payload (a Buffer).
export function stdinGateOpen(gates, input, ctx = {}) {
  const c = withDefaults(gates, ctx);
  return ofPhase(gates, "stdin").every((gate) => FLAGS[gate.flag].open(gate.value, input, c));
}

// The stdin flags' verdict when stdin stalls.
export function stdinStallOpen(gates) {
  return ofPhase(gates, "stdin").every((gate) => FLAGS[gate.flag].onStall);
}

// The idle bound hook::resolve_read_timeout_to applies: the stdin_read_timeout
// option in seconds when it is a positive decimal of at least 10 microseconds,
// else 2 s.
export function stdinIdleMs(env) {
  const raw = env.CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT ?? "";
  const seconds = /^[0-9]+(\.[0-9]+)?$/.test(raw) ? Number(raw) : 0;
  return seconds >= 0.00001 ? seconds * 1000 : 2000;
}

// Read the stream to EOF. Resolves { input, stalled }: the bytes that arrived,
// and whether no byte arrived for idleMs first. A read error ends the read
// with what arrived.
export function readStdin(idleMs, stream = process.stdin) {
  return new Promise((resolve) => {
    const chunks = [];
    let timer;
    const done = (stalled) => {
      clearTimeout(timer);
      resolve({ input: Buffer.concat(chunks), stalled });
    };
    const arm = () => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        stream.destroy();
        done(true);
      }, idleMs);
    };
    stream.on("data", (chunk) => {
      chunks.push(chunk);
      arm();
    });
    stream.on("end", () => done(false));
    stream.on("error", () => done(false));
    arm();
  });
}

// --- What a bash script would read, decided in node -------------------------
// Each check below answers as the script's own early exit does, and where the
// two could differ it answers "run": the launcher may skip only where the
// script would also exit at once.

const DISK = {
  isFile,
  isDir: (p) => {
    try {
      return statSync(p).isDirectory();
    } catch {
      return false;
    }
  },
  read: (p) => {
    try {
      return readFileSync(p);
    } catch {
      return null;
    }
  },
  list: (p) => {
    try {
      return readdirSync(p);
    } catch {
      return [];
    }
  },
};

// The Git Bash root (the directory holding usr\bin), from the bash this
// launcher would start.
function msysRoot(ctx) {
  if (!("msys" in ctx)) {
    const bash = resolveBash(ctx.env, "win32", ctx.fs.isFile);
    ctx.msys = (bash && /^(.*)[\\/](?:usr[\\/])?bin[\\/][^\\/]+$/i.exec(bash)?.[1]) || null;
  }
  return ctx.msys;
}

// The native paths a bash path names. On Windows, Git Bash reads /x/... as
// drive X: and any other /... under its own root; elsewhere a path is itself.
// An empty list means the path cannot be placed. A marker root that cannot be
// placed never skips; a settings file that cannot be placed counts as absent,
// which only happens when no Git Bash resolves, and the gate's own evaluation
// on Windows honors only the C:/Program Files managed file.
export function bashPaths(p, ctx) {
  if (ctx.platform !== "win32" || !p.startsWith("/")) return [p];
  const drive = /^\/([A-Za-z])(?:\/|$)/.exec(p);
  if (drive) return [`${drive[1]}:/${p.slice(3)}`];
  const root = msysRoot(ctx);
  return root ? [`${root}${p}`] : [];
}

// lane-stop-gate.sh's pre-filter files: the managed primaries for every
// platform, and the user settings.json beside a plugins/cache install.
const MANAGED_PRIMARIES = [
  "/Library/Application Support/ClaudeCode/managed-settings.json",
  "C:/Program Files/ClaudeCode/managed-settings.json",
  "/etc/claude-code/managed-settings.json",
];
const CACHE = "/plugins/cache/";

// The script's directory by `${BASH_SOURCE[0]%/*}`, its parent as the plugin
// root (a drive path with `\` folded to `/`), and <config>/settings.json when
// that root matches <config>/plugins/cache/<marketplace>/<name>/... . A
// --plugin-dir or directory-marketplace load has no such anchor, so no file.
export function userSettingsFile(script) {
  const cut = script.lastIndexOf("/");
  const hookDir = cut === -1 ? "." : script.slice(0, cut);
  let root;
  if (hookDir.startsWith("/")) root = `${hookDir}/..`;
  else if (/^.:[/\\]/.test(hookDir)) root = `${hookDir.replaceAll("\\", "/")}/..`;
  else root = path.resolve(hookDir || "/", "..").replaceAll("\\", "/");
  const at = root.indexOf(CACHE);
  if (at === -1) return null;
  const [marketplace, name, ...rest] = root.slice(at + CACHE.length).split("/");
  return marketplace && name && rest.length > 0 ? `${root.slice(0, at)}/settings.json` : null;
}

// gate_maybe_configured's file half: does any of those files, or a
// managed-settings.d/*.json beside a primary, contain text?
export function settingsMention(text, ctx = {}) {
  const c = withDefaults([], ctx);
  const user = c.script ? userSettingsFile(c.script) : null;
  const files = user ? bashPaths(user, c) : [];
  for (const primary of MANAGED_PRIMARIES) {
    for (const file of bashPaths(primary, c)) {
      const dir = `${file.slice(0, file.lastIndexOf("/"))}/managed-settings.d`;
      const dropIns = c.fs.list(dir).filter((e) => !e.startsWith(".") && e.toLowerCase().endsWith(".json"));
      files.push(file, ...dropIns.map((e) => `${dir}/${e}`));
    }
  }
  return files.some((f) => c.fs.isFile(f) && (c.fs.read(f)?.includes(text) ?? false));
}

// The session id run-python-hook.sh recovers: the payload up to its first NUL,
// matched first at the opening key, then anywhere.
const SPACE = "[ \\t\\n\\v\\f\\r]*";
const SESSION_FIELD = `"session_id"${SPACE}:${SPACE}"([^"\\\\]*)"`;
const SESSION_ANCHORED = new RegExp(`^${SPACE}\\{${SPACE}${SESSION_FIELD}`);
const SESSION_ANYWHERE = new RegExp(SESSION_FIELD);

export function payloadSessionId(input) {
  const nul = input.indexOf(0);
  const text = (nul === -1 ? input : input.subarray(0, nul)).toString("latin1");
  return (SESSION_ANCHORED.exec(text) ?? SESSION_ANYWHERE.exec(text))?.[1] ?? "";
}

// run-python-hook.sh --skip-unless-marker skips when a candidate directory
// exists and no candidate holds <session>.launched. This skips only when the
// marker-root directory exists and no candidate it or Git Bash's /tmp could
// name holds the file. A missing or non-printable-ASCII session id (bash folds
// non-ASCII per locale) runs.
// biome-ignore lint/suspicious/noTemplateCurlyInString: the unsubstituted placeholder, verbatim
const DATA_PLACEHOLDER = "${CLAUDE_PLUGIN_DATA}";
function markerSkips(subdir, input, ctx) {
  const session = payloadSessionId(input);
  if (!session || /[^\x20-\x7e]/.test(session)) return false;
  const name = `${session.replace(/[^a-zA-Z0-9_-]/g, "_")}.launched`;
  const rooted = ctx.markerRoot && ctx.markerRoot !== DATA_PLACEHOLDER;
  const rootDirs = rooted ? bashPaths(`${ctx.markerRoot}/${subdir}`, ctx) : [];
  const tmpRoots = [ctx.env.TMPDIR || "/tmp"];
  if (ctx.platform === "win32") tmpRoots.push(ctx.env.TEMP, ctx.env.TMP);
  const tmpDirs = tmpRoots.filter(Boolean).flatMap((t) => bashPaths(`${t}/disk-hygiene-${subdir}`, ctx));
  if ([...rootDirs, ...tmpDirs].some((d) => ctx.fs.isFile(`${d}/${name}`))) return false;
  return rootDirs.some((d) => ctx.fs.isDir(d));
}

function pathCandidates(env, platform) {
  const api = pathApi(platform);
  const exe = platform === "win32" ? "bash.exe" : "bash";
  return (env.PATH ?? env.Path ?? "")
    .split(api.delimiter)
    .map((entry) => (platform === "win32" ? entry.replace(/^"(.*)"$/, "$1") : entry))
    .filter((entry) => api.isAbsolute(entry))
    .map((entry) => api.join(entry, exe));
}

function isFile(p) {
  try {
    return statSync(p).isFile();
  } catch {
    return false;
  }
}

export function resolveBash(env, platform, exists) {
  if (platform === "win32") {
    const fromEnv = env.CLAUDE_CODE_GIT_BASH_PATH;
    if (acceptBash(fromEnv, platform, exists)) return fromEnv;
    const roots = [
      env.ProgramFiles,
      env["ProgramFiles(x86)"],
      env.LOCALAPPDATA ? path.win32.join(env.LOCALAPPDATA, "Programs") : "",
    ].filter(Boolean);
    const candidates = [];
    for (const root of roots) {
      candidates.push(path.win32.join(root, "Git", "bin", "bash.exe"));
      candidates.push(path.win32.join(root, "Git", "usr", "bin", "bash.exe"));
    }
    return firstExisting([...candidates, ...pathCandidates(env, platform)], platform, exists);
  }
  return firstExisting([...pathCandidates(env, platform), "/bin/bash", "/usr/bin/bash"], platform, exists);
}

const WINDOWS_FIX =
  "Set CLAUDE_CODE_GIT_BASH_PATH to Git's bash.exe (System32\\bash.exe is the WSL relay and is never used).";

const NOT_RUN = ({ name }) => `exec-bash: ${name} did not run, so this hook enforces nothing:`;

const FAILURE_LINES = {
  "no-bash": (c) =>
    `${NOT_RUN(c)} no bash found. ${c.platform === "win32" ? WINDOWS_FIX : "Install bash or put bash on PATH."}`,
  spawn: (c) => `${NOT_RUN(c)} could not start ${c.bash}: ${c.detail}`,
  signal: (c) =>
    `exec-bash: ${c.name} was killed by ${c.detail} before it finished, so it enforced nothing for this call.`,
  usage: (c) => `exec-bash: the launcher itself was called wrongly, so no hook ran: ${c.detail}`,
};

// The one stderr line for a launcher failure. Claude Code shows only the
// first stderr line, so the script and the consequence come first. detail is
// the error message for "spawn", the signal name for "signal", and the parse
// error for "usage", which has no script.
export function failureLine(kind, { script = "", bash = "", platform = "", detail = "" } = {}) {
  const name = script.split(/[\\/]/).pop();
  return FAILURE_LINES[kind]({ name, bash, platform, detail }).replace(/\s+/g, " ").trim();
}

function fail(line) {
  process.stderr.write(`${line}\n`);
  process.exit(1);
}

async function main() {
  const parsed = parseLaunchArgs(process.argv.slice(2));
  if (parsed.error) fail(failureLine("usage", { detail: parsed.error }));
  const gateCtx = { script: parsed.script };
  if (!optionGateOpen(parsed.gates, process.env, gateCtx)) process.exit(0);
  let input = null;
  if (needsStdin(parsed.gates)) {
    const read = await readStdin(stdinIdleMs(process.env));
    input = read.input;
    const open = read.stalled ? stdinStallOpen(parsed.gates) : stdinGateOpen(parsed.gates, input, gateCtx);
    if (!open) process.exit(0);
  }
  const { platform } = process;
  const bash = resolveBash(process.env, platform, isFile);
  const ctx = { script: parsed.script, bash, platform };
  if (!bash) fail(failureLine("no-bash", ctx));
  const child = spawn(bash, [parsed.script, ...parsed.args], {
    stdio: input !== null ? ["pipe", "inherit", "inherit"] : "inherit",
    windowsHide: true,
    shell: false,
  });
  if (input !== null) {
    // A script that exits without reading closes the pipe; that is not a failure.
    child.stdin.on("error", () => {});
    child.stdin.end(input);
  }
  const forward = (signal) => {
    if (!child.killed) child.kill(signal);
  };
  process.on("SIGTERM", () => forward("SIGTERM"));
  process.on("SIGINT", () => forward("SIGINT"));
  child.on("error", (err) => fail(failureLine("spawn", { ...ctx, detail: err.message })));
  child.on("exit", (code, signal) => {
    if (signal) fail(failureLine("signal", { ...ctx, detail: signal }));
    process.exit(code ?? 1);
  });
}

// Node realpaths the main entry, so import.meta.url never carries a symlink or
// junction that argv[1] does. Compare real paths, or a launch through a linked
// checkout path would never reach main() and would exit 0 with no output.
function realPath(p) {
  try {
    return realpathSync(p);
  } catch {
    return path.resolve(p);
  }
}

function invokedDirectly() {
  const arg = process.argv[1];
  if (!arg) return false;
  return realPath(arg) === realPath(fileURLToPath(import.meta.url));
}

if (invokedDirectly()) main();
