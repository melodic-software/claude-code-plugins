// Structural checks on /review:merge-risk: the rubric has one home, the
// checker is the read-only brief-reviewer and is never handed the rated rows.
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const SKILL = join(dirname(fileURLToPath(import.meta.url)), "../skills/merge-risk");
const skill = readFileSync(join(SKILL, "SKILL.md"), "utf8");
const rubric = readFileSync(join(SKILL, "reference/rubric.md"), "utf8");
const brief = /## 3\. Check blind[\s\S]*?```text\n([\s\S]*?)```/.exec(skill)[1];

describe("merge-risk", () => {
  test("the checker is the read-only brief-reviewer agent", () => {
    assert.match(skill, /## 3\. Check blind[\s\S]*?read-only\s+`review:brief-reviewer` agent/);
  });
  test("the checker's brief carries only the pull request, repository, rubric and saved reads", () => {
    assert.deepEqual([...new Set(brief.match(/<[^>]+>/g))].sort(), ["<dir>", "<n>", "<owner/repo>", "<rubric path>"]);
  });
  test("the rubric holds the five required areas", () => {
    for (const area of ["Alignment", "Impact", "Verification", "Reversibility", "Error detection"]) {
      assert.match(rubric, new RegExp(`^## ${area}$`, "m"), area);
    }
  });
  test("the skill points at the rubric instead of restating an area", () => {
    assert.ok(!/^## (Alignment|Impact|Verification|Reversibility|Error detection)$/m.test(skill));
  });
  test("the skill grants no shell, so it cannot post or gate", () => {
    const tools = /^allowed-tools: (.*)$/m.exec(skill)[1];
    assert.ok(!tools.includes("Bash"), tools);
  });
});
