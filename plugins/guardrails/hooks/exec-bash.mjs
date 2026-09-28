#!/usr/bin/env node
// Exec-form entry for the guardrails dispatcher (#3686).
//
// hooks.json spells `"command": "node"` and puts this file, then
// run-guards.sh and that script's own arguments, in `args`. Bare `bash`
// is not a legal exec-form command: on Windows it resolves to the WSL
// relay and a failed hook launch does not block. This process finds a
// real bash and spawns it with the script path as argv, stdin inherited,
// and the child's exit code forwarded. `shell` is not used.
//
// On Windows the candidates are CLAUDE_CODE_GIT_BASH_PATH (accepted only
// when the file is named bash.exe, sh.exe, bash, or sh) and
// Git\bin\bash.exe / Git\usr\bin\bash.exe under Program Files. System32
// and WindowsApps are never accepted. On other platforms the candidates
// are /bin/bash and /usr/bin/bash.
//
// Exit 1 when bash cannot be resolved or the usage is wrong. That is a
// hook error, not a guard block. A guard's own exit 2 passes through.

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
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
    return firstExisting(candidates, platform, exists);
  }
  return firstExisting(["/bin/bash", "/usr/bin/bash"], platform, exists);
}

function fail(message) {
  process.stderr.write(`exec-bash: ${message}\n`);
  process.exit(1);
}

function main() {
  const script = process.argv[2];
  if (!script) {
    fail("usage: node exec-bash.mjs <script> [args...]");
  }
  const bash = resolveBash(process.env, process.platform, existsSync);
  if (!bash) {
    fail(
      "no bash resolved. On Windows set CLAUDE_CODE_GIT_BASH_PATH to Git's bash.exe. System32\\bash.exe is the WSL relay and is not used.",
    );
  }
  const child = spawn(bash, [script, ...process.argv.slice(3)], {
    stdio: "inherit",
    windowsHide: true,
    shell: false,
  });
  const forward = (signal) => {
    if (!child.killed) child.kill(signal);
  };
  process.on("SIGTERM", () => forward("SIGTERM"));
  process.on("SIGINT", () => forward("SIGINT"));
  child.on("error", (err) => {
    fail(`failed to spawn ${bash}: ${err.message}`);
  });
  child.on("exit", (code, signal) => {
    if (signal) process.exit(1);
    process.exit(code ?? 1);
  });
}

function invokedDirectly() {
  const arg = process.argv[1];
  if (!arg) return false;
  return path.resolve(arg) === path.resolve(fileURLToPath(import.meta.url));
}

if (invokedDirectly()) main();
