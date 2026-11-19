import assert from "node:assert/strict";
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { describe, test } from "node:test";
import { tempDir } from "../../../lib/test-tmp.mjs";

import { render, state } from "./session-telemetry-state.mjs";

const ID = "session-telemetry@acme";
const INSTALL = `claude plugin install ${ID}`;
const ENABLE = `claude plugin enable ${ID}`;

// A config dir with session-telemetry installed (or not) and enabled (or not) in user settings.
function config({ installed, enabled, options }) {
  const dir = tempDir("st-state-");
  mkdirSync(path.join(dir, "plugins"), { recursive: true });
  const records = {};
  if (installed) {
    const root = path.join(dir, "plugins", "cache", "acme", "session-telemetry", "0.1.0");
    mkdirSync(path.join(root, ".claude-plugin"), { recursive: true });
    writeFileSync(
      path.join(root, ".claude-plugin", "plugin.json"),
      JSON.stringify({
        name: "session-telemetry",
        userConfig: {
          session_event_log_dir: { type: "string", default: ".observability/claude" },
          skill_usage_scope: { type: "string", default: "repo" },
        },
      }),
    );
    records[ID] = [{ scope: "user", installPath: root }];
  }
  writeFileSync(path.join(dir, "plugins", "installed_plugins.json"), JSON.stringify({ plugins: records }));
  writeFileSync(path.join(dir, "settings.json"), JSON.stringify({ enabledPlugins: enabled ? { [ID]: true } : {} }));
  if (options) {
    const data = path.join(dir, "plugins", "data", "session-telemetry-acme");
    mkdirSync(data, { recursive: true });
    writeFileSync(path.join(data, "options.json"), JSON.stringify({ plugin_root: "/x", options }));
  }
  return dir;
}

function run(dir, ownRoot = path.join(dir, "plugins", "cache", "acme", "harness-ops", "1.0.0")) {
  return render(state({ project: "", env: { PATH: process.env.PATH, HOME: dir, CLAUDE_CONFIG_DIR: dir }, ownRoot }));
}

describe("session-telemetry-state.mjs", () => {
  test("not installed: says it is not enabled, prints the install line then the enable line", () => {
    const out = run(config({ installed: false, enabled: false }));
    assert.match(out, /^session-telemetry: not enabled/m);
    assert.ok(out.includes(INSTALL), out);
    assert.ok(out.indexOf(INSTALL) < out.indexOf(ENABLE), out);
  });

  test("installed but off: not enabled, prints only the enable line, and its option defaults", () => {
    const out = run(config({ installed: true, enabled: false }));
    assert.match(out, /^session-telemetry: not enabled/m);
    assert.ok(!out.includes(INSTALL), out);
    assert.ok(out.includes(ENABLE), out);
    assert.match(out, /^option session_event_log_dir=\.observability\/claude$/m);
  });

  test("enabled: says so, names the data dir, and the recorded options win over defaults", () => {
    const dir = config({ installed: true, enabled: true, options: { session_event_log_dir: "telemetry/hooks" } });
    const out = run(dir);
    assert.match(out, /^session-telemetry: enabled$/m);
    assert.ok(!out.includes(ENABLE), out);
    assert.ok(out.includes(`data_dir=${path.join(dir, "plugins", "data", "session-telemetry-acme")}`), out);
    assert.match(out, /^option session_event_log_dir=telemetry\/hooks$/m);
    assert.match(out, /^option skill_usage_scope=repo$/m);
  });

  test("harness-ops outside the plugin cache: the sibling id ends in @inline, as a --plugin-dir session's does", () => {
    const dir = config({ installed: false, enabled: false });
    const out = run(dir, path.join(dir, "src", "plugins", "harness-ops"));
    assert.ok(out.includes("claude plugin enable session-telemetry@inline"), out);
    assert.ok(out.includes(`data_dir=${path.join(dir, "plugins", "data", "session-telemetry-inline")}`), out);
  });

  test("harness-ops outside the plugin cache, session-telemetry installed: the sibling keeps its installed id", () => {
    const dir = config({ installed: true, enabled: true, options: { session_event_log_dir: "telemetry/hooks" } });
    const out = run(dir, path.join(dir, "src", "plugins", "harness-ops"));
    assert.match(out, /^session-telemetry: enabled$/m);
    assert.ok(out.includes(`data_dir=${path.join(dir, "plugins", "data", "session-telemetry-acme")}`), out);
    assert.match(out, /^option session_event_log_dir=telemetry\/hooks$/m);
  });
});
