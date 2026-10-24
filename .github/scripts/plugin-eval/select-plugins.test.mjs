import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { loadTimeChanges, selectPlugins } from "./select-plugins.mjs";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "select-plugins.mjs");
const run = (input) => spawnSync(process.execPath, [SCRIPT], { input, encoding: "utf8" });

test("a change under a plugin's evals selects that plugin only", () => {
  assert.deepEqual(selectPlugins(["plugins/testing/evals/x"]), ["plugins/testing"]);
});

test("a change only under docs selects nothing", () => {
  assert.deepEqual(selectPlugins(["docs/adr/0001-x.md", "docs/conventions/loop-lane/README.md"]), []);
});

test("skills and agents select their plugin once, sorted", () => {
  assert.deepEqual(
    selectPlugins(["plugins/review/agents/a.md", "plugins/evals/skills/plugin-eval/SKILL.md", "plugins/review/skills/x/SKILL.md"]),
    ["plugins/evals", "plugins/review"],
  );
});

test("other plugin files, and a skills directory outside plugins/<name>/, select nothing", () => {
  assert.deepEqual(
    selectPlugins(["plugins/testing/README.md", "plugins/testing/hooks/hooks.json", "plugins/skills/x", ".claude/skills/x/SKILL.md", "plugins/testing/evalsx/y"]),
    [],
  );
});

test("a selected plugin's hook, manifest or server change is refused; another plugin's is not", () => {
  const paths = [
    "plugins/testing/evals/x",
    "plugins/testing/hooks/hooks.json",
    "plugins/testing/.claude-plugin/plugin.json",
    "plugins/testing/.mcp.json",
    "plugins/review/hooks/hooks.json",
    "plugins/testing/README.md",
  ];
  assert.deepEqual(loadTimeChanges(paths, selectPlugins(paths)), [
    "plugins/testing/hooks/hooks.json",
    "plugins/testing/.claude-plugin/plugin.json",
    "plugins/testing/.mcp.json",
  ]);
  const out = run(`${paths.join("\n")}\n`);
  assert.equal(out.status, 1);
  assert.equal(out.stdout, "");
  assert.match(out.stderr, /plugins\/testing\/hooks\/hooks\.json/);
  assert.doesNotMatch(out.stderr, /plugins\/review/);
});

test("the command prints one plugin per line, and nothing for no match", () => {
  assert.equal(run("plugins/testing/evals/x\ndocs/y.md\n").stdout, "plugins/testing\n");
  const none = run("docs/y.md\n");
  assert.equal(none.status, 0);
  assert.equal(none.stdout, "");
});
