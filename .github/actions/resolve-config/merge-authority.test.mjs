import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse, stringify } from "yaml";

import { Rejection, resolve } from "./resolve.mjs";
import { FORCED_DENIED_PATHS } from "../../scripts/pr-merge/merge-holds.mjs";

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
// manual landing, lane pull requests on native auto-merge, and only the
// forced denied paths.
const VALID_MERGE = {
  rung: "off",
  "diff-check": { "denied-paths": [CONFIG_PATH, TRUSTED_ACTORS] },
  "stack-landing": "manual",
  "lane-prs": "native",
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

for (const login of ["lanes bot[bot]", "-lanes[bot]"]) {
  test(`an agent-identity with the [bot] suffix but an invalid login (${login}) fails the schema`, () => {
    rejectedFor(
      withMerge({ authority: "local-babysit", "agent-identity": login }),
      /\/merge\/agent-identity must match pattern/,
    );
  });
}

for (const login of [
  "github-actions[bot]",
  "dependabot[bot]",
  "GitHub-Actions[bot]",
  "Dependabot[bot]",
]) {
  test(`GitHub's shared built-in bot ${login} is rejected as agent-identity`, () => {
    rejectedFor(
      withMerge({ authority: "local-babysit", "agent-identity": login }),
      /\/merge\/agent-identity must NOT be valid/,
    );
  });
}

test("rung C2 with a valid diff-check and no authority still validates (absent authority means pr-merge)", () => {
  assert.doesNotThrow(() =>
    run(
      withMerge({
        rung: "C2",
        "diff-check": { "denied-paths": [".claude/**"], "max-changed-lines": 200 },
      }),
    ),
  );
});

// Merge-criterion plan, Design 3: the enabled pr-merge lane reads no class,
// so the verifier verdict must be required.
const LANE = {
  rung: "C2",
  "agent-identity": IDENTITY,
  "diff-check": { "denied-paths": [".claude/**"], "max-changed-lines": 200 },
};

test("an enabled pr-merge lane above off without a required verdict fails the schema", () => {
  for (const merge of [
    LANE,
    { ...LANE, authority: "pr-merge" },
    { ...LANE, "require-verifier-verdict": false },
    { ...LANE, rung: "C3", "require-verifier-verdict": false },
  ]) {
    rejectedFor(withMerge(merge), /require-verifier-verdict/);
  }
});

test("an enabled pr-merge lane with a required verdict, or at rung off, validates", () => {
  assert.doesNotThrow(() => run(withMerge({ ...LANE, "require-verifier-verdict": true })));
  assert.doesNotThrow(() => run(withMerge({ ...LANE, rung: "off" })));
  assert.doesNotThrow(() =>
    run(withMerge({ ...LANE, authority: "local-babysit" })),
  );
});

// Owner decision Q624: the pr-merge lane needs no denied path or size cap;
// each check is a diff-check setting.
test("a pr-merge rung C2 with no diff-check, or an empty one, validates", () => {
  assert.doesNotThrow(() => run(withMerge({ rung: "C2" })));
  assert.doesNotThrow(() =>
    run(withMerge({ ...LANE, "require-verifier-verdict": true, "diff-check": { "denied-paths": [] } })),
  );
  assert.doesNotThrow(() =>
    run(
      withMerge({
        ...LANE,
        "require-verifier-verdict": true,
        "diff-check": {
          "denied-paths": [".github/**"],
          "max-changed-lines": 400,
          "max-changed-files": 8,
          "high-path-floor": true,
          "c2-contradictions": true,
        },
      }),
    ),
  );
  rejectedFor(withMerge({ ...LANE, "diff-check": { "high-path-floor": "yes" } }), /high-path-floor/);
});

test("a local-babysit rung C2 still needs denied paths and a line cap", () => {
  const local = { rung: "C2", authority: "local-babysit", "agent-identity": IDENTITY };
  rejectedFor(withMerge({ ...local, "diff-check": { "denied-paths": [] } }), /max-changed-lines/);
  rejectedFor(
    withMerge({ ...local, "diff-check": { "denied-paths": [], "max-changed-lines": 200 } }),
    /denied-paths/,
  );
});

test("rung C2 with authority local-babysit and an identity but no diff-check fails the schema", () => {
  rejectedFor(
    withMerge({
      rung: "C2",
      authority: "local-babysit",
      "agent-identity": IDENTITY,
    }),
    /required property 'diff-check'/,
  );
});

test("rung C2 with authority local-babysit fails on both the missing diff-check and the missing identity", () => {
  rejectedFor(
    withMerge({ rung: "C2", authority: "local-babysit" }),
    /required property 'diff-check'.*required property 'agent-identity'|required property 'agent-identity'.*required property 'diff-check'/,
  );
});

test("an agent-identity without the [bot] suffix fails the schema: it must be a GitHub App", () => {
  rejectedFor(
    withMerge({ authority: "local-babysit", "agent-identity": "some-user" }),
    /\/merge\/agent-identity must match pattern/,
  );
});

test("a GitHub App [bot] login validates as agent-identity", () => {
  assert.doesNotThrow(() =>
    run(withMerge({ authority: "local-babysit", "agent-identity": "my-app[bot]" })),
  );
});

test("resolveMerge output for valid.yaml is unchanged", () => {
  assert.deepEqual(run(read("./fixtures/valid.yaml")).merge, VALID_MERGE);
});

// ci-status adds this floor to the base config's denied paths itself.
test("merge-holds.mjs's FORCED_DENIED_PATHS are the denied paths resolveMerge forces", () => {
  assert.deepEqual(
    [...run(read("./fixtures/valid.yaml")).merge["diff-check"]["denied-paths"]].sort(),
    [...FORCED_DENIED_PATHS].sort(),
  );
});

test("resolveMerge does not carry authority or agent-identity into the output", () => {
  assert.deepEqual(
    run(withMerge({ authority: "local-babysit", "agent-identity": IDENTITY }))
      .merge,
    VALID_MERGE,
  );
});

test("merge.dependabot.mode takes off, report or enforce", () => {
  for (const mode of ["off", "report", "enforce"]) {
    assert.doesNotThrow(() => run(withMerge({ dependabot: { mode } })), mode);
  }
});

test("any other merge.dependabot.mode or key fails the schema", () => {
  rejectedFor(
    withMerge({ dependabot: { mode: "on" } }),
    /must be equal to one of the allowed values/,
  );
  rejectedFor(
    withMerge({ dependabot: { mode: "enforce", majors: true } }),
    /must be equal to one of the allowed values/,
  );
  rejectedFor(
    withMerge({ dependabot: { mode: "enforce", other: true } }),
    /must NOT have additional properties/,
  );
});

test("merge.lane-prs takes native or gate, and the schema's default is the resolver's", () => {
  for (const mode of ["native", "gate"]) {
    assert.equal(run(withMerge({ "lane-prs": mode })).merge["lane-prs"], mode);
  }
  rejectedFor(withMerge({ "lane-prs": "off" }), /must be equal to one of the allowed values/);
  const schema = json("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json");
  assert.equal(schema.$defs.merge.properties["lane-prs"].default, run(withMerge({})).merge["lane-prs"]);
});

test("merge.dependabot.majors takes hold or review", () => {
  for (const majors of ["hold", "review"]) {
    assert.doesNotThrow(() => run(withMerge({ dependabot: { mode: "enforce", majors } })), majors);
  }
});
