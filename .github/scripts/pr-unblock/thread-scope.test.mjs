// Cases from issue #8109's Verification section.
import assert from "node:assert/strict";
import { test } from "node:test";

import { inThreadScope, isProtectedPath } from "./thread-scope.mjs";

const kept = new Set(["plugins/p/evals/c/graders/x.md", "src/a.js"]);

test("a kept thread's own path is in scope", () => {
  assert.equal(inThreadScope("src/a.js", kept), true);
  assert.equal(inThreadScope("plugins/p/evals/c/graders/x.md", kept), true);
});

test("a file in the same eval case as a kept thread's path is in scope, at any depth", () => {
  assert.equal(inThreadScope("plugins/p/evals/c/samples/y.json", kept), true);
  assert.equal(inThreadScope("plugins/p/evals/c/samples/deep/z.json", kept), true);
});

test("a sibling eval case, a skill file and an unnamed file stay out of scope", () => {
  assert.equal(inThreadScope("plugins/p/evals/other/samples/y.json", kept), false);
  assert.equal(inThreadScope("plugins/p/skills/s/SKILL.md", kept), false);
  assert.equal(inThreadScope("src/b.js", kept), false);
  assert.equal(inThreadScope("plugins/q/evals/c/samples/y.json", kept), false);
});

test("a file directly under evals/ is no case directory", () => {
  const evalsFile = new Set(["plugins/p/evals/evals.json"]);
  assert.equal(inThreadScope("plugins/p/evals/other.json", evalsFile), false);
  assert.equal(inThreadScope("plugins/p/evals/c/case.yaml", evalsFile), false);
});

test("with no kept thread under evals/, an eval case file is refused", () => {
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

test("a test file in another directory, or a same-directory file that is no test, stays out of scope", () => {
  const surface = new Set(["plugins/planning/surface/round.py", "src/a.js"]);
  for (const path of [
    "plugins/planning/surface/tests/test_round.py",
    "plugins/planning/test_round.py",
    "plugins/planning/other/test_round.py",
    "src/lib/a.test.js",
    "plugins/planning/surface/helper.py",
    "plugins/planning/surface/testing.py",
    "plugins/planning/surface/test_round.sh",
    "test_root.py",
  ]) {
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
