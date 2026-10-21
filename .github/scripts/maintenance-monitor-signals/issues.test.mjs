// The dedup rules: a finding files one issue per key; a repeat with the same
// evidence changes nothing; a repeat with new evidence updates the open issue
// instead of filing a second; closing as not planned or duplicate mutes the
// key; a key closed as completed reopens that issue on new evidence.
import assert from "node:assert/strict";
import { test } from "node:test";

import { MAX_NEW_ISSUES, planIssues, readMarker, renderBody, renderComment } from "./issues.mjs";
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

const issueFrom = (finding, number, extra = {}) => ({
  number,
  state: "open",
  state_reason: null,
  body: renderBody(finding, runUrl),
  ...extra,
});

test("the marker round-trips the key and fingerprint on the body's first line", () => {
  const f = findingFor([1]);
  const body = renderBody(f, runUrl);
  assert.deepEqual(readMarker(body), { key: f.key, fingerprint: f.fingerprint });
  assert.equal(readMarker(`text\n${body}`), null);
  assert.equal(readMarker("<!-- factory-monitor key=x fp=zz -->"), null);
});

test("a new key files one issue", () => {
  const f = findingFor([1]);
  const plan = planIssues({ findings: [f], existing: [] });
  assert.deepEqual(
    plan.file.map((x) => x.finding.key),
    [f.key],
  );
  assert.deepEqual(plan.update, []);
});

test("a repeat with the same evidence skips; with new evidence it updates the open issue", () => {
  const first = findingFor([1]);
  const existing = [issueFrom(first, 41)];
  const same = planIssues({ findings: [findingFor([1])], existing });
  assert.deepEqual(same.file, []);
  assert.deepEqual(same.update, []);
  assert.deepEqual(same.skip, [{ key: first.key, number: 41, reason: "unchanged" }]);

  const changed = planIssues({ findings: [findingFor([1, 2])], existing });
  assert.deepEqual(changed.file, []);
  assert.deepEqual(
    changed.update.map((u) => u.number),
    [41],
  );
});

test("the newest issue for a key decides, and a not-planned close mutes it", () => {
  const f = findingFor([1]);
  const muted = planIssues({
    findings: [findingFor([1, 2])],
    existing: [issueFrom(f, 10), issueFrom(f, 20, { state: "closed", state_reason: "not_planned" })],
  });
  assert.deepEqual(muted.file, []);
  assert.deepEqual(muted.update, []);
  assert.equal(muted.skip[0].reason, "muted");
});

test("a duplicate close mutes the key too", () => {
  const f = findingFor([1]);
  const muted = planIssues({
    findings: [findingFor([1, 2])],
    existing: [issueFrom(f, 20, { state: "closed", state_reason: "duplicate" })],
  });
  assert.deepEqual(muted.file, []);
  assert.deepEqual(muted.reopen, []);
  assert.deepEqual(muted.skip, [{ key: f.key, number: 20, reason: "muted" }]);
});

test("a key closed as completed reopens that issue on new evidence and files nothing", () => {
  const f = findingFor([1]);
  const closed = [issueFrom(f, 30, { state: "closed", state_reason: "completed" })];
  const same = planIssues({ findings: [findingFor([1])], existing: closed });
  assert.deepEqual(same.file, []);
  assert.deepEqual(same.reopen, []);
  assert.deepEqual(same.skip, [{ key: f.key, number: 30, reason: "closed-unchanged" }]);
  const changed = findingFor([1, 2]);
  const again = planIssues({ findings: [changed], existing: closed });
  assert.deepEqual(again.file, []);
  assert.deepEqual(again.update, []);
  assert.deepEqual(again.reopen, [{ number: 30, finding: changed }]);
});

test("no more than MAX_NEW_ISSUES are filed in one run", () => {
  const many = Array.from({ length: MAX_NEW_ISSUES + 2 }, (_, i) => ({ ...findingFor([i + 1]), key: `k${i}` }));
  const plan = planIssues({ findings: many, existing: [] });
  assert.equal(plan.file.length, MAX_NEW_ISSUES);
  assert.equal(plan.skip.filter((s) => s.reason === "cap").length, 2);
});

test("reopens do not count against MAX_NEW_ISSUES", () => {
  const closed = Array.from({ length: MAX_NEW_ISSUES }, (_, i) =>
    issueFrom({ ...findingFor([1]), key: `old${i}` }, 50 + i, { state: "closed", state_reason: "completed" }),
  );
  const reopened = closed.map((_, i) => ({ ...findingFor([1, 2]), key: `old${i}` }));
  const fresh = Array.from({ length: MAX_NEW_ISSUES }, (_, i) => ({ ...findingFor([i + 1]), key: `new${i}` }));
  const plan = planIssues({ findings: [...reopened, ...fresh], existing: closed });
  assert.equal(plan.reopen.length, MAX_NEW_ISSUES);
  assert.equal(plan.file.length, MAX_NEW_ISSUES);
  assert.deepEqual(plan.skip, []);
});

test("the body and comment carry the evidence inside a text fence, and the comment the run", () => {
  const f = findingFor([1, 2]);
  const body = renderBody(f, runUrl);
  assert.match(body, /Owning area/);
  assert.match(body, new RegExp(`\`${f.key}\``));
  assert.match(body, /```text\n[^`]*lane-token-denied[^`]*\n```/);
  const comment = renderComment(f, runUrl);
  assert.ok(comment.includes(runUrl));
  assert.match(comment, /```text\n/);
});

test("a main-red key closed as completed reopens when main fails after the close, even with the same text", () => {
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
  const closed = [issueFrom(red("2026-10-18T09:17:00Z"), 30, { state: "closed", state_reason: "completed", closed_at: "2026-10-18T12:00:00Z" })];
  const before = planIssues({ findings: [red("2026-10-18T09:17:00Z")], existing: closed });
  assert.deepEqual(before.file, []);
  assert.deepEqual(before.reopen, []);
  assert.equal(before.skip[0].reason, "closed-unchanged");
  const again = planIssues({ findings: [red("2026-10-19T16:17:00Z")], existing: closed });
  assert.deepEqual(again.file, []);
  assert.deepEqual(
    again.reopen.map((r) => r.number),
    [30],
  );
});

test("an observation at the close time is not after it, so the same evidence stays closed", () => {
  const f = { ...findingFor([1]), observedAt: "2026-10-18T12:00:00Z" };
  const closed = [issueFrom(f, 30, { state: "closed", state_reason: "completed", closed_at: "2026-10-18T12:00:00Z" })];
  const plan = planIssues({ findings: [f], existing: closed });
  assert.deepEqual(plan.reopen, []);
  assert.deepEqual(plan.file, []);
  assert.deepEqual(plan.skip, [{ key: f.key, number: 30, reason: "closed-unchanged" }]);
  const later = planIssues({ findings: [{ ...f, observedAt: "2026-10-18T12:00:01Z" }], existing: closed });
  assert.deepEqual(
    later.reopen.map((r) => r.number),
    [30],
  );
});
