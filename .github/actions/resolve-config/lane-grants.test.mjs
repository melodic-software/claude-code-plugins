// lane-grants.json: the central grant file, one row per repository the lanes
// token broker admits (ADR 0085 Decision 2; README.md, Central lane grants).
// Expected values come from the trust files and this repository's own
// pipeline config, which the rows must reproduce, not from the rows.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import Ajv2020 from "ajv/dist/2020.js";
import { parse } from "yaml";

import { resolveGrant } from "./resolve.mjs";

const read = (relative) => readFileSync(new URL(relative, import.meta.url), "utf8");
const json = (relative) => JSON.parse(read(relative));
const GRANTS = json("./lane-grants.json");
const LANE_RULES = json("./lane-rules.json");
const EFFECT_GRANTS = json("./effect-grants.json");
const CONFIG_PATH = "docs/conventions/pr-pipeline.yaml";
const FILES = {
  config: read(`../../../${CONFIG_PATH}`),
  schema: json("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json"),
  vocabulary: json("../../standards/github-actions-conventions/vocabulary.json"),
  laneRules: LANE_RULES,
  effectGrants: EFFECT_GRANTS,
  activityRules: json("./activity-rules.json"),
};
const THIS_REPOSITORY = "1277265216";
const NAME = /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/;
const ACTORS_SCHEMA = json("../../standards/trusted-actors/trusted-actors.schema.json");

test("each row is keyed by a repository id and holds exactly the repository label, lanes, trusted-actor additions and ci-workflows commits", () => {
  assert.ok(Object.keys(GRANTS).length > 0);
  for (const [id, row] of Object.entries(GRANTS)) {
    assert.match(id, /^[1-9][0-9]{0,19}$/, id);
    assert.deepEqual(Object.keys(row).sort(), ["ci-workflows-commits", "lanes", "repository", "trusted-actors"], id);
    assert.match(row.repository, /^melodic-software\/[A-Za-z0-9._-]+$/, id);
    assert.ok(Array.isArray(row["trusted-actors"]), id);
    assert.ok(Array.isArray(row["ci-workflows-commits"]), id);
    for (const sha of row["ci-workflows-commits"]) {
      assert.match(sha, /^[0-9a-f]{40}$/, `${id} ${sha}`);
    }
    assert.equal(new Set(row["ci-workflows-commits"]).size, row["ci-workflows-commits"].length, `${id} lists a commit twice`);
  }
  const labels = Object.values(GRANTS).map((row) => row.repository);
  assert.equal(new Set(labels).size, labels.length, "two rows carry one repository label");
});

test("each trusted-actor addition is an entry the trusted-actor list's schema admits", () => {
  const validate = new Ajv2020({ strict: false }).addSchema(ACTORS_SCHEMA).compile({ $ref: `${ACTORS_SCHEMA.$id}#/$defs/actor` });
  for (const [id, row] of Object.entries(GRANTS)) {
    for (const actor of row["trusted-actors"]) {
      assert.ok(validate(actor), `${id} ${JSON.stringify(actor)}: ${JSON.stringify(validate.errors)}`);
    }
  }
  assert.ok(validate({ id: 1, login: "someone", kind: "human" }) && !validate({ id: 1, login: "someone" }), "the check rejects a malformed entry");
});

test("each lane is one lane-rules.json defines, and each activity's effect is one effect-grants.json grants and that lane does not forbid", () => {
  for (const [id, row] of Object.entries(GRANTS)) {
    assert.ok(Object.keys(row.lanes).length > 0, `${id} admits no lane`);
    for (const [lane, activities] of Object.entries(row.lanes)) {
      assert.ok(Object.hasOwn(LANE_RULES, lane), `${id} ${lane} has no lane-rules.json row`);
      assert.ok(Object.keys(activities).length > 0, `${id} ${lane} grants no activity`);
      for (const [activity, effect] of Object.entries(activities)) {
        assert.match(activity, NAME, `${id} ${lane}/${activity}`);
        assert.ok(Object.hasOwn(EFFECT_GRANTS, effect), `${id} ${lane}/${activity} effect ${effect}`);
        assert.ok(!LANE_RULES[lane]["forbidden-effects"].includes(effect), `${id} ${lane}/${activity} effect ${effect} is forbidden by its lane`);
      }
    }
  }
});

test("only pr-merge's activities hold effect merge", () => {
  for (const [id, row] of Object.entries(GRANTS)) {
    for (const [lane, activities] of Object.entries(row.lanes)) {
      for (const [activity, effect] of Object.entries(activities)) {
        assert.equal(effect === "merge", lane === "pr-merge", `${id} ${lane}/${activity}`);
      }
    }
  }
});

test("this repository's row reproduces exactly the grants its own config resolves today: every enabled slot, no disabled one", () => {
  const doc = parse(FILES.config);
  const expected = {};
  for (const [lane, section] of Object.entries(doc.lanes)) {
    for (const { activity } of section.slots ?? []) {
      let effect;
      try {
        ({ effect } = resolveGrant(FILES, { lane, activity, configPath: CONFIG_PATH }));
      } catch (error) {
        if (error.code === "slot-disabled") {
          continue;
        }
        throw error;
      }
      (expected[lane] ??= {})[activity] = effect;
    }
  }
  assert.equal(GRANTS[THIS_REPOSITORY].repository, "melodic-software/claude-code-plugins");
  assert.deepEqual(GRANTS[THIS_REPOSITORY].lanes, expected);
});
