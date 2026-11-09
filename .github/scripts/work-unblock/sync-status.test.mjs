// Expected values come from the requested behavior: a listed human's added
// queue-state label is written to the Work status field unless the field holds
// a hold; an added agent-ready label writes nothing, since the App's write
// would admit with no admission record and people set agent-ready on the field
// itself; an added hold label and any removal but agent-ready's write nothing;
// agent-ready taken off, a person stopping the lane, writes confirmed, never a
// state that reads as ready, only while the field reads agent-ready; a label's
// absence never resets the field.
import assert from "node:assert/strict";
import { test } from "node:test";

import { STATUS_CONFIG } from "../../actions/resolve-config/read-status.fixtures.mjs";
import * as syncStatus from "./sync-status.mjs";

const { onLabelEvent, translateLabel } = syncStatus;
const REPO = "o/r";

// `field` is the field's trusted state (null for none). Records each write and read.
function harness({ field = null } = {}) {
  const calls = [];
  const status = {
    fieldState: async (number) => {
      calls.push(`FIELD ${number}`);
      return field;
    },
    set: async (number, state) => {
      calls.push(`SET ${number} ${state}`);
      return { outcome: "written", state };
    },
    leaveAgentReady: async (number, state) => {
      calls.push(`LEAVE ${number} ${state}`);
      return field === "agent-ready" ? { outcome: "written", state } : { outcome: "unchanged", state: field };
    },
  };
  return { calls, run: (event) => onLabelEvent({ event, config: STATUS_CONFIG, status }) };
}
const event = (action, name, issue = { number: 5 }) => ({ action, label: { name }, issue });
const writesOf = (calls) => calls.filter((call) => call.startsWith("SET ") || call.startsWith("LEAVE "));

test("a person's added queue-state label writes its state, without case", async () => {
  for (const [label, state] of [
    ["status: ready", "ready"],
    ["Status: Confirmed", "confirmed"],
    ["admission-deferred", "deferred"],
    ["needs-triage", "needs-triage"],
  ]) {
    const { calls, run } = harness({ field: "needs-triage" });
    const result = await run(event("labeled", label));
    assert.deepEqual(writesOf(calls), state === "needs-triage" ? [] : [`SET 5 ${state}`], label);
    assert.equal(result.outcome, state === "needs-triage" ? "unchanged" : "written", label);
  }
});

test("a person's added agent-ready label, in any case, writes nothing and reads nothing", async () => {
  for (const label of ["agent-ready", "Agent-Ready"]) {
    const { calls, run } = harness({ field: "needs-triage" });
    assert.deepEqual(await run(event("labeled", label)), { outcome: "skipped", reason: "agent-ready, which a person sets on the Work status field itself" }, label);
    assert.deepEqual(calls, [], label);
  }
});

test("a person's labeled status: ready writes nothing while the field holds needs-human, or any hold", async () => {
  for (const hold of ["needs-human", "needs-owner-decision", "needs-reporter-info", "needs-spec"]) {
    const { calls, run } = harness({ field: hold });
    const result = await run(event("labeled", "status: ready"));
    assert.deepEqual(writesOf(calls), [], hold);
    assert.deepEqual(result, { outcome: "skipped", reason: `the field holds ${hold}` });
  }
});

test("an added hold label writes nothing and reads nothing", async () => {
  for (const label of ["needs-human", "needs-owner-decision", "needs-reporter-info", "needs-spec"]) {
    const { calls, run } = harness();
    assert.equal((await run(event("labeled", label))).outcome, "skipped", label);
    assert.deepEqual(calls, [], label);
  }
});

test("no status labels with the field at confirmed (App) and unlabeled status: ready writes nothing, and no sweep export remains", async () => {
  const { calls, run } = harness({ field: "confirmed" });
  assert.deepEqual(await run(event("unlabeled", "status: ready")), { outcome: "skipped", reason: "a status label taken off, which only a release path writes" });
  assert.deepEqual(calls, []);
  for (const gone of ["sweep", "sweepSince", "FULL_SWEEP_CRON", "SWEEP_WINDOW_MS", "mirrorIssue"]) {
    assert.equal(gone in syncStatus, false, gone);
  }
});

test("every removal but agent-ready's writes nothing", async () => {
  for (const label of ["needs-human", "needs-owner-decision", "status: confirmed", "admission-deferred", "needs-triage"]) {
    const { calls, run } = harness({ field: "agent-ready" });
    assert.equal((await run(event("unlabeled", label))).outcome, "skipped", label);
    assert.deepEqual(calls, [], label);
  }
});

test("agent-ready taken off by a person leaves the field at confirmed, only while it reads agent-ready", async () => {
  const left = harness({ field: "agent-ready" });
  assert.deepEqual(await left.run(event("unlabeled", "agent-ready")), { outcome: "written", state: "confirmed" });
  assert.deepEqual(writesOf(left.calls), ["LEAVE 5 confirmed"]);
  const other = harness({ field: "needs-human" });
  assert.deepEqual(await other.run(event("unlabeled", "agent-ready")), { outcome: "unchanged", state: "needs-human" });
});

test("a non-status label and a pull request's label event exit with no read or write", async () => {
  for (const e of [event("labeled", "priority: high"), event("labeled", "status: ready", { number: 5, pull_request: { url: "x" } })]) {
    const { calls, run } = harness();
    assert.equal((await run(e)).outcome, "skipped");
    assert.deepEqual(calls, []);
  }
});

test("translateLabel names what each event asks of the field", () => {
  assert.deepEqual(translateLabel(event("labeled", "status: ready"), STATUS_CONFIG), { set: "ready" });
  assert.deepEqual(translateLabel(event("unlabeled", "agent-ready"), STATUS_CONFIG), { leave: true });
  assert.deepEqual(translateLabel(event("labeled", "bug"), STATUS_CONFIG), { why: "not a status label" });
  assert.deepEqual(translateLabel({ label: { name: undefined } }, STATUS_CONFIG), { why: "not a status label" });
});

test("main runs only on an issue label event and stops on the kill switch before any read", async () => {
  const lines = [];
  assert.equal(await syncStatus.main({ env: { KILL_SWITCH: "" }, log: (line) => lines.push(line) }), 0);
  assert.match(lines[0], /kill switch stops this run/);
  assert.equal(await syncStatus.main({ env: { KILL_SWITCH: "proceed", GITHUB_REPOSITORY: REPO, GITHUB_EVENT_NAME: "schedule" }, log: (line) => lines.push(line) }), 1);
  assert.match(lines.at(-1), /^::error title=sync-status::this runs only on an issue label event$/);
});
