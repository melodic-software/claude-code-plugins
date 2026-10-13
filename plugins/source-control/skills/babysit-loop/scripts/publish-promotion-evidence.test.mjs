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

const HERE = dirname(fileURLToPath(import.meta.url));
// Real `gh api` responses, recorded 2026-10-12 and 2026-10-13 and trimmed to the fields the
// publisher reads: from this repository (PRs #7352 and #7063, a merge commit, a check run, a
// status, an issue event, a review, a comment page, workflow runs, a compare, NOT_FOUND and 422
// answers) and one ConnectedEvent from cli/cli #14616. The comment page's body is trimmed to its
// first line. Each case copies a record and varies number, labels, merger and timestamps.
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
// REC.pullGraph: a recorded pull whose one closing reference, number 6007, is labeled `work-class: scoped`.
const ISSUE_6007 = REC.pullGraph.data.repository.pullRequest.closingIssuesReferences.nodes;
const queued = (at, enqueuer, actor = enqueuer) => ({ __typename: "AddedToMergeQueueEvent", createdAt: at, actor: actorOf(actor), enqueuer: actorOf(enqueuer) });
// The shape of a real ConnectedEvent on a PR timeline (cli/cli #14616): `subject` is the issue.
const LINK = REC.connectedEventFromCliCli14616;
const link = (type, issue, at) => ({ ...LINK, __typename: type, createdAt: at, subject: { ...LINK.subject, number: issue } });

function pr(
  number,
  mergedAt,
  { labels = [], merger = LANE, title = REC.pullListItem.title, body = REC.pullListItem.body, linked = [], timeline = [], lastEditedAt = null, patch = {}, base = "main", head = shaOf(number + 0x100000) } = {},
) {
  const names = labels.map((name) => ({ name }));
  return {
    graph: {
      ...REC.pullGraph.data.repository.pullRequest,
      number,
      headRefOid: head,
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
      base: { ...REC.pullListItem.base, ref: base },
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
// `workflowRuns`: {<workflow file>: [run]}; `attempts`: {<run id>: {<n>: run}}; `history`: the
// default branch's commits oldest first (linear, as a merge-queue branch is), defaulting to the
// merge commits in merge order.
// `diverged`: head SHAs a compare reports as diverged. A PR number not in `pulls` answers with the
// recorded NOT_FOUND response.
// The lane posts a pin comment on every PR it enqueues and dispatches a full run after every merge
// (babysit_merge.py --unattended, babysit_postmerge.py), so each PR gets a correct pin and a green
// lane dispatch run on its merge commit an hour after merging, unless `comments` sets that PR's
// comments or `noDefaultDispatch` is set; an explicit run with the same id replaces the default.
const pinComment = (sha) => ({ author: actorOf(LANE), body: `<!-- babysit-merge-pin sha=${sha} -->\nThe unattended merge path enqueued this pull request at head \`${sha}\`.`, lastEditedAt: null });
function github({ pulls = [], commits = [], checkRuns = {}, statuses = {}, issueEvents = {}, reviews = {}, issues = {}, workflowRuns: explicitRuns = {}, attempts = {}, history, diverged = [], comments = {}, noDefaultDispatch = false, bumpOnPage2 }) {
  const defaultDispatch = noDefaultDispatch ? [] : pulls.map((p) => wfRun(900000 + p.graph.number, "workflow_dispatch", p.graph.mergeCommit.oid, later(p.graph.mergedAt, 60), { actor: LANE }));
  const explicitIds = new Set(Object.values(explicitRuns).flat().map((r) => r.id));
  const workflowRuns = { ...explicitRuns, [FULL]: [...defaultDispatch.filter((r) => !explicitIds.has(r.id)), ...(explicitRuns[FULL] ?? [])] };
  const branch = history ?? [...pulls].sort((a, b) => a.graph.mergedAt.localeCompare(b.graph.mergedAt)).map((p) => p.graph.mergeCommit.oid);
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
      if (/comments\(/.test(graphql.query)) {
        const pull = pulls.find((p) => p.graph.number === graphql.variables.number);
        const all = comments[graphql.variables.number] ?? [pinComment(pull.graph.headRefOid)];
        const n = Number(graphql.variables.c ?? 0);
        const nodes = all.slice(n * 100, (n + 1) * 100);
        const more = all.length > (n + 1) * 100;
        return { data: { repository: { pullRequest: { comments: { ...REC.commentsPage.data.repository.pullRequest.comments, pageInfo: { hasNextPage: more, endCursor: more ? String(n + 1) : null }, nodes } } } } };
      }
      const found = pulls.find((p) => p.graph.number === graphql.variables.number);
      return found ? { data: { repository: { pullRequest: found.graph } } } : REC.pullNotFound;
    }
    if (path === `repos/${REPO}`) return REC.repo;
    const prefix = `repos/${REPO}/`;
    assert.ok(path.startsWith(prefix), path);
    const rest = path.slice(prefix.length);
    let m;
    if ((m = /^pulls\?state=closed(?:&base=([\w.-]+))?&sort=(created|updated)&direction=(asc|desc)&/.exec(rest))) {
      if (bumpOnPage2 && /[?&]page=2\b/.test(rest)) pulls.find((p) => p.list.number === bumpOnPage2).list.updated_at = "2026-10-04T00:00:00Z";
      const key = m[2] === "created" ? "created_at" : "updated_at";
      const sign = m[3] === "asc" ? 1 : -1;
      const listed = pulls.map((p) => p.list).filter((p) => !m[1] || p.base.ref === m[1]);
      return page(listed.sort((a, b) => sign * a[key].localeCompare(b[key])), rest);
    }
    if ((m = /^issues\/(\d+)$/.exec(rest))) return issues[m[1]];
    if ((m = /^pulls\/(\d+)\/reviews\?/.exec(rest))) return page(reviews[m[1]] ?? [], rest);
    if (/^commits\?since=[^&]+&until=[^&]+&/.test(rest)) return page(commits, rest);
    if ((m = /^commits\/([0-9a-f]{40})\/check-runs\?/.exec(rest))) {
      const runs = runsFor(parseInt(m[1], 16)).filter((r) => /[?&]filter=all\b/.test(rest) || !r.superseded);
      return { total_count: runs.length, check_runs: page(runs, rest) };
    }
    if ((m = /^commits\/([0-9a-f]{40})\/pulls$/.exec(rest))) {
      // A SHA no commit has: the recorded 422, as realGh hands it to ghFailure.
      if (!branch.includes(m[1])) return publisher.ghFailure(path, undefined, REC.commitNotFound.stdout, REC.commitNotFound.stderr);
      return pulls.filter((p) => p.graph.mergeCommit.oid === m[1]).map((p) => ({ number: p.graph.number, merged_at: p.graph.mergedAt, merge_commit_sha: m[1] }));
    }
    if ((m = /^commits\/([0-9a-f]{40})\/statuses\?/.exec(rest))) return page(statuses[parseInt(m[1], 16)] ?? [], rest);
    if ((m = /^issues\/(\d+)\/events\?/.exec(rest))) return page(issueEvents[m[1]] ?? [], rest);
    if ((m = /^actions\/workflows\/([\w.-]+)\/runs\?event=(\w+)&branch=main&created=%3E%3D[^&]+&/.exec(rest))) {
      const runs = (workflowRuns[m[1]] ?? []).filter((r) => r.event === m[2]);
      return { total_count: runs.length, workflow_runs: page(runs, rest) };
    }
    if ((m = /^actions\/runs\/(\d+)\/attempts\/(\d+)$/.exec(rest))) return attempts[m[1]][m[2]];
    if ((m = /^compare\/([0-9a-f]{40})\.\.\.([0-9a-f]{40})\?/.exec(rest))) {
      const [base, head] = [branch.indexOf(m[1]), branch.indexOf(m[2])];
      assert.ok(base >= 0 && head >= 0, `compare outside the recorded history: ${rest}`);
      const status = diverged.includes(m[2]) ? "diverged" : head > base ? "ahead" : head === base ? "identical" : "behind";
      const ahead = head > base ? branch.slice(base + 1, head + 1).map((sha) => ({ sha })) : [];
      return { ...REC.compare, status, ahead_by: ahead.length, total_commits: ahead.length, commits: page(ahead, rest) };
    }
    throw new Error(`unrecorded gh api call: ${path}`);
  };
}

// The recorded check run and status name the post-merge gate in every case.
const GATE = [REC.checkRun.name, REC.status.context];

function run(fixture, extra = {}) {
  return collect({ repo: REPO, since: SINCE, through: THROUGH, laneLogins: [LANE], gateChecks: GATE, missedBlockingLabel: MISSED, gh: github(fixture), ...extra });
}

const termOf = (result, cell, name) => result.cells[cell].terms.find((t) => t.term === name);

const FULL = "pr-require-checks.yml";
const CANARY = "post-merge-detect-silent-revert.yml";
const wfRun = (id, event, sha, created, { conclusion = "success", status = "completed", attempt = 1, actor = "github-merge-queue[bot]", triggering = actor, updated = later(created, 8) } = {}) => ({
  ...REC.workflowRun,
  id,
  event,
  head_sha: sha,
  created_at: created,
  updated_at: updated,
  status,
  conclusion: status === "completed" ? conclusion : null,
  run_attempt: attempt,
  actor: { login: actor },
  triggering_actor: { login: triggering },
});
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
  assert.deepEqual(termOf(result, "C2-auto-merge", "human-reverted merges"), { term: "human-reverted merges", value: 1, threshold: "0", pass: false });
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

const NOT_HUMAN = "the revert was merged or enqueued by a bot or lane identity, not a human";

test("a revert PR a bot or lane identity merged or enqueued is listed, not counted", () => {
  const result = run({
    pulls: [
      pr(1701, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] }),
      pr(1702, "2026-09-02T00:00:00Z", { title: 'Revert "x"', body: `Reverts ${REPO}#1701` }),
      pr(1703, "2026-09-01T00:00:00Z", { labels: [SCOPED] }),
      pr(1704, "2026-09-02T00:00:00Z", { body: `Reverts ${REPO}#1703`, merger: "kyle-sexton", timeline: [queued("2026-09-01T23:00:00Z", null, "some-app[bot]")] }),
    ],
  });
  assert.deepEqual(result.events.filter((e) => e.event === "reverted-merge"), []);
  assert.deepEqual(result.unresolvedReverts, [
    { target: 1701, reason: NOT_HUMAN },
    { target: 1703, reason: NOT_HUMAN },
  ]);
});

test("the squash commit of a lane-merged revert PR does not count as a direct revert", () => {
  const result = run({
    pulls: [pr(1705, "2026-09-01T00:00:00Z", { labels: [MECHANICAL] }), pr(1706, "2026-09-02T00:00:00Z", { body: `Reverts ${REPO}#1705` })],
    commits: [{ ...REC.commit, sha: shaOf(1706), commit: { message: `Revert "x" (#1706)\n\nReverts ${REPO}#1705`, committer: { date: "2026-09-02T00:00:00Z" } } }],
  });
  assert.deepEqual(result.events.filter((e) => e.event === "reverted-merge"), []);
  assert.deepEqual(result.unresolvedReverts, [{ target: 1705, reason: NOT_HUMAN }]);
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
