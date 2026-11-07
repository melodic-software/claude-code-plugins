// Runs end to end through detect, planIssues and writePlan against an
// in-memory issue store: for each signal family, the first run files one
// rolling issue, a run with the same state writes nothing, a new state
// rewrites that issue, a clear run closes it, and the next finding reopens
// the same issue instead of filing a second. Every rewrite takes agent-ready
// off.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { SIGNALS, planIssues, readMarker } from "./issues.mjs";
import { errorLines, readHoldRule, readJobsCarry, writePlan } from "./monitor.mjs";
import { JOBS_ARTIFACT, jobsCarryFile } from "./collect.mjs";
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
const laneCandidate = { pr: 1, enqueued: false, merged: false, reason: "ci-status:failure", updatedAt: "2026-10-19T16:00:00Z" };
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
    "8 throughput",
    { sweep: sweep([laneCandidate]), laneMerges: { lastMergedAt: "2026-10-19T10:00:00Z" }, openLanePulls: [1] },
    { sweep: sweep([laneCandidate]), laneMerges: { lastMergedAt: "2026-10-19T09:00:00Z" }, openLanePulls: [1] },
  ],
];

function store() {
  const issues = [];
  const calls = [];
  const comments = {};
  const call = async (method, path, body) => {
    calls.push(`${method} ${path}`);
    if (method === "POST" && path.endsWith("/issues")) {
      const issue = { number: 100 + issues.length, state: "open", state_reason: null, ...body, labels: [...body.labels] };
      issues.push(issue);
      return issue;
    }
    const number = Number(/issues\/(\d+)/.exec(path)[1]);
    const issue = issues.find((i) => i.number === number);
    if (method === "PATCH") Object.assign(issue, body);
    if (method === "POST" && path.endsWith("/comments")) (comments[number] ??= []).push(body.body);
    if (method === "POST" && path.endsWith("/labels")) issue.labels = [...new Set([...issue.labels, ...body.labels])];
    if (method === "DELETE") {
      const name = decodeURIComponent(path.split("/labels/")[1]);
      // GitHub answers 404 when the label is not on the issue.
      if (!issue.labels.includes(name)) throw Object.assign(new Error(`DELETE ${path}: HTTP 404`), { status: 404 });
      issue.labels = issue.labels.filter((l) => l !== name);
    }
    return {};
  };
  return { issues, calls, comments, call };
}

async function runOnce(s, data, extra = {}) {
  const findings = detect({ now, windowStart, ...data });
  const existing = s.issues.filter((i) => readMarker(i.body));
  const plan = planIssues({ findings, existing, ...extra });
  return writePlan({ plan, call: s.call, repo: "o/r", labels: ["source: factory-monitor"], runUrl: url(900), wait: async () => {} });
}

const nothing = { filed: [], updated: [], reopened: [], closed: [], failed: [] };
const rewrite = (n) => [
  `POST /repos/o/r/issues/${n}/comments`,
  `DELETE /repos/o/r/issues/${n}/labels/agent-ready`,
  `PATCH /repos/o/r/issues/${n}`,
];

for (const [signal, first, changed] of CASES) {
  test(`${signal}: one rolling issue, rewritten on a new state, closed when clear, reopened when it fires again`, async () => {
    const s = store();
    const one = await runOnce(s, first);
    assert.equal(one.filed.length, 1);
    assert.ok(s.issues[0].body.includes(`**Signal:** ${signal}`));
    assert.deepEqual(s.issues[0].labels, ["source: factory-monitor"]);

    const callsBefore = s.calls.length;
    assert.deepEqual(await runOnce(s, first), nothing);
    assert.equal(s.calls.length, callsBefore);

    s.issues[0].labels.push("agent-ready");
    const three = await runOnce(s, changed);
    assert.deepEqual(three.updated, [100]);
    assert.equal(s.issues.length, 1);
    assert.deepEqual(s.calls.slice(-3), rewrite(100));
    assert.deepEqual(s.issues[0].labels, ["source: factory-monitor"]);
    assert.deepEqual(await runOnce(s, changed), nothing);

    const clear = await runOnce(s, {});
    assert.deepEqual(clear.updated, [100]);
    assert.equal(s.issues[0].state, "closed");
    assert.match(s.issues[0].body, /\*\*State:\*\* clear in/);
    assert.deepEqual(await runOnce(s, {}), nothing);

    const back = await runOnce(s, changed);
    assert.deepEqual(back, { ...nothing, reopened: [100] });
    assert.equal(s.issues.length, 1);
    assert.equal(s.issues[0].state, "open");
    assert.deepEqual(s.calls.slice(-3), rewrite(100));
  });
}

test("4 merge-queue ejections: the oldest group leaving the 24-hour window writes nothing", async () => {
  const s = store();
  await runOnce(s, { mergeGroupFailures: [ejection(1), ejection(2), ejection(3), ejection(4)] });
  const callsBefore = s.calls.length;
  const aged = await runOnce(s, { mergeGroupFailures: [ejection(2), ejection(3), ejection(4)] });
  assert.deepEqual(aged, nothing);
  assert.equal(s.calls.length, callsBefore);
});

test("two signals of one family share its issue; two families get two", async () => {
  const s = store();
  const done = await runOnce(s, {
    failedRuns: [denied(1, "lane-token-denied: the broker answered 500 with reason unknown"), denied(2, "HTTP 429 rate limit")],
    mainRun: red("not ok 1 - a"),
  });
  assert.deepEqual(done.filed, [100, 101]);
  assert.deepEqual(
    s.issues.map((i) => i.title),
    ["Monitoring: main red", "Monitoring: throttling"],
  );
  assert.match(s.issues[1].body, /broker-deny:500-unknown/);
  assert.match(s.issues[1].body, /throttle:rate-limited/);
});

test("a platform incident files nothing", async () => {
  const s = store();
  assert.deepEqual(await runOnce(s, { status: { components: [], incidents: [incident("investigating")] } }), nothing);
  assert.deepEqual(s.calls, []);
});

test("an unread source leaves an open issue as it is", async () => {
  const s = store();
  await runOnce(s, CASES[2][1]);
  const callsBefore = s.calls.length;
  assert.deepEqual(await runOnce(s, {}, { unread: new Set(SIGNALS) }), nothing);
  assert.equal(s.calls.length, callsBefore);
  assert.equal(s.issues[0].state, "open");
});

test("open per-key issues close as superseded by the rolling issue filed in the same run", async () => {
  const s = store();
  const legacy = (key, number) => ({
    number,
    state: "open",
    state_reason: null,
    labels: ["needs-triage"],
    body: `<!-- factory-monitor key=${key} fp=0123456789abcdef -->\nold`,
  });
  s.issues.push(legacy("broker-deny:500-unknown", 7), legacy("platform:abc", 8));
  const done = await runOnce(s, CASES[2][1]);
  assert.deepEqual(done.filed, [102]);
  assert.deepEqual(done.closed, [7, 8]);
  assert.equal(s.issues[0].state, "closed");
  assert.equal(s.issues[0].state_reason, "not_planned");
  assert.match(s.comments[7][0], /Superseded by #102/);
  assert.match(s.comments[8][0], /run summary/);
  assert.deepEqual(await runOnce(s, CASES[2][1]), nothing);
});

test("a rewrite of an issue without agent-ready takes the 404 as done; a 500 leaves the old state to retry", async () => {
  const s = store();
  await runOnce(s, CASES[2][1]);
  assert.deepEqual((await runOnce(s, CASES[2][2])).updated, [100]);

  const t = store();
  await runOnce(t, CASES[2][1]);
  const oldBody = t.issues[0].body;
  const failing = async (method, path, body) => {
    if (method === "DELETE") throw Object.assign(new Error(`DELETE ${path}: HTTP 500`), { status: 500 });
    return t.call(method, path, body);
  };
  const findings = detect({ now, windowStart, ...CASES[2][2] });
  const done = await writePlan({
    plan: planIssues({ findings, existing: [...t.issues] }),
    call: failing,
    repo: "o/r",
    labels: [],
    runUrl: url(900),
    wait: async () => {},
  });
  assert.deepEqual(done.updated, []);
  assert.deepEqual(done.failed, [{ target: "#100", error: "DELETE /repos/o/r/issues/100/labels/agent-ready: HTTP 500" }]);
  assert.ok(!t.calls.includes("PATCH /repos/o/r/issues/100"));
  assert.equal(t.issues[0].body, oldBody);
  assert.deepEqual(
    planIssues({ findings, existing: [...t.issues] }).update.map((u) => u.number),
    [100],
  );
});

test("a rewrite takes agent-ready off the label and the Work status field before the PATCH", async () => {
  const s = store();
  await runOnce(s, CASES[2][1]);
  s.issues[0].labels.push("agent-ready");
  const existing = structuredClone(s.issues);
  const log = [];
  const call = async (method, path, body) => (log.push(method), s.call(method, path, body));
  const leaveAgentReady = async (number, state) => log.push(["FIELD", number, state]);
  const findings = detect({ now, windowStart, ...CASES[2][2] });
  const done = await writePlan({ plan: planIssues({ findings, existing }), call, repo: "o/r", labels: [], runUrl: url(900), leaveAgentReady, wait: async () => {} });
  assert.deepEqual(done.updated, [100]);
  assert.deepEqual(log, ["POST", "DELETE", ["FIELD", 100, "needs-triage"], "PATCH"]);
});

test("a rewrite whose Work status write fails leaves the PATCH for the next run", async () => {
  const s = store();
  await runOnce(s, CASES[2][1]);
  const existing = structuredClone(s.issues);
  const log = [];
  const call = async (method, path, body) => (log.push(method), s.call(method, path, body));
  const leaveAgentReady = async () => {
    throw new Error("#100's Work status field could not be read: HTTP 502");
  };
  const findings = detect({ now, windowStart, ...CASES[2][2] });
  const done = await writePlan({ plan: planIssues({ findings, existing }), call, repo: "o/r", labels: [], runUrl: url(900), leaveAgentReady, wait: async () => {} });
  assert.deepEqual(done.updated, []);
  assert.deepEqual(done.failed, [{ target: "#100", error: "#100's Work status field could not be read: HTTP 502" }]);
  assert.deepEqual(log, ["POST", "DELETE"]);
});

test("a failed write is reported and the rest still run", async () => {
  const s = store();
  const failing = async (method, path, body) => {
    if (body?.title === "Monitoring: main red") throw new Error("POST /repos/o/r/issues: HTTP 422");
    return s.call(method, path, body);
  };
  const findings = detect({ now, windowStart, ...CASES[0][1], ...CASES[3][1] });
  const done = await writePlan({ plan: planIssues({ findings, existing: [] }), call: failing, repo: "o/r", labels: [], runUrl: url(900), wait: async () => {} });
  assert.equal(done.filed.length, 1);
  assert.deepEqual(done.failed, [{ target: "1 main red", error: "POST /repos/o/r/issues: HTTP 422" }]);
});

test("signal 11 prints one ::error line per run while it fires; other signals print none", () => {
  const reports = [4, 3, 2, 1].map((runId) => ({ runId, url: `https://github.com/o/r/actions/runs/${runId}`, code: "3", reason: "unreadable: x", createdAt: "2026-10-30T14:00:00Z" }));
  const lines = errorLines(detect({ postMergeReports: reports, mergeGroupFailures: [1, 2, 3].map((id) => ({ id, url: "u", workflow: "w", createdAt: "t" })) }));
  assert.equal(lines.length, 1);
  assert.match(lines[0], /^::error::Post-merge check: unreadable in the last 4 pr-merge sweeps: .*unreadable: x$/);
  assert.deepEqual(errorLines(detect({ postMergeReports: reports.slice(0, 3) })), []);
});

// The job reads carry comes from the newest scheduled or hand-started run of
// main's copy of this workflow, this run aside, and only with JOBS_CARRY_PATH.
const LANE = ".github/workflows/maintenance-monitor-signals.yml";
const carryActions = (runs) => {
  const calls = [];
  const actions = async (method, path) => {
    calls.push(path);
    if (/maintenance-monitor-signals\.yml\/runs/.test(path)) return { workflow_runs: runs };
    if (/runs\/\d+\/artifacts/.test(path)) return { total_count: 1, artifacts: [{ name: JOBS_ARTIFACT, expired: false }] };
    throw new Error(`no route for ${path}`);
  };
  return { actions, calls };
};
const ENTRY = { id: 50, attempt: 1, updated_at: "2026-10-19T15:20:00Z", jobs: [] };
const HOLD = { lane: "work-unblock", runId: 60, url: "https://github.com/o/r/actions/runs/60", item: null, reason: "closed-issue listing failed", at: "2026-10-19T15:10:00Z" };
const HELD = { runs: [HOLD], from: "2026-10-18T09:00:00Z", through: "2026-10-19T15:20:00Z" };

test("the job reads carry is read from the newest trusted run, past a pull_request run and this run", async () => {
  const { actions, calls } = carryActions([
    { id: 903, path: LANE, event: "schedule", head_branch: "main" },
    { id: 902, path: LANE, event: "pull_request", head_branch: "main" },
    { id: 901, path: LANE, event: "workflow_dispatch", head_branch: "main" },
  ]);
  const downloaded = [];
  const { jobs, held } = await readJobsCarry({
    env: { JOBS_CARRY_PATH: "/x", GITHUB_RUN_ID: "903" },
    repo: "o/r",
    actions,
    download: (id) => (downloaded.push(id), jobsCarryFile("o/r", [ENTRY], HELD)),
  });
  assert.deepEqual(downloaded, [901]);
  assert.deepEqual([...jobs.keys()], ["50:1"]);
  assert.deepEqual(held, HELD);
  assert.ok(!calls.some((p) => /runs\/90[23]\/artifacts/.test(p)));
});

test("no JOBS_CARRY_PATH reads nothing, and a carry that cannot be read carries nothing", async (t) => {
  const { actions, calls } = carryActions([{ id: 901, path: LANE, event: "schedule", head_branch: "main" }]);
  assert.deepEqual(await readJobsCarry({ env: {}, repo: "o/r", actions }), { jobs: new Map(), held: null });
  assert.deepEqual(calls, []);
  t.mock.method(console, "log", () => {});
  for (const download of [
    () => {
      throw new Error("gh run download failed");
    },
    () => jobsCarryFile("other/repo", [ENTRY]),
  ]) {
    assert.deepEqual(await readJobsCarry({ env: { JOBS_CARRY_PATH: "/x", GITHUB_RUN_ID: "999" }, repo: "o/r", actions, download }), { jobs: new Map(), held: null });
  }
  // A file from before the carry held runs carries none over no span; a bad held run drops only the held runs.
  const old = JSON.stringify({ version: 1, repository: "o/r", runs: [ENTRY] });
  assert.deepEqual((await readJobsCarry({ env: { JOBS_CARRY_PATH: "/x", GITHUB_RUN_ID: "999" }, repo: "o/r", actions, download: () => old })).held, { runs: [], from: null, through: null });
  const bad = await readJobsCarry({ env: { JOBS_CARRY_PATH: "/x", GITHUB_RUN_ID: "999" }, repo: "o/r", actions, download: () => jobsCarryFile("o/r", [ENTRY], { ...HELD, runs: [{ ...HOLD, lane: "other" }] }) });
  assert.deepEqual([[...bad.jobs.keys()], bad.held], [["50:1"], null]);
});

test("the hold rule is read from pr-pipeline.yaml with its defaults, and a bad one is an error", () => {
  const rule = (text) => readHoldRule({ path: "p.yaml", run: () => text });
  assert.deepEqual(rule("{}"), { threshold: 4, windowHours: 24 });
  assert.deepEqual(rule('{"threshold": 2, "window-hours": 6}'), { threshold: 2, windowHours: 6 });
  for (const text of ['{"threshold": 1}', '{"window-hours": 0}', "not json"]) assert.match(rule(text).message, /monitor\.lane-holds rule was not read/);
  const failing = readHoldRule({
    run: () => {
      throw new Error("yq: not found");
    },
  });
  assert.match(failing.message, /yq: not found/);
});

test("the checkout's pr-pipeline.yaml sets a hold rule the schema and holdRule take", () => {
  const text = readFileSync(new URL("../../../docs/conventions/pr-pipeline.yaml", import.meta.url), "utf8");
  const leaf = /^monitor:\n {2}lane-holds:\n {4}threshold: (\d+)\n(?: {4}#.*\n)* {4}window-hours: (\d+)$/m.exec(text);
  assert.ok(leaf, "pr-pipeline.yaml has a monitor.lane-holds leaf");
  assert.ok(Number(leaf[1]) >= 2);
  const schema = JSON.parse(readFileSync(new URL("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json", import.meta.url), "utf8"));
  const props = schema.properties.monitor.properties["lane-holds"].properties;
  assert.deepEqual([props.threshold.default, props["window-hours"].default], [4, 24]);
});
