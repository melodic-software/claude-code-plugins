import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";

import { applyProposal, check, pathRefusal } from "./hill-climb-edit.mjs";

const refusal = (path) => pathRefusal(path, "testing", "write");

test("a path inside the skill directory passes", () => {
  assert.equal(refusal("plugins/testing/skills/write/SKILL.md"), null);
  assert.equal(refusal("plugins/testing/skills/write/reference/tdd.md"), null);
});

test("a path outside the skill directory is refused", () => {
  for (const path of [
    "plugins/testing/skills/write-other/SKILL.md",
    "plugins/testing/skills/writer/SKILL.md",
    "plugins/testing/skills/write",
    "plugins/testing/skills/SKILL.md",
    "plugins/testing/.claude-plugin/plugin.json",
    "plugins/other/skills/write/SKILL.md",
    ".github/workflows/maintenance-measure-skill-edit.yml",
  ]) {
    assert.match(refusal(path), /^outside plugins\/testing\/skills\/write\/$/, path);
  }
});

test("a path under an evals/ directory is refused, inside the skill too", () => {
  assert.equal(refusal("plugins/testing/skills/write/evals/case/prompt.md"), "under an evals/ directory");
  assert.equal(refusal("plugins/testing/skills/write/reference/evals/x.md"), "under an evals/ directory");
  assert.match(refusal("plugins/testing/evals/write-first-unit/prompt.md"), /^outside /);
});

test("a git-quoted path and a dot segment are refused", () => {
  assert.match(refusal('"plugins/testing/skills/write/\\303\\251.md"'), /git-quoted/);
  assert.match(refusal("plugins/testing/skills/write/../write-other/SKILL.md"), /segment/);
  assert.match(refusal("plugins/testing/skills/write/./SKILL.md"), /segment/);
  assert.match(refusal("plugins/testing/skills/write//SKILL.md"), /segment/);
});

test("check lists each refused path and refuses an empty change as no edit", () => {
  assert.deepEqual(check(["plugins/testing/skills/write/SKILL.md"], "testing", "write"), []);
  assert.deepEqual(check([], "testing", "write"), ["(none): no edit"]);
  assert.deepEqual(check(["plugins/testing/skills/write/SKILL.md", "README.md"], "testing", "write"), ["README.md: outside plugins/testing/skills/write/"]);
});

const withRepo = (files, run) => {
  const root = mkdtempSync(join(tmpdir(), "hill-climb-"));
  try {
    for (const [path, text] of Object.entries(files)) {
      mkdirSync(dirname(join(root, path)), { recursive: true });
      writeFileSync(join(root, path), text);
    }
    return run(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
};

test("apply replaces the one occurrence and prints the changed path", () => {
  withRepo({ "plugins/testing/skills/write/SKILL.md": "Write a test first.\nThen code.\n" }, (root) => {
    const path = applyProposal(root, "testing", "write", { file: "SKILL.md", old_string: "Then code.", new_string: "Then the code, $& kept." });
    assert.equal(path, "plugins/testing/skills/write/SKILL.md");
    assert.equal(readFileSync(join(root, path), "utf8"), "Write a test first.\nThen the code, $& kept.\n");
  });
});

test("apply refuses an edit it cannot place exactly once, or off the skill's markdown", () => {
  const files = { "plugins/testing/skills/write/SKILL.md": "a\na\n", "plugins/testing/skills/write/run.sh": "a\n" };
  withRepo(files, (root) => {
    const apply = (proposal) => () => applyProposal(root, "testing", "write", proposal);
    assert.throws(apply({ file: "SKILL.md", old_string: "a", new_string: "b" }), /occurs 2 times/);
    assert.throws(apply({ file: "SKILL.md", old_string: "zzz", new_string: "b" }), /occurs 0 times/);
    assert.throws(apply({ file: "SKILL.md", old_string: "a", new_string: "a" }), /different new_string/);
    assert.throws(apply({ file: "run.sh", old_string: "a", new_string: "b" }), /not a markdown file/);
    assert.throws(apply({ file: "../other/SKILL.md", old_string: "a", new_string: "b" }), /segment/);
    assert.throws(apply({ file: "evals/c/prompt.md", old_string: "a", new_string: "b" }), /evals/);
    assert.throws(apply({ file: "missing.md", old_string: "a", new_string: "b" }), /not a regular file/);
    assert.throws(apply(null), /needs a file/);
  });
});

test("apply refuses a symbolic link", () => {
  withRepo({ "plugins/testing/skills/write/SKILL.md": "a\n" }, (root) => {
    symlinkSync("SKILL.md", join(root, "plugins/testing/skills/write/LINK.md"));
    assert.throws(() => applyProposal(root, "testing", "write", { file: "LINK.md", old_string: "a", new_string: "b" }), /not a regular file/);
  });
});
