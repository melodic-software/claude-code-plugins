// A skill treats a run as unattended only when its caller passes --unattended,
// so a lane prompt or loop driver that calls such a skill
// without the flag reaches an ask nobody answers. The lane config's args are
// checked by .github/actions/resolve-config/live-config.test.mjs; this suite
// checks the calls the skill bodies write themselves: this skill's CI mode
// (the work-resolve-issue lane's prompt) and its autonomous invocation, and
// the merge lane's driver, babysit-loop. A skill "takes --unattended" when its
// argument-hint lists the flag. A span with arguments is a call; a bare
// `/<plugin>:<skill>` span names the skill without calling it.
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { test } from "node:test";

const ROOT = new URL("../../../../", import.meta.url);
const read = (path) => readFileSync(new URL(path, ROOT), "utf8");

const WORK = "plugins/work-items/skills/work/SKILL.md";
const LOOP = "plugins/source-control/skills/babysit-loop/SKILL.md";
const CYCLE = "plugins/source-control/skills/babysit-loop/reference/cycle-shape.md";

const takesUnattended = (skill) => {
  const [plugin, name] = skill.split(":");
  const path = `plugins/${plugin}/skills/${name}/SKILL.md`;
  assert.ok(existsSync(new URL(path, ROOT)), `${skill} has no SKILL.md at ${path}`);
  const frontmatter = read(path).split(/^---$/m)[1] ?? "";
  return /^argument-hint:.*--unattended/m.test(frontmatter);
};

// Every inline-code span that calls a skill with arguments.
const calls = (text) =>
  [...text.matchAll(/`\/([a-z0-9-]+:[a-z0-9-]+)\s+([^`]*)`/g)].map(([span, skill, args]) => ({
    span: span.replace(/\s+/g, " "),
    skill,
    args: args.trim().split(/\s+/),
  }));

// The text from the line starting with `start` up to the next line starting
// with `end` (or the end of the file).
const between = (path, start, end) => {
  const lines = read(path).split("\n");
  const from = lines.findIndex((line) => line.startsWith(start));
  assert.notEqual(from, -1, `${path} has no line starting ${JSON.stringify(start)}`);
  const rest = lines.slice(from + 1).findIndex((line) => end !== undefined && line.startsWith(end));
  return lines.slice(from, rest === -1 ? undefined : from + 1 + rest).join("\n");
};

// Every call of a skill that takes --unattended passes it, and each skill in
// `expected` is called at least once, so dropping the flag from a call (which
// turns it into a bare name) fails here too.
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
  // The section names /source-control:pull-request's prep and review-venue as
  // procedures to follow and a file the runner writes: the lane loads only
  // this plugin, so neither is a call.
  assertUnattended(
    `${WORK} CI mode`,
    between(WORK, "## CI mode", "## "),
    ["debugging:debug", "discovery:research"],
    { exempt: ["source-control:pull-request"] },
  );
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
