#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

export const PLUGIN = "plugin-profiles";
export const SESSION_START_KEY = "session_start_profile_enabled";
export const MODULE_KEY = "plugin_profile_module_enabled";

const HELPER = join(dirname(fileURLToPath(import.meta.url)), "..", "hooks", "hook-enabled.sh").replaceAll("\\", "/");
const RESOLVE = '. "$1" && shift && hook_enabled::resolve "$@"';
const OFF = 1;

const bashFor = (env, platform) => (platform === "win32" && env.CLAUDE_CODE_GIT_BASH_PATH ? env.CLAUDE_CODE_GIT_BASH_PATH : "bash");

export function hookEnabled(key, fallback, { root = "", fromSettings = false, env = process.env, platform = process.platform, run = spawnSync, stderr = process.stderr } = {}) {
  const args = [...(fromSettings ? ["--git-hook"] : []), ...(root ? ["--root", root] : []), PLUGIN, key, String(fallback)];
  const r = run(bashFor(env, platform), ["-c", RESOLVE, "hook-enabled", HELPER, ...args], { env, encoding: "utf8", timeout: 5000, windowsHide: true });
  if (r.stderr) stderr.write(r.stderr);
  return r.status !== OFF;
}

function main(argv) {
  const [key, fallback, ...rest] = argv;
  const at = rest.indexOf("--root");
  const root = at === -1 ? "" : (rest[at + 1] ?? "");
  return hookEnabled(key, fallback, { root, fromSettings: rest.includes("--settings") }) ? 0 : OFF;
}

const invokedDirectly = () => {
  try {
    return Boolean(process.argv[1]) && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return resolve(process.argv[1] ?? "") === fileURLToPath(import.meta.url);
  }
};

if (invokedDirectly()) process.exit(main(process.argv.slice(2)));
