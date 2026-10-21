// Two runs end to end through detect, planIssues and writePlan against an
// in-memory issue store: for each signal, the first run files one issue, a
// second run with the same evidence writes nothing, and a third with new
// evidence comments on that issue instead of filing a second.
import assert from "node:assert/strict";
import { test } from "node:test";

import { planIssues, readMarker } from "./issues.mjs";
import { writePlan } from "./monitor.mjs";
import { detect } from "./signals.mjs";

const now = new Date("2026-10-19T16:41:00Z");
const windowStart = new Date("2026-10-19T15:36:00Z");
const url = (id) => `https://github.com/o/r/actions/runs/${id}`;
const sweep = (results, extra = {}) => ({
  runId: 9,
  url: url(9),
  live: true,
  startedAt: "2026-10-19T16:30:00Z",
  candidates: 10,
  results,
  ...extra,
});
const denied = (id, message) => ({ id, url: url(id), name: "pr-merge", event: "schedule", annotations: [{ level: "failure", message }] });
const red = (message) => ({
  id: 7,
  url: url(7),
  sha: "abc",
  event: "workflow_dispatch",
  conclusion: "failure",
  failedJobs: [{ name: "lint", conclusion: "failure", annotations: [{ level: "failure", message }] }],
});
const ejection = (id) => ({ id, url: url(id), pr: id, workflow: "pr-require-checks", createdAt: "2026-10-19T15:00:00Z", failedSteps: ["lint / Run"] });
const incident = (status) => ({
  id: "8tzbpcnl75jp",
  name: "Degraded availability for GitHub Actions",
  status,
  created_at: "2026-10-19T15:49:25Z",
  shortlink: "https://stspg.io/x",
  components: ["Actions"],
});
const held = (pr) => ({ pr, enqueued: false, merged: false, reason: "risk:MED", updatedAt: "2026-10-18T06:00:00Z" });

// [signal, first evidence, new evidence]
const CASES = [
  ["1 main red", { mainRun: red("not ok 1 - a") }, { mainRun: red("not ok 1 - b") }],
  [
    "2 ceiling",
    { budgetReadings: [{ phase: "end", name: "lane", used: 4706, limit: 5200, remaining: 494 }] },
    { now: new Date("2026-10-20T00:41:00Z"), windowStart: new Date("2026-10-19T23:36:00Z"), budgetReadings: [{ phase: "end", name: "lane", used: 5000, limit: 5200, remaining: 200 }] },
  ],
  [
    "3 throttling",
    { failedRuns: [denied(1, "lane-token-denied: the broker answered 500 with reason unknown")] },
    { failedRuns: [denied(2, "lane-token-denied: the broker answered 500 with reason unknown")] },
  ],
  ["4 merge-queue ejections", { mergeGroupFailures: [ejection(1), ejection(2), ejection(3)] }, { mergeGroupFailures: [ejection(1), ejection(2), ejection(3), ejection(4)] }],
  ["5 held PRs", { sweep: sweep([held(1)]) }, { sweep: sweep([held(1), held(2)]) }],
  [
    "6 report-only audit",
    { audits: [{ workflow: "maintenance-check-upstream-drift", run: { id: 5, url: url(5), conclusion: "failure", createdAt: "x", failedJobs: [] } }] },
    { audits: [{ workflow: "maintenance-check-upstream-drift", run: { id: 6, url: url(6), conclusion: "failure", createdAt: "y", failedJobs: [] } }] },
  ],
  [
    "7 platform incident",
    { status: { components: [], incidents: [incident("investigating")] } },
    { status: { components: [], incidents: [incident("identified")] } },
  ],
  [
    "8 throughput",
    { sweep: sweep([]), laneMerges: { lastMergedAt: "2026-10-19T10:00:00Z" } },
    { sweep: sweep([]), laneMerges: { lastMergedAt: "2026-10-19T09:00:00Z" } },
  ],
];

function store() {
  const issues = [];
  const calls = [];
  const call = async (method, path, body) => {
    calls.push(`${method} ${path}`);
    if (method === "POST" && path.endsWith("/issues")) {
      const issue = { number: 100 + issues.length, state: "open", state_reason: null, ...body };
      issues.push(issue);
      return issue;
    }
    const number = Number(/issues\/(\d+)/.exec(path)[1]);
    const issue = issues.find((i) => i.number === number);
    if (method === "PATCH") Object.assign(issue, body);
    if (method === "POST" && path.endsWith("/labels")) issue.labels = [...new Set([...issue.labels, ...body.labels])];
    if (method === "DELETE") {
      const name = decodeURIComponent(path.split("/labels/")[1]);
      // GitHub answers 404 when the label is not on the issue.
      if (!issue.labels.includes(name)) throw Object.assign(new Error(`DELETE ${path}: HTTP 404`), { status: 404 });
      issue.labels = issue.labels.filter((l) => l !== name);
    }
    return {};
  };
  return { issues, calls, call };
}

async function runOnce(s, data) {
  const findings = detect({ now, windowStart, ...data });
  const existing = s.issues.filter((i) => readMarker(i.body));
  const plan = planIssues({ findings, existing });
  return writePlan({ plan, existing, call: s.call, repo: "o/r", labels: ["needs-triage"], runUrl: url(900), wait: async () => {} });
}

for (const [signal, first, changed] of CASES) {
  test(`${signal}: files once, stays quiet on the same evidence, updates on new evidence`, async () => {
    const s = store();
    const one = await runOnce(s, first);
    assert.equal(one.filed.length, 1);
    assert.ok(s.issues[0].body.includes(`**Signal:** ${signal}`));
    assert.deepEqual(s.issues[0].labels, ["needs-triage"]);

    const callsBefore = s.calls.length;
    const two = await runOnce(s, first);
    assert.deepEqual(two, { filed: [], updated: [], reopened: [], failed: [] });
    assert.equal(s.calls.length, callsBefore);

    const three = await runOnce(s, changed);
    assert.deepEqual(three.filed, []);
    assert.deepEqual(three.updated, [100]);
    assert.equal(s.issues.length, 1);
    assert.deepEqual(s.calls.slice(-2), ["POST /repos/o/r/issues/100/comments", "PATCH /repos/o/r/issues/100"]);

    const four = await runOnce(s, changed);
    assert.deepEqual(four, { filed: [], updated: [], reopened: [], failed: [] });
  });
}

test("4 merge-queue ejections: the oldest group leaving the 24-hour window writes nothing", async () => {
  const s = store();
  await runOnce(s, { mergeGroupFailures: [ejection(1), ejection(2), ejection(3), ejection(4)] });
  const callsBefore = s.calls.length;
  const aged = await runOnce(s, { mergeGroupFailures: [ejection(2), ejection(3), ejection(4)] });
  assert.deepEqual(aged, { filed: [], updated: [], reopened: [], failed: [] });
  assert.equal(s.calls.length, callsBefore);
});

for (const [signal, first, changed] of CASES) {
  test(`${signal}: new evidence on a completed key comments on, reopens and re-triages its issue`, async () => {
    const s = store();
    await runOnce(s, first);
    Object.assign(s.issues[0], {
      state: "closed",
      state_reason: "completed",
      closed_at: "2026-10-19T16:00:00Z",
      labels: ["agent-ready"],
    });
    const before = s.issues[0].body.split("\n").slice(1);

    const again = await runOnce(s, changed);
    assert.deepEqual(again, { filed: [], updated: [], reopened: [100], failed: [] });
    assert.equal(s.issues.length, 1);
    assert.deepEqual(s.calls.slice(-4), [
      "POST /repos/o/r/issues/100/comments",
      "POST /repos/o/r/issues/100/labels",
      "DELETE /repos/o/r/issues/100/labels/agent-ready",
      "PATCH /repos/o/r/issues/100",
    ]);
    assert.deepEqual(s.issues[0].labels, ["needs-triage"]);
    assert.equal(s.issues[0].state, "open");
    assert.equal(s.issues[0].state_reason, "reopened");
    assert.deepEqual(s.issues[0].body.split("\n").slice(1), before);

    const quiet = await runOnce(s, changed);
    assert.deepEqual(quiet, { filed: [], updated: [], reopened: [], failed: [] });
  });
}

test("a reopen of an issue without agent-ready takes the 404 as done, and a 500 is recorded", async () => {
  const s = store();
  await runOnce(s, CASES[2][1]);
  Object.assign(s.issues[0], { state: "closed", state_reason: "completed", labels: [] });
  const order = [];
  const reopened = await writePlan({
    plan: planIssues({ findings: detect({ now, windowStart, ...CASES[2][2] }), existing: [...s.issues] }),
    existing: [...s.issues],
    call: async (method, path, body) => {
      order.push("call");
      return s.call(method, path, body);
    },
    repo: "o/r",
    labels: ["needs-triage"],
    runUrl: url(900),
    wait: async () => order.push("wait"),
  });
  assert.deepEqual(reopened, { filed: [], updated: [], reopened: [100], failed: [] });
  assert.deepEqual(s.issues[0].labels, ["needs-triage"]);
  assert.deepEqual(order, ["wait", "call", "wait", "call", "wait", "call", "wait", "call"]);

  const t = store();
  await runOnce(t, CASES[2][1]);
  Object.assign(t.issues[0], { state: "closed", state_reason: "completed" });
  const oldBody = t.issues[0].body;
  const failing = async (method, path, body) => {
    if (method === "DELETE") throw Object.assign(new Error(`DELETE ${path}: HTTP 500`), { status: 500 });
    return t.call(method, path, body);
  };
  const findings = detect({ now, windowStart, ...CASES[2][2] });
  const done = await writePlan({
    plan: planIssues({ findings, existing: [...t.issues] }),
    existing: [...t.issues],
    call: failing,
    repo: "o/r",
    labels: [],
    runUrl: url(900),
    wait: async () => {},
  });
  assert.deepEqual(done.reopened, []);
  assert.deepEqual(done.failed, [{ target: "#100", error: "DELETE /repos/o/r/issues/100/labels/agent-ready: HTTP 500" }]);
  assert.ok(!t.calls.includes("POST /repos/o/r/issues/100/labels"));
  assert.ok(!t.calls.includes("PATCH /repos/o/r/issues/100"));
  assert.equal(t.issues[0].state, "closed");
  assert.equal(t.issues[0].body, oldBody);
  assert.deepEqual(
    planIssues({ findings, existing: [...t.issues] }).reopen.map((r) => r.number),
    [100],
  );
});

test("a key closed as not planned or duplicate writes nothing on new evidence", async () => {
  for (const reason of ["not_planned", "duplicate"]) {
    const s = store();
    await runOnce(s, CASES[2][1]);
    Object.assign(s.issues[0], { state: "closed", state_reason: reason });
    const callsBefore = s.calls.length;
    const muted = await runOnce(s, CASES[2][2]);
    assert.deepEqual(muted, { filed: [], updated: [], reopened: [], failed: [] });
    assert.equal(s.calls.length, callsBefore);
    assert.equal(s.issues[0].state, "closed");
  }
});

test("an update keeps the body below the marker line", async () => {
  const s = store();
  await runOnce(s, CASES[2][1]);
  const before = s.issues[0].body.split("\n").slice(1);
  await runOnce(s, CASES[2][2]);
  assert.deepEqual(s.issues[0].body.split("\n").slice(1), before);
});

test("a failed write is reported and the rest still run", async () => {
  const s = store();
  const failing = async (method, path, body) => {
    if (body?.title?.startsWith("Main red")) throw new Error("POST /repos/o/r/issues: HTTP 422");
    return s.call(method, path, body);
  };
  const findings = detect({ now, windowStart, ...CASES[0][1], ...CASES[3][1] });
  const plan = planIssues({ findings, existing: [] });
  const done = await writePlan({ plan, existing: [], call: failing, repo: "o/r", labels: [], runUrl: url(900), wait: async () => {} });
  assert.equal(done.filed.length, 1);
  assert.deepEqual(done.failed, [{ target: "main-red:lint", error: "POST /repos/o/r/issues: HTTP 422" }]);
});
