import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, copyFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { main } from "./prerequisites-fleet.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const checker = path.join(here, "..", "lib", "prerequisites.mjs");
const posix = process.platform !== "win32";

// A config directory laid out the way Claude Code installs plugins: plugins/cache/<marketplace>/<name>/<version>.
function fleet({ plugins, enabled, pluginConfigs = {} }) {
  const config = tempDir("prereq-fleet-");
  const installed = {};
  for (const p of plugins) {
    const root = path.join(config, "plugins", "cache", "mkt", p.name, "1.0.0");
    mkdirSync(path.join(root, ".claude-plugin"), { recursive: true });
    mkdirSync(path.join(root, "lib"));
    copyFileSync(checker, path.join(root, "lib", "prerequisites.mjs"));
    writeFileSync(
      path.join(root, ".claude-plugin", "plugin.json"),
      JSON.stringify({ name: p.name, userConfig: p.userConfig ?? {} }),
    );
    const manifest = {
      ...(p.sessionProbe && { session_probe: p.sessionProbe }),
      requires: [
        {
          id: `${p.name}-tool`,
          kind: "cli",
          need: "required",
          for: ["hook:run.sh"],
          detect: { any: [`${p.name}-absent-tool-x9`] },
          degrade: `Without it the ${p.name} hook skips.`,
          install: { docs: "https://example.com/install" },
          check: `/${p.name}:check`,
        },
      ],
    };
    writeFileSync(path.join(root, "prerequisites.json"), JSON.stringify(manifest));
    installed[`${p.name}@mkt`] = [{ scope: "user", installPath: root }];
  }
  mkdirSync(path.join(config, "plugins"), { recursive: true });
  writeFileSync(path.join(config, "plugins", "installed_plugins.json"), JSON.stringify({ plugins: installed }));
  const enabledPlugins = Object.fromEntries((enabled ?? plugins.map((p) => p.name)).map((n) => [`${n}@mkt`, true]));
  writeFileSync(path.join(config, "settings.json"), JSON.stringify({ enabledPlugins, pluginConfigs }));
  const ownRoot = path.join(config, "plugins", "cache", "mkt", "harness-ops", "1.0.0");
  mkdirSync(ownRoot, { recursive: true });
  // A claude on PATH that leaves a marker: the runner must never start one.
  const bin = path.join(config, "bin");
  mkdirSync(bin);
  writeFileSync(path.join(bin, "claude"), `#!/bin/sh\n: >"${path.join(config, "claude-ran")}"\n`);
  chmodSync(path.join(bin, "claude"), 0o755);
  const run = (session = "s1", env = {}) =>
    main({
      env: { PATH: bin, HOME: config, ...env },
      input: JSON.stringify({ session_id: session, hook_event_name: "SessionStart" }),
      ownRoot,
      managed: [],
    });
  return { config, run };
}

const gated = (name) => ({
  name,
  sessionProbe: { run_if_unset_or_true: "DEMO_ENABLED" },
  userConfig: { demo_enabled: { type: "boolean", default: true } },
});

describe("prerequisites-fleet", { skip: !posix && "the claude stub is a POSIX shell script" }, () => {
  test("two enabled plugins' notices print as one message, and no claude process starts", async () => {
    const f = fleet({ plugins: [gated("alpha"), { name: "beta", sessionProbe: {} }] });
    const message = await f.run();
    assert.match(message, /^alpha: alpha-tool not on the hook PATH/);
    assert.match(message, /\nbeta: beta-tool not on the hook PATH.*\/beta:check diagnoses\.$/);
    assert.equal(existsSync(path.join(f.config, "claude-ran")), false);
  });

  test("a plugin that does not declare session_probe is not probed", async () => {
    const f = fleet({ plugins: [{ name: "alpha" }] });
    assert.equal(await f.run(), "");
  });

  test("a plugin that is installed but not enabled is not probed", async () => {
    const f = fleet({ plugins: [gated("alpha")], enabled: [] });
    assert.equal(await f.run(), "");
  });

  for (const [label, value] of [
    ["a JSON boolean", false],
    ["a string", "false"],
  ]) {
    test(`a kill switch set to false as ${label} in pluginConfigs skips the plugin`, async () => {
      const f = fleet({
        plugins: [gated("alpha"), gated("beta")],
        pluginConfigs: { "alpha@mkt": { options: { demo_enabled: value } } },
      });
      const message = await f.run();
      assert.doesNotMatch(message, /alpha:/);
      assert.match(message, /^beta: /);
    });
  }

  test("a kill switch set to true runs the probe", async () => {
    const f = fleet({ plugins: [gated("alpha")], pluginConfigs: { "alpha@mkt": { options: { demo_enabled: true } } } });
    assert.match(await f.run(), /^alpha: /);
  });

  test("an unset kill switch whose declared default is false skips the plugin", async () => {
    const off = { ...gated("alpha"), userConfig: { demo_enabled: { type: "boolean", default: false } } };
    const f = fleet({ plugins: [off] });
    assert.equal(await f.run(), "");
  });

  test("the latch lands in the probed plugin's own data directory, so the session hears it once", async () => {
    const f = fleet({ plugins: [gated("alpha")] });
    assert.match(await f.run("s7"), /^alpha: /);
    const marker = path.join(f.config, "plugins", "data", "alpha-mkt", "skip-notices", "alpha-alpha-tool.s7.user");
    assert.ok(existsSync(marker), marker);
    assert.equal(await f.run("s7"), "");
    assert.match(await f.run("s8"), /^alpha: /);
  });

  test("the hook prints one systemMessage document and exits 0", () => {
    const f = fleet({ plugins: [gated("alpha")] });
    // Run the script itself from a copy placed as harness-ops in the fake cache.
    const r = spawnSync(process.execPath, [path.join(here, "prerequisites-fleet.mjs")], {
      input: JSON.stringify({ session_id: "cli-1" }),
      env: { PATH: path.join(f.config, "bin"), HOME: f.config, CLAUDE_CONFIG_DIR: f.config },
      encoding: "utf8",
    });
    assert.equal(r.status, 0);
    const lines = r.stdout.trim().split("\n");
    assert.equal(lines.length, 1);
    assert.match(JSON.parse(lines[0]).systemMessage, /^alpha: alpha-tool not on the hook PATH/);
  });
});
