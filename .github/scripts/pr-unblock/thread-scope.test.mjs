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

test("a test file under .github/workflows/ is refused even beside a kept thread's path there", () => {
  assert.equal(inThreadScope(".github/workflows/x.test.mjs", new Set([".github/workflows/x.mjs"])), false);
});

test("a kept thread's path under .github/scripts/ and a test file beside it are in scope", () => {
  const kept = new Set([".github/scripts/x.mjs"]);
  assert.equal(inThreadScope(".github/scripts/x.mjs", kept), true);
  assert.equal(inThreadScope(".github/scripts/x.test.mjs", kept), true);
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

test(".github/workflows/ is refused even when a kept thread names a file there", () => {
  const github = new Set([".github/workflows/x.yml", ".GitHub/Workflows/a.yml"]);
  assert.equal(inThreadScope(".github/workflows/x.yml", github), false);
  assert.equal(inThreadScope(".GitHub/Workflows/a.yml", github), false);
  assert.equal(isProtectedPath(".github/workflows"), true);
  assert.equal(isProtectedPath(".github"), false);
  assert.equal(isProtectedPath(".github/scripts/x.mjs"), false);
  assert.equal(isProtectedPath(".github/workflowsx/a"), false);
});

test("a plugin's .mcp.json, .gitmodules or CODEOWNERS is outside the plugin-wide part of its scope", () => {
  for (const path of ["plugins/p/.mcp.json", "plugins/p/skills/s/.gitmodules", "plugins/p/CODEOWNERS"]) {
    assert.equal(inThreadScope(path, kept), false, path);
  }
});

// #8116's thread PRRT_kwDOTCGFQM6tojDu: on write-transcript.js, the owner's
// fix request named run-transcript.js, which check-paths refused.
const T = "plugins/knowledge/skills/video-digest/extraction/transcript";
const WRITE = `${T}/write-transcript.js`;
const RUN = `${T}/run-transcript.js`;

test("a same-plugin file in a kept thread's named_paths is in scope, and only that thread's", () => {
  const paths = new Set([WRITE]);
  assert.equal(inThreadScope(RUN, paths), false);
  assert.equal(inThreadScope(RUN, paths, [{ path: WRITE, named_paths: [RUN] }]), true);
  assert.equal(inThreadScope(`${T}/run-watch.js`, paths, [{ path: WRITE, named_paths: [RUN] }]), false);
  assert.equal(inThreadScope(`plugins/knowledge/lib/x.sh`, paths, [{ path: WRITE, named_paths: ["plugins/knowledge/lib/x.sh"] }]), true);
});

test("a named path in another plugin, under .github/, or on an instruction path is refused", () => {
  for (const path of [
    "plugins/other/lib/x.js",
    "plugins/knowledgebase/x.js",
    "src/x.js",
    ".github/workflows/x.yml",
    "plugins/knowledge/AGENTS.md",
    "plugins/knowledge/skills/s/claude.md",
    "plugins/knowledge/hooks/guard.mjs",
    "plugins/knowledge/Hooks/hooks.json",
    "plugins/knowledge/.claude-plugin/plugin.json",
    "plugins/knowledge/.claude/settings.json",
    "plugins/knowledge/.mcp.json",
    "plugins/knowledge/.gitmodules",
    "plugins/knowledge/CODEOWNERS",
  ]) {
    assert.equal(inThreadScope(path, new Set([WRITE]), [{ path: WRITE, named_paths: [path] }]), false, path);
  }
  // The thread the name came from decides the plugin, not any other kept thread.
  const other = [{ path: "plugins/other/a.md", named_paths: [RUN] }];
  assert.equal(inThreadScope(RUN, new Set([WRITE, "plugins/other/a.md"]), other), false);
});

test("a named path off normal form or outside plain ASCII is refused", () => {
  for (const path of [
    "plugins/knowledge/../other/x.js",
    `${T}/../../watch/run-watch.js`,
    "plugins/knowledge/./x.js",
    "/plugins/knowledge/x.js",
    "plugins/knowledge//x.js",
    "plugins/knowledge/a b.js",
    "plugins/knowledge\\x.js",
    "plugins/knowledge/ｘ.js",
  ]) {
    assert.equal(inThreadScope(path, new Set([WRITE]), [{ path: WRITE, named_paths: [path] }]), false, path);
  }
});

// From the security review of #8461: a segment named exactly hooks or
// .claude, plugin monitors, bin and .lsp.json, more code extensions, and
// non-ASCII letters JS /i does not fold (U+212A KELVIN SIGN, U+017F LONG S).
test("instruction segments with no trailing /, plugin monitors, bin and .lsp.json, and more code files are refused", () => {
  for (const path of [
    "plugins/p/hooks",
    "plugins/p/.claude",
    "plugins/p/skills/s/.claude-plugin",
    "plugins/p/monitors/monitors.json",
    "plugins/p/bin/tool",
    "plugins/p/.lsp.json",
    "plugins/p/lib/x.cjs",
    "plugins/p/lib/x.mts",
    "plugins/p/lib/x.cts",
    "plugins/p/lib/x.ps1",
    "plugins/p/lib/x.bash",
    "plugins/p/lib/x.zsh",
  ]) {
    assert.equal(inThreadScope(path, kept), false, path);
  }
});

test("a path with a non-ASCII letter is refused, even as a kept thread's own path", () => {
  for (const path of ["plugins/p/hooKs/hooks.json", "plugins/p/AGENTſ.md", "plugins/p/run.ſh", "plugins/p/café.md"]) {
    assert.equal(inThreadScope(path, new Set([...kept, path])), false, path);
  }
});
