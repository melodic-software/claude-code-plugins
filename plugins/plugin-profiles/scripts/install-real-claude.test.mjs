import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, sep } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { claudeCommand } from "../lib/claude-command.mjs";
import { tempDir } from "../tests/temp.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI = join(HERE, "profiles.mjs");
const FIXTURE = join(HERE, "..", "evals", "fixtures", "fixture-market.sh");
const ID = "draw@fixture-market";

const baseEnv = (home) => ({ PATH: process.env.PATH ?? "", HOME: home, DISABLE_AUTOUPDATER: "1" });

const claude = claudeCommand(baseEnv(homedir())).file;
const hasClaude = Boolean(claude) && spawnSync(claude, ["--version"], { env: baseEnv(homedir()), encoding: "utf8" }).status === 0;

test("AC4, AC20: with the real claude, install previews, installs only on --yes, and leaves the plugin off at user level", { skip: hasClaude ? false : "claude is not on PATH", timeout: 180_000 }, () => {
  const root = realpathSync(tempDir("claude-eval-plugin-profiles-"));
  const home = join(root, "home");
  const work = join(root, "work");
  const config = join(home, ".claude");
  mkdirSync(home);
  mkdirSync(work);
  assert.ok(config.startsWith(root + sep), `config folder ${config} is outside the test's temp folder`);
  assert.notEqual(config, join(homedir(), ".claude"));

  const seeded = spawnSync("bash", [FIXTURE, "draw-missing"], { cwd: work, env: baseEnv(home), encoding: "utf8" });
  assert.equal(seeded.status, 0, `fixture-market.sh failed:\n${seeded.stderr}${seeded.stdout}`);

  const env = { ...baseEnv(home), CLAUDE_CONFIG_DIR: config };
  const run = (...args) => spawnSync(process.execPath, [CLI, "install", ID, ...args], { cwd: work, env, encoding: "utf8" });
  const installed = () => JSON.parse(readFileSync(join(config, "plugins", "installed_plugins.json"), "utf8")).plugins;
  const userFile = join(config, "settings.json");
  assert.ok(installed()["notes-hooks@fixture-market"], "the fixture did not install notes-hooks into the throwaway config");

  const preview = run("--dry-run");
  assert.equal(preview.status, 0, preview.stderr);
  assert.match(preview.stdout, /Installs draw@fixture-market from the fixture-market marketplace at user scope: claude plugin install draw@fixture-market --scope user/);
  assert.equal(installed()[ID], undefined, "--dry-run installed the plugin");

  const unasked = run();
  assert.equal(unasked.status, 1, unasked.stderr);
  assert.match(unasked.stderr, /nobody to confirm/);
  assert.equal(installed()[ID], undefined, "install without --yes installed the plugin");

  const approved = run("--yes");
  assert.equal(approved.status, 0, approved.stderr);
  assert.ok(approved.stdout.includes(`Installed ${ID}; it is off in ${userFile}.`), approved.stdout);
  assert.equal(installed()[ID]?.[0]?.scope, "user");
  assert.equal(JSON.parse(readFileSync(userFile, "utf8")).enabledPlugins?.[ID], false);
  assert.ok(!existsSync(join(work, ".claude")), "install wrote project settings");
});
