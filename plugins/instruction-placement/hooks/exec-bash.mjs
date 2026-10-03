#!/usr/bin/env node
// GENERATED from lib/exec-bash.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// Exec-form entry for a bash-scripted hook (#3686).
//
// hooks.json spells `"command": "node"` and puts this file, then an
// optional option gate, then the shell script and that script's own
// arguments, in `args`. `--require-true NAME` exits 0 unless
// CLAUDE_PLUGIN_OPTION_NAME is exactly `true`. `--run-if-unset-or-true NAME`
// exits 0 only when that variable is set to something other than `true`.
// A closed gate does not resolve or spawn bash. Bare `bash`
// is not a legal exec-form command: on Windows it resolves to the WSL
// relay and a failed hook launch does not block. This process finds a
// real bash and spawns it with the script path as argv, stdin inherited,
// and the child's exit code forwarded. `shell` is not used.
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
import { realpathSync, statSync } from "node:fs";
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

export function parseLaunchArgs(argv) {
  const gates = [];
  let i = 0;
  while (i < argv.length) {
    const flag = argv[i];
    if (flag !== "--require-true" && flag !== "--run-if-unset-or-true") break;
    const name = argv[i + 1];
    if (!name || name.startsWith("-") || !/^[A-Z0-9_]+$/.test(name)) {
      return { error: `usage: ${flag} needs the CLAUDE_PLUGIN_OPTION_ suffix (A-Z, digits, underscore)` };
    }
    gates.push({ flag, name });
    i += 2;
  }
  const script = argv[i];
  if (!script) {
    return {
      error: "usage: node exec-bash.mjs [--require-true NAME | --run-if-unset-or-true NAME] <script> [args...]",
    };
  }
  return { gates, script, args: argv.slice(i + 1) };
}

// A closed gate exits 0 before bash is resolved. --require-true matches a
// default-off option (unset is off). --run-if-unset-or-true matches a
// default-on option (only an explicit non-true value skips).
export function optionGateOpen(gates, env) {
  for (const gate of gates) {
    const value = env[`CLAUDE_PLUGIN_OPTION_${gate.name}`];
    if (gate.flag === "--require-true") {
      if (value !== "true") return false;
    } else if (value !== undefined && value !== "" && value !== "true") {
      return false;
    }
  }
  return true;
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

function main() {
  const parsed = parseLaunchArgs(process.argv.slice(2));
  if (parsed.error) fail(failureLine("usage", { detail: parsed.error }));
  if (!optionGateOpen(parsed.gates, process.env)) process.exit(0);
  const { platform } = process;
  const bash = resolveBash(process.env, platform, isFile);
  const ctx = { script: parsed.script, bash, platform };
  if (!bash) fail(failureLine("no-bash", ctx));
  const child = spawn(bash, [parsed.script, ...parsed.args], {
    stdio: "inherit",
    windowsHide: true,
    shell: false,
  });
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
