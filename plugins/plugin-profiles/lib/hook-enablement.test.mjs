import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import process from "node:process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const CLI = join(dirname(fileURLToPath(import.meta.url)), "hook-enablement.mjs");

function world() {
  const root = mkdtempSync(join(tmpdir(), "pp-hook-enablement-"));
  const home = join(root, "home");
  const project = join(root, "project");
  mkdirSync(join(home, ".claude"), { recursive: true });
  mkdirSync(join(project, "docs", "conventions"), { recursive: true });
  const env = { PATH: process.env.PATH, HOME: home, USERPROFILE: home };
  if (process.env.SystemRoot) env.SystemRoot = process.env.SystemRoot;
  if (process.env.CLAUDE_CODE_GIT_BASH_PATH) env.CLAUDE_CODE_GIT_BASH_PATH = process.env.CLAUDE_CODE_GIT_BASH_PATH;
  const repo = (key, value) => writeFileSync(join(project, "docs", "conventions", "plugin-profiles.yaml"), `${key}: ${value}\n`);
  const userSettings = (key, value) =>
    writeFileSync(join(home, ".claude", "settings.json"), JSON.stringify({ pluginConfigs: { "plugin-profiles@melodic-software": { options: { [key]: value } } } }));
  const resolve = (args, extra = {}) => spawnSync(process.execPath, [CLI, ...args], { env: { ...env, ...extra }, encoding: "utf8" });
  return { project, repo, userSettings, resolve };
}

const bashFound = spawnSync(process.platform === "win32" && process.env.CLAUDE_CODE_GIT_BASH_PATH ? process.env.CLAUDE_CODE_GIT_BASH_PATH : "bash", ["-c", "exit 0"]).status === 0;

test("session_start_profile_enabled, read as the SessionStart hook reads it: user layer from CLAUDE_PLUGIN_OPTION_", { skip: !bashFound && "bash not found" }, () => {
  const key = "session_start_profile_enabled";
  const w = world();
  const run = (user) => w.resolve([key, "true", "--root", w.project], user === undefined ? {} : { CLAUDE_PLUGIN_OPTION_SESSION_START_PROFILE_ENABLED: user }).status;
  w.repo(key, "true");
  assert.equal(run("false"), 1, "user false, repository true: off");
  w.repo(key, "false");
  assert.equal(run(undefined), 1, "user unset, repository false: off");
  w.repo(key, "true");
  assert.equal(run(undefined), 0, "user unset, repository true: runs");
});

const jqFound = spawnSync("jq", ["--version"]).status === 0;

test("plugin_profile_module_enabled, read as the module reads it: user layer from pluginConfigs in user settings", { skip: (!bashFound && "bash not found") || (!jqFound && "the helper reads pluginConfigs with jq, which is not installed") }, () => {
  const key = "plugin_profile_module_enabled";
  const w = world();
  const run = () => w.resolve([key, "true", "--settings", "--root", w.project]).status;
  w.userSettings(key, false);
  w.repo(key, "true");
  assert.equal(run(), 1, "user false, repository true: off");
  w.userSettings("remember_folder_profile", true);
  w.repo(key, "false");
  assert.equal(run(), 1, "user unset, repository false: off");
  w.repo(key, "true");
  assert.equal(run(), 0, "user unset, repository true: runs");
});

test("a helper that cannot start leaves the hook on", () => {
  const w = world();
  const r = w.resolve(["plugin_profile_module_enabled", "true", "--root", w.project], { PATH: "", CLAUDE_CODE_GIT_BASH_PATH: "" });
  assert.equal(r.status, 0);
});
