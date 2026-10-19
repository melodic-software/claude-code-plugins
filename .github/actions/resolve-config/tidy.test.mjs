// A skill leaf's tidy, validated by the real schema and passed through to the
// selected activity for collect-base-activity with its defaults and turn share
// applied. Contract: docs/conventions/pr-pipeline/README.md, "Activities", tidy.
// The fixture sets no models, so the run's turn cap is the standard
// profile's 75 (README.md, "Models").
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse, stringify } from "yaml";

import { Rejection, resolve } from "./resolve.mjs";

const read = (relative) => readFileSync(new URL(relative, import.meta.url), "utf8");
const json = (relative) => JSON.parse(read(relative));

const run = (fixDocs, activity = "fix-docs") => {
  const doc = parse(read("./fixtures/valid.yaml"));
  Object.assign(doc.activities[activity], fixDocs);
  return resolve(
    {
      config: stringify(doc),
      schema: json("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json"),
      vocabulary: json("./fixtures/vocabulary.json"),
      laneRules: json("./lane-rules.json"),
      effectGrants: json("./effect-grants.json"),
      activityRules: json("./activity-rules.json"),
    },
    {
      lane: "pr-refine",
      activity: "fix-docs",
      configPath: "docs/conventions/pr-pipeline.yaml",
      basePath: ".base",
      facts: { event: "synchronize", changedPaths: ["README.md"], labels: [], workClasses: [] },
    },
  );
};
const selected = (fixDocs) => run(fixDocs).selected;
const rejected = (fixDocs, activity) =>
  assert.throws(
    () => run(fixDocs, activity),
    (error) => {
      assert.ok(error instanceof Rejection, `expected a Rejection, got ${error}`);
      assert.equal(error.code, "invalid-config", error.message);
      return true;
    },
  );

const PASSES = [
  { skill: "simplify", files: "code" },
  { skill: "code-tidying:dissolve-comments", args: "safe --added-since HEAD", files: "code" },
  { skill: "ai-slop:audit", args: "fix", files: "markdown" },
];

test("an activity without tidy selects none", () => {
  assert.equal(selected({}).tidy, undefined);
});

test("tidy with passes alone takes the 150-line cutoff and a fifth of the 75-turn cap", () => {
  assert.deepEqual(selected({ tidy: { passes: PASSES } }).tidy, {
    "max-changed-lines": 150,
    "turn-share": 0.2,
    turns: 15,
    passes: PASSES,
  });
});

test("a set cutoff passes through, and the turn share rounds down", () => {
  const { tidy } = selected({ tidy: { "max-changed-lines": 80, "turn-share": 0.3, passes: PASSES } });
  assert.equal(tidy["max-changed-lines"], 80);
  // 75 * 0.3 = 22.5.
  assert.equal(tidy.turns, 22);
});

test("tidy on a read activity fails the schema", () => {
  rejected({ effect: "read", tidy: { passes: PASSES } });
});

test("tidy on a script activity fails the schema", () => {
  rejected({ tidy: { passes: PASSES } }, "run-tests");
});

for (const [name, tidy] of [
  ["no passes", {}],
  ["an empty pass list", { passes: [] }],
  ["an unknown key", { passes: PASSES, extra: 1 }],
  ["a zero cutoff", { "max-changed-lines": 0, passes: PASSES }],
  ["a zero share", { "turn-share": 0, passes: PASSES }],
  ["a share over half", { "turn-share": 0.6, passes: PASSES }],
  ["a pass on another file kind", { passes: [{ skill: "simplify", files: "tree" }] }],
  ["a pass with no file kind", { passes: [{ skill: "simplify" }] }],
  ["a capitalized skill", { passes: [{ skill: "Simplify", files: "code" }] }],
  ["a three-part skill", { passes: [{ skill: "a:b:c", files: "code" }] }],
  ["shell characters in args", { passes: [{ skill: "simplify", args: "x; y", files: "code" }] }],
  ["an unknown pass key", { passes: [{ skill: "simplify", files: "code", when: "always" }] }],
]) {
  test(`tidy with ${name} fails the schema`, () => {
    rejected({ tidy });
  });
}
