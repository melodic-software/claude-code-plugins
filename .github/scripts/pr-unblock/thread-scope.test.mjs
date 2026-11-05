import assert from "node:assert/strict";
import { test } from "node:test";

import { copyPathsOf, inThreadScope, isProtectedPath, prPathsOf, sharedCopyPairs } from "./thread-scope.mjs";

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

test("code in the same plugin is in scope, and its permission config and package manifest are refused", () => {
  const named = new Set(["plugins/p/skills/s/SKILL.md"]);
  for (const path of ["plugins/p/scripts/run.sh", "plugins/p/skills/s/scripts/helper.py", "plugins/p/lib/x.mjs", "plugins/p/lib/x.js", "plugins/p/lib/x.ts", "plugins/p/lib/X.SH"]) {
    assert.equal(inThreadScope(path, named), true, path);
  }
  for (const path of ["plugins/p/.claude/settings.json", "plugins/p/package.json"]) {
    assert.equal(inThreadScope(path, named), false, path);
  }
});

test("hooks, manifests, agent rules, monitors, bin and MCP config in the same plugin are in scope", () => {
  const named = new Set(["plugins/p/skills/s/SKILL.md"]);
  for (const path of [
    "plugins/p/hooks/hooks.json",
    "plugins/p/.claude-plugin/plugin.json",
    "plugins/p/AGENTS.md",
    "plugins/p/skills/s/CLAUDE.md",
    "plugins/p/.claude/rules/r.md",
    "plugins/p/monitors/monitors.json",
    "plugins/p/bin/tool",
    "plugins/p/.mcp.json",
    "plugins/p/.lsp.json",
  ]) {
    assert.equal(inThreadScope(path, named), true, path);
  }
});

test("a thread's own path stays in scope whatever its type, and a sibling test of code stays in scope", () => {
  for (const path of ["plugins/p/hooks/guard.sh", "plugins/p/.claude-plugin/plugin.json", "plugins/p/AGENTS.md"]) {
    assert.equal(inThreadScope(path, new Set([path])), true, path);
  }
  assert.equal(inThreadScope("plugins/p/hooks/guard.test.mjs", new Set(["plugins/p/hooks/guard.mjs"])), true);
  assert.equal(inThreadScope("plugins/p/scripts/test_run.py", new Set(["plugins/p/README.md"])), true);
  assert.equal(inThreadScope("src/lib/test_run.py", new Set(["src/README.md"])), false);
});

test("another plugin's file and an unnamed file outside plugins/ stay out of scope", () => {
  assert.equal(inThreadScope("plugins/q/README.md", kept), false);
  assert.equal(inThreadScope("plugins/q/lib/x.mjs", kept), false);
  assert.equal(inThreadScope("plugins/pp/README.md", kept), false);
  assert.equal(inThreadScope("src/b.js", kept), false);
  assert.equal(inThreadScope("plugins/README.md", kept), false);
});

test("with no kept thread under the plugin, its files are refused", () => {
  assert.equal(inThreadScope("plugins/p/README.md", new Set(["src/a.js"])), false);
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

test("a plugin's .gitmodules, CODEOWNERS or settings file is outside the plugin-wide part of its scope", () => {
  for (const path of ["plugins/p/skills/s/.gitmodules", "plugins/p/CODEOWNERS", "plugins/p/settings.json"]) {
    assert.equal(inThreadScope(path, kept), false, path);
  }
});

// #8116's thread PRRT_kwDOTCGFQM6tojDu: on write-transcript.js, the owner's
// fix request named run-transcript.js, which check-paths refused.
const T = "plugins/knowledge/skills/video-digest/extraction/transcript";
const WRITE = `${T}/write-transcript.js`;
const RUN = `${T}/run-transcript.js`;

test("a same-plugin file is in scope named or not", () => {
  const paths = new Set([WRITE]);
  assert.equal(inThreadScope(RUN, paths), true);
  assert.equal(inThreadScope(RUN, paths, [{ path: WRITE, named_paths: [RUN] }]), true);
  assert.equal(inThreadScope(`plugins/knowledge/lib/x.sh`, paths, [{ path: WRITE, named_paths: ["plugins/knowledge/lib/x.sh"] }]), true);
});

test("a named path in another plugin, under .github/, or on an instruction path is refused", () => {
  for (const path of [
    "plugins/other/lib/x.js",
    "plugins/knowledgebase/x.js",
    "src/x.js",
    ".github/workflows/x.yml",
    "plugins/knowledge/.claude/settings.json",
    "plugins/knowledge/package-lock.json",
    "plugins/knowledge/.gitmodules",
    "plugins/knowledge/CODEOWNERS",
  ]) {
    assert.equal(inThreadScope(path, new Set([WRITE]), [{ path: WRITE, named_paths: [path] }]), false, path);
  }
  // A name does not reach past its thread's plugin.
  const other = [{ path: "plugins/other/a.md", named_paths: ["plugins/third/x.js"] }];
  assert.equal(inThreadScope("plugins/third/x.js", new Set([WRITE, "plugins/other/a.md"]), other), false);
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
test("more code files in the same plugin are in scope", () => {
  for (const path of [
    "plugins/p/lib/x.cjs",
    "plugins/p/lib/x.mts",
    "plugins/p/lib/x.cts",
    "plugins/p/lib/x.ps1",
    "plugins/p/lib/x.bash",
    "plugins/p/lib/x.zsh",
  ]) {
    assert.equal(inThreadScope(path, kept), true, path);
  }
});

test("a path with a non-ASCII letter is refused, even as a kept thread's own path", () => {
  for (const path of ["plugins/p/hooKs/hooks.json", "plugins/p/AGENTſ.md", "plugins/p/run.ſh", "plugins/p/café.md"]) {
    assert.equal(inThreadScope(path, new Set([...kept, path])), false, path);
  }
});

// A finding on a doc whose fix lives in a script the pull request also
// changes: thread on A, fix in B.
const DOC = "plugins/p/skills/s/converge.md";
const SCRIPT = "plugins/p/skills/s/scripts/converge-plan.sh";

test("a file the PR already changes is in every kept thread's scope", () => {
  const prPaths = new Set(prPathsOf([{ filename: DOC }, { filename: SCRIPT }, { filename: "src/b.js", previous_filename: "src/old.js" }]));
  for (const path of [SCRIPT, "src/b.js", "src/old.js"]) {
    assert.equal(inThreadScope(path, new Set([DOC]), [], { prPaths }), true, path);
  }
});

test("a file outside plugins/ the PR does not change stays outside a thread's scope", () => {
  const prPaths = new Set([DOC]);
  assert.equal(inThreadScope("src/b.js", new Set([DOC]), [], { prPaths }), false);
});

test("a fix that adds a file the PR lists gets no pr_paths scope", () => {
  const prPaths = new Set([DOC, "src/b.js"]);
  assert.equal(inThreadScope("src/b.js", new Set([DOC]), [], { prPaths, added: true }), false);
  // A new file stays in the thread's own scope as before.
  assert.equal(inThreadScope("plugins/p/skills/s/new.md", new Set([DOC]), [], { prPaths, added: true }), true);
});

test("a protected, instruction, HIGH floor or control-plane path outside plugins/ the PR changes is refused", () => {
  const refused = [
    ".github/workflows/x.yml",
    ".GitHub/Workflows/x.yml",
    "CODEOWNERS",
    ".github/CODEOWNERS",
    ".gitmodules",
    "plugins/p/.claude/settings.json",
    "plugins/p/package.json",
    ".github/standards/trusted-actors/trusted-actors.json",
    ".github/actions/check-trusted-trigger/action.yml",
    ".github/actions/resolve-config/resolve.mjs",
    ".github/scripts/pr-unblock/thread-scope.mjs",
    ".github/actions/setup-runner-isolation/action.yml",
    ".github/standards/runner-policy/x.json",
    "CLAUDE.md",
    "docs/AGENTS.md",
    ".mcp.json",
    ".lsp.json",
    ".claude/rules/r.md",
    ".claude-plugin/marketplace.json",
    "a\\b.md",
    "a b.md",
    "src/../x.md",
  ];
  const listed = refused.map((filename) => ({ filename }));
  assert.deepEqual(prPathsOf(listed), []);
  // Even when a thread file lists them, inThreadScope refuses each beside a
  // thread outside their plugin.
  for (const path of refused) {
    assert.equal(inThreadScope(path, new Set(["docs/x.md"]), [], { prPaths: new Set(refused), copyPaths: new Set(refused) }), false, path);
  }
});

test("a plugin's own hooks, manifest, agent rules, monitors and bin the PR changes join pr_paths", () => {
  const surfaces = ["plugins/p/AGENTS.md", "plugins/p/.lsp.json", "plugins/p/.claude-plugin/plugin.json", "plugins/p/hooks/guard.sh", "plugins/p/monitors/monitors.json", "plugins/p/bin/tool"];
  assert.deepEqual(prPathsOf(surfaces.map((filename) => ({ filename }))), [...surfaces].sort());
});

// #12630: the fix needed eval scaffolds the PR did not list.
test("a plugin's or a skill's eval files are in scope from any thread, new files included", () => {
  for (const path of ["plugins/q/evals/c/case.yaml", "plugins/q/evals/c/graders/g.sh", "plugins/q/skills/s/evals/c/samples/y.json", "plugins/q/skills/s/evals/evals.json"]) {
    assert.equal(inThreadScope(path, new Set(["docs/x.md"]), [], { added: true }), true, path);
  }
  for (const path of ["plugins/q/evals/c/package.json", "plugins/q/evals/c/.claude/settings.json", "plugins/q/skills/s/x/evals/y.json", "evals/c/case.yaml", "plugins/q/evalsx/y.json"]) {
    assert.equal(inThreadScope(path, new Set(["docs/x.md"])), false, path);
  }
});

test("any file in a plugin the PR already changes is in scope, new files included, and another plugin's is not", () => {
  const prPaths = new Set(prPathsOf([{ filename: "plugins/p/skills/s/SKILL.md" }, { filename: "README.md" }]));
  for (const path of ["plugins/p/lib/x.mjs", "plugins/p/hooks/hooks.json", "plugins/p/skills/t/scripts/new.py", "plugins/p/AGENTS.md"]) {
    assert.equal(inThreadScope(path, new Set(["docs/x.md"]), [], { prPaths, added: true }), true, path);
  }
  for (const path of ["plugins/q/README.md", "plugins/p/package.json", "plugins/p/.claude/settings.json", "src/x.js"]) {
    assert.equal(inThreadScope(path, new Set(["docs/x.md"]), [], { prPaths }), false, path);
  }
});

const REGISTRY = `# header
lib/hook-utils.sh plugins/a/hooks/hook-utils.sh
lib/hook-utils.sh plugins/b/hooks/hook-utils.sh # trailing
lib/other.sh plugins/c/scripts/other.sh

lib/settings.json plugins/d/settings.json
lib/x.sh .github/workflows/x.sh
`;

test("sharedCopyPairs reads the registry's two-field lines", () => {
  assert.deepEqual(sharedCopyPairs(REGISTRY), [
    ["lib/hook-utils.sh", "plugins/a/hooks/hook-utils.sh"],
    ["lib/hook-utils.sh", "plugins/b/hooks/hook-utils.sh"],
    ["lib/other.sh", "plugins/c/scripts/other.sh"],
    ["lib/settings.json", "plugins/d/settings.json"],
    ["lib/x.sh", ".github/workflows/x.sh"],
  ]);
});

// #12346: a fix to lib/hook-utils.sh had to regenerate its 20 copies.
test("the copies of a canonical the PR changes are in scope, and do not open the rest of their plugins", () => {
  const files = [{ filename: "lib/hook-utils.sh" }, { filename: "lib/settings.json" }, { filename: "lib/x.sh" }];
  const copyPaths = new Set(copyPathsOf(files, sharedCopyPairs(REGISTRY)));
  assert.deepEqual([...copyPaths], ["plugins/a/hooks/hook-utils.sh", "plugins/b/hooks/hook-utils.sh"]);
  const prPaths = new Set(prPathsOf(files));
  const threads = new Set(["lib/hook-utils.sh"]);
  assert.equal(inThreadScope("plugins/a/hooks/hook-utils.sh", threads, [], { prPaths, copyPaths }), true);
  assert.equal(inThreadScope("plugins/a/hooks/hook-utils.sh", threads, [], { prPaths, copyPaths, added: true }), false);
  for (const path of ["plugins/a/README.md", "plugins/a/hooks/other.sh", "plugins/c/scripts/other.sh", "plugins/d/settings.json", ".github/workflows/x.sh"]) {
    assert.equal(inThreadScope(path, threads, [], { prPaths, copyPaths }), false, path);
  }
});

test(".github/workflows/ stays refused through every widened class", () => {
  const path = ".github/workflows/ci.yml";
  const prPaths = new Set([path, "plugins/p/README.md"]);
  assert.equal(inThreadScope(path, new Set(["plugins/p/README.md"]), [], { prPaths, copyPaths: new Set([path]) }), false);
  assert.deepEqual(copyPathsOf([{ filename: "lib/x.sh" }], [["lib/x.sh", path]]), []);
  assert.equal(inThreadScope(".github/scripts/pr-unblock/thread-scope.mjs", new Set(["plugins/p/README.md"]), [], { prPaths }), false);
});
