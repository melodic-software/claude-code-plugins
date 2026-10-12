import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse, stringify } from "yaml";

import { Rejection, resolve } from "./resolve.mjs";

const read = (relative) =>
  readFileSync(new URL(relative, import.meta.url), "utf8");
const json = (relative) => JSON.parse(read(relative));
const CONFIG_PATH = "docs/conventions/pr-pipeline.yaml";
const TRUSTED_ACTORS = ".github/standards/trusted-actors/trusted-actors.json";
const IDENTITY = "example-lanes[bot]";

const run = (config) =>
  resolve(
    {
      config,
      schema: json("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json"),
      vocabulary: json("./fixtures/vocabulary.json"),
      laneRules: json("./lane-rules.json"),
      effectGrants: json("./effect-grants.json"),
      activityRules: json("./activity-rules.json"),
    },
    {
      lane: "pr-run-checks",
      configPath: CONFIG_PATH,
      basePath: ".base",
      facts: {
        event: "synchronize",
        changedPaths: ["src/app.js"],
        labels: [],
        workClasses: [],
      },
    },
  );
const withMerge = (merge) => {
  const doc = parse(read("./fixtures/valid.yaml"));
  doc.merge = merge;
  return stringify(doc);
};
const rejectedFor = (config, pattern) =>
  assert.throws(
    () => run(config),
    (error) => {
      assert.ok(error instanceof Rejection, `expected a Rejection, got ${error}`);
      assert.equal(error.code, "invalid-config", error.message);
      assert.match(error.message, pattern);
      return true;
    },
  );

// The merge section valid.yaml resolves to: no merge section, so rung off,
// manual landing, and only the forced denied paths.
const VALID_MERGE = {
  rung: "off",
  "diff-check": { "denied-paths": [CONFIG_PATH, ".github/**", TRUSTED_ACTORS] },
  "stack-landing": "manual",
};

test("authority local-babysit without agent-identity fails the schema on the missing identity", () => {
  rejectedFor(
    withMerge({ authority: "local-babysit" }),
    /must have required property 'agent-identity'/,
  );
});

test("authority local-babysit with agent-identity validates", () => {
  assert.doesNotThrow(() =>
    run(withMerge({ authority: "local-babysit", "agent-identity": IDENTITY })),
  );
});

test("authority pr-merge needs no agent-identity", () => {
  assert.doesNotThrow(() => run(withMerge({ authority: "pr-merge" })));
});

test("an authority outside local-babysit and pr-merge fails the schema", () => {
  rejectedFor(
    withMerge({ authority: "babysit", "agent-identity": IDENTITY }),
    /\/merge\/authority must be equal to one of the allowed values/,
  );
});

test("an agent-identity that is not a GitHub login fails the schema", () => {
  rejectedFor(
    withMerge({ authority: "local-babysit", "agent-identity": "lanes bot" }),
    /\/merge\/agent-identity must match pattern/,
  );
});

test("resolveMerge output for valid.yaml is unchanged", () => {
  assert.deepEqual(run(read("./fixtures/valid.yaml")).merge, VALID_MERGE);
});

test("resolveMerge does not carry authority or agent-identity into the output", () => {
  assert.deepEqual(
    run(withMerge({ authority: "local-babysit", "agent-identity": IDENTITY }))
      .merge,
    VALID_MERGE,
  );
});
