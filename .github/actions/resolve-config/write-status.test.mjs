// The Work status writer over the live models.issue-status: one POST of the
// state's option name, checked against the mapped option id; a write that
// does not land throws, so the caller's run fails rather than leave the field
// wrong. Option ids are written by hand from the org field.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse } from "yaml";

import { StatusWriteError, statusWriter, writeState } from "./write-status.mjs";

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
  assert.deepEqual(calls[0].options, { resendOnce: true }, "setting one option is safe to send twice, so a 5xx is resent once");
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

test("statusWriter set with keepHold leaves a listed human's hold and replaces any other state", async () => {
  const human = 153232337;
  const app = 337595936;
  const actionsBot = 41898282;
  const person = fieldWorld(86380005, human);
  assert.deepEqual(await (await writerOver(person.github)).set(7, "needs-triage", { keepHold: true }), { outcome: "held", state: "needs-human" });
  assert.equal(person.posts().length, 0, "a person's needs-human is never replaced");
  for (const [why, w] of [
    ["needs-owner-decision the lanes App set", fieldWorld(84879218, app)],
    ["needs-human a bot-setter set", fieldWorld(86380005, actionsBot)],
    ["a person's confirmed, no hold", fieldWorld(86380002, human)],
    ["unset", fieldWorld(null)],
  ]) {
    assert.equal((await (await writerOver(w.github)).set(7, "needs-triage", { keepHold: true })).outcome, "written", why);
    assert.equal(w.posts().length, 1, why);
  }
  const written = fieldWorld(86380005, human);
  const { set } = await writerOver(written.github);
  await set(7, "ready");
  assert.equal((await set(7, "deferred", { keepHold: true })).outcome, "written", "an issue this process wrote is not read again");
  assert.equal((await set(8, "ready")).outcome, "written", "without keepHold the field is not read");
  assert.deepEqual(written.posts().map(([, path]) => path), ["/repos/o/r/issues/7/issue-field-values", "/repos/o/r/issues/7/issue-field-values", "/repos/o/r/issues/8/issue-field-values"]);
});

test("statusWriter set with keepHold and releases replaces only the person's hold it releases", async () => {
  const human = 153232337;
  const answered = fieldWorld(84879218, human);
  assert.equal((await (await writerOver(answered.github)).set(7, "needs-triage", { keepHold: true, releases: "needs-owner-decision" })).outcome, "written", "the answered needs-owner-decision is released");
  assert.equal(answered.posts().length, 1);
  const other = fieldWorld(86380005, human);
  assert.deepEqual(await (await writerOver(other.github)).set(7, "needs-triage", { keepHold: true, releases: "needs-owner-decision" }), { outcome: "held", state: "needs-human" });
  assert.equal(other.posts().length, 0, "a different person's hold set meanwhile stands");
});

test("statusWriter set with keepHold throws and writes nothing when the field cannot be read", async () => {
  const calls = [];
  const github = async (method, path) => {
    calls.push([method, path]);
    return { message: "Not Found" };
  };
  const { set } = await writerOver(github);
  await assert.rejects(() => set(7, "needs-triage", { keepHold: true }), (error) => error instanceof StatusWriteError && /could not be read/.test(error.message));
  assert.ok(!calls.some(([method, path]) => method === "POST" && path.endsWith("/issue-field-values")));
});

test("statusWriter with an unreadable trusted-actor list still writes a plain set, and throws on every field read", async () => {
  const w = fieldWorld(null);
  const { set, leaveAgentReady } = await writerOver(w.github, { BASE_PATH: ROOT, TRUSTED_ACTORS_PATH: "/nonexistent-trusted-actors.json" });
  assert.equal((await set(7, "needs-human")).outcome, "written", "a plain set needs only the config");
  await assert.rejects(() => set(8, "needs-triage", { keepHold: true }), (error) => error instanceof StatusWriteError && /could not be read/.test(error.message));
  await assert.rejects(() => leaveAgentReady(9, "needs-triage"), StatusWriteError);
  assert.deepEqual(w.posts().map(([, path]) => path), ["/repos/o/r/issues/7/issue-field-values"]);
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
