// cleanup() against a fake GitHub: hand-built branches, pull requests and
// issues, with each expected verdict taken from the branch-cleanup rule
// (docs/conventions/pr-pipeline/README.md, "Branch cleanup").
import assert from "node:assert/strict";
import { test } from "node:test";

import { cleanup } from "./cleanup.mjs";
import { linkedIssues } from "./rules.mjs";

const REPO = "melodic-software/claude-code-plugins";
const BOT = "melodic-automation-lanes[bot]";
const NOW = "2026-10-21T12:00:00Z";
const OLD = "2026-09-01T00:00:00Z";
const sha = (c) => c.repeat(40);

// `branches` are { name, sha, protected }; `pulls` are keyed by branch name;
// `issues` and `comments` by number; `ahead` maps a SHA to its commits ahead
// of main; `rules` maps a branch to its ruleset rules; `moves` maps a branch
// to the tip a re-read returns; `openLater` names branches whose open PR
// appears only at the delete-time re-read.
function world({ branches, pulls = {}, issues = {}, comments = {}, ahead = {}, rules = {}, moves = {}, openLater = [] }) {
  const writes = [];
  const call = async (method, path) => {
    if (method !== "GET") {
      writes.push({ method, path });
      return null;
    }
    const url = new URL(`https://api.test${path}`);
    const p = url.pathname;
    const q = url.searchParams;
    let m;
    if (p === `/repos/${REPO}`) return { default_branch: "main" };
    if (p === `/repos/${REPO}/branches`) {
      return q.get("page") === "1" ? branches.map((b) => ({ name: b.name, protected: !!b.protected, commit: { sha: b.sha } })) : [];
    }
    if (p === `/repos/${REPO}/pulls`) {
      if (q.get("base")) return [];
      const name = q.get("head").slice("melodic-software:".length);
      const list = pulls[name] ?? [];
      if (q.get("state") === "open") return openLater.includes(name) ? [{ number: 999, state: "open" }] : list.filter((x) => x.state === "open");
      return q.get("page") === "1" ? list : [];
    }
    if ((m = /^\/repos\/[^/]+\/[^/]+\/issues\/(\d+)$/.exec(p))) return issues[m[1]] ?? null;
    if ((m = /^\/repos\/[^/]+\/[^/]+\/issues\/(\d+)\/comments$/.exec(p))) return q.get("page") === "1" ? (comments[m[1]] ?? []) : [];
    if ((m = /^\/repos\/[^/]+\/[^/]+\/compare\/main\.\.\.([0-9a-f]{40})$/.exec(p))) return { ahead_by: ahead[m[1]] ?? 0 };
    if ((m = /^\/repos\/[^/]+\/[^/]+\/rules\/branches\/(.+)$/.exec(p))) return rules[decodeURIComponent(m[1])] ?? [];
    if ((m = /^\/repos\/[^/]+\/[^/]+\/git\/ref\/heads\/(.+)$/.exec(p))) {
      const name = m[1].split("/").map(decodeURIComponent).join("/");
      const branch = branches.find((b) => b.name === name);
      return { object: { sha: moves[name] ?? branch.sha } };
    }
    throw new Error(`unexpected GET ${path}`);
  };
  return { call, writes };
}

async function run(w, { dryRun = false, config = {} } = {}) {
  const ledger = [];
  const result = await cleanup(
    { REPOSITORY: REPO, DRY_RUN: dryRun ? "true" : "false" },
    { call: w.call, clock: () => NOW, loadConfig: () => config, append: (e) => ledger.push(e), log: () => {} },
  );
  const verdict = (name) => result.results.find((r) => r.name === name);
  return { ...result, ledger, verdict, deletes: w.writes.filter((x) => x.method === "DELETE").map((x) => x.path) };
}

const closedIssue = (closedAt) => ({ state: "closed", closed_at: closedAt });
const openIssue = { state: "open", closed_at: null };
const mergedPull = (number, head, at, body = "") => ({
  number,
  state: "closed",
  merged_at: at,
  closed_at: at,
  created_at: at,
  head: { sha: head },
  body,
});
const deletePath = (name) => `/repos/${REPO}/git/refs/heads/${name}`;
const lane = (issue) => `work-resolve-issue/issue-${issue}-100-1`;

test("a lane branch whose issue is open is kept, however old its merged PR", async () => {
  const name = lane(10);
  const w = world({
    branches: [{ name, sha: sha("a") }],
    pulls: { [name]: [mergedPull(1, sha("a"), OLD)] },
    issues: { 10: openIssue },
  });
  const r = await run(w);
  assert.equal(r.verdict(name).verdict, "keep");
  assert.deepEqual(r.deletes, []);
});

// Owner decision on #8958: a branch lives while its issue is open and is
// deleted once it closes, whatever the lanes App's outcome markers say.
const stopMarker = { user: { login: BOT }, body: "<!-- work-resolve-issue outcome=turn-cap cap=75 run=100 -->\nPartial work is on the branch." };

test("a stopped lane run's branch is kept while its issue is open", async () => {
  const name = lane(11);
  const w = world({ branches: [{ name, sha: sha("b") }], issues: { 11: openIssue }, comments: { 11: [stopMarker] } });
  const r = await run(w);
  assert.equal(r.verdict(name).verdict, "keep");
  assert.deepEqual(r.deletes, []);
});

test("a stopped lane run's branch is deleted once its issue closes", async () => {
  const name = lane(12);
  const w = world({ branches: [{ name, sha: sha("c") }], issues: { 12: closedIssue(NOW) }, comments: { 12: [stopMarker] } });
  const r = await run(w);
  assert.equal(r.verdict(name).rule, "lane-issue-closed");
  assert.deepEqual(r.deletes, [deletePath(name)]);
});

test("a lane branch with no PR is deleted the run after its issue closes, with a ledger line", async () => {
  const name = lane(14);
  const w = world({ branches: [{ name, sha: sha("e") }], issues: { 14: closedIssue(NOW) } });
  const r = await run(w);
  assert.deepEqual(r.deletes, [deletePath(name)]);
  assert.deepEqual(r.ledger, [
    { repo: REPO, branch: name, sha: sha("e"), rule: "lane-issue-closed", issue: 14, pr: null, deletedAt: NOW },
  ]);
});

test("a branch whose PR closed unmerged at its tip, linking no issue, is deleted", async () => {
  const pull = { ...mergedPull(2, sha("f"), NOW), merged_at: null };
  const w = world({ branches: [{ name: "feat/abandoned", sha: sha("f") }], pulls: { "feat/abandoned": [pull] } });
  const r = await run(w);
  assert.equal(r.verdict("feat/abandoned").rule, "pr-closed");
  assert.deepEqual(r.deletes, [deletePath("feat/abandoned")]);
});

test("a branch with an open PR is kept", async () => {
  const w = world({
    branches: [{ name: "feat/open", sha: sha("1") }],
    pulls: { "feat/open": [{ number: 3, state: "open", created_at: OLD, head: { sha: sha("1") } }] },
  });
  const r = await run(w);
  assert.equal(r.verdict("feat/open").verdict, "keep");
  assert.deepEqual(r.deletes, []);
});

test("a merged PR's branch is deleted; one whose tip moved is deleted only with no commits ahead", async () => {
  const w = world({
    branches: [
      { name: "feat/merged", sha: sha("2") },
      { name: "feat/moved-empty", sha: sha("3") },
      { name: "feat/moved-ahead", sha: sha("4") },
    ],
    pulls: {
      "feat/merged": [mergedPull(4, sha("2"), OLD)],
      "feat/moved-empty": [mergedPull(5, sha("9"), OLD)],
      "feat/moved-ahead": [mergedPull(6, sha("8"), OLD)],
    },
    ahead: { [sha("3")]: 0, [sha("4")]: 2 },
  });
  const r = await run(w);
  assert.equal(r.verdict("feat/merged").rule, "pr-merged");
  assert.equal(r.verdict("feat/moved-empty").rule, "pr-merged-no-commits-ahead");
  assert.equal(r.verdict("feat/moved-ahead").verdict, "report");
  assert.deepEqual(r.deletes.sort(), [deletePath("feat/merged"), deletePath("feat/moved-empty")]);
});

test("a non-lane branch is kept while an issue its last PR body links is open", async () => {
  const w = world({
    branches: [{ name: "fix/linked", sha: sha("5") }],
    pulls: { "fix/linked": [mergedPull(7, sha("5"), OLD, "Refs: #20\n\nCloses #21")] },
    issues: { 20: closedIssue(OLD), 21: openIssue },
  });
  const r = await run(w);
  assert.equal(r.verdict("fix/linked").verdict, "keep");
});

test("a human branch that never had a PR, and an unreadable issue, are reported, never deleted", async () => {
  const w = world({
    branches: [
      { name: "wip/idea", sha: sha("6") },
      { name: lane(30), sha: sha("7") },
    ],
  });
  const r = await run(w);
  assert.equal(r.verdict("wip/idea").verdict, "report");
  assert.equal(r.verdict(lane(30)).verdict, "report");
  assert.deepEqual(r.deletes, []);
});

test("excluded, protected and ruleset branches are never deleted", async () => {
  const old = (s) => [mergedPull(8, s, OLD)];
  const w = world({
    branches: [
      { name: "main", sha: sha("a") },
      { name: "release/plugins", sha: sha("b") },
      { name: "dependabot/npm/x", sha: sha("c") },
      { name: "gh-readonly-queue/main/pr-1", sha: sha("d") },
      { name: "feat/protected", sha: sha("e"), protected: true },
      { name: "feat/ruled", sha: sha("f") },
    ],
    pulls: {
      "release/plugins": old(sha("b")),
      "feat/protected": old(sha("e")),
      "feat/ruled": old(sha("f")),
    },
    rules: { "feat/ruled": [{ type: "deletion" }] },
  });
  const r = await run(w);
  assert.deepEqual(r.deletes, []);
  assert.equal(r.verdict("feat/ruled").verdict, "keep");
  assert.equal(r.verdict("feat/protected").verdict, "keep");
});

test("a branch whose tip moved, or that gained an open PR, between listing and delete is skipped", async () => {
  const w = world({
    branches: [
      { name: "feat/moved", sha: sha("1") },
      { name: "feat/reopened", sha: sha("2") },
    ],
    pulls: {
      "feat/moved": [mergedPull(9, sha("1"), OLD)],
      "feat/reopened": [mergedPull(10, sha("2"), OLD)],
    },
    moves: { "feat/moved": sha("9") },
    openLater: ["feat/reopened"],
  });
  const r = await run(w);
  assert.deepEqual(r.deletes, []);
  assert.deepEqual(r.ledger, []);
  assert.deepEqual(r.skipped.map((s) => s.name).sort(), ["feat/moved", "feat/reopened"]);
});

test("a run deletes at most max-deletes-per-run, the rest wait", async () => {
  const branches = [];
  const pulls = {};
  for (let i = 1; i <= 4; i += 1) {
    const name = `feat/b${i}`;
    branches.push({ name, sha: sha(String(i)) });
    pulls[name] = [mergedPull(i, sha(String(i)), `2026-0${i}-01T00:00:00Z`)];
  }
  const r = await run(world({ branches, pulls }), { config: { "max-deletes-per-run": 2 } });
  assert.equal(r.candidates.length, 4);
  assert.deepEqual(r.deletes, [deletePath("feat/b1"), deletePath("feat/b2")]);
});

test("dry-run deletes nothing and writes no ledger line", async () => {
  const w = world({
    branches: [{ name: "feat/merged", sha: sha("2") }],
    pulls: { "feat/merged": [mergedPull(4, sha("2"), OLD)] },
  });
  const r = await run(w, { dryRun: true });
  assert.equal(r.planned.length, 1);
  assert.deepEqual(w.writes, []);
  assert.deepEqual(r.ledger, []);
});

test("linkedIssues reads same-repository closing and Refs links only", () => {
  const body = `Closes #1, fixes: #2\nResolves ${REPO}#3\nRefs https://github.com/${REPO}/issues/4\nCloses other/repo#5\nsee #6`;
  assert.deepEqual(linkedIssues(body, REPO), [1, 2, 3, 4]);
});
