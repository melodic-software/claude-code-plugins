// Runs end to end through detect, planIssues and writePlan against an
// in-memory issue store: for each signal, the first run files one incident,
// a run with the same findings writes nothing, new findings rewrite that
// issue's body with no
// comment, a clear run closes it, and a later episode files a new incident.
// Every rewrite takes agent-ready off.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { statusWriter } from "../../actions/resolve-config/write-status.mjs";

import { FILING, SIGNALS, familyOf, planIssues, readMarker } from "./issues.mjs";
import { errorLines, incidentFields, readHoldRule, readIncidentRules, readJobsCarry, statusLines, writePlan } from "./monitor.mjs";
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
    { sweep: sweep([]), laneMerges: { lastMergedAt: "2026-10-19T10:00:00Z" } },
    { sweep: sweep([]), laneMerges: { lastMergedAt: "2026-10-19T09:00:00Z" } },
  ],
];

function store() {
  const issues = [];
  const calls = [];
  const comments = {};
  const call = async (method, path, body) => {
    calls.push(`${method} ${path}`);
    if (method === "POST" && path.endsWith("/issues")) {
      const issue = { number: 100 + issues.length, state: "open", state_reason: null, ...body, type: { name: body.type }, labels: [...(body.labels ?? [])] };
      issues.push(issue);
      return issue;
    }
    const number = Number(/issues\/(\d+)/.exec(path)[1]);
    const issue = issues.find((i) => i.number === number);
    if (method === "PATCH") Object.assign(issue, body);
    if (method === "POST" && path.endsWith("/comments")) (comments[number] ??= []).push(body.body);
    if (method === "POST" && path.endsWith("/labels")) issue.labels = [...new Set([...issue.labels, ...body.labels])];
    return {};
  };
  return { issues, calls, comments, call };
}

const RULES = Object.fromEntries(SIGNALS.map((signal) => [signal, { open: 0, close: 0 }]));
const planFor = (s, data, extra = {}) =>
  planIssues({ findings: detect({ now, windowStart, ...data }), existing: s.issues.filter((i) => readMarker(i.body)), rules: RULES, now: data.now ?? now, ...extra });

const runOnce = (s, data, extra = {}) => writePlan({ plan: planFor(s, data, extra), call: s.call, repo: "o/r", runUrl: url(900), wait: async () => {} });

const nothing = { filed: [], updated: [], closed: [], retired: [], failed: [] };
// Throttling's first findings with a second key alongside.
const TWO_KEYS = { failedRuns: [denied(1, "lane-token-denied: the broker answered 500 with reason unknown"), denied(2, "HTTP 429 rate limit")] };

const ROOT = new URL("../../..", import.meta.url).pathname;
// The org Work status field and the option ids it maps, written by hand.
const FIELD = 48484079;
const OPTION = { "needs-triage": 84879216, "needs-owner-decision": 84879218, "agent-ready": 84879220 };
// One issue's Work status field reading `state`, last set by account `setter`,
// behind a real statusWriter. A POST sets it as the lanes App, or throws
// `postError`; `written` lists the states POSTed.
function workStatus(state, setter, postError) {
  const written = [];
  const value = () => (state === null ? [] : [{ issue_field_id: FIELD, single_select_option: { id: OPTION[state] } }]);
  const github = async (method, path, body) => {
    if (method === "GET" && path.endsWith("/issue-field-values")) return value();
    if (method === "POST" && path === "/graphql") {
      const nodes = state === null ? [] : [{ __typename: "IssueFieldAddedEvent", value: state, actor: { databaseId: setter }, issueField: { fullDatabaseId: String(FIELD) } }];
      return { data: { repository: { issue: { timelineItems: { nodes } } } } };
    }
    if (method === "POST" && path.endsWith("/issue-field-values")) {
      if (postError) throw postError;
      state = body.issue_field_values[0].value;
      written.push(state);
      setter = 337595936;
      return value();
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { written, writer: () => statusWriter({ env: { BASE_PATH: ROOT }, github, repository: "o/r" }) };
}

for (const [signal, first, changed] of CASES) {
  test(`${signal}: one incident, unchanged by new evidence for the same key, closed when clear, with no comment`, async () => {
    const s = store();
    const one = await runOnce(s, first);
    assert.equal(one.filed.length, 1);
    assert.ok(s.issues[0].body.includes(`**Signal:** ${signal}`));
    assert.equal(s.issues[0].title, FILING[signal].title);

    const callsBefore = s.calls.length;
    assert.deepEqual(await runOnce(s, first), nothing);
    assert.deepEqual(await runOnce(s, changed), nothing, "new evidence, same keys: nothing written");
    assert.equal(s.calls.length, callsBefore);

    const clear = await runOnce(s, {});
    assert.deepEqual(clear, { ...nothing, closed: [100] });
    assert.equal(s.issues[0].state, "closed");
    assert.equal(s.issues[0].state_reason, "completed");
    assert.match(s.issues[0].body, /\*\*State:\*\* clear in/);
    assert.deepEqual(await runOnce(s, {}), nothing);

    const back = await runOnce(s, first);
    assert.deepEqual(back, { ...nothing, filed: [101] });
    assert.equal(s.issues.length, 2);
    assert.deepEqual(s.comments, {}, "no comment on any state change");
  });
}

test("3 throttling: a new key rewrites the same issue's body with no comment", async () => {
  const s = store();
  await runOnce(s, CASES[2][1]);
  s.issues[0].labels.push("agent-ready");
  const done = await runOnce(s, TWO_KEYS);
  assert.deepEqual(done, { ...nothing, updated: [100] });
  assert.equal(s.issues.length, 1);
  assert.match(s.issues[0].body, /broker-deny:500-unknown/);
  assert.match(s.issues[0].body, /throttle:rate-limited/);
  assert.deepEqual(s.comments, {});
  assert.ok(!s.calls.some((c) => c.startsWith("DELETE")), "no label DELETE: the Work status field takes agent-ready off");
});

test("4 merge-queue ejections: the oldest group leaving the 24-hour window writes nothing", async () => {
  const s = store();
  await runOnce(s, { mergeGroupFailures: [ejection(1), ejection(2), ejection(3), ejection(4)] });
  const callsBefore = s.calls.length;
  const aged = await runOnce(s, { mergeGroupFailures: [ejection(2), ejection(3), ejection(4)] });
  assert.deepEqual(aged, nothing);
  assert.equal(s.calls.length, callsBefore);
});

test("two signals get one incident each", async () => {
  const s = store();
  const done = await runOnce(s, { ...TWO_KEYS, mainRun: red("not ok 1 - a") });
  assert.deepEqual(done.filed, [100, 101]);
  assert.deepEqual(s.issues.map((i) => i.title), [FILING["1 main red"].title, FILING["3 throttling"].title]);
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

test("open rolling and per-key issues are retired with a comment and their history kept, once", async () => {
  const s = store();
  const old = (key, number) => ({
    number,
    state: "open",
    state_reason: null,
    labels: [],
    body: `<!-- factory-monitor key=${key} fp=0123456789abcdef -->\nold`,
  });
  s.issues.push(old("family:throttling", 7), old("broker-deny:500-unknown", 8));
  const done = await runOnce(s, {});
  assert.deepEqual(done, { ...nothing, retired: [7, 8] });
  assert.equal(s.issues[0].state, "closed");
  assert.equal(s.issues[0].state_reason, "not_planned");
  assert.match(s.issues[0].body, /old$/, "the body stays as it was");
  assert.match(s.comments[7][0], /job summary/);
  assert.deepEqual(await runOnce(s, {}), nothing);
});

const HUMAN = 153232337;
const rewriteWith = (s, leaveAgentReady) => writePlan({ plan: planFor(s, TWO_KEYS), call: s.call, repo: "o/r", runUrl: url(900), leaveAgentReady, wait: async () => {} });

for (const [why, state, setter, written] of [
  ["an unset field", null, undefined, ["needs-triage"]],
  ["a field at agent-ready", "agent-ready", HUMAN, ["needs-triage"]],
  ["a person's needs-owner-decision", "needs-owner-decision", HUMAN, []],
]) {
  test(`a rewrite with ${why} writes Work status ${written.join() || "nothing"} and deletes no label`, async () => {
    const s = store();
    await runOnce(s, CASES[2][1]);
    s.issues[0].labels.push("agent-ready");
    const f = workStatus(state, setter);
    const done = await rewriteWith(s, (await f.writer()).leaveAgentReady);
    assert.deepEqual(done, { ...nothing, updated: [100] });
    assert.deepEqual(f.written, written);
    assert.ok(!s.calls.some((c) => c.startsWith("DELETE")), "agent-ready comes off through the field, never a label DELETE");
  });
}

test("a rewrite whose Work status write fails reports it and leaves the PATCH for the next run", async () => {
  const s = store();
  await runOnce(s, CASES[2][1]);
  const oldBody = s.issues[0].body;
  const f = workStatus(null, undefined, new Error("HTTP 500"));
  const done = await rewriteWith(s, (await f.writer()).leaveAgentReady);
  assert.deepEqual(done.updated, []);
  assert.equal(done.failed.length, 1);
  assert.equal(done.failed[0].target, "#100");
  assert.match(done.failed[0].error, /^#100's Work status field was not set to `needs-triage`: HTTP 500/);
  assert.ok(!s.calls.includes("PATCH /repos/o/r/issues/100"));
  assert.equal(s.issues[0].body, oldBody);
});

test("a rewrite takes agent-ready off through the Work status field before the PATCH", async () => {
  const s = store();
  await runOnce(s, CASES[2][1]);
  s.issues[0].labels.push("agent-ready");
  const log = [];
  const call = async (method, path, body) => (log.push(method), s.call(method, path, body));
  const leaveAgentReady = async (number, state, options) => log.push(["FIELD", number, state, options]);
  const done = await writePlan({ plan: planFor(s, TWO_KEYS), call, repo: "o/r", runUrl: url(900), leaveAgentReady, wait: async () => {} });
  assert.deepEqual(done.updated, [100]);
  assert.deepEqual(log, [["FIELD", 100, "needs-triage", { orUnset: true }], "PATCH"]);
});

test("a rewrite whose Work status write fails leaves the PATCH for the next run", async () => {
  const s = store();
  await runOnce(s, CASES[2][1]);
  const log = [];
  const call = async (method, path, body) => (log.push(method), s.call(method, path, body));
  const leaveAgentReady = async () => {
    throw new Error("#100's Work status field could not be read: HTTP 502");
  };
  const done = await writePlan({ plan: planFor(s, TWO_KEYS), call, repo: "o/r", runUrl: url(900), leaveAgentReady, wait: async () => {} });
  assert.deepEqual(done.updated, []);
  assert.deepEqual(done.failed, [{ target: "#100", error: "#100's Work status field could not be read: HTTP 502" }]);
  assert.deepEqual(log, []);
});

test("a failed write is reported and the rest still run", async () => {
  const s = store();
  await runOnce(s, { ...CASES[0][1], ...CASES[2][1] });
  const failing = async (method, path, body) => {
    if (path.endsWith("/issues/100")) throw new Error("PATCH /repos/o/r/issues/100: HTTP 422");
    return s.call(method, path, body);
  };
  const done = await writePlan({ plan: planFor(s, {}), call: failing, repo: "o/r", runUrl: url(900), wait: async () => {} });
  assert.deepEqual(done.closed, [101]);
  assert.deepEqual(done.failed, [{ target: "#100", error: "PATCH /repos/o/r/issues/100: HTTP 422" }]);
});

test("a filing sets Issue Type, Work status and Priority, and leaves the dimensions to triage", async () => {
  const s = store();
  const set = [];
  await writePlan({ plan: planFor(s, CASES[0][1]), call: s.call, repo: "o/r", runUrl: url(900), setFields: async (number, values) => set.push([number, values]), wait: async () => {} });
  assert.deepEqual(s.issues[0].type, { name: "Bug" });
  assert.deepEqual(set, [[100, [{ field_id: 48484079, value: "needs-triage" }, { field_id: 49622037, value: "critical" }]]]);
  assert.deepEqual(incidentFields("5 held PRs")[1], { field_id: 49622037, value: "medium" });
  assert.equal(readMarker(s.issues[0].body).key, "incident:main-red");
});

test("a failed filing is reported and the next still files; a failed field write and a dropped type only warn", async (t) => {
  const logged = t.mock.method(console, "log", () => {});
  const s = store();
  const call = async (method, path, body) => {
    if (body?.title === FILING["1 main red"].title) throw new Error("POST /repos/o/r/issues: HTTP 422");
    const issue = await s.call(method, path, body);
    return { number: issue.number };
  };
  const setFields = async () => {
    throw new Error("HTTP 500");
  };
  const done = await writePlan({ plan: planFor(s, { ...CASES[0][1], ...CASES[2][1] }), call, repo: "o/r", runUrl: url(900), setFields, wait: async () => {} });
  assert.deepEqual(done.filed, [100]);
  assert.deepEqual(done.failed, [{ target: "1 main red", error: "POST /repos/o/r/issues: HTTP 422" }]);
  const lines = logged.mock.calls.map((c) => c.arguments[0]);
  assert.match(lines[0], /#100 came back without Issue Type Bug/);
  assert.match(lines[1], /#100's field values were not set: HTTP 500/);
});

test("every signal's state is in the job summary, its evidence fenced", () => {
  const s = store();
  const lines = statusLines(planFor(s, CASES[2][1])).join("\n");
  for (const signal of SIGNALS) assert.ok(lines.includes(`- **${signal}**:`), signal);
  assert.match(lines, /- \*\*1 main red\*\*: clear/);
  assert.match(lines, /`broker-deny:500-unknown` \(.*\):\n\n```text\n/);
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
  assert.deepEqual(await readJobsCarry({ env: {}, repo: "o/r", actions }), { jobs: new Map(), held: null, episodes: {} });
  assert.deepEqual(calls, []);
  t.mock.method(console, "log", () => {});
  for (const download of [
    () => {
      throw new Error("gh run download failed");
    },
    () => jobsCarryFile("other/repo", [ENTRY]),
  ]) {
    assert.deepEqual(await readJobsCarry({ env: { JOBS_CARRY_PATH: "/x", GITHUB_RUN_ID: "999" }, repo: "o/r", actions, download }), { jobs: new Map(), held: null, episodes: {} });
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

test("the signal timers come back with the job reads", async () => {
  const { actions } = carryActions([{ id: 901, path: LANE, event: "schedule", head_branch: "main" }]);
  const signals = { "3 throttling": { onSince: "2026-10-19T15:00:00Z", clearSince: null } };
  const { episodes } = await readJobsCarry({
    env: { JOBS_CARRY_PATH: "/x", GITHUB_RUN_ID: "999" },
    repo: "o/r",
    actions,
    now,
    download: () => jobsCarryFile("o/r", [ENTRY], HELD, { at: "2026-10-19T15:52:00Z", signals }),
  });
  assert.deepEqual(episodes, signals);
});

test("the incident thresholds are read from pr-pipeline.yaml, and a bad one is an error", () => {
  const full = JSON.stringify(Object.fromEntries(SIGNALS.map((s) => [familyOf(s), { "open-hours": 1, "close-hours": 2 }])));
  assert.deepEqual(readIncidentRules({ path: "p.yaml", run: () => full })["1 main red"], { open: 1, close: 2 });
  assert.match(readIncidentRules({ path: "p.yaml", run: () => "{}" }).message, /monitor\.incidents thresholds were not read/);
  const failing = readIncidentRules({
    run: () => {
      throw new Error("yq: not found");
    },
  });
  assert.match(failing.message, /yq: not found/);
});

test("the checkout's pr-pipeline.yaml sets thresholds for every signal, and main-red opens at once", () => {
  const text = readFileSync(new URL("../../../docs/conventions/pr-pipeline.yaml", import.meta.url), "utf8");
  const row = (slug) => new RegExp(`^ {4}${slug}:\n {6}open-hours: (\\d+)\n {6}close-hours: (\\d+)$`, "m").exec(text);
  for (const signal of SIGNALS) assert.ok(row(familyOf(signal)), familyOf(signal));
  assert.equal(row("main-red")[1], "0");
});
