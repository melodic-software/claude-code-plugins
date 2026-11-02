// The Work status writer over the live models.issue-status: one POST of the
// collapsed state's option name, checked against the mapped option id; a
// failure warns and returns. Option ids are written by hand from the org
// field as read on 2026-11-01.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse } from "yaml";

import { labelsAfter, statusMirror, writeStatus } from "./write-status.mjs";

const CONFIG = parse(readFileSync(new URL("../../../docs/conventions/pr-pipeline.yaml", import.meta.url), "utf8")).models[
  "issue-status"
];
const FIELD = 48484079;

// A fake client recording calls, answering a POST with `option` held.
function fake(answer = (body) => [{ issue_field_id: FIELD, single_select_option: { id: 84879220, name: body.issue_field_values[0].value } }]) {
  const calls = [];
  const github = async (method, path, body, headers) => {
    calls.push({ method, path, body, headers });
    if (answer instanceof Error) {
      throw answer;
    }
    return answer(body);
  };
  return { calls, github };
}

const write = (github, labels, extra = {}) => {
  const lines = [];
  const result = writeStatus({ github, repository: "o/r", number: 7, labels, config: CONFIG, log: (line) => lines.push(line), ...extra });
  return result.then((value) => ({ ...value, lines }));
};

test("a label set POSTs its collapsed state's option name to the Work status field", async () => {
  const { calls, github } = fake();
  const result = await write(github, [{ name: "agent-ready" }, { name: "priority: high" }]);
  assert.equal(result.outcome, "written");
  assert.deepEqual(calls, [
    {
      method: "POST",
      path: "/repos/o/r/issues/7/issue-field-values",
      body: { issue_field_values: [{ field_id: FIELD, value: "agent-ready" }] },
      headers: { "X-GitHub-Api-Version": "2026-03-10" },
    },
  ]);
  assert.deepEqual(result.lines, []);
});

test("stacked labels write the first state in order, and no state label writes needs-triage", async () => {
  const stacked = fake(() => [{ issue_field_id: FIELD, single_select_option: { id: 86380005 } }]);
  await write(stacked.github, ["needs-human", "agent-ready", "status: ready"]);
  assert.equal(stacked.calls[0].body.issue_field_values[0].value, "needs-human");
  const bare = fake(() => [{ issue_field_id: FIELD, single_select_option: { id: 84879216 } }]);
  assert.equal((await write(bare.github, [])).outcome, "written");
  assert.equal(bare.calls[0].body.issue_field_values[0].value, "needs-triage");
});

test("never PUT or DELETE, whatever the labels", async () => {
  for (const labels of [[], ["needs-human"], ["status: confirmed"], ["admission-deferred"]]) {
    const { calls, github } = fake(() => []);
    await write(github, labels);
    assert.deepEqual(
      calls.map(({ method }) => method),
      ["POST"],
    );
  }
});

test("a current value that already matches skips the write", async () => {
  const { calls, github } = fake();
  const result = await write(github, ["agent-ready"], { current: 84879220 });
  assert.equal(result.outcome, "unchanged");
  assert.equal(calls.length, 0);
});

test("a current value that differs, or none, writes", async () => {
  for (const current of [86380003, null]) {
    const { calls, github } = fake();
    assert.equal((await write(github, ["agent-ready"], { current })).outcome, "written");
    assert.equal(calls.length, 1);
  }
});

test("a failed POST is a warning, never a throw", async () => {
  const { github } = fake(new Error("HTTP 403 Resource not accessible by integration"));
  const result = await write(github, ["agent-ready"]);
  assert.equal(result.outcome, "failed");
  assert.equal(result.lines.length, 1);
  assert.match(result.lines[0], /^::warning title=work-status::#7's Work status field not written: HTTP 403/);
});

test("GitHub keeping another option warns as drift", async () => {
  const { github } = fake(() => [{ issue_field_id: FIELD, single_select_option: { id: 84879216 } }]);
  const result = await write(github, ["agent-ready"]);
  assert.equal(result.outcome, "failed");
  assert.match(result.lines[0], /kept option 84879216 for `agent-ready`, not 84879220/);
});

test("no models.issue-status writes nothing", async () => {
  const { calls, github } = fake();
  const result = await writeStatus({ github, repository: "o/r", number: 7, labels: ["agent-ready"], config: null });
  assert.equal(result.outcome, "unset");
  assert.equal(calls.length, 0);
});

test("statusMirror over this checkout's config writes through the client it was given", async () => {
  const { calls, github } = fake();
  const lines = [];
  const mirror = await statusMirror({
    env: { BASE_PATH: new URL("../../..", import.meta.url).pathname },
    github,
    repository: "o/r",
    log: (line) => lines.push(line),
  });
  assert.equal((await mirror(7, { add: ["agent-ready"] })).outcome, "written");
  assert.equal(calls[0].path, "/repos/o/r/issues/7/issue-field-values");
  assert.deepEqual(lines, []);
});

test("statusMirror with no readable config warns once and its mirror writes nothing", async () => {
  const { calls, github } = fake();
  const lines = [];
  const mirror = await statusMirror({ env: { BASE_PATH: "/nonexistent-base" }, github, repository: "o/r", log: (line) => lines.push(line) });
  assert.equal((await mirror(7, { add: ["agent-ready"] })).outcome, "failed");
  assert.equal(calls.length, 0);
  assert.equal(lines.length, 1);
  assert.match(lines[0], /^::warning title=work-status::models.issue-status could not be read/);
});

const mirrorOver = (github) =>
  statusMirror({ env: { BASE_PATH: new URL("../../..", import.meta.url).pathname }, github, repository: "o/r", log: () => {} });

test("statusMirror writes nothing for a change that leaves the label set as it was", async () => {
  const { calls, github } = fake();
  const mirror = await mirrorOver(github);
  assert.equal((await mirror(7, { had: [{ name: "Agent-Ready" }], add: ["agent-ready"], remove: ["status: ready"] })).outcome, "unchanged");
  assert.equal(calls.length, 0);
});

test("statusMirror skips an option it already wrote for the issue in this process", async () => {
  const { calls, github } = fake();
  const mirror = await mirrorOver(github);
  assert.equal((await mirror(7, { add: ["agent-ready"] })).outcome, "written");
  assert.equal((await mirror(7, { had: ["agent-ready"], add: ["priority: high"] })).outcome, "unchanged");
  assert.equal((await mirror(8, { add: ["agent-ready"] })).outcome, "written");
  assert.equal(calls.length, 2);
});

test("labelsAfter adds, removes and dedupes without case", () => {
  assert.deepEqual(labelsAfter([{ name: "Status: Ready" }, "bug"], ["BUG", "agent-ready"], ["status: ready"]), ["bug", "agent-ready"]);
});
