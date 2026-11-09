// models.issue-status: the label collapse and the Work status field reader,
// over the live config. Expected values are written by hand: the option ids
// from the org field as read on 2026-11-01, and the label table and collapse
// order from the owner decision Q-WS (architecture owner-decisions; Refs #7577).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse } from "yaml";

import { checkStatus, collapseStatus, issueStatus as readStatus, StatusDisagreement, statusOption } from "./issue-status.mjs";
import { Rejection } from "./resolve.mjs";

const CONFIG = parse(readFileSync(new URL("../../../docs/conventions/pr-pipeline.yaml", import.meta.url), "utf8")).models[
  "issue-status"
];
const FIELD = 48484079;
// A listed human in the live trusted-actor list, an account not on it, and
// the lanes App.
const TRUSTED = JSON.parse(readFileSync(new URL("../../standards/trusted-actors/trusted-actors.json", import.meta.url), "utf8"));
const LISTED = 153232337;
const UNLISTED = 42;
const issueStatus = (fieldValues, setter = LISTED) =>
  readStatus({ fieldValues, fieldSetters: Object.fromEntries(fieldValues.map(({ field }) => [field, setter])) }, CONFIG, TRUSTED);
const OPTIONS = {
  "needs-triage": 84879216,
  "needs-reporter-info": 84879217,
  "needs-owner-decision": 84879218,
  "needs-spec": 84879219,
  "agent-ready": 84879220,
  confirmed: 86380002,
  ready: 86380003,
  deferred: 86380004,
  "needs-human": 86380005,
};

for (const [label, state] of [
  ["needs-triage", "needs-triage"],
  ["needs-reporter-info", "needs-reporter-info"],
  ["needs-spec", "needs-spec"],
  ["agent-ready", "agent-ready"],
  ["status: confirmed", "confirmed"],
  ["status: ready", "ready"],
  ["admission-deferred", "deferred"],
  ["needs-human", "needs-human"],
  ["needs-owner-decision", "needs-owner-decision"],
]) {
  test(`collapse: \`${label}\` alone is ${state}`, () => {
    assert.equal(collapseStatus([label], CONFIG), state);
  });
}

for (const [why, labels, state] of [
  ["no label", [], "needs-triage"],
  ["only labels that are no state", ["bug", "priority: high", "host-run"], "needs-triage"],
  ["needs-owner-decision with agent-ready", ["agent-ready", "needs-owner-decision"], "needs-owner-decision"],
  ["mixed-case labels", ["Status: Ready", "Agent-Ready"], "agent-ready"],
  ["status: ready with agent-ready", ["status: ready", "agent-ready"], "agent-ready"],
  ["needs-human with every other state", ["needs-triage", "status: confirmed", "status: ready", "admission-deferred", "agent-ready", "needs-reporter-info", "needs-spec", "needs-owner-decision", "needs-human"], "needs-human"],
  ["needs-human with agent-ready", ["agent-ready", "needs-human"], "needs-human"],
  ["needs-decision over needs-spec and needs-info", ["needs-reporter-info", "needs-spec", "needs-owner-decision"], "needs-owner-decision"],
  ["needs-spec over needs-info", ["needs-reporter-info", "needs-spec"], "needs-spec"],
  ["needs-info over agent-ready", ["agent-ready", "needs-reporter-info"], "needs-reporter-info"],
  ["agent-ready over admission-deferred", ["admission-deferred", "agent-ready"], "agent-ready"],
  ["admission-deferred over status: ready", ["status: ready", "admission-deferred"], "deferred"],
  ["status: ready over status: confirmed", ["status: confirmed", "status: ready"], "ready"],
  ["status: confirmed over needs-triage", ["needs-triage", "status: confirmed"], "confirmed"],
]) {
  test(`collapse: ${why} is ${state}`, () => {
    assert.equal(collapseStatus(labels, CONFIG), state);
  });
}

test("collapse: REST label objects read as their names", () => {
  assert.equal(collapseStatus([{ name: "status: ready" }, { name: "agent-ready" }], CONFIG), "agent-ready");
});

for (const [state, option] of Object.entries(OPTIONS)) {
  test(`read: option ${option} is ${state}, and ${state} writes as it`, () => {
    assert.equal(issueStatus([{ field: 15462270, option: 27053568 }, { field: FIELD, option }]), state);
    assert.equal(statusOption(state, CONFIG), option);
  });
}

test("read: an option the config does not map fails closed", () => {
  assert.throws(
    () => issueStatus([{ field: FIELD, option: 99999999 }]),
    (error) => error instanceof Rejection && error.code === "unmapped-status" && error.message.includes("99999999"),
  );
});

test("read: an issue with no Work status value reads null", () => {
  assert.equal(issueStatus([]), null);
  assert.equal(issueStatus([{ field: 15462270, option: 27053568 }]), null);
});

// A row with no option fails like issueDimensions does with one.
test("read: a trusted row with no option fails closed", () => {
  assert.throws(() => issueStatus([{ field: FIELD, option: null }]), (error) => error instanceof Rejection && error.code === "unmapped-status");
});

test("read: a value no trusted account set reads null, mapped or not", () => {
  assert.equal(issueStatus([{ field: FIELD, option: 84879220 }], UNLISTED), null);
  assert.equal(issueStatus([{ field: FIELD, option: 99999999 }], UNLISTED), null);
  assert.equal(issueStatus([{ field: FIELD, option: 84879220 }], null), null);
});

test("write: a state no option maps is rejected", () => {
  assert.throws(() => statusOption("blocked", CONFIG), (error) => error instanceof Rejection && error.code === "undefined-status");
});

// The owner's rule for Work status bot setters: the job token's bot and
// the melodic- Apps count for every state but agent-ready; third-party bots
// never count; agent-ready counts only from a listed human or the lanes App.
const ACTIONS_BOT = 41898282;
const MELODIC_AI = 288071998;
const CLAUDE_BOT = 209825114;
const LANES_APP = 337595936;
const BOT_SETTERS = [41898282, 300666570, 288071998, 296023097, 300690090, 302525172, 315045210, 337859524];

test("read: github-actions[bot] setting needs-human reads needs-human, and melodic-ai[bot] setting confirmed reads confirmed", () => {
  assert.equal(issueStatus([{ field: FIELD, option: OPTIONS["needs-human"] }], ACTIONS_BOT), "needs-human");
  assert.equal(issueStatus([{ field: FIELD, option: OPTIONS.confirmed }], MELODIC_AI), "confirmed");
});

test("read: every bot-setter counts for every state but agent-ready, which reads null", () => {
  assert.deepEqual(CONFIG["bot-setters"].map((entry) => entry.id), BOT_SETTERS);
  for (const setter of BOT_SETTERS) {
    for (const [state, option] of Object.entries(OPTIONS)) {
      assert.equal(issueStatus([{ field: FIELD, option }], setter), state === "agent-ready" ? null : state, `${setter} ${state}`);
    }
  }
});

test("read: a third-party bot's value reads null, whatever the state", () => {
  for (const [state, option] of Object.entries(OPTIONS)) {
    assert.equal(issueStatus([{ field: FIELD, option }], CLAUDE_BOT), null, state);
  }
});

test("read: a listed human and the lanes App setting agent-ready read agent-ready", () => {
  assert.equal(issueStatus([{ field: FIELD, option: OPTIONS["agent-ready"] }], LISTED), "agent-ready");
  assert.equal(issueStatus([{ field: FIELD, option: OPTIONS["agent-ready"] }], LANES_APP), "agent-ready");
});

test("read: a bot-setter's option no entry maps fails closed, and a bot-setter with no value reads null", () => {
  assert.throws(
    () => issueStatus([{ field: FIELD, option: 99999999 }], ACTIONS_BOT),
    (error) => error instanceof Rejection && error.code === "unmapped-status" && error.message.includes("99999999"),
  );
  assert.equal(issueStatus([{ field: 15462270, option: 27053568 }], ACTIONS_BOT), null);
});

const rejectsSetters = (setters, text) =>
  assert.throws(
    () => checkStatus({ ...CONFIG, "bot-setters": setters }, undefined),
    (error) => error instanceof Rejection && error.code === "undefined-status" && error.message.includes(text),
    text,
  );

test("check: the live bot-setters pass, and so does a config with none", () => {
  checkStatus(CONFIG, undefined);
  checkStatus({ ...CONFIG, "bot-setters": undefined }, undefined);
});

test("check: a third-party bot, the lanes App, a wrong id or login, and a repeated id are rejected", () => {
  const actions = { id: ACTIONS_BOT, login: "github-actions[bot]" };
  rejectsSetters([actions, { id: CLAUDE_BOT, login: "claude[bot]" }], "claude[bot]");
  rejectsSetters([{ id: 49699333, login: "dependabot[bot]" }], "dependabot[bot]");
  rejectsSetters([{ id: 199161495, login: "cursoragent" }], "cursoragent");
  rejectsSetters([{ id: LANES_APP, login: "melodic-automation-lanes[bot]" }], "other than the lanes App");
  rejectsSetters([{ id: 1, login: "github-actions[bot]" }], "github-actions[bot] is 41898282");
  rejectsSetters([{ id: ACTIONS_BOT, login: "melodic-ai[bot]" }], "github-actions[bot] is 41898282");
  rejectsSetters([actions, { id: MELODIC_AI, login: "melodic-ai[bot]" }, { id: MELODIC_AI, login: "melodic-ai[bot]" }], `id ${MELODIC_AI} twice`);
});

// The trusted-actor list may drop or rename a melodic- bot before the config
// follows: that entry stops counting, so its value reads as unset and the
// labels decide, and the config still loads.
test("read: a melodic- bot-setter the trusted-actor list no longer holds as that bot is ignored, not rejected", () => {
  const dropped = { ...TRUSTED, actors: TRUSTED.actors.filter((actor) => actor.id !== MELODIC_AI) };
  const renamed = { ...TRUSTED, actors: TRUSTED.actors.map((actor) => (actor.id === MELODIC_AI ? { ...actor, login: "melodic-ai-2[bot]" } : actor)) };
  const row = [{ field: FIELD, option: OPTIONS["needs-human"] }];
  const setters = { [FIELD]: MELODIC_AI };
  for (const [why, list] of [["dropped", dropped], ["renamed", renamed], ["no list", undefined]]) {
    checkStatus(CONFIG, undefined);
    assert.equal(readStatus({ fieldValues: row, fieldSetters: setters }, CONFIG, list), null, why);
  }
  assert.equal(readStatus({ fieldValues: row, fieldSetters: setters }, CONFIG, TRUSTED), "needs-human");
  // github-actions[bot] is not on the list and counts without it.
  assert.equal(readStatus({ fieldValues: row, fieldSetters: { [FIELD]: ACTIONS_BOT } }, CONFIG, { actors: [] }), "needs-human");
});

// The value (REST) and setter (GraphQL) are separate reads; `fieldNames`
// carries the option the newest event left, and a disagreement throws.
test("read: a value the newest field event names differently throws, for any setter", () => {
  const fieldValues = [{ field: FIELD, option: OPTIONS["needs-human"] }];
  for (const setter of [LISTED, LANES_APP, ACTIONS_BOT]) {
    const fieldSetters = { [FIELD]: setter };
    assert.throws(() => readStatus({ fieldValues, fieldSetters, fieldNames: { [FIELD]: "needs-triage" } }, CONFIG, TRUSTED), /holds option 86380005, but its newest field event set `needs-triage`/, setter);
    assert.equal(readStatus({ fieldValues, fieldSetters, fieldNames: { [FIELD]: "needs-human" } }, CONFIG, TRUSTED), "needs-human", setter);
    assert.equal(readStatus({ fieldValues, fieldSetters, fieldNames: { [FIELD]: null } }, CONFIG, TRUSTED), "needs-human", `${setter}, no name`);
  }
});

test("check: field-events-since must be a real ISO UTC time, and may be unset", () => {
  checkStatus({ ...CONFIG, "field-events-since": "2026-11-07T12:00:00Z" }, undefined);
  checkStatus({ ...CONFIG, "field-events-since": undefined }, undefined);
  for (const since of ["2026-13-01T00:00:00Z", "2026-02-30T00:00:00Z", "yesterday", "2026-11-07T12:00:00+01:00", "2026-11-07", 20261107]) {
    assert.throws(
      () => checkStatus({ ...CONFIG, "field-events-since": since }, undefined),
      (error) => error instanceof Rejection && error.code === "undefined-status" && error.message.includes("field-events-since"),
      String(since),
    );
  }
});

// With `fieldEvents` (resolve-config.mjs fieldEvents, oldest first), the
// newest event whose setter counts for the value it set decides; an uncounted
// change neither sets nor clears. The REST value holds the newest write.
const set = (actorId, to) => ({ field: String(FIELD), removed: false, actorId, to });
const removal = (actorId) => ({ field: String(FIELD), removed: true, actorId, to: null });
const fromEvents = (fieldEvents, now) =>
  readStatus({ fieldValues: now === undefined ? [] : [{ field: FIELD, option: OPTIONS[now] }], fieldSetters: {}, fieldEvents }, CONFIG, TRUSTED);

test("events: claude[bot] setting ready over a person's needs-human leaves needs-human", () => {
  assert.equal(fromEvents([set(LISTED, "needs-human"), set(CLAUDE_BOT, "ready")], "ready"), "needs-human");
});

test("events: an unlisted user removing a person's needs-human leaves needs-human", () => {
  assert.equal(fromEvents([set(LISTED, "needs-human"), removal(UNLISTED)]), "needs-human");
});

test("events: a counted removal clears a person's needs-human", () => {
  assert.equal(fromEvents([set(LISTED, "needs-human"), removal(ACTIONS_BOT)]), null);
});

test("events: only uncounted events read null", () => {
  assert.equal(fromEvents([set(CLAUDE_BOT, "needs-human"), set(UNLISTED, "ready")], "ready"), null);
});

test("events: a REST value the newest event does not name throws", () => {
  assert.throws(() => fromEvents([set(LISTED, "ready")], "needs-human"), /but its newest field event set `ready`/);
  assert.equal(fromEvents([set(LISTED, "needs-human")], "needs-human"), "needs-human");
});

test("events: github-actions[bot] setting agent-ready over a person's ready leaves ready", () => {
  assert.equal(fromEvents([set(LISTED, "ready"), set(ACTIONS_BOT, "agent-ready")], "agent-ready"), "ready");
});

test("events: a newest set with no REST value, or a newest removal over one, throws", () => {
  assert.throws(() => fromEvents([set(LISTED, "needs-human")]), /holds no value, but its newest field event set `needs-human`/);
  assert.throws(() => fromEvents([set(LISTED, "needs-human"), removal(LISTED)], "needs-human"), /but its newest field event removed it/);
});

test("events: a full window with no counted setter throws; one with a counted setter decides", () => {
  const full = (fieldEvents, now) =>
    readStatus({ fieldValues: [{ field: FIELD, option: OPTIONS[now] }], fieldSetters: {}, fieldEvents, fieldEventsFull: true }, CONFIG, TRUSTED);
  assert.throws(() => full([set(UNLISTED, "ready")], "ready"), /no counted setter among its newest field events/);
  assert.equal(full([set(LISTED, "needs-human"), set(UNLISTED, "ready")], "ready"), "needs-human");
});

test("read: the two reads disagreeing throws StatusDisagreement, so a reader may read again", () => {
  assert.throws(() => fromEvents([set(LISTED, "needs-human")]), StatusDisagreement);
  assert.throws(() => fromEvents([set(LISTED, "ready")], "needs-human"), StatusDisagreement);
});
