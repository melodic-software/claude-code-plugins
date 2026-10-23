#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import * as publisher from "./publish-promotion-evidence.mjs";
import { collect, PublishError, publish } from "./publish-promotion-evidence.mjs";
import { actorOf, CANARY, demotionIssue, FULL, GATE, github, issueComment, issueItem, LANE, later, MECHANICAL, MISSED, page1, pinComment, pr, REC, REPO, SCOPED, shaOf, wfRun } from "./fixtures/publish-promotion-evidence/github-fake.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const SINCE = "2026-08-01T00:00:00Z";
const THROUGH = "2026-10-05T00:00:00Z";

const base = mkdtempSync(join(tmpdir(), "publish-promotion-evidence-"));
after(() => rmSync(base, { recursive: true, force: true }));

// REC.pullGraph: a recorded pull whose one closing reference, number 6007, is labeled `work-class: scoped`.
const ISSUE_6007 = REC.pullGraph.data.repository.pullRequest.closingIssuesReferences.nodes;
const queued = (at, enqueuer, actor = enqueuer) => ({ __typename: "AddedToMergeQueueEvent", createdAt: at, actor: actorOf(actor), enqueuer: actorOf(enqueuer) });
// The shape of a real ConnectedEvent on a PR timeline (cli/cli #14616): `subject` is the issue.
const LINK = REC.connectedEventFromCliCli14616;
const link = (type, issue, at) => ({ ...LINK, __typename: type, createdAt: at, subject: { ...LINK.subject, number: issue } });

const labelEvent = (event, name, at, login = "kyle-sexton", type = "User") => ({ ...REC.issueEvent, event, label: { name }, actor: { login, type }, created_at: at });

function run(fixture, extra = {}) {
  return collect({ repo: REPO, since: SINCE, through: THROUGH, laneLogins: [LANE], gateChecks: GATE, missedBlockingLabel: MISSED, gh: github(fixture), ...extra });
}

const termOf = (result, cell, name) => result.cells[cell].terms.find((t) => t.term === name);

const gateEvents = (at, ...cells) => cells.map((cell) => ({ cell, event: "gate-failure", at }));
// A green lane dispatch run and a green canary run on `tip`: check() calls each merge they contain
// verified.
// Each merge gets them on its own merge commit `minutes` after merging (within the 6-hour dispatch
// deadline by default).
const verifiedEach = (pulls, minutes = 60) => ({
  [FULL]: pulls.map((p) => wfRun(900000 + p.graph.number, "workflow_dispatch", p.graph.mergeCommit.oid, later(p.graph.mergedAt, minutes), { actor: LANE })),
  [CANARY]: pulls.map((p) => wfRun(800000 + p.graph.number, "push", p.graph.mergeCommit.oid, later(p.graph.mergedAt, minutes))),
});

test("a red full run on a later SHA containing two merges yields gate-failure for each", () => {
  const tip = shaOf(0xa001);
  const result = run({
    pulls: [pr(1301, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] }), pr(1302, "2026-09-02T00:00:00Z", { labels: [SCOPED] })],
    history: [shaOf(1301), shaOf(1302), tip],
    workflowRuns: { [FULL]: [wfRun(1, "schedule", tip, "2026-09-03T00:00:00Z", { conclusion: "failure" })] },
  });
  assert.deepEqual(result.events, gateEvents("2026-09-03T00:08:00Z", "C2-auto-merge", "C3-auto-merge"));
  assert.deepEqual(
    result.gateFailures.map((g) => [g.number, g.check, g.conclusion]),
    [
      [1301, `${FULL} schedule`, "failure"],
      [1302, `${FULL} schedule`, "failure"],
    ],
  );
});

test("a run created before the merge is not its evidence", () => {
  // Run 3 on #1303's own SHA predates #1303's merge, so it is evidence for #1309 only.
  const result = run({
    pulls: [pr(1309, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] }), pr(1303, "2026-09-02T00:00:00Z", { labels: [SCOPED] })],
    workflowRuns: { [FULL]: [wfRun(3, "schedule", shaOf(1303), "2026-09-01T12:00:00Z", { conclusion: "failure" })] },
  });
  assert.deepEqual(result.events, gateEvents("2026-09-01T12:08:00Z", "C2-auto-merge"));
});

test("a post-merge run behind the merge is not its evidence; a diverged one refuses the publish", () => {
  const other = shaOf(0xa002);
  const red = { [FULL]: [wfRun(2, "schedule", other, "2026-09-03T00:00:00Z", { conclusion: "failure" })] };
  const behind = run({ pulls: [pr(1310, "2026-09-02T00:00:00Z", { labels: [MECHANICAL] })], history: [other, shaOf(1310)], workflowRuns: red });
  assert.deepEqual(behind.events, []);
  const diverged = { pulls: [pr(1310, "2026-09-02T00:00:00Z", { labels: [MECHANICAL] })], history: [shaOf(1310), other], diverged: [other] };
  assert.throws(() => run({ ...diverged, workflowRuns: red }), (error) => error instanceof PublishError && /diverged/.test(error.message));
});

test("a merge that is an ancestor of a same-time merge listed before it is still covered by a later run", () => {
  const tip = shaOf(0xa007);
  const result = run({
    pulls: [pr(1401, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] }), pr(1402, "2026-09-01T00:00:00Z", { labels: [SCOPED] })],
    history: [shaOf(1402), shaOf(1401), tip],
    workflowRuns: { [FULL]: [wfRun(11, "schedule", tip, "2026-09-02T00:00:00Z", { conclusion: "failure" })] },
  });
  assert.deepEqual(result.events, gateEvents("2026-09-02T00:08:00Z", "C2-auto-merge", "C3-auto-merge"));
});

test("a post-merge run created after --through still counts", () => {
  const result = run({
    pulls: [pr(1403, "2026-10-04T00:00:00Z", { labels: [MECHANICAL] })],
    workflowRuns: { [CANARY]: [wfRun(12, "push", shaOf(1403), "2026-10-06T00:00:00Z", { conclusion: "failure" })] },
  });
  assert.deepEqual(result.events, gateEvents("2026-10-06T00:08:00Z", "C2-auto-merge"));
});

const gateOf = (result, cell = "C2-auto-merge") => termOf(result, cell, "deterministic-gate pass").detail;
const PASSED = { passed: 1, failed: 0, unsettled: 0, total: 1 };
const FAILED = { passed: 0, failed: 1, unsettled: 0, total: 1 };
const UNSETTLED = { passed: 0, failed: 0, unsettled: 1, total: 1 };

test("a merge passes the gate only with a lane dispatch within 6 hours and a green canary; no timely dispatch is a gate failure", () => {
  const pulls = () => [pr(1404, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] })];
  const noDispatch = gateEvents("2026-09-01T06:00:00Z", "C2-auto-merge");
  const bare = run({ pulls: pulls(), noDefaultDispatch: true });
  assert.deepEqual([gateOf(bare), bare.events], [FAILED, noDispatch]);
  assert.deepEqual(bare.gateFailures, [{ number: 1404, check: "dispatch deadline", conclusion: "no dispatch run by a lane identity within 6 h", at: "2026-09-01T06:00:00Z" }]);
  const dispatchOnly = run({ pulls: pulls(), workflowRuns: { [FULL]: verifiedEach(pulls())[FULL] } });
  assert.deepEqual([gateOf(dispatchOnly), dispatchOnly.events], [UNSETTLED, []]);
  const canaryOnly = run({ pulls: pulls(), noDefaultDispatch: true, workflowRuns: { [CANARY]: verifiedEach(pulls())[CANARY] } });
  assert.deepEqual([gateOf(canaryOnly), canaryOnly.events], [FAILED, noDispatch]);
  assert.deepEqual(gateOf(run({ pulls: pulls(), workflowRuns: verifiedEach(pulls()) })), PASSED);
  const late = run({ pulls: pulls(), workflowRuns: verifiedEach(pulls(), 7 * 60) });
  assert.deepEqual([gateOf(late), late.events], [FAILED, noDispatch]);
});

test("a lane-enqueued merge passes only when its unedited lane pin names headRefOid; otherwise a gate failure", () => {
  const pulls = () => [pr(1501, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] })];
  const head = shaOf(1501 + 0x100000);
  const withComments = (list) => run({ pulls: pulls(), workflowRuns: verifiedEach(pulls()), comments: { 1501: list } });
  assert.deepEqual(gateOf(withComments([pinComment(head)])), PASSED);
  const filler = Array.from({ length: 120 }, () => REC.commentsPage.data.repository.pullRequest.comments.nodes[0]);
  assert.deepEqual(gateOf(withComments([...filler, pinComment(head)])), PASSED);
  const noPin = gateEvents("2026-09-01T06:00:00Z", "C2-auto-merge");
  for (const list of [[], [{ ...pinComment(head), lastEditedAt: "2026-09-01T00:30:00Z" }], [{ ...pinComment(head), author: actorOf("kyle-sexton") }]]) {
    const result = withComments(list);
    assert.deepEqual([gateOf(result), result.events], [FAILED, noPin]);
  }
  const mismatch = withComments([pinComment(shaOf(0xbad))]);
  assert.deepEqual([gateOf(mismatch), mismatch.events], [FAILED, gateEvents("2026-09-01T00:00:00Z", "C2-auto-merge")]);
  // Before the deadline a missing pin is pending, as in check().
  const fresh = [pr(1502, "2026-10-04T22:00:00Z", { labels: [MECHANICAL] })];
  const pending = run({ pulls: fresh, workflowRuns: verifiedEach(fresh, 30), comments: { 1502: [] } });
  assert.deepEqual([gateOf(pending), pending.events], [UNSETTLED, []]);
  // A merge another bot enqueued is autonomous but not the lane's: it has no pin to read back.
  const bot = [pr(1503, "2026-09-01T00:00:00Z", { labels: [MECHANICAL], merger: "kyle-sexton", timeline: [queued("2026-08-31T23:00:00Z", null, "some-app[bot]")] })];
  assert.deepEqual(gateOf(run({ pulls: bot, workflowRuns: verifiedEach(bot), comments: { 1503: [] } })), PASSED);
});

test("a lane identity's native auto-merge owes no pin, as in native_auto_merge", () => {
  const armed = (kind, at, login = LANE) => ({ nodes: [{ __typename: kind, createdAt: at, actor: actorOf(login) }] });
  const enqueue = [queued("2026-08-31T23:50:00Z", LANE)];
  const pulls = (autoMerge, extra = {}) => [pr(1505, "2026-09-01T00:00:00Z", { labels: [MECHANICAL], timeline: enqueue, patch: { autoMerge, ...extra } })];
  const judge = (autoMerge, extra) => {
    const result = run({ pulls: pulls(autoMerge, extra), workflowRuns: verifiedEach(pulls(autoMerge, extra)), comments: { 1505: [] } });
    return [gateOf(result), result.events];
  };
  const noPin = [FAILED, gateEvents("2026-09-01T06:00:00Z", "C2-auto-merge")];
  assert.deepEqual(judge(armed("AutoMergeEnabledEvent", "2026-08-31T23:40:00Z")), [PASSED, []]);
  assert.deepEqual(judge(armed("AutoMergeEnabledEvent", "2026-08-31T23:50:00Z")), [PASSED, []]);
  // The gate's disarm, an arm after the enqueue, a person's arm, or no events: the pin stays owed.
  assert.deepEqual(judge(armed("AutoMergeDisabledEvent", "2026-08-31T23:40:00Z")), noPin);
  assert.deepEqual(judge(armed("AutoMergeEnabledEvent", "2026-08-31T23:55:00Z")), noPin);
  assert.deepEqual(judge(armed("AutoMergeEnabledEvent", "2026-08-31T23:40:00Z", "kyle-sexton")), noPin);
  assert.deepEqual(judge(undefined), noPin);
  // A lane arm on a pull request the lane did not open from this repository is off the gate.
  assert.deepEqual(judge(armed("AutoMergeEnabledEvent", "2026-08-31T23:40:00Z"), { author: actorOf("kyle-sexton") }), noPin);
  assert.deepEqual(judge(armed("AutoMergeEnabledEvent", "2026-08-31T23:40:00Z"), { isCrossRepository: true }), noPin);
  // A red full run after a native merge is still its gate failure.
  const native = pulls(armed("AutoMergeEnabledEvent", "2026-08-31T23:40:00Z"));
  const red = run({ pulls: native, workflowRuns: { [FULL]: [wfRun(9, "schedule", shaOf(1505), "2026-09-01T02:00:00Z", { conclusion: "failure" })] }, comments: { 1505: [] } });
  assert.deepEqual(red.gateFailures.map((g) => [g.number, g.check]), [[1505, `${FULL} schedule`]]);
});

test("a pin past the 30th comment page is no pin, as in read_pin", () => {
  const pulls = () => [pr(1504, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] })];
  const filler = (count) => Array.from({ length: count }, () => REC.commentsPage.data.repository.pullRequest.comments.nodes[0]);
  const withComments = (list) => run({ pulls: pulls(), workflowRuns: verifiedEach(pulls()), comments: { 1504: list } });
  const head = shaOf(1504 + 0x100000);
  assert.deepEqual(gateOf(withComments([...filler(2999), pinComment(head)])), PASSED);
  const beyond = withComments([...filler(3000), pinComment(head)]);
  assert.deepEqual([gateOf(beyond), beyond.events], [FAILED, gateEvents("2026-09-01T06:00:00Z", "C2-auto-merge")]);
});

test("a revert number that is not a GraphQL Int is listed without a lookup", () => {
  const result = run({
    pulls: [
      pr(1601, "2026-09-01T00:00:00Z", { body: `Reverts ${REPO}#99999999999999999999`, merger: "kyle-sexton" }),
      pr(1602, "2026-09-01T00:00:00Z", { body: `Reverts ${REPO}#2147483648`, merger: "kyle-sexton" }),
      pr(1603, "2026-09-01T00:00:00Z", { body: `Reverts ${REPO}#0`, merger: "kyle-sexton" }),
    ],
  });
  const reason = "not a pull request number (a positive GraphQL Int)";
  assert.deepEqual(result.unresolvedReverts, [
    { target: "99999999999999999999", reason },
    { target: "2147483648", reason },
    { target: "0", reason },
  ]);
});

test("a bogus `This reverts commit` SHA is listed, not fatal", () => {
  const bogus = "0123456789abcdef0123456789abcdef01234567";
  const result = run({
    pulls: [pr(1408, "2026-09-01T00:00:00Z", { merger: "kyle-sexton" })],
    commits: [{ ...REC.commit, sha: shaOf(1408), commit: { message: `Revert "x"\n\nThis reverts commit ${bogus}.`, committer: { date: "2026-09-01T00:00:00Z" } } }],
  });
  assert.deepEqual(result.unresolvedReverts, [{ target: bogus, reason: "no commit found for this SHA" }]);
});

test("gh failures: a missing PR is an answer, a missing commit is unresolvable, anything else fails", () => {
  assert.equal(typeof publisher.ghFailure, "function");
  assert.deepEqual(publisher.ghFailure("graphql", true, JSON.stringify(REC.pullNotFound), ""), REC.pullNotFound);
  assert.throws(() => publisher.ghFailure("x/pulls", false, REC.commitNotFound.stdout, REC.commitNotFound.stderr), publisher.UnresolvableError);
  const fails = (body) =>
    assert.throws(
      () => publisher.ghFailure("graphql", true, JSON.stringify(body), "gh: Could not resolve"),
      (error) => error instanceof PublishError && !(error instanceof publisher.UnresolvableError),
    );
  fails(REC.repoNotFound);
  // Each half of the PR-NOT_FOUND test alone: a null pullRequest with a repository-level error, and
  // a pullRequest-path error with the repository gone.
  fails({ ...REC.pullNotFound, errors: REC.repoNotFound.errors });
  fails({ ...REC.repoNotFound, errors: REC.pullNotFound.errors });
});

test("an incomplete page on a lane PR leaves it unclassed, not a refused publish", () => {
  const paged = (patch) => run({ pulls: [pr(1409, "2026-09-01T00:00:00Z", { labels: [MECHANICAL], linked: ISSUE_6007, patch })] });
  const reason = "a linked-issue, label or timeline page is unreadable or incomplete: class unknown";
  for (const patch of [{ closingIssuesReferences: page1(ISSUE_6007, true) }, { timelineItems: page1([], true) }, { labels: page1([{ name: MECHANICAL }], true) }]) {
    assert.deepEqual(paged(patch).unclassedAutonomous, [{ number: 1409, reason }]);
  }
  const issueLabelsPaged = [{ ...ISSUE_6007[0], labels: { ...ISSUE_6007[0].labels, pageInfo: { hasNextPage: true } } }];
  const noLabels = [{ number: 6007 }];
  for (const nodes of [issueLabelsPaged, noLabels]) {
    assert.deepEqual(paged({ closingIssuesReferences: page1(nodes) }).unclassedAutonomous, [{ number: 1409, reason }]);
  }
});

test("an unparsable date refuses the publish", () => {
  const result = () =>
    run({ pulls: [pr(1410, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] })], workflowRuns: { [CANARY]: [wfRun(13, "push", shaOf(1410), "not-a-date", { updated: "not-a-date" })] } });
  assert.throws(result, (error) => error instanceof PublishError && /date/.test(error.message));
});

test("a PR merged into a branch other than the default is not read", () => {
  const result = run({ pulls: [pr(1405, "2026-09-01T00:00:00Z", { labels: [MECHANICAL], base: "release" })] });
  assert.equal(termOf(result, "C2-auto-merge", "autonomous C2 completions").value, 0);
});

test("a link event after the merge in an unrecognized shape leaves the class unknown", () => {
  const odd = { ...link("DisconnectedEvent", 6007, "2026-09-02T00:00:00Z"), subject: { __typename: "PullRequest", number: 5 } };
  const result = run({ pulls: [pr(1406, "2026-09-01T00:00:00Z", { labels: [MECHANICAL], timeline: [odd] })] });
  assert.equal(termOf(result, "C2-auto-merge", "autonomous C2 completions").value, 0);
  assert.deepEqual(result.unclassedAutonomous, [{ number: 1406, reason: "a link event after the merge has an unrecognized shape: links unknown" }]);
});

test("a revert naming a PR that is not merged or does not exist is listed, not fatal", () => {
  const result = run({ pulls: [pr(1407, "2026-09-01T00:00:00Z", { body: `Reverts ${REPO}#999999`, merger: "kyle-sexton" })] });
  assert.deepEqual(result.unresolvedReverts, [{ target: 999999, reason: "not a merged pull request" }]);
});

test("a red full run is a flake only when a lane identity's re-run passed", () => {
  const tip = shaOf(0xa003);
  const rerun = (id, triggering) => wfRun(id, "schedule", tip, "2026-09-02T00:00:00Z", { attempt: 2, triggering, updated: "2026-09-02T01:00:00Z" });
  const firstAttempt = (id) => ({ 1: wfRun(id, "schedule", tip, "2026-09-02T00:00:00Z", { conclusion: "failure" }) });
  const result = run({
    pulls: [pr(1304, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] })],
    history: [shaOf(1304), tip],
    workflowRuns: { [FULL]: [rerun(4, LANE), rerun(5, "kyle-sexton")] },
    attempts: { 4: firstAttempt(4), 5: firstAttempt(5) },
  });
  assert.deepEqual(result.events, gateEvents("2026-09-02T01:00:00Z", "C2-auto-merge"));
});

test("a red run after a merge was verified by a green lane dispatch and canary is not that merge's", () => {
  const [s1, s2] = [shaOf(0xa004), shaOf(0xa005)];
  const result = run({
    pulls: [pr(1305, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] }), pr(1306, "2026-09-01T12:00:00Z", { labels: [SCOPED] })],
    history: [shaOf(1305), s1, shaOf(1306), s2],
    workflowRuns: {
      [FULL]: [wfRun(6, "workflow_dispatch", s1, "2026-09-01T01:00:00Z", { actor: LANE }), wfRun(7, "schedule", s2, "2026-09-02T00:00:00Z", { conclusion: "failure" })],
      [CANARY]: [wfRun(8, "push", s1, "2026-09-01T01:05:00Z")],
    },
  });
  assert.deepEqual(result.events, gateEvents("2026-09-02T00:08:00Z", "C3-auto-merge"));
});

test("a red canary run on a SHA containing the merge yields gate-failure", () => {
  const result = run({
    pulls: [pr(1307, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] })],
    workflowRuns: { [CANARY]: [wfRun(9, "push", shaOf(1307), "2026-09-01T00:01:00Z", { conclusion: "failure" })] },
  });
  assert.deepEqual(result.events, gateEvents("2026-09-01T00:09:00Z", "C2-auto-merge"));
});

test("a red full run awaiting its re-run is unsettled for 6 hours, then a failure", () => {
  const tip = shaOf(0xa006);
  const red = (id, updated) => wfRun(id, "schedule", tip, later(updated, -8), { conclusion: "failure", updated });
  const recent = run({
    pulls: [pr(1308, "2026-10-04T00:00:00Z", { labels: [MECHANICAL] })],
    history: [shaOf(1308), tip],
    workflowRuns: { [FULL]: [red(10, "2026-10-04T23:00:00Z")] },
  });
  assert.deepEqual(recent.events, []);
  assert.equal(termOf(recent, "C2-auto-merge", "deterministic-gate pass").detail.unsettled, 1);
  const stale = run({
    pulls: [pr(1308, "2026-10-04T00:00:00Z", { labels: [MECHANICAL] })],
    history: [shaOf(1308), tip],
    workflowRuns: { [FULL]: [red(10, "2026-10-04T17:00:00Z")] },
  });
  assert.deepEqual(stale.events, gateEvents("2026-10-04T17:00:00Z", "C2-auto-merge"));
});

test("only the named gate checks and status contexts are gate evidence", () => {
  const other = (name, conclusion) => ({ ...REC.checkRun, name, conclusion, completed_at: "2026-09-01T00:10:00Z" });
  const pulls = [pr(1201, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] })];
  const result = run({
    pulls,
    checkRuns: { 1201: [REC.checkRun, other("dispatch", "failure"), other("resolve-conflicts / run", "cancelled")] },
    statuses: { 1201: [{ ...REC.status, context: "GitGuardian", state: "error" }] },
    workflowRuns: verifiedEach(pulls),
  });
  assert.deepEqual(result.events, []);
  assert.deepEqual(termOf(result, "C2-auto-merge", "deterministic-gate pass").detail, { passed: 1, failed: 0, unsettled: 0, total: 1 });
});

test("no gate check named is refused rather than read as an empty gate", () => {
  assert.throws(() => run({ pulls: [] }, { gateChecks: [] }), (error) => error instanceof PublishError && /--gate-check/.test(error.message));
  const cli = spawnSync(process.execPath, [join(HERE, "publish-promotion-evidence.mjs"), "--repo", REPO, "--since", SINCE, "--lane-login", LANE], { encoding: "utf8" });
  assert.equal(cli.status, 2);
  assert.match(cli.stderr, /--gate-check/);
});

test("merges outside --since..--through appear in no list, count and event", () => {
  const failing = (at) => [{ ...REC.checkRun, conclusion: "failure", completed_at: at }];
  const result = run({
    pulls: [pr(1202, "2026-07-31T00:00:00Z"), pr(1203, "2026-07-31T00:00:00Z", { labels: [MECHANICAL] }), pr(1204, "2026-10-06T00:00:00Z", { labels: [SCOPED] })],
    checkRuns: { 1202: failing("2026-08-02T00:00:00Z"), 1203: failing("2026-08-02T00:00:00Z"), 1204: failing("2026-10-06T00:10:00Z") },
  });
  assert.deepEqual([result.events, result.unclassedAutonomous], [[], []]);
  assert.equal(termOf(result, "C2-auto-merge", "autonomous C2 completions").value, 0);
  assert.equal(termOf(result, "C3-auto-merge", "autonomous C3 completions").value, 0);
});

test("a revert-button PR of an autonomous C2 merge yields reverted-merge at the revert's merge time", () => {
  const result = run({
    pulls: [
      pr(101, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] }),
      pr(102, "2026-09-02T00:00:00Z", { title: 'Revert "chore: bump"', body: `Reverts ${REPO}#101`, merger: "kyle-sexton" }),
    ],
  });
  assert.deepEqual(result.events, [{ cell: "C2-auto-merge", event: "reverted-merge", at: "2026-09-02T00:00:00Z" }]);
  assert.deepEqual(termOf(result, "C2-auto-merge", "reverted merges"), { term: "reverted merges", value: 1, threshold: "0", pass: false });
});

test("a git-revert commit pushed straight to the default branch yields reverted-merge for C3 auto-merge", () => {
  // No PR merged the revert commit, and its git author can be forged, so it counts.
  const result = run({
    pulls: [pr(201, "2026-09-01T00:00:00Z", { labels: [SCOPED] })],
    history: [shaOf(201), shaOf(999)],
    commits: [{ ...REC.commit, sha: shaOf(999), commit: { message: `Revert "x"\n\nThis reverts commit ${shaOf(201)}.`, committer: { date: "2026-09-03T00:00:00Z" } } }],
  });
  assert.deepEqual(result.events, [{ cell: "C3-auto-merge", event: "reverted-merge", at: "2026-09-03T00:00:00Z" }]);
});

test("a revert commit whose REST-named PR GraphQL cannot resolve counts as a direct push, not a crash", () => {
  const fixture = {
    pulls: [pr(201, "2026-09-01T00:00:00Z", { labels: [SCOPED] })],
    history: [shaOf(201), shaOf(999)],
    commits: [{ ...REC.commit, sha: shaOf(999), commit: { message: `Revert "x"\n\nThis reverts commit ${shaOf(201)}.`, committer: { date: "2026-09-03T00:00:00Z" } } }],
  };
  const base = github(fixture);
  const gh = (path, graphql) =>
    path === `repos/${REPO}/commits/${shaOf(999)}/pulls` ? [{ number: 998, merged_at: "2026-09-03T00:00:00Z", merge_commit_sha: shaOf(999) }] : base(path, graphql);
  const result = run(fixture, { gh });
  assert.deepEqual(result.events, [{ cell: "C3-auto-merge", event: "reverted-merge", at: "2026-09-03T00:00:00Z" }]);
});

test("a revert PR counts whoever merged or enqueued it, a lane or another bot included", () => {
  const result = run({
    pulls: [
      pr(1701, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] }),
      pr(1702, "2026-09-02T00:00:00Z", { title: 'Revert "x"', body: `Reverts ${REPO}#1701` }),
      pr(1703, "2026-09-01T00:00:00Z", { labels: [SCOPED] }),
      pr(1704, "2026-09-02T00:00:00Z", { body: `Reverts ${REPO}#1703`, merger: "kyle-sexton", timeline: [queued("2026-09-01T23:00:00Z", null, "some-app[bot]")] }),
    ],
  });
  assert.deepEqual(result.events.filter((e) => e.event === "reverted-merge"), [
    { cell: "C2-auto-merge", event: "reverted-merge", at: "2026-09-02T00:00:00Z" },
    { cell: "C3-auto-merge", event: "reverted-merge", at: "2026-09-02T00:00:00Z" },
  ]);
  assert.deepEqual(result.unresolvedReverts, []);
});

test("a lane-merged revert PR and its squash commit count once", () => {
  const result = run({
    pulls: [pr(1705, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] }), pr(1706, "2026-09-02T00:00:00Z", { body: `Reverts ${REPO}#1705` })],
    commits: [{ ...REC.commit, sha: shaOf(1706), commit: { message: `Revert "x" (#1706)\n\nReverts ${REPO}#1705`, committer: { date: "2026-09-02T00:00:00Z" } } }],
  });
  assert.deepEqual(result.events.filter((e) => e.event === "reverted-merge"), [{ cell: "C2-auto-merge", event: "reverted-merge", at: "2026-09-02T00:00:00Z" }]);
  assert.deepEqual(result.unresolvedReverts, []);
});

test("a revert of a human merge, and a revert written only in prose, emit no event; prose is listed unresolved", () => {
  const result = run({
    pulls: [
      pr(301, "2026-09-01T00:00:00Z", { labels: [MECHANICAL], merger: "kyle-sexton" }),
      pr(302, "2026-09-02T00:00:00Z", { body: `Reverts ${REPO}#301` }),
      pr(303, "2026-09-03T00:00:00Z", { title: "revert(x): drop the K3 check", body: "Reverts the bullet #301 added." }),
    ],
  });
  assert.deepEqual(result.events, []);
  assert.deepEqual(result.unresolvedReverts, [{ number: 303, title: "revert(x): drop the K3 check" }]);
});

test("a failing check run on an autonomous merge commit yields gate-failure at its completion", () => {
  const failing = { ...REC.checkRun, conclusion: "failure", completed_at: "2026-09-01T00:10:00Z" };
  const result = run({ pulls: [pr(401, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] })], checkRuns: { 401: [REC.checkRun, failing] } });
  assert.deepEqual(result.events, [{ cell: "C2-auto-merge", event: "gate-failure", at: "2026-09-01T00:10:00Z" }]);
  assert.deepEqual(termOf(result, "C2-auto-merge", "deterministic-gate pass").detail, { passed: 0, failed: 1, unsettled: 0, total: 1 });
});

test("a missed-blocking label a human applied to a C3 PR yields verification-divergence; one a bot applied does not", () => {
  const labeled = (login, type, at) => ({ ...REC.issueEvent, event: "labeled", label: { name: MISSED }, actor: { login, type }, created_at: at });
  const result = run({
    pulls: [
      pr(501, "2026-09-01T00:00:00Z", { labels: [SCOPED, MISSED], merger: "kyle-sexton" }),
      pr(502, "2026-09-01T00:00:00Z", { labels: [SCOPED, MISSED] }),
      pr(503, "2026-09-01T00:00:00Z", { labels: [SCOPED, MISSED], merger: "kyle-sexton" }),
    ],
    issueEvents: {
      501: [labeled("kyle-sexton", "User", "2026-09-04T00:00:00Z")],
      502: [labeled(LANE, "Bot", "2026-09-05T00:00:00Z")],
      503: [labeled("github-actions[bot]", "Bot", "2026-09-06T00:00:00Z")],
    },
  });
  assert.deepEqual(result.events, [{ cell: "C3-ai-review-blocking", event: "verification-divergence", at: "2026-09-04T00:00:00Z" }]);
});

test("20 autonomous C2 merges over 14+ days pass the C2 term and 19 fail it", () => {
  const merges = (count) => Array.from({ length: count }, (_, i) => pr(600 + i, `2026-09-${String(i + 1).padStart(2, "0")}T00:00:00Z`, { labels: [MECHANICAL] }));
  const pulls = merges(20);
  const twenty = run({ pulls, workflowRuns: verifiedEach(pulls) });
  assert.equal(termOf(twenty, "C2-auto-merge", "autonomous C2 completions").pass, true);
  assert.equal(twenty.cells["C2-auto-merge"].pass, true);
  const nineteen = run({ pulls: merges(19) });
  assert.deepEqual(termOf(nineteen, "C2-auto-merge", "autonomous C2 completions"), { term: "autonomous C2 completions", value: 19, threshold: ">= 20", pass: false });
  assert.equal(nineteen.cells["C2-auto-merge"].pass, false);
});

test("a class carried only by the linked issue counts, and the higher of issue and PR class wins", () => {
  const result = run({
    pulls: [pr(801, "2026-09-01T00:00:00Z", { linked: ISSUE_6007 }), pr(802, "2026-09-02T00:00:00Z", { labels: [MECHANICAL], linked: ISSUE_6007 })],
  });
  assert.equal(termOf(result, "C3-auto-merge", "autonomous C3 completions").value, 2);
  assert.equal(termOf(result, "C2-auto-merge", "autonomous C2 completions").value, 0);
});

test("advisory reviews are counted from the named AI reviewers and reported unmeasured without one", () => {
  const fixture = { pulls: [pr(701, "2026-09-01T00:00:00Z", { labels: [SCOPED], merger: "kyle-sexton" })], reviews: { 701: [REC.review] } };
  assert.equal(termOf(run(fixture, { aiReviewers: [REC.review.user.login] }), "C3-ai-review-blocking", "advisory AI reviews on C3").value, 1);
  assert.equal(termOf(run(fixture), "C3-ai-review-blocking", "advisory AI reviews on C3").value, null);
});

test("a failed check run that was re-run green still yields gate-failure (filter=all)", () => {
  const failed = { ...REC.checkRun, conclusion: "failure", completed_at: "2026-09-01T00:10:00Z", superseded: true };
  const result = run({ pulls: [pr(901, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] })], checkRuns: { 901: [failed, REC.checkRun] } });
  assert.deepEqual(result.events, [{ cell: "C2-auto-merge", event: "gate-failure", at: "2026-09-01T00:10:00Z" }]);
  assert.equal(termOf(result, "C2-auto-merge", "deterministic-gate pass").pass, false);
});

test("a failure or error commit status, even one later superseded by success, yields gate-failure", () => {
  const statuses = [
    { ...REC.status, state: "success", created_at: "2026-09-01T00:30:00Z" },
    { ...REC.status, state: "error", created_at: "2026-09-01T00:20:00Z" },
    { ...REC.status, context: "other", state: "failure", created_at: "2026-09-01T00:15:00Z" },
  ];
  const result = run({ pulls: [pr(902, "2026-09-01T00:00:00Z", { labels: [SCOPED] })], statuses: { 902: statuses } }, { gateChecks: [...GATE, "other"] });
  assert.deepEqual(result.events, [
    { cell: "C3-auto-merge", event: "gate-failure", at: "2026-09-01T00:15:00Z" },
    { cell: "C3-auto-merge", event: "gate-failure", at: "2026-09-01T00:20:00Z" },
  ]);
});

test("a gate failure that completes after --through is still emitted", () => {
  const failing = { ...REC.checkRun, conclusion: "failure", completed_at: "2026-10-06T00:00:00Z" };
  const result = run({ pulls: [pr(903, "2026-10-04T23:00:00Z", { labels: [MECHANICAL] })], checkRuns: { 903: [failing] } });
  assert.deepEqual(result.events, [{ cell: "C2-auto-merge", event: "gate-failure", at: "2026-10-06T00:00:00Z" }]);
});

test("a missed-blocking label a human applied and someone later removed still counts", () => {
  const result = run({
    pulls: [pr(904, "2026-09-01T00:00:00Z", { labels: [SCOPED], merger: "kyle-sexton" })],
    issueEvents: { 904: [labelEvent("labeled", MISSED, "2026-09-04T00:00:00Z"), labelEvent("unlabeled", MISSED, "2026-09-05T00:00:00Z", LANE, "Bot")] },
  });
  assert.deepEqual(result.events, [{ cell: "C3-ai-review-blocking", event: "verification-divergence", at: "2026-09-04T00:00:00Z" }]);
});

test("the class is read as of the merge: post-merge relabeling neither adds nor drops a merge", () => {
  const result = run({
    pulls: [
      pr(905, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] }),
      pr(906, "2026-09-01T00:00:00Z"),
      pr(907, "2026-09-01T00:00:00Z", { labels: [MECHANICAL], linked: ISSUE_6007 }),
    ],
    issueEvents: {
      905: [labelEvent("labeled", MECHANICAL, "2026-09-02T00:00:00Z")],
      906: [labelEvent("labeled", MECHANICAL, "2026-08-31T00:00:00Z"), labelEvent("unlabeled", MECHANICAL, "2026-09-02T00:00:00Z", LANE, "Bot")],
      // The linked 6007 is labeled scoped now, but gained that label after 907 merged.
      6007: [labelEvent("labeled", SCOPED, "2026-09-03T00:00:00Z")],
    },
  });
  assert.equal(termOf(result, "C2-auto-merge", "autonomous C2 completions").value, 2);
  assert.equal(termOf(result, "C3-auto-merge", "autonomous C3 completions").value, 0);
});

test("20 merges inside one day fail the 14-day window, which ends at the last counted merge", () => {
  const sameDay = Array.from({ length: 20 }, (_, i) => pr(1000 + i, later("2026-09-01T00:00:00Z", i), { labels: [MECHANICAL] }));
  const result = run({ pulls: sameDay });
  assert.equal(termOf(result, "C2-auto-merge", "window days").pass, false);
  assert.equal(result.cells["C2-auto-merge"].window.to, "2026-09-01T00:19:00.000Z");
});

test("--through is clamped to now", () => {
  const result = run({ pulls: [] }, { through: "2099-01-01T00:00:00Z" });
  assert.ok(Date.parse(result.through) <= Date.now());
});

test("an issue unlinked after the merge still classes the merge; one linked after it does not", () => {
  const result = run({
    pulls: [
      pr(1101, "2026-09-01T00:00:00Z", { timeline: [link("ConnectedEvent", 6007, "2026-08-31T00:00:00Z"), link("DisconnectedEvent", 6007, "2026-09-02T00:00:00Z")] }),
      pr(1102, "2026-09-01T00:00:00Z", { linked: ISSUE_6007, timeline: [link("ConnectedEvent", 6007, "2026-09-02T00:00:00Z")] }),
    ],
    issues: { 6007: REC.issue },
  });
  assert.equal(termOf(result, "C3-auto-merge", "autonomous C3 completions").value, 1);
  assert.deepEqual(result.unclassedAutonomous, [{ number: 1102, reason: "no work-class label at merge" }]);
});

test("an autonomous merge whose links cannot be rebuilt is unclassed, and its contrary events hit every cell", () => {
  const failing = { ...REC.checkRun, conclusion: "failure", completed_at: "2026-09-01T00:10:00Z" };
  const result = run({
    pulls: [pr(1103, "2026-09-01T00:00:00Z", { labels: [MECHANICAL], lastEditedAt: "2026-09-02T00:00:00Z" })],
    checkRuns: { 1103: [failing] },
  });
  assert.deepEqual(result.unclassedAutonomous, [{ number: 1103, reason: "PR body edited after the merge: closing-keyword links unknown" }]);
  assert.deepEqual(result.events, ["C2-auto-merge", "C3-ai-review-blocking", "C3-auto-merge"].map((cell) => ({ cell, event: "gate-failure", at: "2026-09-01T00:10:00Z" })));
  assert.equal(termOf(result, "C2-auto-merge", "autonomous C2 completions").value, 0);
});

test("a revert of an unclassed autonomous merge yields reverted-merge against every cell", () => {
  const result = run({
    pulls: [pr(1104, "2026-09-01T00:00:00Z"), pr(1105, "2026-09-02T00:00:00Z", { body: `Reverts ${REPO}#1104`, merger: "kyle-sexton" })],
  });
  assert.deepEqual(result.events, ["C2-auto-merge", "C3-ai-review-blocking", "C3-auto-merge"].map((cell) => ({ cell, event: "reverted-merge", at: "2026-09-02T00:00:00Z" })));
});

test("a User owning the bare slug of an App lane is human, not the lane", () => {
  const result = run({ pulls: [pr(1110, "2026-09-01T00:00:00Z", { labels: [MECHANICAL], merger: "lane-bot", timeline: [queued("2026-08-31T23:00:00Z", "lane-bot")] })] });
  assert.equal(termOf(result, "C2-auto-merge", "autonomous C2 completions").value, 0);
});

test("lane logins match case-insensitively", () => {
  const result = run({ pulls: [pr(1106, "2026-09-01T00:00:00Z", { labels: [MECHANICAL], merger: "Lane-User", timeline: [queued("2026-08-31T23:00:00Z", "Lane-User")] })] }, { laneLogins: ["lane-user"] });
  assert.equal(termOf(result, "C2-auto-merge", "autonomous C2 completions").value, 1);
});

test("a merge a bot or nobody enqueued is autonomous even under a human merged_by; a human enqueue is not", () => {
  const result = run({
    pulls: [
      pr(1107, "2026-09-01T00:00:00Z", { labels: [MECHANICAL], merger: "kyle-sexton", timeline: [queued("2026-08-31T23:00:00Z", null, "some-app[bot]")] }),
      pr(1108, "2026-09-01T00:00:00Z", { labels: [MECHANICAL], merger: "kyle-sexton", timeline: [queued("2026-08-31T23:00:00Z", "kyle-sexton")] }),
      pr(1109, "2026-09-01T00:00:00Z", { labels: [MECHANICAL], merger: "kyle-sexton" }),
    ],
  });
  assert.equal(termOf(result, "C2-auto-merge", "autonomous C2 completions").value, 1);
});

test("a cancelled gate run counts as a failure unless a later run of the same check succeeded", () => {
  const cancelled = (name, at) => ({ ...REC.checkRun, name, conclusion: "cancelled", completed_at: at });
  const pulls = [pr(1110, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] }), pr(1111, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] })];
  const result = run({
    pulls,
    checkRuns: {
      1110: [cancelled("lint-repo", "2026-09-01T00:10:00Z")],
      1111: [cancelled("lint-repo", "2026-09-01T00:10:00Z"), { ...REC.checkRun, completed_at: "2026-09-01T00:20:00Z" }],
    },
    workflowRuns: verifiedEach(pulls),
  });
  assert.deepEqual(result.events, [{ cell: "C2-auto-merge", event: "gate-failure", at: "2026-09-01T00:10:00Z" }]);
  assert.deepEqual(termOf(result, "C2-auto-merge", "deterministic-gate pass").detail, { passed: 1, failed: 1, unsettled: 0, total: 2 });
  assert.deepEqual(result.gateFailures, [{ number: 1110, check: "lint-repo", conclusion: "cancelled", at: "2026-09-01T00:10:00Z" }]);
});

test("a revert seen in both the PR body and the squash commit yields one event at the earlier time", () => {
  const result = run({
    pulls: [
      pr(909, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] }),
      pr(910, "2026-09-02T00:00:00Z", { title: 'Revert "x"', body: `Reverts ${REPO}#909`, merger: "kyle-sexton" }),
    ],
    commits: [{ ...REC.commit, sha: shaOf(910), commit: { message: `Revert "x" (#910)\n\nReverts ${REPO}#909`, committer: { date: "2026-09-01T23:55:00Z" } } }],
  });
  assert.deepEqual(result.events, [{ cell: "C2-auto-merge", event: "reverted-merge", at: "2026-09-01T23:55:00Z" }]);
});

test("a PR updated while the listing pages is not skipped", () => {
  // 101 unclassed merges plus one C3 merge that sorts last by update time until it is updated.
  const pulls = Array.from({ length: 101 }, (_, i) => pr(2000 + i, later("2026-09-10T00:00:00Z", i)));
  pulls.push(pr(3000, "2026-09-05T00:00:00Z", { labels: [SCOPED] }));
  const result = run({ pulls, bumpOnPage2: 3000 });
  assert.equal(termOf(result, "C3-auto-merge", "autonomous C3 completions").value, 1);
});

const A = { cell: "C2-auto-merge", event: "reverted-merge", at: "2026-09-02T00:00:00Z" };
const B = { cell: "C3-auto-merge", event: "gate-failure", at: "2026-09-03T00:00:00Z" };
const hash = (text) => createHash("sha256").update(text).digest("hex");

test("the sidecar hash matches the published file, and prev_sha256 names the file it replaced", () => {
  const out = mkdtempSync(join(base, "out-"));
  const first = publish(out, [A], THROUGH, new Date("2026-10-05T00:00:01Z"));
  const firstBytes = readFileSync(join(out, "evidence.json"), "utf8");
  assert.deepEqual(JSON.parse(firstBytes), [A]);
  assert.deepEqual(JSON.parse(readFileSync(join(out, "evidence.meta.json"), "utf8")), {
    generated_at: "2026-10-05T00:00:01.000Z",
    through: THROUGH,
    sha256: hash(firstBytes),
    prev_sha256: null,
  });
  assert.equal(first.sha256, hash(firstBytes));
  const second = publish(out, [A, B], THROUGH);
  assert.equal(second.sha256, hash(readFileSync(join(out, "evidence.json"), "utf8")));
  assert.equal(second.prev_sha256, hash(firstBytes));
});

test("publishing a set that drops a previously published event is refused and leaves both files unchanged", () => {
  const out = mkdtempSync(join(base, "out-"));
  publish(out, [A, B], THROUGH);
  const before = [readFileSync(join(out, "evidence.json"), "utf8"), readFileSync(join(out, "evidence.meta.json"), "utf8")];
  assert.throws(() => publish(out, [B], THROUGH), (error) => error instanceof PublishError && /refusing.*drop 1/.test(error.message));
  assert.deepEqual([readFileSync(join(out, "evidence.json"), "utf8"), readFileSync(join(out, "evidence.meta.json"), "utf8")], before);
});

test("an existing temp file is neither overwritten nor removed, and nothing is published", () => {
  const out = mkdtempSync(join(base, "out-"));
  const temp = join(out, `evidence.json.${process.pid}.tmp`);
  writeFileSync(temp, "planted");
  assert.throws(() => publish(out, [A], THROUGH), { code: "EEXIST" });
  assert.equal(readFileSync(temp, "utf8"), "planted");
  assert.throws(() => readFileSync(join(out, "evidence.json")), { code: "ENOENT" });
});

test("an events file that no longer matches its sidecar is refused and left unchanged", () => {
  const out = mkdtempSync(join(base, "out-"));
  publish(out, [A], THROUGH);
  writeFileSync(join(out, "evidence.json"), `${JSON.stringify([A, B], null, 2)}\n`);
  assert.throws(() => publish(out, [A, B], THROUGH), /refusing.*sidecar/);
  assert.deepEqual(JSON.parse(readFileSync(join(out, "evidence.json"), "utf8")), [A, B]);
});

test("a sidecar write failure leaves the published events file unchanged", () => {
  const out = mkdtempSync(join(base, "out-"));
  publish(out, [A], THROUGH);
  const before = readFileSync(join(out, "evidence.json"), "utf8");
  writeFileSync(join(out, `evidence.meta.json.${process.pid}.tmp`), "planted");
  assert.throws(() => publish(out, [A, B], THROUGH), { code: "EEXIST" });
  assert.equal(readFileSync(join(out, "evidence.json"), "utf8"), before);
  assert.throws(() => readFileSync(join(out, `evidence.json.${process.pid}.tmp`)), { code: "ENOENT" });
});

test("a failed sidecar rename puts the previous events file back, or removes a first one", () => {
  const failMeta = (from, to) => {
    if (to.endsWith("evidence.meta.json")) throw Object.assign(new Error("rename failed"), { code: "EIO" });
    renameSync(from, to);
  };
  const out = mkdtempSync(join(base, "out-"));
  assert.throws(() => publish(out, [A], THROUGH, new Date(), { rename: failMeta }), { code: "EIO" });
  assert.deepEqual(readdirSync(out), []);
  publish(out, [A], THROUGH);
  const before = readFileSync(join(out, "evidence.json"), "utf8");
  assert.throws(() => publish(out, [A, B], THROUGH, new Date(), { rename: failMeta }), { code: "EIO" });
  assert.equal(readFileSync(join(out, "evidence.json"), "utf8"), before);
  assert.deepEqual(readdirSync(out).sort(), ["evidence.json", "evidence.meta.json"]);
  publish(out, [A, B], THROUGH);
});

test("an existing events file that is not a JSON array is refused", () => {
  const out = mkdtempSync(join(base, "out-"));
  writeFileSync(join(out, "evidence.json"), "{}");
  assert.throws(() => publish(out, [A], THROUGH), /refusing.*not a JSON array/);
});

test("the CLI exits 2 on missing required arguments", () => {
  const cli = spawnSync(process.execPath, [join(HERE, "publish-promotion-evidence.mjs"), "--repo", REPO], { encoding: "utf8" });
  assert.equal(cli.status, 2);
  assert.match(cli.stderr, /--lane-login/);
});

// Deletion. run_number starts at 1 per workflow, rises with each new run and a re-run keeps it
// (GitHub's contexts reference, github.run_number), so a missing number between two runs created
// inside the window is a deleted run. The fake numbers runs that way and drops `deletedRuns`.
const ALL = ["C2-auto-merge", "C3-ai-review-blocking", "C3-auto-merge"];
const schedules = (ids, day = 2) => ids.map((id, n) => wfRun(id, "schedule", shaOf(0xb000 + id), `2026-09-${String(day + n).padStart(2, "0")}T00:00:00Z`));
const refusesWith = (reason) => (error) => error instanceof PublishError && error.failClosedReason?.startsWith(reason) && error.message.startsWith(`refusing to publish: ${reason}`);

test("a run deleted between two runs created inside the window refuses with run-deleted, in either workflow", () => {
  assert.throws(() => run({ workflowRuns: { [FULL]: schedules([21, 22, 23]) }, deletedRuns: [22] }), refusesWith(`run-deleted: ${FULL}`));
  const canaries = [41, 42, 43].map((id, n) => wfRun(id, "push", shaOf(0xb100 + id), `2026-09-0${n + 2}T00:00:00Z`));
  assert.throws(() => run({ workflowRuns: { [CANARY]: canaries }, deletedRuns: [42] }), refusesWith(`run-deleted: ${CANARY}`));
});

// That a re-run keeps its number is GitHub's (the pointer above); the fake only lists it that way.
test("consecutive run numbers pass, a run on its second attempt among them", () => {
  assert.deepEqual(run({ workflowRuns: { [FULL]: schedules([21, 22, 23]) } }).events, []);
  const rerun = wfRun(31, "schedule", shaOf(0xb031), "2026-09-02T00:00:00Z", { attempt: 2, triggering: LANE });
  const result = run({ workflowRuns: { [FULL]: [rerun, ...schedules([32], 3)] }, attempts: { 31: { 1: { ...rerun, run_attempt: 1 } } } });
  assert.deepEqual(result.events, []);
});

test("a deleted run at a window edge is no gap: the newest, the oldest, or one before --since", () => {
  for (const deleted of [21, 23]) assert.deepEqual(run({ workflowRuns: { [FULL]: schedules([21, 22, 23]) }, deletedRuns: [deleted] }).events, []);
  const beforeSince = [wfRun(20, "schedule", shaOf(0xb020), "2026-07-30T00:00:00Z"), wfRun(19, "schedule", shaOf(0xb019), "2026-07-31T00:00:00Z")];
  assert.deepEqual(run({ workflowRuns: { [FULL]: [...beforeSince, ...schedules([21, 22])] }, deletedRuns: [19] }).events, []);
});

test("over 1,000 runs in the window are read in halves, and a deletion among them still refuses", () => {
  const many = Array.from({ length: 1002 }, (_, n) => wfRun(100000 + n, "pull_request", shaOf(0xc000), later("2026-09-01T00:00:00Z", n)));
  assert.deepEqual(run({ workflowRuns: { [FULL]: many } }).events, []);
  // Any one run but the oldest and newest, so a deletion where two halves meet refuses too.
  for (let id = 100001; id < 101001; id += 1) {
    assert.throws(() => run({ workflowRuns: { [FULL]: many }, deletedRuns: [id] }), refusesWith(`run-deleted: ${FULL}`), `run ${id}`);
  }
});

// A run listed after page 1 was read shifts every later page by one, so the oldest run falls off the
// last page and one deletion would fit the count: a count that changes between pages refuses.
test("a run count that changes between page reads refuses, though one deletion would otherwise fit", () => {
  const runs = Array.from({ length: 202 }, (_, n) => wfRun(200000 + n, "pull_request", shaOf(0xd000), later("2026-09-01T00:00:00Z", n)));
  const shifted = { workflowRuns: { [FULL]: runs }, deletedRuns: [200099], lateRuns: [200201] };
  assert.throws(
    () => run(shifted),
    (error) => error instanceof PublishError && !(error.failClosedReason ?? "").startsWith("run-deleted") && /run count changed from 200 to 201/.test(error.message),
  );
});

// The alert workflow's record: first body line `<!-- babysit-merge-demotion sha=<S> signal=<name> -->`,
// filed by github-actions[bot], a repeat failure commented as `The post-merge check found this
// failure again: <run>/attempts/<n>` (.github/workflows/post-merge-demotion-alert.yml).
const AGAIN = (at, login) => issueComment(`The post-merge check found this failure again: https://github.com/${REPO}/actions/runs/9/attempts/2`, at, login);

test("a demotion issue filed inside the window, open or closed, is a gate-failure on every cell at its creation", () => {
  const result = run({ demotionIssues: [demotionIssue(7001, "2026-09-10T00:00:00Z")] });
  assert.deepEqual(result.events, gateEvents("2026-09-10T00:00:00Z", ...ALL));
  assert.deepEqual(result.gateFailures.map((g) => g.issue), [7001]);
});

test("a repeat-failure comment inside the window counts; an issue filed before the window does not", () => {
  const old = demotionIssue(7002, "2026-07-01T00:00:00Z", { updatedAt: "2026-09-12T00:00:00Z", comments: [AGAIN("2026-07-02T00:00:00Z"), AGAIN("2026-09-12T00:00:00Z")] });
  assert.deepEqual(run({ demotionIssues: [old] }).events, gateEvents("2026-09-12T00:00:00Z", ...ALL));
});

// The repository is public, so anyone can comment on a record: only a filer's comment is a repeat
// failure, as the alert workflow reads only its own. Every comment is read, however many.
test("only a filer's repeat-failure comment counts, past the first hundred comments too", () => {
  const spam = Array.from({ length: 150 }, (_, i) => AGAIN(later("2026-09-12T00:00:00Z", i), "someone"));
  const record = demotionIssue(7008, "2026-07-01T00:00:00Z", { updatedAt: "2026-09-20T00:00:00Z", comments: [...spam, AGAIN("2026-09-20T00:00:00Z")] });
  assert.deepEqual(run({ demotionIssues: [record] }).events, gateEvents("2026-09-20T00:00:00Z", ...ALL));
  const ignored = demotionIssue(7009, "2026-07-01T00:00:00Z", { updatedAt: "2026-09-20T00:00:00Z", comments: spam });
  assert.deepEqual(run({ demotionIssues: [ignored] }).events, []);
});

test("a lane-filed lookalike or an edited record can only add gate-failures; an unmarked unedited issue adds none", () => {
  const lookalike = demotionIssue(7003, "2026-09-10T00:00:00Z", { author: LANE, comments: [issueComment("re-run passed: cleared", "2026-09-11T00:00:00Z", LANE)] });
  const stripped = demotionIssue(7004, "2026-09-11T00:00:00Z", { body: "nothing here", edits: [{ diff: REC.demotionIssue.body, deletedAt: null }] });
  const truncated = demotionIssue(7005, "2026-09-12T00:00:00Z", { body: "nothing here", edits: [], editCount: 3 });
  const hidden = demotionIssue(7006, "2026-09-13T00:00:00Z", { updatedAt: "2026-09-20T00:00:00Z", comments: [AGAIN("2026-09-20T00:00:00Z", LANE)] });
  const report = demotionIssue(7007, "2026-09-14T00:00:00Z", { body: "<!-- link-check report -->" });
  const result = run({ demotionIssues: [lookalike, stripped, truncated, hidden, report] });
  assert.deepEqual(result.events, [
    ...gateEvents("2026-09-10T00:00:00Z", ...ALL),
    ...gateEvents("2026-09-11T00:00:00Z", ...ALL),
    ...gateEvents("2026-09-12T00:00:00Z", ...ALL),
    ...gateEvents("2026-09-13T00:00:00Z", ...ALL),
    ...gateEvents("2026-09-20T00:00:00Z", ...ALL),
  ]);
});

test("an issue number missing inside the window refuses with issue-deleted on 410, and issue-missing when it moved", () => {
  const listed = [issueItem(7101, "2026-09-01T00:00:00Z"), issueItem(7103, "2026-09-03T00:00:00Z", { pull: true })];
  assert.throws(() => run({ issueList: listed, goneIssues: [7102] }), refusesWith("issue-deleted: #7102"));
  const moved = { ...REC.issue, number: 7102, repository_url: "https://api.github.com/repos/someone/elsewhere" };
  assert.throws(() => run({ issueList: listed, issues: { 7102: moved } }), refusesWith("issue-missing: #7102"));
  assert.deepEqual(run({ issueList: listed, issues: { 7102: { ...REC.issueListItem, number: 7102 } } }).events, []);
  // Discussions share the number sequence and read 404 as issues: anyone else's is no gap, a filer's
  // fails closed, and a 404 that is no discussion is missing.
  assert.deepEqual(run({ issueList: listed, discussions: { 7102: "someone" } }).events, []);
  assert.throws(() => run({ issueList: listed, discussions: { 7102: "github-actions[bot]" } }), refusesWith("issue-missing: #7102"));
  assert.throws(() => run({ issueList: listed, discussions: { 7102: LANE } }), refusesWith("issue-missing: #7102"));
  assert.throws(() => run({ issueList: listed, missingIssues: [7102] }), refusesWith("issue-missing: #7102"));
  // Only numbers between items created inside the window are read.
  assert.deepEqual(run({ issueList: [issueItem(7100, "2026-07-01T00:00:00Z"), ...listed.slice(1)], goneIssues: [7101, 7102] }).events, []);
});
