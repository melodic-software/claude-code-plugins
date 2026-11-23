import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { test } from "node:test";

import { LANE_RECORDS } from "../pr-merge/clear-escalations.mjs";
import { REVIEW_LANES } from "../pr-merge/merge-holds.mjs";
import { LANE_WORKFLOWS } from "./lane-binding.mjs";
import { callers, jobNames, laneJob, listedJob, REGISTRY, reviewLanes, statusChecks } from "./lane-registry.mjs";
import { workflowText } from "./workflow-text.mjs";

const FIXTURE = {
  workflows: {
    "caller.yml": {
      lane: "fixture-review",
      jobs: {
        gate: { name: "Check Gate", earlier: ["Gate", "gate"] },
        write: { name: "Apply Write", calls: "./.github/workflows/runner.yml" },
        other: { name: "Apply Other", calls: "./.github/workflows/runner.yml" },
        renamed: { name: "Renamed Write", earlier: ["renamed"], calls: "./.github/workflows/runner.yml" },
        review: { name: "Code Review", earlier: ["code-review"], calls: "org/repo/.github/workflows/review.yml", status: ["status", "Publish"] },
      },
    },
    "runner.yml": { jobs: { run: { name: "Run" } } },
  },
};

test("a job is read by id, with its earlier names after its name", () => {
  assert.deepEqual(laneJob("caller.yml", "gate", FIXTURE), { id: "gate", name: "Check Gate", earlier: ["Gate", "gate"], calls: undefined, status: [] });
  assert.deepEqual(jobNames("caller.yml", "gate", FIXTURE), ["Check Gate", "Gate", "gate"]);
  assert.deepEqual(jobNames("runner.yml", "run", FIXTURE), ["Run"]);
});

test("a job or workflow the registry does not name throws", () => {
  assert.throws(() => laneJob("caller.yml", "missing", FIXTURE), /names no job missing in caller\.yml/);
  assert.throws(() => laneJob("absent.yml", "gate", FIXTURE), /names no job gate in absent\.yml/);
  assert.throws(() => statusChecks("runner.yml", FIXTURE), /no status job in runner\.yml/);
});

test("a local workflow call is listed as caller / called job, by name and by id", () => {
  assert.deepEqual(listedJob("caller.yml", "write", "run", FIXTURE), { id: "write / run", name: "Apply Write / Run", earlier: [] });
  assert.deepEqual(listedJob("caller.yml", "gate", undefined, FIXTURE), { id: "gate", name: "Check Gate", earlier: ["Gate", "gate"] });
  assert.throws(() => listedJob("caller.yml", "review", "status", FIXTURE), /not a local workflow call/);
  assert.throws(() => listedJob("caller.yml", "renamed", "run", FIXTURE), /with one name/);
  assert.throws(() => listedJob("caller.yml", "write", "report", FIXTURE), /names no job report in runner\.yml/);
});

test("callers are the jobs that call one workflow", () => {
  assert.deepEqual(callers("caller.yml", "./.github/workflows/runner.yml", FIXTURE), ["write", "other", "renamed"]);
  assert.deepEqual(callers("caller.yml", "./.github/workflows/none.yml", FIXTURE), []);
});

test("a review caller's status checks pair each status job name with each caller name", () => {
  assert.deepEqual(statusChecks("caller.yml", FIXTURE), ["Code Review / status", "code-review / status", "Code Review / Publish", "code-review / Publish"]);
  assert.deepEqual(reviewLanes(FIXTURE), [{ lane: "fixture-review", workflow: "caller.yml" }]);
});

const WORKFLOWS = new URL("../../workflows/", import.meta.url);
const parsed = (file) => {
  const wf = workflowText(readFileSync(new URL(file, WORKFLOWS), "utf8"));
  const field = (id, key) => new RegExp(`^ {4}${key}: (.*)$`, "m").exec(wf.job(id))?.[1];
  return { ids: wf.ids, name: (id) => field(id, "name"), uses: (id) => field(id, "uses")?.replace(/\s+#.*$/, "").replace(/@.*$/, "") };
};

test("every job the registry names is in its workflow, under that name and calling that workflow", () => {
  for (const [file, { jobs }] of Object.entries(REGISTRY.workflows)) {
    assert.ok(existsSync(new URL(file, WORKFLOWS)), file);
    const wf = parsed(file);
    for (const [id, job] of Object.entries(jobs)) {
      assert.ok(wf.ids.includes(id), `${file} has job ${id}`);
      assert.equal(wf.name(id), job.name, `${file} ${id} name`);
      assert.equal(wf.uses(id), job.calls, `${file} ${id} uses`);
      assert.ok(job.status === undefined || job.calls !== undefined, `${file} ${id}: a status job is a reusable's`);
    }
  }
});

test("an earlier name is no other job's current name or id", () => {
  for (const [file, { jobs }] of Object.entries(REGISTRY.workflows)) {
    const wf = parsed(file);
    const current = new Set(wf.ids.flatMap((id) => [id, wf.name(id)]));
    for (const [id, job] of Object.entries(jobs)) {
      for (const name of job.earlier ?? []) {
        assert.ok(name === id || !current.has(name), `${file} ${id}: ${name} is a job in the workflow now`);
        assert.notEqual(name, job.name, `${file} ${id}`);
      }
    }
  }
});

test("a workflow names every job that calls a local workflow one of its named jobs calls", () => {
  for (const [file, { jobs }] of Object.entries(REGISTRY.workflows)) {
    const wf = parsed(file);
    const called = new Set(Object.values(jobs).flatMap(({ calls }) => (calls?.startsWith("./") ? [calls] : [])));
    for (const id of wf.ids) {
      if (called.has(wf.uses(id))) assert.ok(id in jobs, `${file} job ${id} calls ${wf.uses(id)} and is not in the registry`);
    }
  }
});

test("the review lanes' tables that cannot import the registry agree with it", () => {
  const lanes = reviewLanes();
  assert.deepEqual(lanes.map(({ lane }) => lane), ["claude-review", "claude-security-review"]);
  assert.deepEqual(REVIEW_LANES, lanes.map(({ workflow }) => [workflow, statusChecks(workflow)]));
  assert.deepEqual(
    LANE_RECORDS.map(({ file, lane, jobs }) => ({ file, lane, jobs })),
    lanes.map(({ lane, workflow }) => ({ file: workflow, lane, jobs: statusChecks(workflow) })),
  );
  assert.deepEqual(LANE_WORKFLOWS, Object.fromEntries(lanes.map(({ lane, workflow }) => [lane, `.github/workflows/${workflow}`])));
});
