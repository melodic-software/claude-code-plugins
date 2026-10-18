// Cases from issue #8109's Verification section.
import assert from "node:assert/strict";
import { test } from "node:test";

import { inThreadScope, isProtectedPath } from "./thread-scope.mjs";

const kept = new Set(["plugins/p/evals/c/graders/x.md", "src/a.js"]);

test("a kept thread's own path is in scope", () => {
  assert.equal(inThreadScope("src/a.js", kept), true);
  assert.equal(inThreadScope("plugins/p/evals/c/graders/x.md", kept), true);
});

// plugins/planning/README.md is the file #8178's run 39117146913 refused.
test("any file in the same plugins/<p>/ directory as a kept thread's path is in scope, at any depth", () => {
  for (const path of [
    "plugins/p/evals/c/samples/y.json",
    "plugins/p/evals/other/samples/deep/z.json",
    "plugins/p/evals/evals.json",
    "plugins/p/skills/s/SKILL.md",
    "plugins/p/README.md",
  ]) {
    assert.equal(inThreadScope(path, kept), true, path);
  }
  assert.equal(inThreadScope("plugins/planning/README.md", new Set(["plugins/planning/surface/round.py"])), true);
});

// Each refused path and the kept thread paths of the four recorded trips.
test("the four recorded trips are in scope", () => {
  const trips = [
    // #8043, run 39100052790: an eval sample beside the thread's case.
    ["plugins/session-flow/evals/rr-skill-fit-names-owner/samples/names-skill-and-plugin.json", ["plugins/session-flow/evals/rr-skill-fit-names-owner/case.yaml"]],
    // #8103, run 39107762307: the thread is on case.yaml:18.
    ["plugins/discipline/evals/ror-second-error-way/samples/second-way-named.json", ["plugins/discipline/evals/ror-second-error-way/case.yaml"]],
    // #8142, run 39113747960: a .py file, in scope only as a sibling test.
    ["plugins/planning/surface/test_round.py", ["plugins/planning/surface/round.py"]],
    // #8178, run 39117146913: the PR's kept thread paths.
    [
      "plugins/planning/README.md",
      ["plugins/session-flow/skills/retro/SKILL.md", "plugins/planning/skills/draft-goal-condition/SKILL.md", "plugins/planning/.claude-plugin/plugin.json"],
    ],
  ];
  for (const [path, threads] of trips) {
    assert.equal(inThreadScope(path, new Set(threads)), true, path);
  }
});

test("hooks, manifests, agent rules and non-test code in the same plugin are refused", () => {
  const named = new Set(["plugins/p/skills/s/SKILL.md"]);
  for (const path of [
    "plugins/p/hooks/hooks.json",
    "plugins/p/hooks/guard.md",
    "plugins/p/.claude-plugin/plugin.json",
    "plugins/p/scripts/run.sh",
    "plugins/p/skills/s/scripts/helper.py",
    "plugins/p/lib/x.mjs",
    "plugins/p/lib/x.js",
    "plugins/p/lib/x.ts",
    "plugins/p/lib/X.SH",
    "plugins/p/AGENTS.md",
    "plugins/p/skills/s/CLAUDE.md",
    "plugins/p/.claude/rules/r.md",
    "plugins/p/.claude/settings.json",
  ]) {
    assert.equal(inThreadScope(path, named), false, path);
  }
});

test("a thread's own path stays in scope whatever its type, and a sibling test of code stays in scope", () => {
  for (const path of ["plugins/p/hooks/guard.sh", "plugins/p/.claude-plugin/plugin.json", "plugins/p/AGENTS.md"]) {
    assert.equal(inThreadScope(path, new Set([path])), true, path);
  }
  assert.equal(inThreadScope("plugins/p/hooks/guard.test.mjs", new Set(["plugins/p/hooks/guard.mjs"])), true);
  assert.equal(inThreadScope("plugins/p/scripts/test_run.py", new Set(["plugins/p/README.md"])), false);
});

test("another plugin's file and an unnamed file outside plugins/ stay out of scope", () => {
  assert.equal(inThreadScope("plugins/q/evals/c/samples/y.json", kept), false);
  assert.equal(inThreadScope("plugins/pp/README.md", kept), false);
  assert.equal(inThreadScope("src/b.js", kept), false);
  assert.equal(inThreadScope("plugins/README.md", kept), false);
});

test("with no kept thread under the plugin, its files are refused", () => {
  assert.equal(inThreadScope("plugins/p/evals/c/samples/y.json", new Set(["src/a.js"])), false);
});

// Names from the coordinator's addition; plugins/planning/surface/test_round.py
// is the file #8142's run 39113747960 refused.
test("a test file in the same directory as a kept thread's path is in scope", () => {
  const surface = new Set(["plugins/planning/surface/round.py", "src/a.js", "README.md"]);
  for (const path of [
    "plugins/planning/surface/test_round.py",
    "plugins/planning/surface/round_test.py",
    "src/a.test.js",
    "src/a.spec.ts",
    "test_root.py",
  ]) {
    assert.equal(inThreadScope(path, surface), true, path);
  }
});

test("outside plugins/, a test file in another directory, or a same-directory file that is no test, stays out of scope", () => {
  const surface = new Set(["src/a.js"]);
  for (const path of ["src/lib/a.test.js", "src/helper.js", "src/testing.js", "src/test_a.sh", "test_root.py"]) {
    assert.equal(inThreadScope(path, surface), false, path);
  }
});

test("a test file under .github/ is refused even beside a kept thread's path there", () => {
  assert.equal(inThreadScope(".github/scripts/x.test.mjs", new Set([".github/scripts/x.mjs"])), false);
});

test("a path with an empty, . or .. segment, or a leading /, is refused before any other rule", () => {
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

test(".github/ is refused even when a kept thread names a file there", () => {
  const github = new Set([".github/workflows/x.yml", ".GitHub/evals/c/a.md"]);
  assert.equal(inThreadScope(".github/workflows/x.yml", github), false);
  assert.equal(inThreadScope(".GitHub/evals/c/b.md", github), false);
  assert.equal(isProtectedPath(".github"), true);
  assert.equal(isProtectedPath(".githubx/a"), false);
});
