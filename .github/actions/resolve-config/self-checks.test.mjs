// A skill leaf's self-checks, validated by the real schema and passed through
// to the selected activity for collect-base-activity, apart from its checks,
// which the issue lane's run-checks job reruns. Contract:
// docs/conventions/pr-pipeline/README.md, "Activities", self-checks.
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

const resolveDoc = (doc, request) =>
  resolve(
    { ...FILES, config: stringify(doc) },
    { configPath: "docs/conventions/pr-pipeline.yaml", basePath: ".base", ...request },
  );
const run = (fixDocs) => {
  const doc = parse(read("./fixtures/valid.yaml"));
  Object.assign(doc.activities["fix-docs"], fixDocs);
  return resolveDoc(doc, {
    lane: "pr-refine",
    activity: "fix-docs",
    facts: { event: "synchronize", changedPaths: ["README.md"], labels: [], workClasses: [] },
  });
};
const rejected = (thunk) =>
  assert.throws(thunk, (error) => {
    assert.ok(error instanceof Rejection, `expected a Rejection, got ${error}`);
    assert.equal(error.code, "invalid-config", error.message);
    return true;
  });

test("an activity without self-checks selects none", () => {
  assert.equal(run({}).selected["self-checks"], undefined);
});

test("self-checks pass through apart from checks", () => {
  const { selected } = run({
    checks: ["scripts/check-changelog-fragments.sh --check"],
    "self-checks": ["scripts/check-affected.sh --uncommitted"],
  });
  assert.deepEqual(selected.checks, ["scripts/check-changelog-fragments.sh --check"]);
  assert.deepEqual(selected["self-checks"], ["scripts/check-affected.sh --uncommitted"]);
});

for (const entry of ["scripts/x.sh; rm -rf /", "../scripts/x.sh", "scripts/x.sh --x=1", "plugins/a/scripts/x.sh"]) {
  test(`self-check ${JSON.stringify(entry)} fails the schema`, () => {
    rejected(() => run({ "self-checks": [entry] }));
  });
}

// Only the runner that stages edit tools stages them, so a read skill that
// hands on no patch would list them for nothing.
test("self-checks with effect read and no applied-by.patch fail the schema", () => {
  rejected(() => run({ effect: "read", "self-checks": ["scripts/check-x.sh"] }));
});

test("an empty or repeating self-checks list fails the schema", () => {
  rejected(() => run({ "self-checks": [] }));
  rejected(() => run({ "self-checks": ["scripts/check-x.sh", "scripts/check-x.sh"] }));
});

test("self-checks on a script activity fail the schema", () => {
  const doc = parse(read("./fixtures/valid.yaml"));
  doc.activities["run-tests"]["self-checks"] = ["scripts/check-x.sh"];
  rejected(() =>
    resolveDoc(doc, {
      lane: "pr-run-checks",
      facts: { event: "synchronize", changedPaths: ["src/app.js"], labels: [], workClasses: [] },
    }),
  );
});
