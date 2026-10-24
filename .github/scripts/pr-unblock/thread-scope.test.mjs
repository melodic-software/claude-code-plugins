import assert from "node:assert/strict";
import { test } from "node:test";

import { inThreadScope, isProtectedPath, namedInScope, prPathsOf } from "./thread-scope.mjs";

const kept = new Set(["plugins/p/evals/c/graders/x.md", "src/a.js"]);

test("a kept thread's own path is in scope", () => {
  assert.equal(inThreadScope("src/a.js", kept), true);
  assert.equal(inThreadScope("plugins/p/evals/c/graders/x.md", kept), true);
});

// Scope is path hygiene only: what a fix touches beyond the thread is the
// code and security review lanes' finding, never a stop.
test("any plain path in normal form is in scope: another plugin, code, a new file, instruction and control surfaces", () => {
  for (const path of [
    "plugins/q/evals/c/samples/new.json",
    "plugins/p/lib/run.js",
    "plugins/p/scripts/run.sh",
    "src/lib/test_round.py",
    "CODEOWNERS",
    ".gitmodules",
    "plugins/p/package.json",
    "plugins/p/.claude/settings.json",
    "CLAUDE.md",
    "plugins/p/AGENTS.md",
    ".mcp.json",
    "plugins/p/.lsp.json",
    "plugins/p/.claude-plugin/plugin.json",
    "plugins/p/hooks/guard.sh",
    "plugins/p/monitors/monitors.json",
    "plugins/p/bin/tool",
    ".github/actions/check-trusted-trigger/action.yml",
    ".github/standards/trusted-actors/trusted-actors.json",
    ".github/workflows/ci.yml",
  ]) {
    assert.equal(inThreadScope(path, kept), true, path);
    assert.equal(inThreadScope(path, kept, [], { added: true }), true, path);
  }
});

test("a path with an empty, . or .. segment, or a leading /, is refused", () => {
  for (const path of [
    "plugins/p/evals/c/../../../../.github/workflows/x.yml",
    "plugins/p/evals/c/./samples/y.json",
    "plugins/p/evals/c//y.json",
    "/src/a.js",
    "./src/a.js",
  ]) {
    assert.equal(inThreadScope(path, new Set([...kept, path])), false, path);
  }
});

test("a path off plain ASCII is refused, even as a kept thread's own path", () => {
  for (const path of ["plugins/p/hoo\u212As/hooks.json", "plugins/p/AGENTſ.md", "plugins/p/café.md", "plugins/p/a b.js", "plugins/p\\x.js", "plugins/p/ｘ.js"]) {
    assert.equal(inThreadScope(path, new Set([...kept, path])), false, path);
  }
});

test("isProtectedPath names .github/workflows/ in any case", () => {
  assert.equal(isProtectedPath(".github/workflows"), true);
  assert.equal(isProtectedPath(".GitHub/Workflows/a.yml"), true);
  assert.equal(isProtectedPath(".github"), false);
  assert.equal(isProtectedPath(".github/scripts/x.mjs"), false);
  assert.equal(isProtectedPath(".github/workflowsx/a"), false);
});

test("a named path joins a thread's scope when it is plain and in normal form, in any plugin or none", () => {
  for (const path of ["plugins/other/lib/x.js", "src/x.js", "plugins/knowledge/CODEOWNERS", ".github/workflows/x.yml"]) {
    assert.equal(namedInScope(path, "plugins/knowledge/a.md"), true, path);
  }
  for (const path of ["plugins/knowledge/../other/x.js", "plugins/knowledge//x.js", "plugins/knowledge/a b.js"]) {
    assert.equal(namedInScope(path, "plugins/knowledge/a.md"), false, path);
  }
});

test("prPathsOf lists every plain path the PR changes, rename sources included, and drops the rest", () => {
  const listed = [
    { filename: "plugins/p/skills/s/converge.md" },
    { filename: "src/b.js", previous_filename: "src/old.js" },
    { filename: ".github/workflows/x.yml" },
    { filename: "CLAUDE.md" },
    { filename: "a\\b.md" },
    { filename: "a b.md" },
    { filename: "src/../x.md" },
  ];
  assert.deepEqual(prPathsOf(listed), [".github/workflows/x.yml", "CLAUDE.md", "plugins/p/skills/s/converge.md", "src/b.js", "src/old.js"]);
});
