#!/usr/bin/env node

import { spawn, spawnSync } from "node:child_process";
import { existsSync, lstatSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
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

function acceptBash(p, platform, exists) {
  if (!p || !exists(p)) return false;
  if (!SHELL_NAMES.has(pathApi(platform).basename(p).toLowerCase())) return false;
  return !(platform === "win32" && isWslRelay(p));
}

function firstExisting(candidates, platform, exists) {
  return candidates.find((candidate) => acceptBash(candidate, platform, exists)) ?? null;
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
  return value || null;
}

function directory(value) {
  return value === undefined || value.startsWith("-") ? null : value;
}

const optionValues = (names, env) => names.map((name) => env[`CLAUDE_PLUGIN_OPTION_${name}`]);
const unsetOrTrue = (v) => v === undefined || v === "" || v === "true";

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
  "--bps-seed": {
    phase: "stdin",
    parse: literal,
    problem: "needs the path of the hook-utils.sh the script sources",
    onStall: true,
    open: () => true,
  },
};

const USAGE = "usage: node exec-bash.mjs [--FLAG VALUE]... <script> [args...] (flags: docs/contracts/hook-budget/README.md#the-exec-bashmjs-launcher)";

const SWITCHES = { "--fail-closed": "failClosed", "--require-verdict": "requireVerdict" };

export const VERDICT_ENV = "EXEC_BASH_VERDICT_FILE";

export function parseLaunchArgs(argv) {
  const gates = [];
  const switches = { failClosed: false, requireVerdict: false };
  let i = 0;
  while (i < argv.length && (Object.hasOwn(SWITCHES, argv[i]) || Object.hasOwn(FLAGS, argv[i]))) {
    if (Object.hasOwn(SWITCHES, argv[i])) {
      switches[SWITCHES[argv[i]]] = true;
      i += 1;
      continue;
    }
    const flag = argv[i];
    const value = FLAGS[flag].parse(argv[i + 1]);
    if (value === null) return { error: `usage: ${flag} ${FLAGS[flag].problem}` };
    gates.push({ flag, value });
    i += 2;
  }
  const script = argv[i];
  if (!script) return { error: USAGE };
  return { gates, ...switches, script, args: argv.slice(i + 1) };
}

const ofPhase = (gates, phase) => gates.filter((gate) => FLAGS[gate.flag].phase === phase);

function withDefaults(gates, ctx) {
  const markerRoot = gates.find((gate) => gate.flag === "--marker-root")?.value ?? "";
  return { env: process.env, platform: process.platform, uid: process.getuid?.(), script: "", fs: DISK, markerRoot, ...ctx };
}

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

export function stdinGateOpen(gates, input, ctx = {}) {
  const c = withDefaults(gates, ctx);
  return ofPhase(gates, "stdin").every((gate) => FLAGS[gate.flag].open(gate.value, input, c));
}

export function stdinStallOpen(gates) {
  return ofPhase(gates, "stdin").every((gate) => FLAGS[gate.flag].onStall);
}

export function stdinIdleMs(env) {
  const raw = env.CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT ?? "";
  const seconds = /^[0-9]+(\.[0-9]+)?$/.test(raw) ? Number(raw) : 0;
  return seconds >= 0.00001 ? seconds * 1000 : 2000;
}

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

const orElse = (fn, fallback) => (p) => {
  try {
    return fn(p);
  } catch {
    return fallback();
  }
};

const isFile = orElse((p) => statSync(p).isFile(), () => false);

const DISK = {
  isFile,
  isDir: orElse((p) => statSync(p).isDirectory(), () => false),
  lstat: orElse((p) => lstatSync(p), () => null),
  read: orElse((p) => readFileSync(p), () => null),
  list: orElse((p) => readdirSync(p), () => []),
};

function msysRoot(ctx) {
  if (!("msys" in ctx)) {
    const bash = resolveBash(ctx.env, "win32", ctx.fs.isFile);
    ctx.msys = (bash && /^(.*)[\\/](?:usr[\\/])?bin[\\/][^\\/]+$/i.exec(bash)?.[1]) || null;
  }
  return ctx.msys;
}

export function bashPaths(p, ctx) {
  if (ctx.platform !== "win32" || !p.startsWith("/")) return [p];
  const drive = /^\/([A-Za-z])(?:\/|$)/.exec(p);
  if (drive) return [`${drive[1]}:/${p.slice(3)}`];
  const root = msysRoot(ctx);
  return root ? [`${root}${p}`] : [];
}

const MANAGED_PRIMARIES = [
  "/Library/Application Support/ClaudeCode/managed-settings.json",
  "C:/Program Files/ClaudeCode/managed-settings.json",
  "/etc/claude-code/managed-settings.json",
];
const CACHE = "/plugins/cache/";

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

const SPACE = "[ \\t\\n\\v\\f\\r]*";
const SESSION_FIELD = `"session_id"${SPACE}:${SPACE}"([^"\\\\]*)"`;
const SESSION_ANCHORED = new RegExp(`^${SPACE}\\{${SPACE}${SESSION_FIELD}`);
const SESSION_ANYWHERE = new RegExp(SESSION_FIELD);

export function payloadSessionId(input) {
  const nul = input.indexOf(0);
  const text = (nul === -1 ? input : input.subarray(0, nul)).toString("latin1");
  return (SESSION_ANCHORED.exec(text) ?? SESSION_ANYWHERE.exec(text))?.[1] ?? "";
}

// biome-ignore lint/suspicious/noTemplateCurlyInString: the unsubstituted placeholder, verbatim
const DATA_PLACEHOLDER = "${CLAUDE_PLUGIN_DATA}";
function markerSkips(subdir, input, ctx) {
  const session = payloadSessionId(input);
  if (!session || /[^\x20-\x7e]/.test(session)) return false;
  const base = session.replace(/[^a-zA-Z0-9_-]/g, "_");
  const rooted = ctx.markerRoot && ctx.markerRoot !== DATA_PLACEHOLDER;
  const rootDirs = rooted ? bashPaths(`${ctx.markerRoot}/${subdir}`, ctx) : [];
  const tmpRoots = [ctx.env.TMPDIR || "/tmp"];
  if (ctx.platform === "win32") tmpRoots.push(ctx.env.TEMP, ctx.env.TMP);
  const tmpDirs = tmpRoots.filter(Boolean).flatMap((t) => bashPaths(`${t}/disk-hygiene-${subdir}`, ctx));
  const trusted = (d) => rootDirs.includes(d) || (ctx.platform !== "win32" && ownedMarkerDir(d, ctx));
  const marked = [...rootDirs, ...tmpDirs].filter((d) => ctx.fs.isFile(`${d}/${base}.launched`));
  if (marked.length > 0) return marked.every((d) => trusted(d) && launchSeen(`${d}/${base}`, ctx));
  if (rootDirs.some((d) => ctx.fs.isDir(d))) return true;
  return ctx.platform !== "win32" && tmpDirs.some((d) => ownedMarkerDir(d, ctx));
}

const LAUNCH_TOKEN = /^[0-9]{1,15}-[0-9]{1,10}-[0-9]{1,5}\n?$/;

function launchSeen(base, ctx) {
  const launched = ctx.fs.read(`${base}.launched`);
  if (launched === null || !LAUNCH_TOKEN.test(launched.toString("latin1"))) return false;
  const seen = ctx.fs.isFile(`${base}.seen`) ? ctx.fs.read(`${base}.seen`) : null;
  return seen !== null && seen.equals(launched);
}

function ownedMarkerDir(p, ctx) {
  if (ctx.uid === undefined) return ctx.fs.isDir(p);
  const st = ctx.fs.lstat(p);
  return st?.isDirectory() === true && st.uid === ctx.uid;
}

function pathCandidates(env, platform, name = "bash") {
  const api = pathApi(platform);
  const exe = platform === "win32" ? `${name}.exe` : name;
  return (env.PATH ?? env.Path ?? "")
    .split(api.delimiter)
    .map((entry) => (platform === "win32" ? entry.replace(/^"(.*)"$/, "$1") : entry))
    .filter((entry) => api.isAbsolute(entry))
    .map((entry) => api.join(entry, exe));
}

export function resolveTool(name, env, platform, exists) {
  return pathCandidates(env, platform, name).find((p) => exists(p)) ?? null;
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
    const candidates = roots.flatMap((root) => [
      path.win32.join(root, "Git", "bin", "bash.exe"),
      path.win32.join(root, "Git", "usr", "bin", "bash.exe"),
    ]);
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
  deny: (c) => `exec-bash: ${c.name} failed (${c.detail}), so this call is blocked (--fail-closed).`,
  "no-verdict": (c) =>
    `exec-bash: ${c.name} ${c.detail || "exited 0 without writing its verdict marker"}, so this call is blocked (--require-verdict).`,
};

export function failureLine(kind, { script = "", bash = "", platform = "", detail = "" } = {}) {
  const name = script.split(/[\\/]/).pop();
  return FAILURE_LINES[kind]({ name, bash, platform, detail }).replace(/\s+/g, " ").trim();
}

function fail(line, code = 1) {
  process.stderr.write(`${line}\n`);
  process.exit(code);
}

function childFailure(parsed, ctx, kind, detail) {
  if (parsed.failClosed) fail(failureLine("deny", { ...ctx, detail: kind === "spawn" ? `could not start: ${detail}` : detail }), 2);
  fail(failureLine(kind, { ...ctx, detail }));
}

export const BPS_SEED_ENV = ["HOOK_BPS_SEED_KEY", "HOOK_BPS_SEED_VAL"];
// A seeded value stays under the 32,767 characters a Windows environment variable holds:
// https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setenvironmentvariable
const BPS_SEED_MAX_CMD = 8192;
const BPS_SEED_MAX_LIST = 24576;
const BPS_SEED_TIMEOUT_MS = 5000;
export const bpsSeedPlatform = (platform) => platform === "win32";

export function bpsSeed(input, libPath, run = spawnSync, resolve = (name) => resolveTool(name, process.env, process.platform, isFile)) {
  let command;
  try {
    const payload = JSON.parse(input.toString("utf8"));
    if (payload?.tool_name !== "Bash" && payload?.tool_name !== "PowerShell") return null;
    command = payload.tool_input?.command;
  } catch {
    return null;
  }
  if (typeof command !== "string" || command.length > BPS_SEED_MAX_CMD || /[^\x01-\x7f]/.test(command)) return null;
  let program;
  try {
    program = readFileSync(libPath, "utf8").match(/^HOOK_BPS_JQ='([^']*)'/m)?.[1];
  } catch {
    return null;
  }
  if (!program) return null;
  const shfmt = resolve("shfmt");
  const jq = resolve("jq");
  if (!shfmt || !jq) return null;
  const opts = { timeout: BPS_SEED_TIMEOUT_MS, windowsHide: true, maxBuffer: 64 << 20 };
  const json = run(shfmt, ["-ln", "bash", "--to-json"], { ...opts, input: command });
  if (json.error || json.status !== 0) return null;
  const list = run(jq, ["-j", program], { ...opts, input: json.stdout });
  if (list.error || list.status !== 0) return null;
  const value = list.stdout.toString("utf8").replace(/\n+$/, "").replace(/\r$/, "");
  if (value.length > BPS_SEED_MAX_LIST || value.includes("\0")) return null;
  return { key: command, value };
}

const MSYS_SIGNALS = { 1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 6: "SIGABRT", 9: "SIGKILL", 11: "SIGSEGV", 14: "SIGALRM", 15: "SIGTERM" };

export function msysSignal(code, platform, failClosed) {
  if (!failClosed || platform !== "win32" || !Number.isInteger(code) || code < 0x100 || code > 0x4000 || (code & 0xff) !== 0) return null;
  const n = code >> 8;
  return MSYS_SIGNALS[n] ?? `signal ${n}`;
}

async function main() {
  const parsed = parseLaunchArgs(process.argv.slice(2));
  if (parsed.error) fail(failureLine("usage", { detail: parsed.error }));
  const gateCtx = { script: parsed.script };
  const gates = bpsSeedPlatform(process.platform) ? parsed.gates : parsed.gates.filter((gate) => gate.flag !== "--bps-seed");
  if (!optionGateOpen(parsed.gates, process.env, gateCtx)) process.exit(0);
  let input = null;
  let seed = null;
  let holdOpen = false;
  if (needsStdin(gates)) {
    const read = await readStdin(stdinIdleMs(process.env));
    input = read.input;
    const open = read.stalled ? stdinStallOpen(gates) : stdinGateOpen(gates, input, gateCtx);
    if (!open) process.exit(0);
    const seedGate = gates.find((gate) => gate.flag === "--bps-seed");
    if (seedGate && !read.stalled) seed = bpsSeed(input, seedGate.value);
    holdOpen = Boolean(seedGate) && read.stalled;
  }
  const { platform } = process;
  const bash = resolveBash(process.env, platform, isFile);
  const ctx = { script: parsed.script, bash, platform };
  if (!bash) fail(failureLine("no-bash", ctx));
  let marker = null;
  let env = process.env;
  const dropped = [VERDICT_ENV, ...BPS_SEED_ENV];
  if (Object.keys(env).some((k) => dropped.includes(k.toUpperCase()))) env = Object.fromEntries(Object.entries(env).filter(([k]) => !dropped.includes(k.toUpperCase())));
  if (seed) env = { ...env, [BPS_SEED_ENV[0]]: seed.key, [BPS_SEED_ENV[1]]: seed.value };
  if (parsed.requireVerdict) {
    let dir;
    try {
      dir = mkdtempSync(path.join(tmpdir(), "exec-bash-verdict-"));
    } catch (err) {
      fail(failureLine("no-verdict", { ...ctx, detail: `could not get a verdict marker (${err.message})` }), 2);
    }
    process.on("exit", () => {
      try {
        rmSync(dir, { recursive: true, force: true });
      } catch {}
    });
    marker = path.join(dir, "verdict");
    env = { ...env, [VERDICT_ENV]: platform === "win32" ? marker.replaceAll("\\", "/") : marker };
  }
  const child = spawn(bash, [parsed.script, ...parsed.args], {
    stdio: input !== null ? ["pipe", "inherit", "inherit"] : "inherit",
    env,
    windowsHide: true,
    shell: false,
  });
  if (input !== null) {
    child.stdin.on("error", () => {});
    if (holdOpen) child.stdin.write(input);
    else child.stdin.end(input);
  }
  const forward = (signal) => {
    if (!child.killed) child.kill(signal);
  };
  process.on("SIGTERM", () => forward("SIGTERM"));
  process.on("SIGINT", () => forward("SIGINT"));
  child.on("error", (err) => childFailure(parsed, ctx, "spawn", err.message));
  child.on("exit", (code, signal) => {
    const killedBy = signal ?? msysSignal(code, platform, parsed.failClosed);
    if (killedBy) childFailure(parsed, ctx, "signal", killedBy);
    if (parsed.failClosed && code !== 0 && code !== 2) childFailure(parsed, ctx, "code", `exit ${code}`);
    if (marker !== null && code === 0 && !existsSync(marker)) fail(failureLine("no-verdict", ctx), 2);
    process.exit(code ?? 1);
  });
}

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
