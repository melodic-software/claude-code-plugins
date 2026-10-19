// The dedup rules: a finding files one issue per key; a repeat with the same
// evidence changes nothing; a repeat with new evidence updates the open issue
// instead of filing a second; closing as not planned mutes the key; a key
// closed as completed files again only on new evidence.
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

test("a key closed as completed files again only on new evidence, naming the old issue", () => {
  const f = findingFor([1]);
  const closed = [issueFrom(f, 30, { state: "closed", state_reason: "completed" })];
  assert.deepEqual(planIssues({ findings: [findingFor([1])], existing: closed }).file, []);
  const again = planIssues({ findings: [findingFor([1, 2])], existing: closed });
  assert.equal(again.file.length, 1);
  assert.equal(again.file[0].recurrenceOf, 30);
  assert.match(renderBody(again.file[0].finding, runUrl, 30), /#30/);
});

test("no more than MAX_NEW_ISSUES are filed in one run", () => {
  const many = Array.from({ length: MAX_NEW_ISSUES + 2 }, (_, i) => ({ ...findingFor([i + 1]), key: `k${i}` }));
  const plan = planIssues({ findings: many, existing: [] });
  assert.equal(plan.file.length, MAX_NEW_ISSUES);
  assert.equal(plan.skip.filter((s) => s.reason === "cap").length, 2);
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
