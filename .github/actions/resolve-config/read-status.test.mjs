// The Work status reader over the live models.issue-status: a field a trusted
// account set replaces the issue's queue labels with its state's and keeps
// hold labels; a field unset, set by an untrusted account, or unreadable
// leaves the labels as they are. statusEvents merges the field's history into
// the REST events as label events.
import assert from "node:assert/strict";
import { test } from "node:test";

import { collapseStatus, StatusDisagreement } from "./issue-status.mjs";
import { HUMAN_ID, STATUS_CONFIG, STRANGER_ID, TRUSTED_ACTORS, withFields } from "./read-status.fixtures.mjs";
import { DISAGREEMENT_WAIT_MS, fieldStatusSetter, readyWhileDeferred, StatusReadError, statusEvents, statusLabels, statusReader, syntheticFrom } from "./read-status.mjs";

const unexpected = async (method, path) => {
  throw new Error(`unexpected ${method} ${path}`);
};

function reader(fields, extra = {}) {
  const calls = [];
  const fielded = withFields(unexpected, fields);
  const github = async (method, path, body, headers) => {
    calls.push({ method, path, headers });
    return fielded(method, path, body, headers);
  };
  const lines = [];
  const labels = statusReader({ github, repository: "o/r", config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, log: (line) => lines.push(line), ...extra });
  return { labels, lines, calls };
}

test("with no trusted field state, the labels are returned unchanged", () => {
  for (const state of [null, undefined]) {
    assert.deepEqual(statusLabels(state, ["agent-ready", "status: ready"], STATUS_CONFIG), ["agent-ready", "status: ready"]);
  }
});

test("a trusted queue state replaces a stale queue label with its own first label", () => {
  assert.deepEqual(statusLabels("ready", ["status: confirmed", "priority: high"], STATUS_CONFIG), ["priority: high", "status: ready"]);
  assert.deepEqual(statusLabels("needs-triage", ["Status: Ready"], STATUS_CONFIG), ["needs-triage"]);
  assert.deepEqual(statusLabels("deferred", ["status: ready", "admission-deferred"], STATUS_CONFIG), ["admission-deferred"]);
  assert.deepEqual(statusLabels("confirmed", [], STATUS_CONFIG), ["status: confirmed"]);
});

test("a trusted state keeps every hold label, drops a stale agent-ready, and adds a hold's first label once", () => {
  assert.deepEqual(statusLabels("ready", ["needs-human", "agent-ready", "status: confirmed"], STATUS_CONFIG), ["needs-human", "status: ready"]);
  assert.deepEqual(statusLabels("confirmed", ["Agent-Ready"], STATUS_CONFIG), ["status: confirmed"]);
  assert.deepEqual(statusLabels("needs-human", ["status: needs-decision"], STATUS_CONFIG), ["status: needs-decision", "needs-human"]);
  assert.deepEqual(statusLabels("needs-human", ["Needs-Human"], STATUS_CONFIG), ["Needs-Human"]);
  assert.deepEqual(statusLabels("needs-owner-decision", [], STATUS_CONFIG), ["status: needs-decision"]);
});

test("a trusted agent-ready adds the agent-ready label once and drops stale queue labels", () => {
  assert.deepEqual(statusLabels("agent-ready", ["priority: high"], STATUS_CONFIG), ["priority: high", "agent-ready"]);
  assert.deepEqual(statusLabels("agent-ready", ["status: ready", "agent-ready"], STATUS_CONFIG), ["agent-ready"]);
  assert.deepEqual(statusLabels("agent-ready", ["needs-spec"], STATUS_CONFIG), ["needs-spec", "agent-ready"]);
});

// A field holding what the labels collapse to leaves the collapse as it was.
test("a field equal to what the labels collapse to leaves their collapse unchanged", () => {
  const sets = [[], ["priority: high"], ["needs-triage"], ["agent-ready"], ["agent-ready", "needs-spec"], ["status: ready", "admission-deferred"], ["status: confirmed", "status: ready"], ["needs-owner-decision"], ["needs-human", "agent-ready"]];
  for (const names of sets) {
    const state = collapseStatus(names, STATUS_CONFIG);
    assert.equal(collapseStatus(statusLabels(state, names, STATUS_CONFIG), STATUS_CONFIG), state, JSON.stringify(names));
  }
});

test("a deferred issue reads as status: ready too, unless its own labels lost status: ready while deferred", async () => {
  assert.deepEqual(await readyWhileDeferred(["admission-deferred"], ["agent-ready"]), ["admission-deferred", "status: ready"]);
  assert.deepEqual(await readyWhileDeferred(["admission-deferred", "status: ready"], []), ["admission-deferred", "status: ready"]);
  assert.deepEqual(await readyWhileDeferred(["needs-triage"], ["admission-deferred"]), ["needs-triage"]);
  assert.deepEqual(await readyWhileDeferred(["admission-deferred"], ["admission-deferred"]), ["admission-deferred"], "a legacy deferral without status: ready");
  assert.deepEqual(await readyWhileDeferred(["admission-deferred"], ["admission-deferred"], async () => true), ["admission-deferred", "status: ready"], "the field itself at deferred");
});

test("a hold a listed human set is added to the labels, and replaces a stale agent-ready", async () => {
  const { labels, lines, calls } = reader({ 7: { state: "needs-human" } });
  assert.deepEqual(await labels(7, ["agent-ready", "priority: high"]), ["priority: high", "needs-human"]);
  assert.deepEqual(calls.map((call) => `${call.method} ${call.path}`), ["GET /repos/o/r/issues/7/issue-field-values", "POST /graphql"]);
  assert.deepEqual(calls[0].headers, { "X-GitHub-Api-Version": "2026-03-10" });
  assert.deepEqual(lines, []);
});

test("an unset field, or one an untrusted account set, leaves the labels to decide", async () => {
  assert.deepEqual(await reader({}).labels(7, []), []);
  assert.deepEqual(await reader({ 7: { state: "needs-human", setter: STRANGER_ID } }).labels(7, ["agent-ready"]), ["agent-ready"]);
});

// The live bot-setters: github-actions[bot] counts for every state but
// agent-ready, and a third-party bot for none.
test("a hold github-actions[bot] set is added to the labels; its agent-ready, and a third-party bot's hold, leave the labels", async () => {
  const actionsBot = 41898282;
  assert.deepEqual(await reader({ 7: { state: "needs-human", setter: actionsBot } }).labels(7, ["priority: high"]), ["priority: high", "needs-human"]);
  assert.deepEqual(await reader({ 7: { state: "agent-ready", setter: actionsBot } }).labels(7, ["priority: high"]), ["priority: high"]);
  assert.deepEqual(await reader({ 7: { state: "needs-human", setter: 209825114 } }).labels(7, ["priority: high"]), ["priority: high"]);
});

// The value (REST) and its setter (GraphQL events) are two reads: when the
// newest event left another option than the value names, the setter belongs to
// another write, and the read fails rather than miss a hold.
test("a value the newest field event does not name throws StatusReadError", async () => {
  await assert.rejects(
    () => reader({ 7: { state: "needs-human", named: "needs-triage" } }).labels(7, ["priority: high"]),
    (error) => error instanceof StatusReadError && error.number === 7 && /newest field event set `needs-triage`/.test(error.message),
  );
  assert.deepEqual(await reader({ 7: { state: "needs-human", named: "needs-human" } }).labels(7, ["priority: high"]), ["priority: high", "needs-human"]);
});

test("a listed human's hold that claude[bot] then changed is still added to the labels", async () => {
  const event = (newValue, databaseId) => ({ __typename: "IssueFieldChangedEvent", newValue, actor: { databaseId }, issueField: { fullDatabaseId: String(STATUS_CONFIG["field-id"]) } });
  const nodes = [event("needs-human", 11), event("ready", 209825114)];
  const github = async (method, path) =>
    method === "GET"
      ? [{ issue_field_id: STATUS_CONFIG["field-id"], single_select_option: { id: 86380003 } }]
      : { data: { repository: { issue: { timelineItems: { nodes } } } } };
  const labels = statusReader({ github, repository: "o/r", config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, log: () => {} });
  assert.deepEqual(await labels(7, ["priority: high"]), ["priority: high", "needs-human"]);
});

// The labels alone could miss a hold that exists only on the field.
const unreadable = (error) => error instanceof StatusReadError && error.name === "StatusReadError" && error.number === 7;

test("a failed field read throws StatusReadError naming the issue and the cause", async () => {
  const { labels } = reader({ 7: new Error("GET answered 500") });
  await assert.rejects(() => labels(7, ["agent-ready"]), (error) => unreadable(error) && error.message === "#7's Work status could not be read: GET answered 500");
});

test("an unset models.issue-status reads nothing", async () => {
  const { labels, lines, calls } = reader({ 7: { state: "needs-human" } }, { config: null });
  assert.deepEqual(await labels(7, ["agent-ready"]), ["agent-ready"]);
  assert.deepEqual(await labels(7, ["needs-triage", "status: ready"]), ["needs-triage", "status: ready"]);
  assert.deepEqual(calls, []);
  assert.deepEqual(lines, []);
});

test("an unreadable trusted-actor list warns once and makes every read throw, naming the load cause", async () => {
  const { labels, lines, calls } = reader({ 7: { state: "needs-human" } }, { trustedActors: undefined, env: { TRUSTED_ACTORS_PATH: "/nonexistent/trusted.json" } });
  const loadFailed = (number) => (error) => error instanceof StatusReadError && error.number === number && /ENOENT/.test(error.message);
  await assert.rejects(() => labels(7, ["agent-ready"]), loadFailed(7));
  await assert.rejects(() => labels(8, ["agent-ready"]), loadFailed(8));
  await assert.rejects(() => labels.events(7), loadFailed(7));
  assert.deepEqual(calls, []);
  assert.equal(lines.length, 1);
});

test("a base models.issue-status that cannot be loaded makes every read throw, naming the load cause", async () => {
  const { labels, lines, calls } = reader({ 7: { state: "needs-human" } }, { config: undefined, env: { BASE_PATH: "/nonexistent/base" } });
  const loadFailed = (error) => error instanceof StatusReadError && error.number === 7 && /no schema at .* under base-path/.test(error.message);
  await assert.rejects(() => labels(7, ["agent-ready"]), loadFailed);
  await assert.rejects(() => labels.events(7), loadFailed);
  assert.deepEqual(calls, []);
  assert.equal(lines.length, 1);
});

test("each call reads the field fresh, and a read past the limit throws", async () => {
  const fields = { 7: { state: "ready" }, 8: { state: "ready" } };
  const { labels, calls } = reader(fields, { limit: 2 });
  assert.deepEqual(await labels(7, []), ["status: ready"]);
  fields[7] = { state: "needs-human" };
  assert.deepEqual(await labels(7, []), ["needs-human"]);
  await assert.rejects(() => labels(8, []), (error) => error instanceof StatusReadError && error.number === 8 && /limit of 2 field reads/.test(error.message));
  assert.equal(calls.length, 4);
});

test("reader state is the trusted state its newest labels call read, with no second read", async () => {
  const fields = { 7: { state: "deferred" } };
  const { labels, calls } = reader(fields);
  await labels(7, ["admission-deferred"]);
  fields[7] = { state: "needs-human" };
  assert.equal(await labels.state(7), "deferred");
  assert.equal(calls.length, 2, "one field read: the values and the events");
  await labels(7, []);
  assert.equal(await labels.state(7), "needs-human", "a newer labels call's read");
});

test("reader state reads the field once when no labels call has, and is null for an unset or untrusted field", async () => {
  const fields = { 7: { state: "ready" }, 8: { state: "needs-human", setter: STRANGER_ID } };
  const { labels, calls } = reader(fields);
  assert.equal(await labels.state(7), "ready");
  assert.equal(await labels.state(7), "ready");
  assert.equal(calls.length, 2);
  assert.equal(await labels.state(8), null);
  assert.equal(await labels.state(9), null);
  const unset = reader(fields, { config: null });
  assert.equal(await unset.labels.state(7), null);
  assert.deepEqual(unset.calls, []);
});

test("reader state throws StatusReadError as labels does", async () => {
  await assert.rejects(() => reader({ 7: new Error("GET answered 500") }).labels.state(7), (error) => unreadable(error) && /GET answered 500/.test(error.message));
  await assert.rejects(() => reader({ 7: { state: "ready" } }, { limit: 0 }).labels.state(7), (error) => unreadable(error) && /limit of 0 field reads/.test(error.message));
});

// statusEvents: field events (fieldEvents' shape) as REST label events.
const FIELD = String(STATUS_CONFIG["field-id"]);
const PERSON = { actorId: HUMAN_ID, actorLogin: "person", actorType: "User" };
const APP = { actorId: 337595936, actorLogin: "melodic-automation-lanes", actorType: "Bot" };
const change = (at, from, to, who = PERSON, rest = {}) => ({ field: FIELD, removed: false, at, from, to, ...who, ...rest });
const label = (event, name, actor, created_at, id = null) => ({ id, event, label: { name }, actor, created_at });
const personActor = { id: HUMAN_ID, login: "person", type: "User" };
const appActor = { id: 337595936, login: "melodic-automation-lanes[bot]", type: "Bot" };

// `github` answering the REST event list of number 7 with `rest`.
function restEvents(rest, calls = []) {
  return async (method, path) => {
    calls.push(`${method} ${path}`);
    if (method === "GET" && path === "/repos/o/r/issues/7/events?per_page=100&page=1") {
      return rest;
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
}
const eventsOf = (rest, field, extra = {}) =>
  statusEvents({ github: restEvents(rest), repository: "o/r", number: 7, config: STATUS_CONFIG, fieldEvents: async () => field, ...extra });

test("a field change is an unlabeled of the old state's first label, then a labeled of the new one's", () => {
  assert.deepEqual(syntheticFrom(change("2026-11-08T10:00:00Z", "needs-human", "needs-triage"), STATUS_CONFIG), [
    label("unlabeled", "needs-human", personActor, "2026-11-08T10:00:00Z"),
    label("labeled", "needs-triage", personActor, "2026-11-08T10:00:00Z"),
  ]);
  assert.deepEqual(syntheticFrom(change("2026-11-08T10:00:00Z", null, "needs-owner-decision"), STATUS_CONFIG), [
    label("labeled", "status: needs-decision", personActor, "2026-11-08T10:00:00Z"),
  ]);
});

test("a field removal is an unlabeled of the state it held", () => {
  assert.deepEqual(syntheticFrom(change("2026-11-08T10:00:00Z", "confirmed", null, PERSON, { removed: true }), STATUS_CONFIG), [
    label("unlabeled", "status: confirmed", personActor, "2026-11-08T10:00:00Z"),
  ]);
});

test("a bot actor's login gets [bot], as REST names it", () => {
  assert.deepEqual(syntheticFrom(change("2026-11-08T10:00:00Z", null, "ready", APP), STATUS_CONFIG), [label("labeled", "status: ready", appActor, "2026-11-08T10:00:00Z")]);
});

test("a change into or out of agent-ready makes no agent-ready event", () => {
  assert.deepEqual(syntheticFrom(change("2026-11-08T10:00:00Z", "deferred", "agent-ready"), STATUS_CONFIG), [
    label("unlabeled", "admission-deferred", personActor, "2026-11-08T10:00:00Z"),
  ]);
  assert.deepEqual(syntheticFrom(change("2026-11-08T10:00:00Z", "agent-ready", "needs-human"), STATUS_CONFIG), [
    label("labeled", "needs-human", personActor, "2026-11-08T10:00:00Z"),
  ]);
  assert.deepEqual(syntheticFrom(change("2026-11-08T10:00:00Z", null, "agent-ready"), STATUS_CONFIG), []);
});

test("bot field events before since are dropped, and a person's before it are kept", async () => {
  const field = [
    change("2026-11-07T11:00:00Z", null, "needs-human", APP),
    change("2026-11-07T11:30:00Z", "needs-human", "needs-triage"),
    change("2026-11-07T13:00:00Z", "needs-triage", "ready", APP),
  ];
  const kept = [
    label("unlabeled", "needs-human", personActor, "2026-11-07T11:30:00Z"),
    label("labeled", "needs-triage", personActor, "2026-11-07T11:30:00Z"),
    label("unlabeled", "needs-triage", appActor, "2026-11-07T13:00:00Z"),
    label("labeled", "status: ready", appActor, "2026-11-07T13:00:00Z"),
  ];
  assert.deepEqual(await eventsOf([], field, { since: "2026-11-07T12:00:00Z" }), kept);
  // With no `since`, the config's field-events-since applies.
  assert.deepEqual(await eventsOf([], field, { config: { ...STATUS_CONFIG, "field-events-since": "2026-11-07T12:00:00Z" } }), kept);
  // A config with no cutoff keeps every field event.
  assert.equal((await eventsOf([], field, { config: { ...STATUS_CONFIG, "field-events-since": undefined } })).length, 5);
});

test("a bot field event exactly at since is kept, and one a second earlier is dropped", async () => {
  const field = [change("2026-11-07T11:59:59Z", null, "needs-human", APP), change("2026-11-07T12:00:00Z", "needs-human", "ready", APP)];
  assert.deepEqual(await eventsOf([], field, { since: "2026-11-07T12:00:00Z" }), [
    label("unlabeled", "needs-human", appActor, "2026-11-07T12:00:00Z"),
    label("labeled", "status: ready", appActor, "2026-11-07T12:00:00Z"),
  ]);
});

test("events merge by time, REST first at the same second, REST by id", async () => {
  const rest = [
    label("labeled", "priority: high", personActor, "2026-11-08T09:00:00Z", 9),
    label("labeled", "bug", personActor, "2026-11-08T10:00:00Z", 5),
    label("labeled", "docs", personActor, "2026-11-08T10:00:00Z", 3),
  ];
  const field = [change("2026-11-08T09:30:00Z", null, "confirmed"), change("2026-11-08T10:00:00Z", "confirmed", "needs-human")];
  assert.deepEqual(
    (await eventsOf(rest, field)).map((event) => `${event.id ?? "field"} ${event.event} ${event.label.name}`),
    ["9 labeled priority: high", "field labeled status: confirmed", "3 labeled docs", "5 labeled bug", "field unlabeled status: confirmed", "field labeled needs-human"],
  );
});

test("an issue with only field history and no label event reads its field changes, other fields ignored", async () => {
  const field = [change("2026-11-08T09:00:00Z", null, "deferred", APP), { ...change("2026-11-08T09:01:00Z", null, "Medium"), field: "15462270" }];
  assert.deepEqual(await eventsOf([], field), [label("labeled", "admission-deferred", appActor, "2026-11-08T09:00:00Z")]);
});

// statusReader's events(number): one field event read serves labels and events.
const node = (typename, at, values, actor) => ({ __typename: typename, createdAt: at, ...values, actor, issueField: { fullDatabaseId: FIELD } });
const historyFields = () => ({
  7: {
    state: "needs-triage",
    nodes: [
      node("IssueFieldAddedEvent", "2026-11-08T09:00:00Z", { value: "needs-human" }, { __typename: "Bot", login: "melodic-automation-lanes", databaseId: 337595936 }),
      node("IssueFieldChangedEvent", "2026-11-08T10:00:00Z", { previousValue: "needs-human", newValue: "needs-triage" }, { __typename: "User", login: "person", databaseId: HUMAN_ID }),
    ],
  },
});
function historyReader(extra = {}) {
  const calls = [];
  const github = withFields(restEvents([], calls), historyFields());
  const counted = async (method, path, body, headers) => {
    if (path === "/graphql" || path.includes("issue-field-values")) {
      calls.push(`${method} ${path}`);
    }
    return github(method, path, body, headers);
  };
  const lines = [];
  const labels = statusReader({ github: counted, repository: "o/r", config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, log: (line) => lines.push(line), ...extra });
  return { labels, calls, lines };
}

test("reader events reuse the field events its labels call read, so the issue's field history is read once", async () => {
  const { labels, calls, lines } = historyReader();
  assert.deepEqual(await labels(7, ["needs-human"]), ["needs-human", "needs-triage"]);
  assert.deepEqual(await labels.events(7), [
    label("labeled", "needs-human", appActor, "2026-11-08T09:00:00Z"),
    label("unlabeled", "needs-human", personActor, "2026-11-08T10:00:00Z"),
    label("labeled", "needs-triage", personActor, "2026-11-08T10:00:00Z"),
  ]);
  assert.deepEqual(calls, ["GET /repos/o/r/issues/7/issue-field-values", "POST /graphql", "GET /repos/o/r/issues/7/events?per_page=100&page=1"]);
  assert.deepEqual(lines, []);
});

test("reader events with no labels call read the field events themselves", async () => {
  const { labels, calls } = historyReader();
  assert.equal((await labels.events(7)).length, 3);
  assert.deepEqual(calls, ["GET /repos/o/r/issues/7/events?per_page=100&page=1", "POST /graphql"]);
});

test("reader events with no config are the REST events alone", async () => {
  const unset = historyReader({ config: null });
  assert.deepEqual(await unset.labels.events(7), []);
  assert.deepEqual(unset.calls, ["GET /repos/o/r/issues/7/events?per_page=100&page=1"]);
});

test("reader events past the limit throw and read nothing", async () => {
  const capped = historyReader({ limit: 0 });
  await assert.rejects(() => capped.labels.events(7), (error) => unreadable(error) && /limit of 0 field reads/.test(error.message));
  assert.deepEqual(capped.calls, []);
});

test("reader events whose field history cannot be read throw StatusReadError", async () => {
  const github = withFields(restEvents([label("labeled", "needs-human", personActor, "2026-11-08T09:00:00Z", 1)]), { 7: new Error("GraphQL answered 502") });
  const failing = async (method, path, body, headers) => {
    if (path === "/graphql") {
      throw new Error("GraphQL answered 502");
    }
    return github(method, path, body, headers);
  };
  const labels = statusReader({ github: failing, repository: "o/r", config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, log: () => {} });
  await assert.rejects(() => labels.events(7), (error) => unreadable(error) && error.message.endsWith("GraphQL answered 502"));
});

// fieldStatusSetter over fakes: `answers` is what each status call does in turn.
function disagreeing(answers) {
  const calls = [];
  let turn = 0;
  const read = {
    github: async (method, path) => {
      calls.push(`${method} ${path}`);
      return [];
    },
    repository: "o/r",
    number: 5,
    config: STATUS_CONFIG,
    trustedActors: TRUSTED_ACTORS,
    fieldEvents: async (_github, _repository, _number, options) => {
      calls.push(`events ${options?.again ? "again" : "first"}`);
      return [];
    },
    issueStatusSetter: () => {
      const answer = answers[turn++];
      if (answer instanceof Error) {
        throw answer;
      }
      return answer;
    },
    sleep: async (ms) => calls.push(`sleep ${ms}`),
  };
  return { read, calls };
}

test("fieldStatusSetter reads both again once when the two reads disagree", async () => {
  const { read, calls } = disagreeing([new StatusDisagreement("raced"), { state: "ready", setter: HUMAN_ID }]);
  assert.deepEqual(await fieldStatusSetter(read), { state: "ready", setter: HUMAN_ID });
  const values = "GET /repos/o/r/issues/5/issue-field-values";
  assert.deepEqual(calls, [values, "events first", `sleep ${DISAGREEMENT_WAIT_MS}`, values, "events again"]);
});

test("fieldStatusSetter throws a second disagreement", async () => {
  const { read } = disagreeing([new StatusDisagreement("raced"), new StatusDisagreement("still")]);
  await assert.rejects(fieldStatusSetter(read), /still/);
});

test("fieldStatusSetter does not read again for any other failure", async () => {
  const { read, calls } = disagreeing([new Error("unmapped")]);
  await assert.rejects(fieldStatusSetter(read), /unmapped/);
  assert.equal(calls.filter((call) => call.startsWith("sleep")).length, 0);
});

test("a reader's re-read of a disagreeing field is not counted against its limit", async () => {
  const fields = { 7: { state: "ready", named: "needs-triage" }, 8: { state: "ready" } };
  const fielded = withFields(unexpected, fields);
  const github = async (method, path, body, headers) => {
    const answer = await fielded(method, path, body, headers);
    if (method === "POST" && body?.variables?.number === 7) {
      fields[7] = { state: "ready" };
    }
    return answer;
  };
  const labels = statusReader({ github, repository: "o/r", config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, log: () => {}, limit: 2, sleep: async () => {} });
  assert.deepEqual(await labels(7, []), ["status: ready"]);
  assert.deepEqual(await labels(8, []), ["status: ready"]);
});
