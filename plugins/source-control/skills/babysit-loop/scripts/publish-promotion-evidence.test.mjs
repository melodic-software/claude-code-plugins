#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import { collect, PublishError, publish } from "./publish-promotion-evidence.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
// Real `gh api` responses from this repository (PR #7352, its merge commit, a check run, an
// issue event and a review), recorded 2026-10-12 and trimmed to the fields the publisher reads.
// Each case copies a record and varies number, labels, merger and timestamps.
const REC = JSON.parse(readFileSync(join(HERE, "fixtures", "publish-promotion-evidence", "recorded.json"), "utf8"));
const REPO = "melodic-software/claude-code-plugins";
const LANE = "lane-bot[bot]";
const SINCE = "2026-08-01T00:00:00Z";
const THROUGH = "2026-10-05T00:00:00Z";
const MECHANICAL = "work-class: mechanical";
const SCOPED = "work-class: scoped";
const MISSED = "ai-review: missed-blocking";

const base = mkdtempSync(join(tmpdir(), "publish-promotion-evidence-"));
after(() => rmSync(base, { recursive: true, force: true }));

const shaOf = (number) => number.toString(16).padStart(40, "0");
const later = (at, minutes) => new Date(Date.parse(at) + minutes * 60_000).toISOString().replace(".000Z", "Z");

// GraphQL spells an App as `__typename: Bot` with the bare slug; REST adds `[bot]`.
const actorOf = (login) => (login === null ? null : login.endsWith("[bot]") ? { __typename: "Bot", login: login.slice(0, -5) } : { __typename: "User", login });
const page1 = (nodes, hasNextPage = false) => ({ pageInfo: { hasNextPage }, nodes });
// REC.pullGraph: PR #7063, which closes issue #6007 (labeled `work-class: scoped`).
const ISSUE_6007 = REC.pullGraph.data.repository.pullRequest.closingIssuesReferences.nodes;
const queued = (at, enqueuer, actor = enqueuer) => ({ __typename: "AddedToMergeQueueEvent", createdAt: at, actor: actorOf(actor), enqueuer: actorOf(enqueuer) });
const link = (type, issue, at) => ({ __typename: type, createdAt: at, subject: { __typename: "Issue", number: issue } });

function pr(
  number,
  mergedAt,
  { labels = [], merger = LANE, title = REC.pullListItem.title, body = REC.pullListItem.body, linked = [], timeline = [], lastEditedAt = null, patch = {} } = {},
) {
  const names = labels.map((name) => ({ name }));
  return {
    graph: {
      ...REC.pullGraph.data.repository.pullRequest,
      number,
      mergedAt,
      lastEditedAt,
      mergeCommit: { oid: shaOf(number) },
      mergedBy: actorOf(merger),
      labels: page1(names),
      closingIssuesReferences: page1(linked),
      timelineItems: page1(timeline),
      ...patch,
    },
    list: {
      ...REC.pullListItem,
      number,
      title,
      body,
      labels: names,
      created_at: later(mergedAt, -60),
      merged_at: mergedAt,
      updated_at: later(mergedAt, 1),
      merge_commit_sha: shaOf(number),
    },
  };
}
const labelEvent = (event, name, at, login = "kyle-sexton", type = "User") => ({ ...REC.issueEvent, event, label: { name }, actor: { login, type }, created_at: at });

// A recorded GitHub: answers only the GET paths the publisher is expected to call, with the
// documented semantics of each (list sort order, check-runs `filter=latest` by default, statuses
// newest first), and throws on any other, so an unexpected or mutating call fails the case.
// A run marked `superseded` was re-run: only `filter=all` returns it.
// `bumpOnPage2` updates that PR (a comment, a label) between the listing's first and second page.
function github({ pulls = [], commits = [], checkRuns = {}, statuses = {}, issueEvents = {}, reviews = {}, issues = {}, bumpOnPage2 }) {
  const page = (items, path) => {
    const n = Number(/[?&]page=(\d+)/.exec(path)[1]);
    return items.slice((n - 1) * 100, n * 100);
  };
  const runsFor = (number) => checkRuns[number] ?? [{ ...REC.checkRun, completed_at: later(pulls.find((p) => p.graph.number === number).graph.mergedAt, 5) }];
  return (path, graphql) => {
    if (path === "graphql") {
      assert.deepEqual([graphql.variables.owner, graphql.variables.name], REPO.split("/"));
      assert.match(graphql.query, /^query\(/);
      assert.doesNotMatch(graphql.query, /mutation/);
      return { data: { repository: { pullRequest: pulls.find((p) => p.graph.number === graphql.variables.number).graph } } };
    }
    const prefix = `repos/${REPO}/`;
    assert.ok(path.startsWith(prefix), path);
    const rest = path.slice(prefix.length);
    let m;
    if ((m = /^pulls\?state=closed&sort=(created|updated)&direction=(asc|desc)&/.exec(rest))) {
      if (bumpOnPage2 && /[?&]page=2\b/.test(rest)) pulls.find((p) => p.list.number === bumpOnPage2).list.updated_at = "2026-10-04T00:00:00Z";
      const key = m[1] === "created" ? "created_at" : "updated_at";
      const sign = m[2] === "asc" ? 1 : -1;
      return page(pulls.map((p) => p.list).sort((a, b) => sign * a[key].localeCompare(b[key])), rest);
    }
    if ((m = /^issues\/(\d+)$/.exec(rest))) return issues[m[1]];
    if ((m = /^pulls\/(\d+)\/reviews\?/.exec(rest))) return page(reviews[m[1]] ?? [], rest);
    if (/^commits\?since=[^&]+&until=[^&]+&/.test(rest)) return page(commits, rest);
    if ((m = /^commits\/([0-9a-f]{40})\/check-runs\?/.exec(rest))) {
      const runs = runsFor(parseInt(m[1], 16)).filter((r) => /[?&]filter=all\b/.test(rest) || !r.superseded);
      return { total_count: runs.length, check_runs: page(runs, rest) };
    }
    if ((m = /^commits\/([0-9a-f]{40})\/statuses\?/.exec(rest))) return page(statuses[parseInt(m[1], 16)] ?? [], rest);
    if ((m = /^issues\/(\d+)\/events\?/.exec(rest))) return page(issueEvents[m[1]] ?? [], rest);
    throw new Error(`unrecorded gh api call: ${path}`);
  };
}

// The recorded check run and status name the post-merge gate in every case.
const GATE = [REC.checkRun.name, REC.status.context];

function run(fixture, extra = {}) {
  return collect({ repo: REPO, since: SINCE, through: THROUGH, laneLogins: [LANE], gateChecks: GATE, missedBlockingLabel: MISSED, gh: github(fixture), ...extra });
}

const termOf = (result, cell, name) => result.cells[cell].terms.find((t) => t.term === name);

test("only the named gate checks and status contexts are gate evidence", () => {
  const other = (name, conclusion) => ({ ...REC.checkRun, name, conclusion, completed_at: "2026-09-01T00:10:00Z" });
  const result = run({
    pulls: [pr(1201, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] })],
    checkRuns: { 1201: [REC.checkRun, other("dispatch", "failure"), other("resolve-conflicts / run", "cancelled")] },
    statuses: { 1201: [{ ...REC.status, context: "GitGuardian", state: "error" }] },
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
  assert.deepEqual(termOf(result, "C2-auto-merge", "human-reverted merges"), { term: "human-reverted merges", value: 1, threshold: "0", pass: false });
});

test("a git-revert commit of an autonomous C3 merge yields reverted-merge for C3 auto-merge", () => {
  const result = run({
    pulls: [pr(201, "2026-09-01T00:00:00Z", { labels: [SCOPED] })],
    commits: [{ ...REC.commit, sha: shaOf(999), commit: { message: `Revert "x"\n\nThis reverts commit ${shaOf(201)}.`, committer: { date: "2026-09-03T00:00:00Z" } } }],
  });
  assert.deepEqual(result.events, [{ cell: "C3-auto-merge", event: "reverted-merge", at: "2026-09-03T00:00:00Z" }]);
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
  const twenty = run({ pulls: merges(20) });
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
      // Linked issue #6007 is labeled scoped now, but gained that label after #907 merged.
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

test("a linked-issue read with another page fails closed", () => {
  const paged = (patch) => ({ pulls: [pr(908, "2026-09-01T00:00:00Z", { linked: ISSUE_6007, patch })] });
  assert.throws(() => run(paged({ closingIssuesReferences: page1(ISSUE_6007, true) })), (error) => error instanceof PublishError && /hasNextPage/.test(error.message));
  const labelsPaged = [{ ...ISSUE_6007[0], labels: { ...ISSUE_6007[0].labels, pageInfo: { hasNextPage: true } } }];
  assert.throws(() => run(paged({ closingIssuesReferences: page1(labelsPaged) })), /hasNextPage/);
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
  const result = run({
    pulls: [pr(1110, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] }), pr(1111, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] })],
    checkRuns: {
      1110: [cancelled("lint-repo", "2026-09-01T00:10:00Z")],
      1111: [cancelled("lint-repo", "2026-09-01T00:10:00Z"), { ...REC.checkRun, completed_at: "2026-09-01T00:20:00Z" }],
    },
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
