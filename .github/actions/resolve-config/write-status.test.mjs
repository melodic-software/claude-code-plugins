// The Work status writer over the live models.issue-status: one POST of the
// collapsed state's option name, checked against the mapped option id; a
// failure warns and returns. Option ids are written by hand from the org
// field as read on 2026-11-01.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse } from "yaml";

import { labelsAfter, statusMirror, StatusWriteError, statusWriter, writeState, writeStatus } from "./write-status.mjs";

const CONFIG = parse(readFileSync(new URL("../../../docs/conventions/pr-pipeline.yaml", import.meta.url), "utf8")).models[
  "issue-status"
];
const FIELD = 48484079;

// A fake client recording calls, answering a POST with `option` held.
function fake(answer = (body) => [{ issue_field_id: FIELD, single_select_option: { id: 84879220, name: body.issue_field_values[0].value } }]) {
  const calls = [];
  const github = async (method, path, body, headers, options) => {
    calls.push({ method, path, body, headers, options });
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
      // Setting the field to one option is safe to send twice, so a 5xx on it
      // is resent once (run 41814435576 lost it to one 502).
      options: { resendOnce: true },
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

// The state writer: the field is written from a state, and a write that does
// not land throws, so the caller's run fails rather than leave the field wrong.
const ROOT = new URL("../../..", import.meta.url).pathname;
const held = (option) => (body) => [{ issue_field_id: FIELD, single_select_option: { id: option, name: body.issue_field_values[0].value } }];

test("writeState POSTs the state's option name once and checks the option GitHub kept", async () => {
  const { calls, github } = fake(held(84879216));
  assert.deepEqual(await writeState({ github, repository: "o/r", number: 7, state: "needs-triage", config: CONFIG }), {
    outcome: "written",
    state: "needs-triage",
    option: 84879216,
  });
  assert.deepEqual(calls.map(({ method, path, body }) => [method, path, body]), [
    ["POST", "/repos/o/r/issues/7/issue-field-values", { issue_field_values: [{ field_id: FIELD, value: "needs-triage" }] }],
  ]);
  assert.equal(calls[0].headers["X-GitHub-Api-Version"], "2026-03-10");
});

test("writeState skips the write when the field already holds the option", async () => {
  const { calls, github } = fake();
  assert.equal((await writeState({ github, repository: "o/r", number: 7, state: "needs-human", config: CONFIG, current: 86380005 })).outcome, "unchanged");
  assert.equal(calls.length, 0);
});

for (const [why, answer, state, config, text] of [
  ["a failed POST", new Error("HTTP 500"), "needs-triage", CONFIG, "HTTP 500"],
  ["GitHub keeping another option", held(84879220), "needs-triage", CONFIG, "kept option 84879220, not 84879216"],
  ["a state no option maps", held(84879216), "blocked", CONFIG, "maps no option to `blocked`"],
  ["no models.issue-status", held(84879216), "needs-triage", null, "is not set"],
]) {
  test(`writeState throws StatusWriteError on ${why}`, async () => {
    const { github } = fake(answer);
    await assert.rejects(
      () => writeState({ github, repository: "o/r", number: 7, state, config }),
      (error) => error instanceof StatusWriteError && error.message.startsWith("#7's Work status field was not set") && error.message.includes(text),
    );
  });
}

// A fake whose field reads `option`, last set by `setter`, and whose POSTs
// answer with the posted state's option.
function fieldWorld(option, setter) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push([method, path, body]);
    if (method === "GET" && path.endsWith("/issue-field-values")) return option === null ? [] : [{ issue_field_id: FIELD, single_select_option: { id: option } }];
    if (method === "POST" && path === "/graphql") {
      const nodes = option === null ? [] : [{ __typename: "IssueFieldAddedEvent", actor: { databaseId: setter }, issueField: { fullDatabaseId: String(FIELD) } }];
      return { data: { repository: { issue: { timelineItems: { nodes } } } } };
    }
    if (method === "POST" && path.endsWith("/issue-field-values")) {
      const state = body.issue_field_values[0].value;
      return [{ issue_field_id: FIELD, single_select_option: { id: Number(Object.keys(CONFIG.options).find((id) => CONFIG.options[id] === state)) } }];
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  const posts = () => calls.filter(([method, path]) => method === "POST" && path.endsWith("/issue-field-values"));
  return { github, posts };
}
const writerOver = (github, env = { BASE_PATH: ROOT }) => statusWriter({ env, github, repository: "o/r" });

test("statusWriter set writes a state once per issue in a process, and skips one `fields` shows", async () => {
  const w = fieldWorld(null);
  const { set } = await writerOver(w.github);
  assert.equal((await set(7, "needs-triage")).outcome, "written");
  assert.equal((await set(7, "needs-triage")).outcome, "unchanged");
  assert.equal((await set(8, "needs-triage", { fields: { [FIELD]: { option: 84879216 } } })).outcome, "unchanged");
  assert.equal((await set(7, "confirmed")).outcome, "written");
  assert.deepEqual(w.posts().map(([, , body]) => body.issue_field_values[0].value), ["needs-triage", "confirmed"]);
});

test("statusWriter leaveAgentReady writes only while the trusted field reads agent-ready", async () => {
  const human = 153232337;
  const ready = fieldWorld(84879220, human);
  assert.equal((await (await writerOver(ready.github)).leaveAgentReady(7, "needs-triage")).outcome, "written");
  assert.equal(ready.posts().length, 1);
  // The field holds a person's hold: taking agent-ready off writes nothing.
  for (const [why, w] of [
    ["needs-human", fieldWorld(86380005, human)],
    ["unset", fieldWorld(null)],
    ["agent-ready from an untrusted bot", fieldWorld(84879220, 209825114)],
    ["agent-ready from github-actions[bot]", fieldWorld(84879220, 41898282)],
  ]) {
    assert.equal((await (await writerOver(w.github)).leaveAgentReady(7, "needs-triage")).outcome, "unchanged", why);
    assert.equal(w.posts().length, 0, why);
  }
});

test("statusWriter with no readable config throws on every call and writes nothing", async () => {
  const w = fieldWorld(null);
  const { set, leaveAgentReady } = await writerOver(w.github, { BASE_PATH: "/nonexistent-base" });
  await assert.rejects(() => set(7, "needs-triage"), (error) => error instanceof StatusWriteError && /could not be read/.test(error.message));
  await assert.rejects(() => leaveAgentReady(7, "needs-triage"), StatusWriteError);
  assert.equal(w.posts().length, 0);
});

test("statusWriter leaveAgentReady throws when the field cannot be read", async () => {
  const github = async () => ({ message: "Not Found" });
  const { leaveAgentReady } = await writerOver(github);
  await assert.rejects(() => leaveAgentReady(7, "needs-triage"), (error) => error instanceof StatusWriteError && /could not be read/.test(error.message));
});
