// The Work status reader over the live models.issue-status: a field a trusted
// account set replaces the issue's status labels with its state's; a field
// unset, set by an untrusted account, or unreadable leaves the labels as they
// are.
import assert from "node:assert/strict";
import { test } from "node:test";

import { mirroredStatusOf, STATUS_CONFIG, STRANGER_ID, TRUSTED_ACTORS, withFields } from "./read-status.fixtures.mjs";
import { statusLabels, statusReader } from "./read-status.mjs";

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

test("with a status label on the issue, the labels decide and the field only adds a hold they lack", () => {
  assert.deepEqual(statusLabels("agent-ready", ["needs-human", "priority: high"], STATUS_CONFIG), ["needs-human", "priority: high"]);
  assert.deepEqual(statusLabels("ready", ["status: needs-info"], STATUS_CONFIG), ["status: needs-info"]);
  assert.deepEqual(statusLabels("needs-human", ["agent-ready"], STATUS_CONFIG), ["agent-ready", "needs-human"]);
  assert.deepEqual(statusLabels("needs-human", ["status: needs-decision"], STATUS_CONFIG), ["status: needs-decision"]);
  assert.deepEqual(statusLabels("needs-triage", ["Status: Ready"], STATUS_CONFIG), ["Status: Ready"]);
});

test("with no status label, the field decides alone, and its floor adds nothing", () => {
  assert.deepEqual(statusLabels("agent-ready", ["priority: high"], STATUS_CONFIG), ["priority: high", "agent-ready"]);
  assert.deepEqual(statusLabels("needs-owner-decision", [], STATUS_CONFIG), ["status: needs-decision", "needs-owner-decision"]);
  assert.deepEqual(statusLabels("needs-triage", [], STATUS_CONFIG), []);
  assert.deepEqual(statusLabels(null, ["agent-ready"], STATUS_CONFIG), ["agent-ready"]);
});

test("a field equal to what the labels collapse to changes no label set", async () => {
  const sets = [[], ["priority: high"], ["needs-triage"], ["agent-ready"], ["agent-ready", "needs-spec"], ["status: ready", "admission-deferred"], ["status: confirmed", "status: ready"], ["needs-owner-decision"], ["needs-human", "agent-ready"]];
  for (const names of sets) {
    assert.deepEqual(await mirroredStatusOf(1, names), names, JSON.stringify(names));
  }
});

test("a hold a listed human set is added to the labels", async () => {
  const { labels, lines, calls } = reader({ 7: { state: "needs-human" } });
  assert.deepEqual(await labels(7, ["agent-ready"]), ["agent-ready", "needs-human"]);
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
// another write, so the field reads as unset.
test("a value the newest field event does not name reads as unset", async () => {
  assert.deepEqual(await reader({ 7: { state: "needs-human", named: "needs-triage" } }).labels(7, ["priority: high"]), ["priority: high"]);
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

test("a failed read warns and leaves the labels to decide", async () => {
  const { labels, lines } = reader({ 7: new Error("GET answered 500") });
  assert.deepEqual(await labels(7, ["agent-ready"]), ["agent-ready"]);
  assert.match(lines[0], /^::warning title=work-status::#7's Work status field could not be read/);
});

test("an unset models.issue-status reads nothing", async () => {
  const { labels, lines, calls } = reader({ 7: { state: "needs-human" } }, { config: null });
  assert.deepEqual(await labels(7, ["agent-ready"]), ["agent-ready"]);
  assert.deepEqual(calls, []);
  assert.deepEqual(lines, []);
});

test("an unreadable trusted-actor list warns once and reads nothing", async () => {
  const { labels, lines, calls } = reader({ 7: { state: "needs-human" } }, { trustedActors: undefined, env: { TRUSTED_ACTORS_PATH: "/nonexistent/trusted.json" } });
  assert.deepEqual(await labels(7, ["agent-ready"]), ["agent-ready"]);
  assert.deepEqual(await labels(8, ["agent-ready"]), ["agent-ready"]);
  assert.deepEqual(calls, []);
  assert.equal(lines.length, 1);
});

test("each call reads the field fresh, and past the limit the labels decide", async () => {
  const fields = { 7: { state: "ready" }, 8: { state: "ready" } };
  const { labels, calls } = reader(fields, { limit: 2 });
  assert.deepEqual(await labels(7, []), ["status: ready"]);
  fields[7] = { state: "needs-human" };
  assert.deepEqual(await labels(7, []), ["needs-human"]);
  assert.deepEqual(await labels(8, []), []);
  assert.equal(calls.length, 4);
});
