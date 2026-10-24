// The rolling-issue rules: a signal family gets one issue, found by its
// marker; the same state writes nothing; a new state updates it in place; a
// clear state closes it, and a later finding reopens that same issue instead
// of filing a second; closing as not planned or duplicate mutes the family;
// platform incidents are logged, never filed; issues of the earlier
// one-issue-per-key scheme still open are closed.
import assert from "node:assert/strict";
import { test } from "node:test";

import { LOG_ONLY, SIGNALS, familyOf, planIssues, readMarker, renderBody, renderComment, renderSupersede } from "./issues.mjs";
import { detect } from "./signals.mjs";

const now = new Date("2026-10-19T16:41:00Z");
const windowStart = new Date("2026-10-19T15:36:00Z");
const runUrl = "https://github.com/o/r/actions/runs/900";
const denied = (id) => ({
  id,
  url: `https://github.com/o/r/actions/runs/${id}`,
  name: "pr-merge",
  event: "schedule",
  annotations: [{ level: "failure", message: "lane-token-denied: the broker answered 500 with reason unknown" }],
});
const findingFor = (runs) => detect({ now, windowStart, failedRuns: runs.map(denied) })[0];
const THROTTLING = "3 throttling";
const family = (findings) => ({ signal: THROTTLING, findings });

const issueFrom = (findings, number, extra = {}) => ({
  number,
  state: "open",
  state_reason: null,
  body: renderBody(family(findings), runUrl),
  ...extra,
});
const legacyIssue = (key, number, extra = {}) => ({
  number,
  state: "open",
  state_reason: null,
  body: `<!-- factory-monitor key=${key} fp=0123456789abcdef -->\n**Signal:** old`,
  ...extra,
});

test("the marker names the family on the body's first line", () => {
  const body = renderBody(family([findingFor([1])]), runUrl);
  assert.equal(readMarker(body).key, "family:throttling");
  assert.equal(readMarker(`text\n${body}`), null);
  assert.equal(readMarker("<!-- factory-monitor key=x fp=zz -->"), null);
  assert.equal(familyOf("4 merge-queue ejections"), "merge-queue-ejections");
  assert.equal(familyOf("5 held PRs"), "held-prs");
});

test("a family's first finding files one issue holding every finding of that signal", () => {
  const a = findingFor([1]);
  const b = { ...findingFor([2]), key: "throttle:rate-limited" };
  const plan = planIssues({ findings: [a, b], existing: [] });
  assert.equal(plan.file.length, 1);
  assert.equal(plan.file[0].family.signal, THROTTLING);
  assert.deepEqual(
    plan.file[0].family.findings.map((f) => f.key),
    [a.key, b.key].sort(),
  );
});

test("the same state skips; a new state updates the open issue", () => {
  const existing = [issueFrom([findingFor([1])], 41)];
  const same = planIssues({ findings: [findingFor([1])], existing });
  assert.deepEqual(same.file, []);
  assert.deepEqual(same.update, []);
  assert.deepEqual(same.skip, [{ family: "throttling", number: 41, reason: "unchanged" }]);

  const changed = planIssues({ findings: [findingFor([1, 2])], existing });
  assert.deepEqual(changed.file, []);
  assert.deepEqual(
    changed.update.map((u) => u.number),
    [41],
  );
});

test("a family with no finding clears its open issue, unless a source went unread", () => {
  const existing = [issueFrom([findingFor([1])], 41)];
  const clear = planIssues({ findings: [], existing });
  assert.deepEqual(clear.update, [{ number: 41, family: family([]) }]);
  const unread = planIssues({ findings: [], existing, complete: false });
  assert.deepEqual(unread.update, []);
  assert.deepEqual(unread.skip, [{ family: "throttling", number: 41, reason: "not read" }]);
});

test("a closed rolling issue is reopened, never filed again, when its signal fires", () => {
  const closed = [issueFrom([], 30, { state: "closed", state_reason: "completed", closed_at: "2026-10-19T10:00:00Z" })];
  const plan = planIssues({ findings: [findingFor([1])], existing: closed });
  assert.deepEqual(plan.file, []);
  assert.deepEqual(
    plan.reopen.map((r) => r.number),
    [30],
  );
  assert.deepEqual(planIssues({ findings: [], existing: closed }), {
    file: [],
    update: [],
    reopen: [],
    close: [],
    skip: [],
    logged: [],
  });
});

test("a person's close with the same state stays closed until the evidence changes", () => {
  const f = findingFor([1]);
  const closed = [issueFrom([f], 30, { state: "closed", state_reason: "completed", closed_at: "2026-10-19T16:00:00Z" })];
  const same = planIssues({ findings: [findingFor([1])], existing: closed });
  assert.deepEqual(same.reopen, []);
  assert.deepEqual(same.skip, [{ family: "throttling", number: 30, reason: "closed-unchanged" }]);
  assert.deepEqual(
    planIssues({ findings: [findingFor([1, 2])], existing: closed }).reopen.map((r) => r.number),
    [30],
  );
});

test("a not-planned or duplicate close mutes the family, and the newest issue decides", () => {
  for (const reason of ["not_planned", "duplicate"]) {
    const muted = planIssues({
      findings: [findingFor([1, 2])],
      existing: [issueFrom([findingFor([1])], 10), issueFrom([findingFor([1])], 20, { state: "closed", state_reason: reason })],
    });
    assert.deepEqual(muted.file, []);
    assert.deepEqual(muted.update, []);
    assert.deepEqual(muted.reopen, []);
    assert.deepEqual(muted.skip, [{ family: "throttling", number: 20, reason: "muted" }]);
  }
});

test("a platform incident is logged in the plan and never filed", () => {
  const findings = detect({
    now,
    windowStart,
    status: {
      components: [],
      incidents: [{ id: "x1", name: "Actions down", status: "investigating", created_at: "2026-10-19T16:00:00Z", shortlink: "s", components: ["Actions"] }],
    },
  });
  assert.ok(LOG_ONLY.has(findings[0].signal));
  const plan = planIssues({ findings, existing: [] });
  assert.deepEqual(plan.file, []);
  assert.deepEqual(plan.logged, findings);
});

test("every open per-key issue is closed, pointing at its family's rolling issue", () => {
  const plan = planIssues({
    findings: [],
    existing: [
      issueFrom([findingFor([1])], 90),
      legacyIssue("broker-deny:500-unknown", 12),
      legacyIssue("throttle:rate-limited", 11),
      legacyIssue("platform:abc", 13),
      legacyIssue("main-red:lint", 14),
      legacyIssue("main-red:lint", 15),
      legacyIssue("held-over-24h", 16, { state: "closed", state_reason: "completed" }),
    ],
  });
  assert.deepEqual(plan.close, [
    { number: 11, key: "throttle:rate-limited", signal: THROTTLING, rolling: 90 },
    { number: 12, key: "broker-deny:500-unknown", signal: THROTTLING, rolling: 90 },
    { number: 13, key: "platform:abc", signal: "7 platform incident", rolling: null },
    { number: 14, key: "main-red:lint", signal: "1 main red", rolling: null },
    { number: 15, key: "main-red:lint", signal: "1 main red", rolling: null },
  ]);
  assert.match(renderSupersede(THROTTLING, 90), /Superseded by #90/);
  assert.match(renderSupersede("7 platform incident", null), /run summary/);
  assert.match(renderSupersede("1 main red", null), /next fires/);
});

test("every detector's signal is a rolling family or logged only, and an unknown one is named in the plan", () => {
  const all = detect({
    now,
    windowStart,
    failedRuns: [denied(1)],
    mainRun: { id: 1, url: "u", sha: "a", event: "schedule", conclusion: "failure", failedJobs: [{ name: "j", annotations: [{ level: "failure", message: "m" }] }] },
    budgetReadings: [{ phase: "end", name: "lane", used: 99, limit: 100, remaining: 1 }],
    mergeGroupFailures: [1, 2, 3].map((id) => ({ id, url: "u", workflow: "w", createdAt: "t" })),
    sweep: { url: "u", live: true, startedAt: "2026-10-19T16:30:00Z", candidates: 3, results: [{ pr: 1, updatedAt: "2026-10-17T00:00:00Z" }] },
    laneMerges: { lastMergedAt: null },
    audits: [{ workflow: "w", run: { id: 1, url: "u", conclusion: "failure", createdAt: "t" } }],
    status: { components: [{ name: "Actions", status: "major_outage" }], incidents: [] },
    laneStops: [{ id: 1, outcome: "funding", issue: 3, createdAt: "t", url: "u" }],
  });
  assert.deepEqual(new Set(all.map((f) => f.signal)), new Set([...SIGNALS, ...LOG_ONLY]));
  const plan = planIssues({ findings: [{ ...findingFor([1]), signal: "10 renamed" }], existing: [] });
  assert.deepEqual(plan.file, []);
  assert.deepEqual(plan.skip, [{ family: "renamed", number: null, reason: "unknown signal" }]);
});

test("the body carries each finding's evidence inside a text fence; the comment names the change", () => {
  const f = findingFor([1, 2]);
  const body = renderBody(family([f]), runUrl);
  assert.match(body, /Owning area/);
  assert.match(body, new RegExp(`### \`${f.key}\``));
  assert.match(body, /```text\n[^`]*lane-token-denied[^`]*\n```/);
  assert.match(body, /\*\*State:\*\* 1 current finding in/);
  const comment = renderComment(family([f]), runUrl);
  assert.ok(comment.includes(runUrl));
  assert.ok(comment.includes(`\`${f.key}\``));
  assert.match(renderBody(family([]), runUrl), /\*\*State:\*\* clear in/);
  assert.match(renderComment(family([]), runUrl), /^Clear in/);
});

test("a main-red family closed as completed reopens when main fails after the close, even with the same text", () => {
  const red = (createdAt) =>
    detect({
      now,
      windowStart,
      mainRun: {
        id: 77,
        url: "https://github.com/o/r/actions/runs/77",
        sha: "abc",
        event: "schedule",
        conclusion: "failure",
        createdAt,
        failedJobs: [{ name: "lint", conclusion: "failure", annotations: [{ level: "failure", message: "flaky 3" }] }],
      },
    })[0];
  const closed = [
    {
      number: 30,
      state: "closed",
      state_reason: "completed",
      closed_at: "2026-10-18T12:00:00Z",
      body: renderBody({ signal: "1 main red", findings: [red("2026-10-18T09:17:00Z")] }, runUrl),
    },
  ];
  const before = planIssues({ findings: [red("2026-10-18T09:17:00Z")], existing: closed });
  assert.deepEqual(before.reopen, []);
  assert.equal(before.skip[0].reason, "closed-unchanged");
  const at = planIssues({ findings: [red("2026-10-18T12:00:00Z")], existing: closed });
  assert.deepEqual(at.reopen, []);
  const again = planIssues({ findings: [red("2026-10-19T16:17:00Z")], existing: closed });
  assert.deepEqual(again.file, []);
  assert.deepEqual(
    again.reopen.map((r) => r.number),
    [30],
  );
});
