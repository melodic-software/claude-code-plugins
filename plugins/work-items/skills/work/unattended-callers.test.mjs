// test-scope: plugins/debugging/skills/debug/SKILL.md plugins/discovery/skills/research/SKILL.md plugins/implementation/skills/implement-dispatch/SKILL.md
// test-scope: plugins/source-control/skills/babysit-prs/SKILL.md plugins/source-control/skills/pull-request/SKILL.md plugins/testing/skills/fix-failing/SKILL.md
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { test } from "node:test";

const ROOT = new URL("../../../../", import.meta.url);
const read = (path) => readFileSync(new URL(path, ROOT), "utf8");

const WORK = "plugins/work-items/skills/work/SKILL.md";
const CI_MODE = "plugins/work-items/skills/work/reference/ci-mode.md";
const LOOP = "plugins/source-control/skills/babysit-loop/SKILL.md";
const CYCLE = "plugins/source-control/skills/babysit-loop/reference/cycle-shape.md";

const takesUnattended = (skill) => {
  const [plugin, name] = skill.split(":");
  const path = `plugins/${plugin}/skills/${name}/SKILL.md`;
  assert.ok(existsSync(new URL(path, ROOT)), `${skill} has no SKILL.md at ${path}`);
  const frontmatter = read(path).split(/^---$/m)[1] ?? "";
  return /^argument-hint:.*--unattended/m.test(frontmatter);
};

const calls = (text) =>
  [...text.matchAll(/`\/([a-z0-9-]+:[a-z0-9-]+)\s+([^`]*)`/g)].map(([span, skill, args]) => ({
    span: span.replace(/\s+/g, " "),
    skill,
    args: args.trim().split(/\s+/),
  }));

const between = (path, start, end) => {
  const lines = read(path).split("\n");
  const from = lines.findIndex((line) => line.startsWith(start));
  assert.notEqual(from, -1, `${path} has no line starting ${JSON.stringify(start)}`);
  const rest = lines.slice(from + 1).findIndex((line) => end !== undefined && line.startsWith(end));
  return lines.slice(from, rest === -1 ? undefined : from + 1 + rest).join("\n");
};

const assertUnattended = (where, text, expected, { exempt = [] } = {}) => {
  const called = new Set();
  for (const { span, skill, args } of calls(text)) {
    if (exempt.includes(skill) || !takesUnattended(skill)) continue;
    assert.ok(args.includes("--unattended"), `${where}: ${span} calls ${skill} without --unattended`);
    called.add(skill);
  }
  for (const skill of expected) {
    assert.ok(called.has(skill), `${where}: no call of /${skill} with --unattended`);
  }
};

test("work --ci: the CI-mode prompt passes --unattended to each skill it calls that takes it", () => {
  assertUnattended(
    CI_MODE,
    between(CI_MODE, "# CI mode", "## "),
    ["debugging:debug", "discovery:research"],
    { exempt: ["source-control:pull-request"] },
  );
});

test("work --ci: the skill body sends CI mode to the file the check above reads", () => {
  assert.ok(between(WORK, "## CI mode", "## ").includes("skills/work/reference/ci-mode.md"));
});

test("work: an autonomous invocation passes --unattended to each later skill that takes it", () => {
  assertUnattended(
    `${WORK} autonomous invocation`,
    between(WORK, "**Autonomous invocation (no interactive user).**", "### "),
    [
      "debugging:debug",
      "implementation:implement-dispatch",
      "source-control:pull-request",
      "source-control:babysit-prs",
    ],
  );
});

test("babysit-loop: each cycle calls babysit-prs with --unattended", () => {
  assertUnattended(
    `${LOOP} Owned mechanics`,
    between(LOOP, "## Owned mechanics", "## "),
    ["source-control:babysit-prs"],
  );
  assertUnattended(
    `${CYCLE} step 4`,
    between(CYCLE, "4. **Invoke the mechanic.**", "5. "),
    ["source-control:babysit-prs"],
  );
});
