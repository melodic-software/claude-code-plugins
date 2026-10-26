// A skill leaf's verify-scripts, validated by the real schema and passed
// through to the selected activity for collect-base-activity. Contract:
// docs/conventions/pr-pipeline/README.md, "Activities", verify-scripts: exact
// paths of scripts under scripts/ or a plugin's (or plugin skill's) scripts/.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse, stringify } from "yaml";

import { Rejection, resolve } from "./resolve.mjs";

const read = (relative) => readFileSync(new URL(relative, import.meta.url), "utf8");
const json = (relative) => JSON.parse(read(relative));
const FILES = {
  schema: json("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json"),
  vocabulary: json("./fixtures/vocabulary.json"),
  laneRules: json("./lane-rules.json"),
  effectGrants: json("./effect-grants.json"),
  activityRules: json("./activity-rules.json"),
};

const run = (fixDocs) => {
  const doc = parse(read("./fixtures/valid.yaml"));
  Object.assign(doc.activities["fix-prose"], fixDocs);
  return resolve(
    { ...FILES, config: stringify(doc) },
    {
      lane: "pr-refine",
      activity: "fix-prose",
      configPath: "docs/conventions/pr-pipeline.yaml",
      basePath: ".base",
      facts: { event: "synchronize", changedPaths: ["README.md"], labels: [] },
    },
  );
};
const rejected = (fixDocs) =>
  assert.throws(
    () => run(fixDocs),
    (error) => {
      assert.ok(error instanceof Rejection, `expected a Rejection, got ${error}`);
      assert.equal(error.code, "invalid-config", error.message);
      return true;
    },
  );

test("an activity without verify-scripts selects none", () => {
  assert.equal(run({}).selected["verify-scripts"], undefined);
});

test("verify-scripts under scripts/, a plugin and a plugin skill pass through", () => {
  const list = [
    "scripts/check-x.sh",
    "plugins/skill-quality/scripts/check-evals-quality.sh",
    "plugins/testing/skills/audit/scripts/cant-fail-scan.sh",
  ];
  assert.deepEqual(run({ "verify-scripts": list }).selected["verify-scripts"], list);
});

for (const path of [
  "plugins/testing/skills/audit/scripts/*.sh",
  "plugins/testing/**",
  "plugins/testing/skills/audit/scripts/cant-fail-scan.sh --check",
  "/plugins/testing/scripts/x.sh",
  "plugins/testing/scripts/../../../x.sh",
  "plugins/testing/x.sh",
  "plugins/Testing/scripts/x.sh",
  "plugins/testing/scripts/sub/x.sh",
  "plugins/testing/scripts/x.py",
  "x.sh",
  ".github/scripts/x.sh",
  "plugins/testing/scripts/x y.sh",
]) {
  test(`verify-scripts path ${JSON.stringify(path)} fails the schema`, () => {
    rejected({ "verify-scripts": [path] });
  });
}

// Only the runner that stages edit tools grants them, so a read skill that
// hands on no patch would list them for nothing.
test("verify-scripts with effect read and no applied-by.patch fails the schema", () => {
  rejected({ effect: "read", "verify-scripts": ["scripts/check-x.sh"] });
});

// A skill with an effect other than read runs in the write runner's run job,
// which holds the lane token and id-token: write. Code a verify-script runs can
// read that token from an ancestor's /proc/<pid>/environ, so the schema refuses
// the scripts that run checkout code there (pr-run-activity.md, Skill
// activities).
for (const script of ["scripts/run-test-file.sh", "plugins/skill-quality/scripts/check-skill.sh"]) {
  test(`verify-scripts listing ${script} on a write-effect skill fails the schema`, () => {
    rejected({ "verify-scripts": [script] });
    rejected({ "verify-scripts": ["scripts/check-x.sh", script] });
  });
}

test("an empty or repeating verify-scripts list fails the schema", () => {
  rejected({ "verify-scripts": [] });
  rejected({ "verify-scripts": ["scripts/check-x.sh", "scripts/check-x.sh"] });
});

test("verify-scripts on a script activity fails the schema", () => {
  const doc = parse(read("./fixtures/valid.yaml"));
  doc.activities["run-tests"]["verify-scripts"] = ["scripts/check-x.sh"];
  assert.throws(
    () =>
      resolve(
        { ...FILES, config: stringify(doc) },
        {
          lane: "pr-run-checks",
          configPath: "docs/conventions/pr-pipeline.yaml",
          basePath: ".base",
          facts: { event: "synchronize", changedPaths: ["src/app.js"], labels: [] },
        },
      ),
    (error) => error instanceof Rejection && error.code === "invalid-config",
  );
});
