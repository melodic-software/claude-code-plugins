import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { test } from "node:test";

import { parse, stringify } from "yaml";

import {
  checkConfigPath,
  neededFacts,
  Rejection,
  resolve,
  resolveGrant,
} from "./resolve.mjs";

const read = (relative) =>
  readFileSync(new URL(relative, import.meta.url), "utf8");
const fixture = (name) => read(`./fixtures/${name}`);
const SCHEMA = JSON.parse(
  read("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json"),
);
const EXAMPLE = read(
  "../../../docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml",
);
const LIVE_VOCABULARY = new URL(
  "../../standards/github-actions-conventions/vocabulary.json",
  import.meta.url,
);
const VOCABULARY = JSON.parse(fixture("vocabulary.json"));
const LANE_RULES = JSON.parse(read("./lane-rules.json"));
const EFFECT_GRANTS = JSON.parse(read("./effect-grants.json"));
const CONFIG_PATH = "docs/conventions/pr-pipeline.yaml";
const FACTS = {
  event: "synchronize",
  changedPaths: ["src/app.js"],
  labels: [],
  workClasses: [],
};

const files = (config, overrides = {}) => ({
  config,
  schema: SCHEMA,
  vocabulary: VOCABULARY,
  laneRules: LANE_RULES,
  effectGrants: EFFECT_GRANTS,
  ...overrides,
});
const run = (config, options = {}, overrides = {}) =>
  resolve(files(config, overrides), {
    lane: "pr-run-checks",
    configPath: CONFIG_PATH,
    basePath: ".base",
    facts: FACTS,
    ...options,
  });
const assertRejected = (fn, code) =>
  assert.throws(fn, (error) => {
    assert.ok(error instanceof Rejection, `expected a Rejection, got ${error}`);
    assert.equal(error.code, code, error.message);
    return true;
  });
// valid.yaml with an edit applied to its parsed form.
const edited = (edit) => {
  const doc = parse(fixture("valid.yaml"));
  edit(doc);
  return stringify(doc);
};

// Rejection 1

test("rejection 1: a schema-invalid config is rejected", () => {
  assertRejected(() => run(fixture("schema-invalid.yaml")), "invalid-config");
});

test("rejection 1: no file at the config path is rejected", () => {
  assertRejected(() => run(undefined), "invalid-config");
});

test("rejection 1: unparsable YAML and duplicate keys are rejected", () => {
  assertRejected(() => run("version: [1\n"), "invalid-config");
  assertRejected(
    () => run(`${fixture("valid.yaml")}version: 1\n`),
    "invalid-config",
  );
});

test("rejection 1: a YAML alias is rejected rather than expanded", () => {
  const withInputs = (first, second) =>
    fixture("valid.yaml")
      .replace("    effect: read\n", `    effect: read\n    inputs: ${first}\n`)
      .replace(
        "    effect: mutate-branch\n",
        `    effect: mutate-branch\n    inputs: ${second}\n`,
      );
  assert.deepEqual(
    run(withInputs("[head-sha]", "[head-sha]"), { activity: "run-tests" })
      .selected.inputs,
    ["head-sha"],
  );
  assertRejected(
    () => run(withInputs("&shared [head-sha]", "*shared")),
    "invalid-config",
  );
});

// Rejection 2

test("rejection 2: extends with a value is rejected", () => {
  assertRejected(() => run(fixture("extends.yaml")), "extends");
});

test("rejection 2: extends is rejected whatever its value, even one the schema refuses", () => {
  for (const value of ['""', "null", "[a]", "{}"]) {
    assertRejected(
      () => run(`extends: ${value}\n${fixture("valid.yaml")}`),
      "extends",
    );
  }
});

// Rejection 3

test("rejection 3: an effect the lane forbids is rejected (mutate-branch in pr-run-checks)", () => {
  assertRejected(
    () => run(fixture("forbidden-effect.yaml")),
    "forbidden-by-lane",
  );
});

test("rejection 3: a gate activity in pr-explain is rejected", () => {
  assertRejected(
    () => run(fixture("forbidden-gating.yaml"), { lane: "pr-explain" }),
    "forbidden-by-lane",
  );
});

test("rejection 3: a merge effect outside pr-merge is rejected in a lane the run did not ask for", () => {
  const config = edited((doc) => {
    doc.activities["fix-docs"].effect = "merge";
  });
  assertRejected(() => run(config), "forbidden-by-lane");
});

// Rejection 4

test("rejection 4: a lane whose stage differs from lane-rules.json is rejected", () => {
  assertRejected(() => run(fixture("stage-mismatch.yaml")), "lane-stage");
});

test("rejection 4: a lane with no lane-rules.json row is rejected", () => {
  assertRejected(
    () => run(fixture("unknown-lane.yaml"), { lane: "pr-review-docs" }),
    "lane-stage",
  );
});

// Rejection 5

test("rejection 5: a needs entry naming an activity outside the lane is rejected", () => {
  assertRejected(
    () => run(fixture("needs-outside-lane.yaml")),
    "needs-outside-lane",
  );
});

// Rejection 6

test("rejection 6: an activity name the vocabulary refuses is rejected", () => {
  assertRejected(
    () => run(fixture("activity-not-in-vocabulary.yaml")),
    "vocabulary",
  );
});

test("rejection 6: a lane name the vocabulary lacks is rejected", () => {
  const vocabulary = structuredClone(VOCABULARY);
  vocabulary.functions.pr = vocabulary.functions.pr.filter(
    (entry) => entry.name !== "refine",
  );
  assertRejected(
    () => run(fixture("valid.yaml"), {}, { vocabulary }),
    "vocabulary",
  );
});

test("rejection 6: a missing or malformed vocabulary is rejected", () => {
  assertRejected(
    () => run(fixture("valid.yaml"), {}, { vocabulary: undefined }),
    "vocabulary",
  );
  assertRejected(
    () => run(fixture("valid.yaml"), {}, { vocabulary: { stages: [] } }),
    "vocabulary",
  );
});

// Rejection 7

test("rejection 7: a slot naming an undefined activity is rejected", () => {
  assertRejected(
    () => run(fixture("undefined-activity.yaml")),
    "undefined-activity",
  );
});

test("rejection 7: a requested lane the config lacks is rejected", () => {
  assertRejected(
    () => run(fixture("valid.yaml"), { lane: "pr-review" }),
    "undefined-lane",
  );
  assertRejected(
    () => run(fixture("valid.yaml"), { lane: "__proto__" }),
    "undefined-lane",
  );
});

test("rejection 7: a requested activity the lane has no slot for is rejected", () => {
  assertRejected(
    () => run(fixture("valid.yaml"), { activity: "fix-docs" }),
    "undefined-activity",
  );
});

test("rejection 7: an activity in two slots of the requested lane cannot be selected", () => {
  const config = edited((doc) => {
    doc.lanes["pr-run-checks"].slots.push({ activity: "run-tests" });
  });
  assertRejected(
    () => run(config, { activity: "run-tests" }),
    "undefined-activity",
  );
});

// Rejection 8

test("rejection 8: an absolute config-path is rejected", () => {
  assertRejected(() => checkConfigPath("/etc/pr-pipeline.yaml"), "config-path");
  assertRejected(
    () => run(fixture("valid.yaml"), { configPath: "/docs/pr-pipeline.yaml" }),
    "config-path",
  );
});

test("rejection 8: a config-path with .. is rejected", () => {
  assertRejected(() => checkConfigPath("../pr-pipeline.yaml"), "config-path");
  assertRejected(
    () => checkConfigPath("docs/../../pr-pipeline.yaml"),
    "config-path",
  );
});

test("rejection 8: a config-path whose basename is not pr-pipeline.yaml is rejected", () => {
  assertRejected(
    () => checkConfigPath("docs/conventions/grants.yaml"),
    "config-path",
  );
  assertRejected(
    () => checkConfigPath("docs/conventions/pr-pipeline.yml"),
    "config-path",
  );
  assertRejected(() => checkConfigPath(""), "config-path");
});

test("rejection 8: a config-path under .github/actions is rejected", () => {
  assertRejected(
    () =>
      checkConfigPath(
        ".github/actions/resolve-config/fixtures/pr-pipeline.yaml",
      ),
    "config-path",
  );
  assertRejected(
    () => checkConfigPath("./.github//actions/x/pr-pipeline.yaml"),
    "config-path",
  );
});

test("rejection 8: a relative config-path named pr-pipeline.yaml elsewhere is accepted", () => {
  assert.equal(checkConfigPath("tests/invalid/pr-pipeline.yaml"), undefined);
  assert.equal(checkConfigPath(CONFIG_PATH), undefined);
});

// Rejection 9

test("rejection 9: an activity named run is rejected", () => {
  assertRejected(() => run(fixture("reserved-run.yaml")), "reserved-name");
});

test("rejection 9: an activity named report is rejected", () => {
  assertRejected(() => run(fixture("reserved-report.yaml")), "reserved-name");
});

// Forced denied paths

const TRUSTED_ACTORS = ".github/standards/trusted-actors/trusted-actors.json";

test("forced denied paths are added when the config sets no merge section", () => {
  assert.deepEqual(
    run(fixture("valid.yaml")).merge["diff-check"]["denied-paths"],
    [CONFIG_PATH, ".github/**", TRUSTED_ACTORS],
  );
});

test("forced denied paths are added after the config's own, once each", () => {
  const config = edited((doc) => {
    doc.merge = {
      rung: "C2",
      "diff-check": {
        "denied-paths": [".claude/**", ".github/**"],
        "max-changed-lines": 400,
      },
    };
  });
  const resolved = run(config);
  assert.deepEqual(resolved.merge["diff-check"], {
    "denied-paths": [".claude/**", ".github/**", CONFIG_PATH, TRUSTED_ACTORS],
    "max-changed-lines": 400,
  });
});

test("the denied config path is the one the run read", () => {
  const configPath = "tests/invalid/pr-pipeline.yaml";
  assert.ok(
    run(fixture("valid.yaml"), { configPath }).merge["diff-check"][
      "denied-paths"
    ].includes(configPath),
  );
});

// Defaults

test("defaults are materialized: loop 2/3, merge off and manual, slot scope diff and enabled", () => {
  const resolved = run(fixture("valid.yaml"), { activity: "run-tests" });
  assert.deepEqual(resolved.loop, { "review-rounds": 2, "no-progress": 3 });
  assert.equal(resolved.merge.rung, "off");
  assert.equal(resolved.merge["stack-landing"], "manual");
  assert.equal(resolved.version, 1);
  assert.deepEqual(resolved.source, {
    "base-path": ".base",
    "config-path": CONFIG_PATH,
  });
  assert.deepEqual(resolved.lane, {
    ...resolved.lane,
    name: "pr-run-checks",
    stage: "verify",
    enabled: true,
  });
  assert.deepEqual(resolved.selected, {
    name: "run-tests",
    kind: "script",
    script: "scripts/run-tests.sh",
    effect: "read",
    gating: "gate",
    "reads-untrusted": false,
    scope: "diff",
    inputs: [],
    needs: [],
    enabled: true,
    model: null,
    "max-turns": null,
    grant: { contents: "read", "pull-requests": "read", issues: "read" },
    applies: true,
    "skip-reason": null,
  });
});

test("a skill slot carries its skill, args, needs and predicate", () => {
  const selected = run(fixture("valid.yaml"), {
    activity: "measure-coverage",
  }).selected;
  assert.equal(selected.kind, "skill");
  assert.equal(selected.skill, "code-metrics:audit-coverage");
  assert.equal(selected.args, "--diff");
  assert.deepEqual(selected.needs, ["run-tests"]);
  assert.deepEqual(selected["applies-when"], { paths: ["src/**"] });
});

test("without an activity, selected is null and every lane slot is resolved", () => {
  const resolved = run(fixture("valid.yaml"));
  assert.equal(resolved.selected, null);
  assert.deepEqual(
    resolved.lane.slots.map((slot) => slot.name),
    ["run-tests", "measure-coverage"],
  );
});

test("a slot's applies-when replaces its activity's", () => {
  const config = edited((doc) => {
    doc.lanes["pr-run-checks"].slots[1]["applies-when"] = {
      paths: ["docs/**"],
    };
  });
  const selected = run(config, { activity: "measure-coverage" }).selected;
  assert.deepEqual(selected["applies-when"], { paths: ["docs/**"] });
  assert.equal(selected["skip-reason"], "not-applicable-paths");
});

// Skip reasons

test("enabled false on the lane skips every slot with disabled-by-config", () => {
  const config = edited((doc) => {
    doc.lanes["pr-run-checks"].enabled = false;
  });
  const resolved = run(config);
  assert.equal(resolved.lane.enabled, false);
  for (const slot of resolved.lane.slots) {
    assert.equal(slot.applies, false);
    assert.equal(slot["skip-reason"], "disabled-by-config");
  }
});

test("enabled false on a slot skips that slot only with disabled-by-config", () => {
  const config = edited((doc) => {
    doc.lanes["pr-run-checks"].slots[0].enabled = false;
  });
  const [first, second] = run(config).lane.slots;
  assert.deepEqual(
    [first.enabled, first.applies, first["skip-reason"]],
    [false, false, "disabled-by-config"],
  );
  assert.deepEqual([second.applies, second["skip-reason"]], [true, null]);
});

test("a paths miss gives not-applicable-paths", () => {
  const selected = run(fixture("valid.yaml"), {
    activity: "measure-coverage",
    facts: { ...FACTS, changedPaths: ["docs/guide.md"] },
  }).selected;
  assert.deepEqual(
    [selected.applies, selected["skip-reason"]],
    [false, "not-applicable-paths"],
  );
});

test("a label, event or work-class miss gives not-applicable", () => {
  for (const predicate of [
    { labels: ["security"] },
    { events: ["push"] },
    { "work-classes": ["C3"] },
  ]) {
    const config = edited((doc) => {
      doc.activities["run-tests"]["applies-when"] = predicate;
    });
    const selected = run(config, { activity: "run-tests" }).selected;
    assert.deepEqual(
      [selected.applies, selected["skip-reason"]],
      [false, "not-applicable"],
      JSON.stringify(predicate),
    );
  }
});

test("neededFacts names only what enabled slots of the lane read", () => {
  assert.deepEqual(
    neededFacts(files(fixture("valid.yaml")), {
      lane: "pr-run-checks",
      configPath: CONFIG_PATH,
    }),
    ["changedPaths"],
  );
  const disabled = edited((doc) => {
    doc.lanes["pr-run-checks"].slots[1].enabled = false;
  });
  assert.deepEqual(
    neededFacts(files(disabled), {
      lane: "pr-run-checks",
      configPath: CONFIG_PATH,
    }),
    [],
  );
});

test("with an activity, neededFacts names only what the selected slot reads", () => {
  const request = { lane: "pr-run-checks", configPath: CONFIG_PATH };
  assert.deepEqual(
    neededFacts(files(fixture("valid.yaml")), {
      ...request,
      activity: "run-tests",
    }),
    [],
  );
  assert.deepEqual(
    neededFacts(files(fixture("valid.yaml")), {
      ...request,
      activity: "measure-coverage",
    }),
    ["changedPaths"],
  );
});

test("with an activity, another slot's undecidable predicate leaves that slot undecided", () => {
  const config = edited((doc) => {
    doc.activities["measure-coverage"]["applies-when"] = {
      "work-classes": ["C1"],
    };
  });
  const facts = { ...FACTS };
  delete facts.workClasses;
  const resolved = run(config, { activity: "run-tests", facts });
  assert.deepEqual(
    [resolved.selected.applies, resolved.selected["skip-reason"]],
    [true, null],
  );
  const other = resolved.lane.slots[1];
  assert.deepEqual([other.applies, other["skip-reason"]], [null, null]);
  assert.throws(
    () => run(config, { activity: "measure-coverage", facts }),
    /work/i,
  );
});

// Effect grants (contract-spec.md EffectGrant)

test("each effect resolves to its App grant", () => {
  const expected = {
    read: { contents: "read", "pull-requests": "read", issues: "read" },
    "publish-artifact": {
      contents: "read",
      "pull-requests": "write",
      issues: "write",
    },
    "mutate-tracker": {
      contents: "read",
      "pull-requests": "read",
      issues: "write",
    },
    "mutate-branch": {
      contents: "write",
      "pull-requests": "write",
      issues: "write",
    },
    merge: { contents: "write", "pull-requests": "write", issues: "write" },
  };
  for (const [effect, grant] of Object.entries(expected)) {
    const config = `version: 1
activities:
  merge:
    script: scripts/merge.sh
    effect: ${effect}
    gating: advisory
    reads-untrusted: false
lanes:
  pr-merge:
    stage: merge
    slots:
      - activity: merge
`;
    assert.deepEqual(
      run(config, { lane: "pr-merge", activity: "merge" }).selected.grant,
      grant,
      effect,
    );
  }
});

test("an effect with no grant row fails rather than mint an empty grant", () => {
  const effectGrants = { ...EFFECT_GRANTS };
  delete effectGrants.read;
  assertRejected(
    () =>
      run(fixture("valid.yaml"), { activity: "run-tests" }, { effectGrants }),
    "effect-grant",
  );
});

// resolveGrant: the token broker's entry point, which decides no predicate

const grantOf = (config, options = {}, overrides = {}) =>
  resolveGrant(files(config, overrides), {
    lane: "pr-run-checks",
    configPath: CONFIG_PATH,
    ...options,
  });
const READ_GRANT = { contents: "read", "pull-requests": "read", issues: "read" };

test("resolveGrant returns the selected slot's effect and grant", () => {
  assert.deepEqual(grantOf(fixture("valid.yaml"), { activity: "run-tests" }), {
    effect: "read",
    grant: READ_GRANT,
  });
  assert.deepEqual(
    grantOf(fixture("valid.yaml"), { lane: "pr-refine", activity: "fix-docs" }),
    {
      effect: "mutate-branch",
      grant: { contents: "write", "pull-requests": "write", issues: "write" },
    },
  );
});

test("resolveGrant resolves a slot whose applies-when needs the event fact, with no facts", () => {
  const config = edited((doc) => {
    doc.activities["run-tests"]["applies-when"] = { events: ["ready"] };
  });
  assert.deepEqual(grantOf(config, { activity: "run-tests" }), {
    effect: "read",
    grant: READ_GRANT,
  });
});

test("resolveGrant rejects a disabled slot or lane", () => {
  const slotOff = edited((doc) => {
    doc.lanes["pr-run-checks"].slots[0].enabled = false;
  });
  assertRejected(
    () => grantOf(slotOff, { activity: "run-tests" }),
    "slot-disabled",
  );
  assert.deepEqual(grantOf(slotOff, { activity: "measure-coverage" }), {
    effect: "read",
    grant: READ_GRANT,
  });
  const laneOff = edited((doc) => {
    doc.lanes["pr-run-checks"].enabled = false;
  });
  assertRejected(
    () => grantOf(laneOff, { activity: "measure-coverage" }),
    "slot-disabled",
  );
});

test("resolveGrant rejects an unknown lane", () => {
  assertRejected(
    () => grantOf(fixture("valid.yaml"), { lane: "pr-review", activity: "run-tests" }),
    "undefined-lane",
  );
});

test("resolveGrant rejects an activity outside the lane, or none", () => {
  assertRejected(
    () => grantOf(fixture("valid.yaml"), { activity: "fix-docs" }),
    "undefined-activity",
  );
  for (const activity of [undefined, ""]) {
    assertRejected(
      () => grantOf(fixture("valid.yaml"), { activity }),
      "undefined-activity",
    );
  }
});

test("resolveGrant rejects a lane-forbidden effect", () => {
  assertRejected(
    () => grantOf(fixture("forbidden-effect.yaml"), { activity: "fix-tests" }),
    "forbidden-by-lane",
  );
});

test("resolveGrant rejects a lane with no lane-rules.json row", () => {
  assertRejected(
    () =>
      grantOf(fixture("unknown-lane.yaml"), {
        lane: "pr-review-docs",
        activity: "run-tests",
      }),
    "lane-stage",
  );
});

test("resolveGrant rejects an effect with no grant row", () => {
  const effectGrants = { ...EFFECT_GRANTS };
  delete effectGrants.read;
  assertRejected(
    () =>
      grantOf(fixture("valid.yaml"), { activity: "run-tests" }, { effectGrants }),
    "effect-grant",
  );
});

test("a grant row that is not exactly three read or write scopes is rejected", () => {
  const rows = [
    null,
    {},
    { ...READ_GRANT, administration: "write" },
    { ...READ_GRANT, contents: "admin" },
    { contents: "read", "pull-requests": "read" },
    ["read", "read", "read"],
  ];
  for (const row of rows) {
    const effectGrants = { ...EFFECT_GRANTS, read: row };
    assertRejected(
      () =>
        grantOf(
          fixture("valid.yaml"),
          { activity: "run-tests" },
          { effectGrants },
        ),
      "effect-grant",
    );
    assertRejected(
      () =>
        run(fixture("valid.yaml"), { activity: "run-tests" }, { effectGrants }),
      "effect-grant",
    );
  }
});

test("a resolved grant is frozen and leaves effect-grants.json untouched", () => {
  const { grant } = grantOf(fixture("valid.yaml"), { activity: "run-tests" });
  assert.throws(() => {
    grant.contents = "write";
  }, TypeError);
  assert.deepEqual(EFFECT_GRANTS.read, READ_GRANT);
  const { selected } = run(fixture("valid.yaml"), { activity: "run-tests" });
  assert.ok(Object.isFrozen(selected.grant));
});

test("a non-string effect is rejected even when the schema lets it through", () => {
  const schema = structuredClone(SCHEMA);
  schema.$defs.activity.properties.effect = {};
  const config = edited((doc) => {
    doc.activities["run-tests"].effect = ["mutate-branch"];
  });
  assertRejected(
    () => grantOf(config, { activity: "run-tests" }, { schema }),
    "invalid-config",
  );
  assertRejected(
    () => run(config, { activity: "run-tests" }, { schema }),
    "invalid-config",
  );
});

test("resolveGrant rejects a non-string lane or activity", () => {
  assertRejected(
    () =>
      grantOf(fixture("valid.yaml"), {
        lane: ["pr-run-checks"],
        activity: "run-tests",
      }),
    "undefined-lane",
  );
  assertRejected(
    () => grantOf(fixture("valid.yaml"), { activity: ["run-tests"] }),
    "undefined-activity",
  );
});

// The README example

const EXAMPLE_FACTS = {
  event: "synchronize",
  changedPaths: ["README.md"],
  labels: [],
  workClasses: [],
};

function resolveEveryExampleSlot(vocabulary) {
  const results = {};
  for (const [lane, section] of Object.entries(parse(EXAMPLE).lanes)) {
    for (const slot of section.slots) {
      results[`${lane} / ${slot.activity}`] = run(
        EXAMPLE,
        { lane, activity: slot.activity, facts: EXAMPLE_FACTS },
        { vocabulary },
      ).selected;
    }
  }
  return results;
}

test("the README example validates and resolves for each of its lanes", () => {
  const results = resolveEveryExampleSlot(VOCABULARY);
  assert.equal(Object.keys(results).length, 15);
  assert.deepEqual(
    [
      results["pr-review / claude"].model,
      results["pr-review / claude"]["max-turns"],
    ],
    ["opus", 100],
  );
  assert.equal(results["pr-refine / fix-docs"].applies, true);
  assert.equal(results["pr-update / update"]["skip-reason"], "not-applicable");
  assert.equal(
    results["post-merge-sweep-comments / sweep-comments"]["skip-reason"],
    "disabled-by-config",
  );
  assert.equal(results["pr-merge / merge"].grant.contents, "write");
});

test("integration: the README example resolves against the synced standards vocabulary", {
  skip: existsSync(LIVE_VOCABULARY)
    ? false
    : "the synced .github/standards/github-actions-conventions/vocabulary.json is absent until the standards sync lands",
}, () => {
  const results = resolveEveryExampleSlot(
    JSON.parse(readFileSync(LIVE_VOCABULARY, "utf8")),
  );
  assert.equal(Object.keys(results).length, 15);
});
