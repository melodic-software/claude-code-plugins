import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { loadRules, REFUSALS } from "./apply-patch.mjs";
import { PATH_RULES, segments } from "./protected-paths.mjs";
import { denyRules, main, PATTERNS } from "./deny-rules.mjs";

const REPO_ROOT = join(import.meta.dirname, "../../..");
const ISSUE_REFUSE = loadRules(REPO_ROOT).issue.refuse;
const refused = (path) => Object.values(PATH_RULES).some((rule) => rule(segments(path)));

// A gitignore pattern as the permission docs describe Edit rules
// (https://code.claude.com/docs/en/permissions#how-path-patterns-match): a
// leading `/` anchors at the checkout, a bare name matches at any depth, `**/`
// spans zero or more directories, a trailing `/**` everything below, `*` one
// segment's characters.
function matches(rule, path) {
  const pattern = /^Edit\((.*)\)$/.exec(rule)[1];
  const anchored = pattern.startsWith("/");
  const body = anchored ? pattern.slice(1) : pattern;
  let source = "";
  for (let i = 0; i < body.length; ) {
    if (body.startsWith("**/", i)) {
      source += "(?:.*/)?";
      i += 3;
    } else if (body.startsWith("/**", i) && i + 3 === body.length) {
      source += "/.*";
      i += 3;
    } else if (body[i] === "*") {
      source += "[^/]*";
      i += 1;
    } else {
      source += body[i].replace(/[.+?^${}()|[\]\\]/g, "\\$&");
      i += 1;
    }
  }
  return new RegExp(`^${anchored ? "" : "(?:.*/)?"}${source}$`).test(path);
}

const DIRS = [".claude", ".github", "docs", "plugins", "scripts"];

test("every path rule has deny patterns, so a new one cannot reach the lane without them", () => {
  assert.deepEqual(Object.keys(PATTERNS).toSorted(), Object.keys(PATH_RULES).toSorted());
});

test("the issue row's path refusals become Edit rules; its symlink, gitlink and rename refusals name no path", () => {
  assert.deepEqual(denyRules(ISSUE_REFUSE, DIRS), [
    "Edit(/.github/workflows/**)",
    "Edit(/CODEOWNERS)",
    "Edit(/.github/CODEOWNERS)",
    "Edit(/docs/CODEOWNERS)",
    "Edit(.gitmodules)",
    "Edit(/settings*.json)",
    "Edit(/.claude/**/settings*.json)",
    "Edit(/.github/**/settings*.json)",
    "Edit(/docs/**/settings*.json)",
    "Edit(/scripts/**/settings*.json)",
  ]);
  assert.ok(ISSUE_REFUSE.some((name) => Object.hasOwn(REFUSALS, name) && !Object.hasOwn(PATH_RULES, name)));
});

test("a row that refuses no path rule gets no rules", () => {
  assert.deepEqual(denyRules(["symlink", "gitlink"], DIRS), []);
});

// The lane must never lose an edit apply-patch would push: no tracked file it
// accepts, and none of these, matches a rule. The paths it refuses that the
// lane hits most match one.
test("the rules match only paths apply-patch refuses, plugins/ settings files included, and cover the common ones", () => {
  const dirs = execFileSync("git", ["-C", REPO_ROOT, "ls-tree", "-d", "--name-only", "HEAD"], { encoding: "utf8" }).split("\n").filter(Boolean);
  const rules = denyRules(ISSUE_REFUSE, dirs);
  const tracked = execFileSync("git", ["-C", REPO_ROOT, "ls-files"], { encoding: "utf8" }).split("\n").filter(Boolean);
  const accepted = [
    ...tracked,
    "plugins/x/settings.json",
    "plugins/x/.claude/settings.local.json",
    ".github/scripts/settings.mjs",
    ".github/actions/x/action.yml",
    "docs/x/CODEOWNERS",
    "a/CODEOWNERS",
    "settings.yaml",
  ].filter((path) => !refused(path));
  assert.ok(accepted.some((path) => path.startsWith("plugins/") && path.endsWith("/settings.json")));
  for (const path of accepted) {
    assert.deepEqual(
      rules.filter((rule) => matches(rule, path)),
      [],
      path,
    );
  }
  for (const path of [".github/workflows/ci.yml", ".github/workflows/sub/x.yml", ".github/CODEOWNERS", "CODEOWNERS", "a/b/.gitmodules", ".claude/settings.json", ".claude/settings.local.json", "settings.json", "docs/x/settings.json"]) {
    assert.ok(refused(path), path);
    assert.ok(
      rules.some((rule) => matches(rule, path)),
      path,
    );
  }
});

test("main prints the row's rules for the base's top-level directories", (t) => {
  const base = mkdtempSync(join(tmpdir(), "deny-rules-"));
  t.after(() => rmSync(base, { recursive: true, force: true }));
  for (const dir of [".git", ".github/actions/resolve-config", "plugins", "lib"]) mkdirSync(join(base, dir), { recursive: true });
  writeFileSync(join(base, "README.md"), "");
  writeFileSync(join(base, ".github/actions/resolve-config/patch-rules.json"), JSON.stringify({ issue: { refuse: ["settings", "symlink"] } }));
  const lines = [];
  main([base, "issue"], { log: (line) => lines.push(line) });
  assert.deepEqual(lines, ["Edit(/settings*.json)", "Edit(/.github/**/settings*.json)", "Edit(/lib/**/settings*.json)"]);
  assert.throws(() => main([base, "none"], { log() {} }), /no none row/);
  mkdirSync(join(base, "a b"));
  assert.throws(() => main([base, "issue"], { log() {} }), /name a rule cannot carry/);
});
