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

function pr(number, mergedAt, { labels = [], merger = LANE, title = REC.pullListItem.title, body = REC.pullListItem.body } = {}) {
  const names = labels.map((name) => ({ name }));
  return {
    list: { ...REC.pullListItem, number, title, body, labels: names, merged_at: mergedAt, updated_at: later(mergedAt, 1), merge_commit_sha: shaOf(number) },
    detail: { ...REC.pull, number, title, labels: names, merged_at: mergedAt, merge_commit_sha: shaOf(number), merged_by: { login: merger, type: merger === LANE ? "Bot" : "User" } },
  };
}

// A recorded GitHub: answers only the GET paths the publisher is expected to call and throws on
// any other, so an unexpected or mutating call fails the case.
function github({ pulls = [], commits = [], checkRuns = {}, issueEvents = {}, reviews = {} }) {
  const page = (items, path) => {
    const n = Number(/[?&]page=(\d+)/.exec(path)[1]);
    return items.slice((n - 1) * 100, n * 100);
  };
  const runsFor = (number) => checkRuns[number] ?? [{ ...REC.checkRun, completed_at: later(pulls.find((p) => p.detail.number === number).detail.merged_at, 5) }];
  return (path) => {
    const prefix = `repos/${REPO}/`;
    assert.ok(path.startsWith(prefix), path);
    const rest = path.slice(prefix.length);
    let m;
    if (rest.startsWith("pulls?state=closed&sort=updated&direction=desc&")) {
      return page(pulls.map((p) => p.list).sort((a, b) => b.updated_at.localeCompare(a.updated_at)), rest);
    }
    if ((m = /^pulls\/(\d+)$/.exec(rest))) return pulls.find((p) => p.detail.number === Number(m[1])).detail;
    if ((m = /^pulls\/(\d+)\/reviews\?/.exec(rest))) return page(reviews[m[1]] ?? [], rest);
    if (/^commits\?since=[^&]+&until=[^&]+&/.test(rest)) return page(commits, rest);
    if ((m = /^commits\/([0-9a-f]{40})\/check-runs\?/.exec(rest))) {
      const number = parseInt(m[1], 16);
      return { total_count: runsFor(number).length, check_runs: page(runsFor(number), rest) };
    }
    if ((m = /^issues\/(\d+)\/events\?/.exec(rest))) return page(issueEvents[m[1]] ?? [], rest);
    throw new Error(`unrecorded gh api call: ${path}`);
  };
}

function run(fixture, extra = {}) {
  return collect({ repo: REPO, since: SINCE, through: THROUGH, laneLogins: [LANE], missedBlockingLabel: MISSED, gh: github(fixture), ...extra });
}

const termOf = (result, cell, name) => result.cells[cell].terms.find((t) => t.term === name);

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

test("advisory reviews are counted from the named AI reviewers and reported unmeasured without one", () => {
  const fixture = { pulls: [pr(701, "2026-09-01T00:00:00Z", { labels: [SCOPED], merger: "kyle-sexton" })], reviews: { 701: [REC.review] } };
  assert.equal(termOf(run(fixture, { aiReviewers: [REC.review.user.login] }), "C3-ai-review-blocking", "advisory AI reviews on C3").value, 1);
  assert.equal(termOf(run(fixture), "C3-ai-review-blocking", "advisory AI reviews on C3").value, null);
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
