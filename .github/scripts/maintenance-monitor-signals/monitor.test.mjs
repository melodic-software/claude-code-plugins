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
    if (method === "PATCH") Object.assign(issues.find((i) => i.number === number), body);
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
    assert.deepEqual(two, { filed: [], updated: [], failed: [] });
    assert.equal(s.calls.length, callsBefore);

    const three = await runOnce(s, changed);
    assert.deepEqual(three.filed, []);
    assert.deepEqual(three.updated, [100]);
    assert.equal(s.issues.length, 1);
    assert.deepEqual(s.calls.slice(-2), ["POST /repos/o/r/issues/100/comments", "PATCH /repos/o/r/issues/100"]);

    const four = await runOnce(s, changed);
    assert.deepEqual(four, { filed: [], updated: [], failed: [] });
  });
}

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
