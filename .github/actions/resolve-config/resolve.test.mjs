import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { test } from "node:test";

import { parse, stringify } from "yaml";

import { WIP_DEFAULTS, resolveWip } from "../../scripts/work-resolve-issue/limits.mjs";

import {
  checkAppliedBySupported,
  checkConfigPath,
  neededFacts,
  Rejection,
  resolve,
  resolveGrant,
} from "./resolve.mjs";
import { checkPatchRules } from "./patch-rules.mjs";

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
const ACTIVITY_RULES = JSON.parse(read("./activity-rules.json"));
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
  activityRules: ACTIVITY_RULES,
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
    () => run(`${fixture("valid.yaml")}version: 2\n`),
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
    doc.activities["fix-prose"].effect = "merge";
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
    () => run(fixture("valid.yaml"), { activity: "fix-prose" }),
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
    [CONFIG_PATH, TRUSTED_ACTORS],
  );
});

test("forced denied paths are added after the config's own, once each", () => {
  const config = edited((doc) => {
    doc.merge = {
      rung: "C2",
      "diff-check": {
        "denied-paths": [".claude/**", CONFIG_PATH],
        "max-changed-lines": 400,
      },
    };
  });
  const resolved = run(config);
  assert.deepEqual(resolved.merge["diff-check"], {
    "denied-paths": [".claude/**", CONFIG_PATH, TRUSTED_ACTORS],
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

// The values the lanes must keep with no limits leaf, as the request for the
// leaf states them: a 5-hour fallback reset, a 1-hour to 7-day clamp, 5
// restarts per sweep, 3 limit stops per head and per issue.
const LIMITS = {
  "fallback-reset": 5,
  "reset-clamp-min": 1,
  "reset-clamp-max": 168,
  "restarts-per-run": 5,
  "limit-stops-per-head": 3,
  "limit-stops-per-issue": 3,
  "wip-cap": 60,
  // The fix-ci defaults the owner chose (2026-10-18 interview).
  "fix-ci-per-run": 2,
  "fix-ci-restarts": 1,
  "fix-docs-per-run": 2,
  // The queued cap's pace the owner chose (2026-10-19).
  "admission-factor": 0.8,
  // The release-point floor the owner chose (2026-10-21 interview).
  "admission-min-per-hour": 1,
};

test("limits: a config with no limits leaf resolves today's twelve values", () => {
  assert.deepEqual(run(fixture("valid.yaml")).limits, LIMITS);
});

test("limits: a set leaf overrides its default and leaves the others", () => {
  const config = edited((doc) => {
    doc.limits = { "fallback-reset": 2, "limit-stops-per-issue": 4, "admission-factor": 0.5 };
  });
  assert.deepEqual(run(config).limits, { ...LIMITS, "fallback-reset": 2, "limit-stops-per-issue": 4, "admission-factor": 0.5 });
});

test("limits: an unknown key, a value that is not an integer, or one out of its range is rejected", () => {
  for (const limits of [{ "fallback-resets": 5 }, { "fallback-reset": 0 }, { "restarts-per-run": -1 }, { "reset-clamp-max": 1.5 }, { "limit-stops-per-head": "3" }, { "limit-stops-per-head": 11 }, { "limit-stops-per-issue": 11 }, { "restarts-per-run": 51 }, { "fallback-reset": 721 }, { "reset-clamp-max": 721 }, { "wip-cap": 0 }, { "wip-cap": 501 }, { "turn-cap-restarts": 1 }, { "fix-ci-per-run": 0 }, { "fix-ci-per-run": 21 }, { "fix-ci-restarts": -1 }, { "fix-ci-restarts": 6 }, { "fix-docs-per-run": 0 }, { "fix-docs-per-run": 21 }, { "admission-window-hours": 24 }, { "admission-factor": 0 }, { "admission-factor": 1.1 }, { "admission-min-per-hour": -1 }, { "admission-min-per-hour": 101 }]) {
    const config = edited((doc) => {
      doc.limits = limits;
    });
    assertRejected(() => run(config), "invalid-config");
  }
});

// The owner-set WIP values: a 2-hour target lead time over a 24-hour window,
// admissions at 0.8 of merges, a held buffer of 60 with a 24-hour alarm, and
// no pause date. The resolver passes the leaf through as set; its readers
// apply these defaults.
const WIP = {
  "target-lead-time-hours": 2,
  "min-cap": 1,
  "merge-rate-window-hours": 24,
  "opened-to-merged-ratio": 0.8,
  "held-cap": 60,
  "held-alarm-hours": 24,
  "pause-from": "",
};

test("wip: a config with no wip leaf resolves to the readers' defaults", () => {
  assert.deepEqual(run(fixture("valid.yaml")).wip, {});
  assert.deepEqual(resolveWip(run(fixture("valid.yaml")).wip), WIP);
});

test("wip: a set leaf overrides its default and leaves the others", () => {
  const set = { "held-cap": 30, "opened-to-merged-ratio": 0.5, "pause-from": "2026-11-01" };
  const config = edited((doc) => {
    doc.wip = set;
  });
  assert.deepEqual(run(config).wip, set);
  assert.deepEqual(resolveWip(run(config).wip), { ...WIP, ...set });
});

test("wip: an unknown key, a wrong type, or a value out of range is rejected", () => {
  for (const wip of [{ "held-caps": 30 }, { "target-lead-time-hours": 0 }, { "min-cap": 0 }, { "min-cap": 2.5 }, { "min-cap": 501 }, { "opened-to-merged-ratio": 1.5 }, { "opened-to-merged-ratio": 0 }, { "held-cap": 0 }, { "held-cap": 2.5 }, { "merge-rate-window-hours": 1.5 }, { "pause-from": "soon" }, { "pause-from": 20261101 }]) {
    const config = edited((doc) => {
      doc.wip = wip;
    });
    assertRejected(() => run(config), "invalid-config");
  }
});

test("wip: the schema's defaults are the readers' defaults", () => {
  const schema = JSON.parse(readFileSync(new URL("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json", import.meta.url), "utf8"));
  assert.deepEqual(Object.fromEntries(Object.entries(schema.properties.wip.properties).map(([key, value]) => [key, value.default])), WIP_DEFAULTS);
  assert.deepEqual(WIP_DEFAULTS, WIP);
});

test("defaults are materialized: loop 2/3/2/3, merge off, manual and native, slot scope diff and enabled", () => {
  const resolved = run(fixture("valid.yaml"), { activity: "run-tests" });
  assert.deepEqual(resolved.loop, { "review-rounds": 2, "no-progress": 3, "dependency-review-rounds": 2, "fix-ci-rounds": 3 });
  assert.equal(resolved.merge.rung, "off");
  assert.equal(resolved.merge["stack-landing"], "manual");
  assert.equal(resolved.merge["lane-prs"], "native");
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
    models: null,
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

// Owner rule (#7032 amendment): a token with contents: write and
// pull-requests: write can enqueue a pull request, so only merge holds both;
// the broker refuses any other such grant.
test("no effect but merge grants both contents: write and pull-requests: write", () => {
  const both = Object.entries(EFFECT_GRANTS)
    .filter(([, grant]) => grant.contents === "write" && grant["pull-requests"] === "write")
    .map(([effect]) => effect);
  assert.deepEqual(both, ["merge"]);
});

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
      "pull-requests": "read",
      issues: "read",
    },
    merge: { contents: "write", "pull-requests": "write", issues: "write" },
  };
  for (const [effect, grant] of Object.entries(expected)) {
    const config = `version: 2
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
    grantOf(fixture("valid.yaml"), { lane: "pr-refine", activity: "fix-prose" }),
    {
      effect: "mutate-branch",
      grant: { contents: "write", "pull-requests": "read", issues: "read" },
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
    () => grantOf(fixture("valid.yaml"), { activity: "fix-prose" }),
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

const withActivityGrants = (activityGrants, lane = "pr-run-checks") => ({
  laneRules: {
    ...LANE_RULES,
    [lane]: { ...LANE_RULES[lane], "activity-grants": activityGrants },
  },
});

test("a lane-rules.json activity grant adds actions read to that activity alone", () => {
  const overrides = withActivityGrants({ "run-tests": { actions: "read" } });
  const widened = { ...READ_GRANT, actions: "read" };
  assert.deepEqual(
    grantOf(fixture("valid.yaml"), { activity: "run-tests" }, overrides),
    { effect: "read", grant: widened },
  );
  assert.deepEqual(
    grantOf(fixture("valid.yaml"), { activity: "measure-coverage" }, overrides),
    { effect: "read", grant: READ_GRANT },
  );
  const { selected, lane } = run(fixture("valid.yaml"), { activity: "run-tests" }, overrides);
  assert.deepEqual(selected.grant, widened);
  assert.ok(Object.isFrozen(selected.grant));
  assert.deepEqual(lane.slots.find((slot) => slot.name === "measure-coverage").grant, READ_GRANT);
  assert.deepEqual(EFFECT_GRANTS.read, READ_GRANT);
});

test("an activity grant other than exactly actions read is rejected", () => {
  const grants = [
    null,
    [],
    "actions",
    { "run-tests": { actions: "write" } },
    { "run-tests": { contents: "write" } },
    { "run-tests": { actions: "read", contents: "write" } },
    { "run-tests": {} },
    { "run-tests": null },
    { "no-such-activity": { actions: "write" } },
  ];
  for (const activityGrants of grants) {
    const overrides = withActivityGrants(activityGrants);
    assertRejected(
      () => grantOf(fixture("valid.yaml"), { activity: "measure-coverage" }, overrides),
      "lane-grant",
    );
    assertRejected(
      () => run(fixture("valid.yaml"), { activity: "measure-coverage" }, overrides),
      "lane-grant",
    );
  }
});

test("an activity grant naming an activity the lane does not hold adds nothing", () => {
  const overrides = withActivityGrants({ "fix-prose": { actions: "read" }, constructor: { actions: "read" } });
  for (const activity of ["run-tests", "measure-coverage"]) {
    assert.deepEqual(
      grantOf(fixture("valid.yaml"), { activity }, overrides),
      { effect: "read", grant: READ_GRANT },
    );
  }
});

test("a non-string effect is rejected even when the schema lets it through", () => {
  const schema = structuredClone(SCHEMA);
  schema.$defs.leaf.properties.effect = {};
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

// The changed-paths input

const CODEOWNERS = `# owned and unowned entries
/plugins/ai-slop/** @owner
/docs/conventions/pr-pipeline/** @owner
/docs/unowned.md
`;

const withChangedPaths = (edit = () => {}) =>
  edited((doc) => {
    doc.activities["fix-prose"].inputs = ["changed-paths"];
    doc.activities["fix-prose"]["applies-when"] = { paths: ["**/*.md"] };
    edit(doc);
  });

const targetsOf = (changedTargets, config = withChangedPaths()) =>
  run(
    config,
    {
      lane: "pr-refine",
      activity: "fix-prose",
      facts: { ...FACTS, changedPaths: changedTargets, changedTargets },
    },
    { codeowners: CODEOWNERS },
  ).selected;

test("changed-paths asks a write activity to fix only changed markdown outside instruction surfaces and CODEOWNERS", () => {
  const selected = targetsOf([
    "docs/guide.md",
    "README.md",
    "src/app.js",
    "CLAUDE.md",
    "nested/AGENTS.md",
    "docs/Claude.md",
    ".claude/rules/style.md",
    "plugins/x/skills/y/SKILL.md",
    "plugins/x/skills/y/reference/guide.md",
    "plugins/x/agents/worker.md",
    "plugins/x/hooks/README.md",
    "plugins/ai-slop/README.md",
    "docs/conventions/pr-pipeline/README.md",
    "docs/unowned.md",
    "docs/guide.md",
  ]);
  assert.equal(selected.applies, true);
  assert.deepEqual(selected["changed-paths"], ["README.md", "docs/guide.md"]);
});

test("changed-paths drops a name that could read as an option, a mention, a glob or two words", () => {
  const selected = targetsOf([
    "@docs/x.md",
    "@x.md",
    "docs/@kept.md",
    "docs/two words.md",
    "docs/a,b.md",
    "docs/-rf.md",
    "-x.md",
    "docs/*.md",
    "docs/$(id).md",
    "docs/../x.md",
    "docs/ok.md",
  ]);
  assert.deepEqual(selected["changed-paths"], ["docs/@kept.md", "docs/ok.md"]);
});

test("changed-paths with nothing left skips the activity as not-applicable-paths", () => {
  const selected = targetsOf(["CLAUDE.md", "plugins/ai-slop/README.md"]);
  assert.equal(selected.applies, false);
  assert.equal(selected["skip-reason"], "not-applicable-paths");
  assert.equal(Object.hasOwn(selected, "changed-paths"), false);
});

test("a read activity's changed-paths keeps instruction surfaces and owned paths", () => {
  const config = withChangedPaths((doc) => {
    doc.activities["fix-prose"].effect = "read";
  });
  assert.deepEqual(
    targetsOf(["CLAUDE.md", "plugins/ai-slop/README.md"], config)[
      "changed-paths"
    ],
    ["CLAUDE.md", "plugins/ai-slop/README.md"],
  );
});

test("an activity with the changed-paths input needs the changed files even without a paths predicate", () => {
  const config = edited((doc) => {
    doc.activities["fix-prose"].inputs = ["changed-paths"];
  });
  assert.deepEqual(
    neededFacts(files(config), {
      lane: "pr-refine",
      activity: "fix-prose",
      configPath: CONFIG_PATH,
    }),
    ["changedPaths"],
  );
});

// Composite activities

const COMPOSITE = `version: 2
activities:
  simplify:
    skill: code-tidying:batch-simplify
    effect: mutate-branch
    gating: advisory
    reads-untrusted: false
  fix-lint:
    script: scripts/fix-lint.sh
    effect: mutate-branch
    gating: advisory
    reads-untrusted: false
    applies-when:
      labels: [lint]
  format-code:
    script: scripts/format-code.sh
    effect: mutate-branch
    gating: advisory
    reads-untrusted: false
  measure-coverage:
    script: scripts/measure-coverage.sh
    effect: read
    gating: advisory
    reads-untrusted: false
  fix-ci:
    children:
      - activity: fix-lint
      - activity: format-code
        needs: [fix-lint]
      - activity: measure-coverage
    applies-when:
      events: [synchronize]
lanes:
  pr-refine:
    stage: refine
    slots:
      - activity: simplify
      - activity: fix-ci
        needs: [simplify]
`;
const composite = (edit) => {
  const doc = parse(COMPOSITE);
  edit(doc);
  return stringify(doc);
};
const runRefine = (config, options = {}, overrides = {}) =>
  run(config, { lane: "pr-refine", ...options }, overrides);
const LINT_FACTS = { ...FACTS, labels: ["lint"] };

test("a composite expands into its leaves in list order, depth first", () => {
  const resolved = runRefine(COMPOSITE, { facts: LINT_FACTS });
  assert.deepEqual(
    resolved.lane.slots.map((slot) => slot.name),
    ["simplify", "fix-lint", "format-code", "measure-coverage"],
  );
  assert.equal(
    resolved.lane.slots.some((slot) => slot.name === "fix-ci"),
    false,
  );
});

test("a leaf under a composite resolves with its own definition and grant", () => {
  const selected = runRefine(COMPOSITE, {
    activity: "format-code",
    facts: LINT_FACTS,
  }).selected;
  assert.deepEqual(
    [selected.kind, selected.script, selected.effect, selected.grant.contents],
    ["script", "scripts/format-code.sh", "mutate-branch", "write"],
  );
  assert.deepEqual([selected.applies, selected["skip-reason"]], [true, null]);
});

test("a leaf's needs are its composite slot's needs, then its own sibling needs", () => {
  const slots = runRefine(COMPOSITE, { facts: LINT_FACTS }).lane.slots;
  const needs = Object.fromEntries(slots.map((slot) => [slot.name, slot.needs]));
  assert.deepEqual(needs, {
    simplify: [],
    "fix-lint": ["simplify"],
    "format-code": ["simplify", "fix-lint"],
    "measure-coverage": ["simplify"],
  });
});

test("enabled is the AND of lane, composite slot and child slot", () => {
  const compositeOff = composite((doc) => {
    doc.lanes["pr-refine"].slots[1].enabled = false;
  });
  const slots = runRefine(compositeOff, { facts: LINT_FACTS }).lane.slots;
  assert.deepEqual(
    slots.map((slot) => [slot.name, slot.enabled, slot["skip-reason"]]),
    [
      ["simplify", true, null],
      ["fix-lint", false, "disabled-by-config"],
      ["format-code", false, "disabled-by-config"],
      ["measure-coverage", false, "disabled-by-config"],
    ],
  );
  const childOff = composite((doc) => {
    doc.activities["fix-ci"].children[1].enabled = false;
  });
  assert.deepEqual(
    runRefine(childOff, { facts: LINT_FACTS }).lane.slots.map(
      (slot) => slot.enabled,
    ),
    [true, true, false, true],
  );
  const laneOff = composite((doc) => {
    doc.lanes["pr-refine"].enabled = false;
  });
  assert.ok(
    runRefine(laneOff, { facts: LINT_FACTS }).lane.slots.every(
      (slot) => slot["skip-reason"] === "disabled-by-config",
    ),
  );
});

test("a composite's applies-when gates its subtree, and a leaf's own predicate must also match", () => {
  const onPush = runRefine(COMPOSITE, {
    facts: { ...LINT_FACTS, event: "push" },
  }).lane.slots;
  assert.deepEqual(
    onPush.map((slot) => [slot.name, slot["skip-reason"]]),
    [
      ["simplify", null],
      ["fix-lint", "not-applicable"],
      ["format-code", "not-applicable"],
      ["measure-coverage", "not-applicable"],
    ],
  );
  const noLintLabel = runRefine(COMPOSITE, { facts: FACTS }).lane.slots;
  assert.deepEqual(
    noLintLabel.map((slot) => slot.applies),
    [true, false, true, true],
  );
});

test("a composite slot's applies-when replaces the composite's own", () => {
  const config = composite((doc) => {
    doc.lanes["pr-refine"].slots[1]["applies-when"] = { events: ["push"] };
  });
  const slots = runRefine(config, {
    facts: { ...LINT_FACTS, event: "push" },
  }).lane.slots;
  assert.ok(slots.every((slot) => slot.applies === true));
});

test("neededFacts for a leaf under a composite include the composite's predicate facts", () => {
  const config = composite((doc) => {
    doc.activities["fix-ci"]["applies-when"] = { mergeable: ["conflicting"] };
  });
  assert.deepEqual(
    neededFacts(files(config), {
      lane: "pr-refine",
      activity: "format-code",
      configPath: CONFIG_PATH,
    }),
    ["mergeable"],
  );
});

test("lane rules apply to every leaf of a composite", () => {
  const mergeLeaf = composite((doc) => {
    doc.activities["format-code"].effect = "merge";
  });
  assertRejected(() => runRefine(mergeLeaf), "forbidden-by-lane");
  const inChecks = composite((doc) => {
    doc.lanes["pr-run-checks"] = {
      stage: "verify",
      slots: [{ activity: "fix-ci" }],
    };
  });
  assertRejected(() => runRefine(inChecks), "forbidden-by-lane");
});

test("a child needs entry must name a sibling in the same children list", () => {
  const config = composite((doc) => {
    doc.activities["fix-ci"].children[0].needs = ["simplify"];
  });
  assertRejected(() => runRefine(config), "needs-not-sibling");
});

test("a lane slot cannot need a leaf that sits inside a composite", () => {
  const config = composite((doc) => {
    doc.activities["check-tree"] = {
      script: "scripts/check-tree.sh",
      effect: "read",
      gating: "advisory",
      "reads-untrusted": false,
    };
    doc.lanes["pr-refine"].slots.push({
      activity: "check-tree",
      needs: ["fix-lint"],
    });
  });
  assertRejected(() => runRefine(config), "needs-outside-lane");
});

test("a lane slot that needs a composite waits on each of its leaves", () => {
  const config = composite((doc) => {
    doc.activities["check-tree"] = {
      script: "scripts/check-tree.sh",
      effect: "read",
      gating: "advisory",
      "reads-untrusted": false,
    };
    doc.lanes["pr-refine"].slots.push({
      activity: "check-tree",
      needs: ["fix-ci"],
    });
  });
  assert.deepEqual(
    runRefine(config, { activity: "check-tree", facts: LINT_FACTS }).selected
      .needs,
    ["fix-lint", "format-code", "measure-coverage"],
  );
});

test("a child naming an undefined activity is rejected", () => {
  const config = composite((doc) => {
    doc.activities["fix-ci"].children.push({ activity: "fix-types" });
  });
  assertRejected(() => runRefine(config), "undefined-activity");
});

test("a composite that contains itself, directly or through another, is rejected as a cycle", () => {
  const direct = composite((doc) => {
    doc.activities["fix-ci"].children.push({ activity: "fix-ci" });
  });
  assertRejected(() => runRefine(direct), "activity-cycle");
  const indirect = composite((doc) => {
    doc.activities["fix-all"] = { children: [{ activity: "fix-ci" }] };
    doc.activities["fix-ci"].children.push({ activity: "fix-all" });
  });
  assertRejected(() => runRefine(indirect), "activity-cycle");
});

test("a composite inside a composite is rejected: at most two layers below the lane", () => {
  const config = composite((doc) => {
    doc.activities["fix-all"] = { children: [{ activity: "fix-ci" }] };
    doc.lanes["pr-refine"].slots[1].activity = "fix-all";
  });
  assertRejected(() => runRefine(config), "activity-depth");
});

test("a composite name must pass the vocabulary like a leaf's", () => {
  const config = COMPOSITE.replaceAll("fix-ci", "lint-fixes");
  assertRejected(() => runRefine(config), "vocabulary");
});

test("a composite named run or report is rejected", () => {
  assertRejected(
    () => runRefine(COMPOSITE.replaceAll("fix-ci", "report")),
    "reserved-name",
  );
});

test("a leaf key may appear once in a lane's expanded tree", () => {
  const config = composite((doc) => {
    doc.lanes["pr-refine"].slots.push({ activity: "fix-lint" });
  });
  assertRejected(() => runRefine(config), "undefined-activity");
});

test("a composite carries no effect, gating, skill, script or inputs, and needs a child", () => {
  for (const extra of [
    { effect: "read" },
    { gating: "gate" },
    { skill: "a:b" },
    { script: "scripts/x.sh" },
    { inputs: ["pr"] },
  ]) {
    const config = composite((doc) => {
      Object.assign(doc.activities["fix-ci"], extra);
    });
    assertRejected(() => runRefine(config), "invalid-config");
  }
  const empty = composite((doc) => {
    doc.activities["fix-ci"].children = [];
  });
  assertRejected(() => runRefine(empty), "invalid-config");
});

test("resolveGrant grants a leaf under a composite and refuses the composite key", () => {
  const request = { lane: "pr-refine" };
  assert.deepEqual(
    grantOf(COMPOSITE, { ...request, activity: "fix-lint" }),
    {
      effect: "mutate-branch",
      grant: { contents: "write", "pull-requests": "read", issues: "read" },
    },
  );
  assertRejected(
    () => grantOf(COMPOSITE, { ...request, activity: "fix-ci" }),
    "undefined-activity",
  );
  const compositeOff = composite((doc) => {
    doc.lanes["pr-refine"].slots[1].enabled = false;
  });
  assertRejected(
    () => grantOf(compositeOff, { ...request, activity: "fix-lint" }),
    "slot-disabled",
  );
});

test("selecting a composite key is rejected as undefined-activity", () => {
  assertRejected(
    () => runRefine(COMPOSITE, { activity: "fix-ci", facts: LINT_FACTS }),
    "undefined-activity",
  );
});

// prepare

const withPrepare = (edit) =>
  composite((doc) => {
    doc.activities.simplify.prepare = "merge-base";
    edit?.(doc);
  });

test("prepare on a non-read skill leaf resolves and is carried on the slot", () => {
  const selected = runRefine(withPrepare(), {
    activity: "simplify",
    facts: LINT_FACTS,
  }).selected;
  assert.equal(selected.prepare, "merge-base");
  assert.equal(
    Object.hasOwn(
      runRefine(COMPOSITE, { activity: "simplify", facts: LINT_FACTS })
        .selected,
      "prepare",
    ),
    false,
  );
});

test("prepare: review-threads on a non-read skill leaf resolves and is carried on the slot", () => {
  const config = withPrepare((doc) => {
    doc.activities.simplify.prepare = "review-threads";
  });
  assert.equal(runRefine(config, { activity: "simplify", facts: LINT_FACTS }).selected.prepare, "review-threads");
});

// A read merge-base skill must hand its resolutions on as a patch: the schema
// requires applied-by.patch of it.
test("prepare on a read skill leaf with no applied-by.patch is rejected", () => {
  const config = withPrepare((doc) => {
    doc.activities.simplify.effect = "read";
  });
  assertRejected(() => runRefine(config), "invalid-config");
});

test("prepare on a script leaf, or a value other than merge-base, fails the schema", () => {
  const onScript = composite((doc) => {
    doc.activities["fix-lint"].prepare = "merge-base";
  });
  assertRejected(() => runRefine(onScript), "invalid-config");
  const otherMode = withPrepare((doc) => {
    doc.activities.simplify.prepare = "rebase";
  });
  assertRejected(() => runRefine(otherMode), "invalid-config");
});

// A read ci-context skill that hands on its patch resolves: the live fix-ci
// (live-config.test.mjs). Without applied-by.patch its edits would leave nowhere.
test("prepare: ci-context needs effect read, and a read one needs applied-by.patch", () => {
  const read = withPrepare((doc) => {
    doc.activities.simplify.prepare = "ci-context";
    doc.activities.simplify.effect = "read";
  });
  assertRejected(() => runRefine(read), "invalid-config");
  const write = withPrepare((doc) => {
    doc.activities.simplify.prepare = "ci-context";
  });
  assertRejected(() => runRefine(write), "invalid-prepare");
});

test("prepare: apply-patch is the one mode a script may set, and it needs effect mutate-branch", () => {
  const onScript = (effect) =>
    composite((doc) => {
      doc.activities["fix-lint"].prepare = "apply-patch";
      doc.activities["fix-lint"].effect = effect;
    });
  assert.equal(runRefine(onScript("mutate-branch"), { activity: "fix-lint", facts: LINT_FACTS }).selected.prepare, "apply-patch");
  assertRejected(() => runRefine(onScript("read")), "invalid-prepare");
  assertRejected(() => runRefine(onScript("publish-artifact")), "invalid-prepare");
  const onSkill = withPrepare((doc) => {
    doc.activities.simplify.prepare = "apply-patch";
  });
  assertRejected(() => runRefine(onSkill), "invalid-config");
});

// Activity rules (trust root, beside lane-rules.json)

test("an activity rule's forbidden effect rejects the leaf whatever lane it is in", () => {
  const activityRules = {
    "format-code": {
      "forbidden-effects": ["mutate-branch"],
      never: "Writes to the branch",
    },
  };
  assert.throws(
    () => runRefine(COMPOSITE, {}, { activityRules }),
    (error) => {
      assert.equal(error.code, "forbidden-by-activity");
      assert.match(error.message, /Writes to the branch/);
      return true;
    },
  );
});

test("a leaf with no activity rule is valid", () => {
  assert.equal(
    runRefine(COMPOSITE, { facts: LINT_FACTS }, { activityRules: {} }).lane
      .slots.length,
    4,
  );
});

test("a malformed activity-rules.json is rejected", () => {
  for (const activityRules of [
    [],
    { "fix-lint": "never" },
    { "fix-lint": {} },
    { "fix-lint": { never: "x", "forbidden-effects": "merge" } },
  ]) {
    assertRejected(
      () => runRefine(COMPOSITE, {}, { activityRules }),
      "activity-rules",
    );
  }
});

test("no activity rules at all is rejected, never read as no rules", () => {
  assertRejected(
    () => runRefine(COMPOSITE, {}, { activityRules: undefined }),
    "activity-rules",
  );
  assertRejected(
    () =>
      grantOf(
        COMPOSITE,
        { lane: "pr-refine", activity: "fix-lint" },
        { activityRules: undefined },
      ),
    "activity-rules",
  );
});

test("a forbidden effect that is not an effect-grants.json key is rejected", () => {
  const activityRules = {
    "fix-lint": { never: "Merges", "forbidden-effects": ["merges"] },
  };
  assertRejected(
    () => runRefine(COMPOSITE, {}, { activityRules }),
    "activity-rules",
  );
});

test("the shipped activity rules keep report-escalation off the branch", () => {
  const config = `version: 2
activities:
  report-escalation:
    script: .github/scripts/pr-unblock/report-escalation.sh
    effect: mutate-branch
    gating: advisory
    reads-untrusted: false
lanes:
  pr-unblock:
    stage: unblock
    slots:
      - activity: report-escalation
`;
  assertRejected(
    () => run(config, { lane: "pr-unblock" }),
    "forbidden-by-activity",
  );
});

// Owner shape (#7032 amendment): the model job only pushes, the reply job
// only posts.
const feedbackLeaf = (activity, effect) => `version: 2
activities:
  ${activity}:
    ${activity === "address-feedback" ? "skill: source-control:pull-request" : "script: .github/scripts/pr-unblock/publish-feedback.mjs"}
    effect: ${effect}
    gating: advisory
    reads-untrusted: true
lanes:
  pr-unblock:
    stage: unblock
    slots:
      - activity: ${activity}
`;

// address-feedback runs on the read runner: it neither pushes nor posts.
for (const [activity, allowed, forbidden] of [
  ["address-feedback", "read", ["mutate-branch", "publish-artifact", "mutate-tracker", "merge"]],
  ["publish-feedback", "publish-artifact", ["mutate-branch", "mutate-tracker", "merge"]],
]) {
  test(`the shipped activity rules give ${activity} ${allowed} and nothing that ${allowed === "read" ? "pushes or posts" : "pushes"}`, () => {
    // The live vocabulary: the fixture lacks the verb "publish".
    const live = { vocabulary: JSON.parse(readFileSync(LIVE_VOCABULARY, "utf8")) };
    assert.equal(run(feedbackLeaf(activity, allowed), { lane: "pr-unblock", activity }, live).selected.effect, allowed);
    for (const effect of forbidden) {
      assertRejected(() => run(feedbackLeaf(activity, effect), { lane: "pr-unblock", activity }, live), "forbidden-by-activity");
    }
  });
}

// Stages

test("the respond stage is gone; pr-unblock has stage unblock", () => {
  const lane = (stage) => `version: 2
activities:
  report-escalation:
    script: .github/scripts/pr-unblock/report-escalation.sh
    effect: publish-artifact
    gating: advisory
    reads-untrusted: false
lanes:
  pr-unblock:
    stage: ${stage}
    slots:
      - activity: report-escalation
`;
  assert.equal(
    run(lane("unblock"), { lane: "pr-unblock" }).lane.stage,
    "unblock",
  );
  assertRejected(
    () => run(lane("respond"), { lane: "pr-unblock" }),
    "invalid-config",
  );
});

// The README example

const EXAMPLE_FACTS = {
  event: "synchronize",
  changedPaths: ["README.md"],
  changedTargets: ["README.md"],
  labels: [],
  workClasses: [],
  mergeable: "conflicting",
  draft: false,
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
  assert.equal(Object.keys(results).length, 16);
  // The example's models block routes claude to review and leaves the rest
  // on default-profile standard.
  assert.deepEqual(results["pr-review / claude"].models, {
    profile: "review",
    model: "opus",
    effort: null,
    "subagent-model": "inherit",
    "max-turns": 100,
  });
  assert.equal(results["pr-unblock / fix-docs"].models.profile, "standard");
  assert.equal(results["pr-require-checks / require-checks"].models, null);
  assert.equal(results["pr-unblock / fix-docs"].applies, true);
  assert.deepEqual(results["pr-unblock / fix-docs"]["changed-paths"], [
    "README.md",
  ]);
  const resolveConflicts = results["pr-unblock / resolve-conflicts"];
  assert.deepEqual(
    [
      resolveConflicts.applies,
      resolveConflicts.prepare,
      resolveConflicts["reads-untrusted"],
      resolveConflicts.effect,
    ],
    [true, "merge-base", true, "read"],
  );
  assert.deepEqual(resolveConflicts["applies-when"], {
    mergeable: ["conflicting"],
    "labels-absent": ["do-not-merge"],
    draft: [false],
  });
  assert.deepEqual(results["pr-unblock / report-escalation"].needs, [
    "resolve-conflicts",
    "apply-conflict-patch",
  ]);
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
  assert.equal(Object.keys(results).length, 16);
});

// applied-by: a read skill names the script activity that applies each thing
// it hands on (README.md, Activities). The live vocabulary: the fixture lacks
// the verb "apply".

const liveVocabulary = () => ({ vocabulary: JSON.parse(readFileSync(LIVE_VOCABULARY, "utf8")) });
const APPLIED_BY = fixture("invalid-applied-by-missing-needs.yaml").replace(
  "      - activity: apply-patch\n",
  "      - activity: apply-patch\n        needs: [fix-ci]\n",
);
const unblock = (config, activity = "fix-ci", facts = {}) =>
  run(config, { lane: "pr-unblock", activity, facts: { ...FACTS, ...facts } }, liveVocabulary()).selected;
const appliedByEdit = (edit) => {
  const doc = parse(APPLIED_BY);
  edit(doc);
  return stringify(doc);
};

// review-threads also hands on its replies, which the schema requires: the
// reply job is the only way they reach the pull request.
test("prepare: a read skill that hands on a patch may set a writing skill's prepare mode; without applied-by.patch it may not", () => {
  for (const prepare of ["review-threads", "dependency-review", "merge-base"]) {
    const handsOn = appliedByEdit((doc) => {
      doc.activities["fix-ci"].prepare = prepare;
      if (prepare === "review-threads") doc.activities["fix-ci"]["applied-by"]["feedback-replies"] = "apply-patch";
      if (prepare === "dependency-review") doc.activities["fix-ci"]["applied-by"]["dependency-verdict"] = "apply-patch";
    });
    assert.equal(unblock(handsOn).prepare, prepare, prepare);
    const noPatch = appliedByEdit((doc) => {
      doc.activities["fix-ci"].prepare = prepare;
      delete doc.activities["fix-ci"]["applied-by"];
    });
    // The schema requires applied-by.patch of a read skill in each mode.
    assertRejected(() => unblock(noPatch), "invalid-config");
  }
  const noReplies = appliedByEdit((doc) => {
    doc.activities["fix-ci"].prepare = "review-threads";
  });
  assertRejected(() => unblock(noReplies), "invalid-config");
  // A read dependency-review skill hands on its verdict too.
  const noVerdict = appliedByEdit((doc) => {
    doc.activities["fix-ci"].prepare = "dependency-review";
  });
  assertRejected(() => unblock(noVerdict), "invalid-config");
});

test("applied-by: a read skill whose patch an apply-patch script in its lane needs resolves and carries the map", () => {
  assert.deepEqual(unblock(APPLIED_BY)["applied-by"], { patch: "apply-patch" });
  assert.equal(Object.hasOwn(unblock(APPLIED_BY, "apply-patch"), "applied-by"), false);
});

// Each fixture breaks one rule, and the message names that rule.
const assertAppliedByRejected = (fn, message) =>
  assert.throws(fn, (error) => {
    assert.ok(error instanceof Rejection, `expected a Rejection, got ${error}`);
    assert.equal(error.code, "invalid-applied-by", error.message);
    assert.match(error.message, message);
    return true;
  });

for (const [name, why, message] of [
  ["invalid-applied-by-not-script.yaml", "a target that is a skill", /`review-patch`, which is not a script activity/],
  ["invalid-applied-by-outside-lane.yaml", "a target outside the producer's lane", /`apply-patch` is not in the lane/],
  [
    "invalid-applied-by-apply-patch-prepare.yaml",
    "an apply-patch target without prepare: apply-patch",
    /`apply-patch`, which does not set prepare: apply-patch/,
  ],
  ["invalid-applied-by-missing-needs.yaml", "a target whose slot does not need the producer", /slot `apply-patch` .* does not need it/],
]) {
  test(`applied-by: ${why} is rejected (${name})`, () => {
    assertAppliedByRejected(() => unblock(fixture(name)), message);
  });
}

test("applied-by: an apply-issue-patch target without prepare: apply-patch is rejected", () => {
  assertAppliedByRejected(
    () =>
      run(
        fixture("invalid-applied-by-apply-issue-patch-prepare.yaml"),
        { lane: "work-resolve-issue", activity: "resolve-issue" },
        liveVocabulary(),
      ),
    /`apply-issue-patch`, which does not set prepare: apply-patch/,
  );
});

test("applied-by: a target no activity defines is rejected", () => {
  const config = appliedByEdit((doc) => {
    doc.activities["fix-ci"]["applied-by"]["feedback-replies"] = "publish-feedback";
  });
  assertAppliedByRejected(() => unblock(config), /`publish-feedback`, which is not a script activity/);
});

test("applied-by: a non-patch target needs no prepare mode", () => {
  const config = appliedByEdit((doc) => {
    doc.activities["fix-ci"]["applied-by"]["feedback-replies"] = "publish-feedback";
    doc.activities["publish-feedback"] = {
      script: ".github/scripts/pr-unblock/publish-feedback.mjs",
      effect: "publish-artifact",
      gating: "advisory",
      "reads-untrusted": true,
    };
    doc.lanes["pr-unblock"].slots.push({ activity: "publish-feedback", needs: ["fix-ci"] });
  });
  assert.deepEqual(unblock(config)["applied-by"], { patch: "apply-patch", "feedback-replies": "publish-feedback" });
});

for (const [why, edit] of [
  ["on a script", (doc) => (doc.activities["apply-patch"]["applied-by"] = { patch: "apply-patch" })],
  ["with effect mutate-branch", (doc) => (doc.activities["fix-ci"].effect = "mutate-branch")],
  ["with gating gate", (doc) => (doc.activities["fix-ci"].gating = "gate")],
  ["with a key outside the closed set", (doc) => (doc.activities["fix-ci"]["applied-by"].verdict = "apply-patch")],
  ["empty", (doc) => (doc.activities["fix-ci"]["applied-by"] = {})],
]) {
  test(`applied-by ${why} fails the schema`, () => {
    assertRejected(() => unblock(appliedByEdit(edit)), "invalid-config");
  });
}

// Only the runner that stages a skill's edit tools grants these, and the read
// runner does so only for applied-by.patch without ci-context.
for (const [key, value] of [
  ["checks", ["scripts/check-x.sh"]],
  ["self-checks", ["scripts/check-x.sh"]],
  ["verify-scripts", ["scripts/check-x.sh"]],
  ["web-access", { enabled: true, domains: "any" }],
]) {
  test(`${key} on a read skill that hands on a patch resolves and is carried`, () => {
    const config = appliedByEdit((doc) => {
      delete doc.activities["fix-ci"].prepare;
      doc.activities["fix-ci"][key] = value;
    });
    assert.deepEqual(unblock(config)[key], value);
  });

  test(`${key} on a read skill with prepare: ci-context fails the schema`, () => {
    assertRejected(() => unblock(appliedByEdit((doc) => (doc.activities["fix-ci"][key] = value))), "invalid-config");
  });
}

test("applied-by-supported: an applying leaf fails on a key its runner does not name", () => {
  const selected = unblock(APPLIED_BY);
  assert.doesNotThrow(() => checkAppliedBySupported(selected, "patch"));
  assert.doesNotThrow(() => checkAppliedBySupported(selected, "feedback-replies, patch"));
  for (const supported of ["", "feedback-replies", "patches"]) {
    assertRejected(() => checkAppliedBySupported(selected, supported), "applied-by-unsupported");
  }
});

test("applied-by-supported: a leaf with no applied-by, or one that does not apply, passes on any runner", () => {
  assert.doesNotThrow(() => checkAppliedBySupported(unblock(APPLIED_BY, "apply-patch"), ""));
  assert.doesNotThrow(() => checkAppliedBySupported({ ...unblock(APPLIED_BY), applies: false }, ""));
});

test("changed-paths: a read skill that hands on a patch is not asked to fix instruction surfaces or owned paths", () => {
  const config = appliedByEdit((doc) => {
    doc.activities["fix-ci"].inputs = ["changed-paths"];
  });
  const changed = ["docs/guide.md", "CLAUDE.md", "plugins/ai-slop/README.md"];
  const selected = run(
    config,
    { lane: "pr-unblock", activity: "fix-ci", facts: { ...FACTS, changedPaths: changed, changedTargets: changed } },
    { ...liveVocabulary(), codeowners: CODEOWNERS },
  ).selected;
  assert.deepEqual(selected["changed-paths"], ["docs/guide.md"]);
});

// patch-rules.json: apply-patch's registry, one row per prepare mode
// (README.md, Patch rules).

const PATCH_RULES = JSON.parse(read("./patch-rules.json"));
const PATCH_RULES_SCHEMA = JSON.parse(read("./patch-rules.schema.json"));
const patchRules = (name) => JSON.parse(fixture(name));

test("patch rules: the shipped registry passes, with a row for each prepare mode and the default and issue targets", () => {
  assert.equal(checkPatchRules(PATCH_RULES, PATCH_RULES_SCHEMA), PATCH_RULES);
  assert.deepEqual(Object.keys(PATCH_RULES).sort(), [
    "ci-context",
    "default",
    "dependency-review",
    "issue",
    "merge-base",
    "review-threads",
  ]);
});

for (const [name, why, message] of [
  ["patch-rules-missing-universal.json", "a row that does not refuse the universal set", /row `issue` does not refuse codeowners$/],
  ["patch-rules-unknown-predicate.json", "an allow rule apply-patch does not know", /fails its schema: \/default\/allow\/0/],
  [
    "patch-rules-merge-parents.json",
    "a two-parent commit without allow merge-result",
    /row `merge-base` commits with the base as a parent, so its allow must be exactly \[merge-result\]/,
  ],
  [
    "patch-rules-merge-allow-any.json",
    "a two-parent commit that also allows any path",
    /row `merge-base` commits with the base as a parent, so its allow must be exactly \[merge-result\]/,
  ],
]) {
  test(`patch rules: ${why} is rejected (${name})`, () => {
    assert.throws(
      () => checkPatchRules(patchRules(name), PATCH_RULES_SCHEMA),
      (error) => error instanceof Rejection && error.code === "patch-rules" && message.test(error.message),
    );
  });
}

test("patch rules: a missing registry or schema is rejected", () => {
  assertRejected(() => checkPatchRules(undefined, PATCH_RULES_SCHEMA), "patch-rules");
  assertRejected(() => checkPatchRules(PATCH_RULES, undefined), "patch-rules");
});

test("patch rules: a row with an unknown key, or a registry without the default or issue row, fails its schema", () => {
  assertRejected(
    () => checkPatchRules({ ...PATCH_RULES, default: { ...PATCH_RULES.default, paths: ["**"] } }, PATCH_RULES_SCHEMA),
    "patch-rules",
  );
  for (const row of ["default", "issue"]) {
    const { [row]: _dropped, ...rest } = PATCH_RULES;
    assertRejected(() => checkPatchRules(rest, PATCH_RULES_SCHEMA), "patch-rules");
  }
});

test("patch rules: a patch producer whose prepare mode has no row is rejected; one with no prepare mode takes default", () => {
  const { "ci-context": _dropped, ...withoutCiContext } = PATCH_RULES;
  const producer = { skill: "source-control:pull-request", effect: "read", "applied-by": { patch: "apply-patch" } };
  assertRejected(
    () => checkPatchRules(withoutCiContext, PATCH_RULES_SCHEMA, { "fix-ci": { ...producer, prepare: "ci-context" } }),
    "patch-rules",
  );
  assert.doesNotThrow(() => checkPatchRules(withoutCiContext, PATCH_RULES_SCHEMA, { "fix-docs": producer }));
});
