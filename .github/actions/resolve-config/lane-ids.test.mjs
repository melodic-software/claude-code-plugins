import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { test } from "node:test";

const read = (relative) => readFileSync(new URL(relative, import.meta.url), "utf8");
const json = (relative) => JSON.parse(read(relative));

const LANE_RULES = json("./lane-rules.json");
const GRANTS = json("./lane-grants.json");
const REGISTRY = json("../../lane-registry.json");
const FUNDING = json("../../lane-funding.json");
const SCHEMA = json("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json");
const README = read("../../../docs/conventions/pr-pipeline/README.md");
const GLOSSARY = read("../../../docs/glossary.md");
const THIS_REPOSITORY = "1277265216";

const stem = (file) => file.replace(/\.yml$/, "");
const STEMS = new Set(readdirSync(new URL("../../workflows/", import.meta.url)).filter((file) => file.endsWith(".yml")).map(stem));
const LANES = new Set(Object.keys(LANE_RULES));

const NOT_LANES = {
  "maintenance-measure-skill-edit-pass": "a workflow_call reusable maintenance-measure-skill-edit calls once per measuring pass",
  "pr-run-activity-write": "the workflow_call runner every write activity of a lane runs on",
  "pr-dispatch-feedback": "a scripted dispatcher with no model that starts pr-unblock",
};

const otherRepositoryLanes = new Set(
  Object.entries(GRANTS)
    .filter(([id]) => id !== THIS_REPOSITORY)
    .flatMap(([, row]) => Object.keys(row.lanes)),
);

function readmeLanes() {
  const section = README.split(/^## Lanes$/m)[1].split(/^## /m)[0];
  const table = section.split(/^\| Lane \| Starts on \|$/m)[1].split(/\n\n/)[0];
  return table
    .split("\n")
    .filter((line) => line.startsWith("| `"))
    .flatMap((line) => [...line.split("|")[1].matchAll(/`([^`]+)`/g)].map((match) => match[1]));
}

test("each lane id is a workflow file stem here or a lane another repository's grant row admits", () => {
  for (const lane of LANES) {
    assert.ok(STEMS.has(lane) || otherRepositoryLanes.has(lane), `${lane} has no workflow here and no other repository's grant`);
  }
});

test("each lane this repository's grant row admits is a workflow file stem here", () => {
  for (const lane of Object.keys(GRANTS[THIS_REPOSITORY].lanes)) {
    assert.ok(STEMS.has(lane), lane);
  }
});

test("each workflow the registry names is a lane or recorded as not a lane", () => {
  for (const file of Object.keys(REGISTRY.workflows)) {
    assert.ok(LANES.has(stem(file)) || Object.hasOwn(NOT_LANES, stem(file)), `lane-registry.json ${file}`);
  }
});

test("each workflow the funding file funds is a lane or recorded as not a lane", () => {
  for (const { id, lanes } of FUNDING.roles) {
    for (const { workflow } of lanes) {
      assert.ok(LANES.has(stem(workflow)) || Object.hasOwn(NOT_LANES, stem(workflow)), `lane-funding.json ${id} ${workflow}`);
    }
  }
});

test("each workflow recorded as not a lane is a workflow here, no lane, and named by the registry or the funding file", () => {
  const named = new Set([
    ...Object.keys(REGISTRY.workflows).map(stem),
    ...FUNDING.roles.flatMap(({ lanes }) => lanes.map(({ workflow }) => stem(workflow))),
  ]);
  for (const workflow of Object.keys(NOT_LANES)) {
    assert.ok(STEMS.has(workflow), workflow);
    assert.ok(!LANES.has(workflow), workflow);
    assert.ok(named.has(workflow), workflow);
  }
});

test("each lane the README's Lanes table names is a lane id and a workflow file stem here", () => {
  const lanes = readmeLanes();
  assert.ok(lanes.length > 0, "the README's Lanes table names no lane");
  for (const lane of lanes) {
    assert.ok(LANES.has(lane), `README lane ${lane} has no lane-rules.json row`);
    assert.ok(STEMS.has(lane), `README lane ${lane} has no workflow here`);
  }
});

test("each lane's stage is one the schema allows, and the glossary lists every one", () => {
  const stages = SCHEMA.$defs.stage.enum;
  for (const [lane, { stage }] of Object.entries(LANE_RULES)) {
    assert.ok(stages.includes(stage), `${lane} stage ${stage}`);
  }
  const entry = GLOSSARY.split(/^\*\*stage\*\*$/m)[1].split(/^\*\*/m)[0];
  assert.deepEqual([...entry.matchAll(/`([a-z-]+)`/g)].map((match) => match[1]), stages);
});
