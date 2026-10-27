// plan() and remove() against a fake GitHub: hand-built branches, pull requests and
// issues, with each expected verdict taken from the branch-cleanup rule
// (docs/conventions/pr-pipeline/README.md, "Branch cleanup").
import assert from "node:assert/strict";
import { test } from "node:test";

import { DELETE_REF, ZERO_OID, client, deleteBudget, plan, readList, remove } from "./cleanup.mjs";
import { linkedIssues } from "./rules.mjs";

const REPO = "melodic-software/claude-code-plugins";
const BOT = "melodic-automation-lanes[bot]";
const NOW = "2026-10-21T12:00:00Z";
const OLD = "2026-09-01T00:00:00Z";
const sha = (c) => c.repeat(40);

// `branches` are { name, sha, protected }; `pulls` are keyed by branch name;
// `issues` and `comments` by number; `ahead` maps a SHA to its commits ahead
// of main; `rules` maps a branch to its ruleset rules; `moves` maps a branch
// to the tip a re-read returns; `movesAtDelete` maps a branch to the tip it
// holds once the delete-time re-read is done; `openLater` names branches whose
// open PR appears only at the delete-time re-read. The GraphQL updateRefs
// fake refuses, as GitHub does, an update whose beforeOid is not the tip,
// returning HTTP 200 with an errors list; `call` throws on it as the client
// does.
function world({ branches, pulls = {}, issues = {}, comments = {}, ahead = {}, rules = {}, moves = {}, movesAtDelete = {}, openLater = [] }) {
  const writes = [];
  const reread = new Set();
  const tip = (name) => (reread.has(name) && movesAtDelete[name]) || moves[name] || branches.find((b) => b.name === name)?.sha;
  const respond = (method, path, body) => {
    if (method === "POST" && path === "/graphql") {
      const { name, beforeOid, afterOid, repositoryId } = body.variables;
      const branch = name.slice("refs/heads/".length);
      if (body.query !== DELETE_REF || repositoryId !== "R_repo" || afterOid !== ZERO_OID) throw new Error(`unexpected mutation ${JSON.stringify(body)}`);
      if (tip(branch) !== beforeOid) return { errors: [{ message: `refs/heads/${branch} is at ${tip(branch)}, not ${beforeOid}` }] };
      writes.push({ method, path, name: branch, beforeOid });
      return { data: { updateRefs: { clientMutationId: null } } };
    }
    if (method !== "GET") throw new Error(`unexpected ${method} ${path}`);
    const url = new URL(`https://api.test${path}`);
    const p = url.pathname;
    const q = url.searchParams;
    let m;
    if (p === `/repos/${REPO}`) return { default_branch: "main", node_id: "R_repo" };
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
      const sha = tip(name);
      reread.add(name);
      return sha ? { object: { sha } } : null;
    }
    throw new Error(`unexpected GET ${path}`);
  };
  // The same answers as the client gives: a GraphQL errors list throws.
  const call = async (method, path, body) => {
    const answer = respond(method, path, body);
    if (answer?.errors) throw new Error(`POST /graphql: ${answer.errors.map((e) => e.message).join("; ")}`);
    return answer;
  };
  return { call, respond, writes };
}

// Both stages, the candidate list passed through JSON as the artifact carries it.
async function run(w, { dryRun = false, config = {} } = {}) {
  const ledger = [];
  const env = { REPOSITORY: REPO, DRY_RUN: dryRun ? "true" : "false" };
  const planned = await plan(env, { call: w.call, loadConfig: () => config, log: () => {} });
  const list = JSON.parse(JSON.stringify(planned.list));
  const removed = await remove(env, { call: w.call, clock: () => NOW, loadConfig: () => config, append: (e) => ledger.push(e), list, log: () => {} });
  const verdict = (name) => planned.results.find((r) => r.name === name);
  return { ...planned, ...removed, ledger, verdict, deletes: w.writes.map((x) => deletePath(x.name)) };
}

// The real client over a stubbed fetch that answers from a world.
function stubFetch(t, w, onWrite = () => {}) {
  t.mock.method(globalThis, "fetch", async (url, { method, body }) => {
    const path = String(url).slice("https://api.test".length);
    const answer = w.respond(method, path, body === undefined ? undefined : JSON.parse(body));
    if (method !== "GET" && !answer?.errors) onWrite(answer, path, JSON.parse(body));
    return answer === null ? new Response(null, { status: 404 }) : Response.json(answer);
  });
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
const deletePath = (name) => `refs/heads/${name}`;
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

test("a run deletes at most max-deletes-per-run and leaves the rest unevaluated for the next run", async () => {
  const branches = [];
  const pulls = {};
  for (let i = 1; i <= 4; i += 1) {
    const name = `feat/b${i}`;
    branches.push({ name, sha: sha(String(i)) });
    pulls[name] = [mergedPull(i, sha(String(i)), `2026-0${i}-01T00:00:00Z`)];
  }
  const r = await run(world({ branches, pulls }), { config: { "max-deletes-per-run": 2 } });
  assert.deepEqual(r.deletes, [deletePath("feat/b1"), deletePath("feat/b2")]);
  assert.equal(r.unevaluated, 2);
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

// The real client over a stubbed fetch, so its call budget applies (#8959
// review: evaluation spent the whole budget and every delete then failed).
// The plan stage gets the budget less the delete stage's share; the delete
// stage gets that share.
test("300 deletable branches under a 600-call budget: the run deletes the cap of 25", async (t) => {
  const branches = [];
  const pulls = {};
  for (let i = 1; i <= 300; i += 1) {
    const name = `feat/old-${i}`;
    const tip = i.toString(16).padStart(40, "0");
    branches.push({ name, sha: tip });
    pulls[name] = [mergedPull(i, tip, OLD)];
  }
  const w = world({ branches, pulls });
  stubFetch(t, w);
  const env = { REPOSITORY: REPO, DRY_RUN: "false", CALL_BUDGET: "600", GITHUB_API_URL: "https://api.test" };
  const planCall = client(env, { pace: async () => {}, dryRun: true });
  const planned = await plan(env, { call: planCall, loadConfig: () => ({}), log: () => {} });
  assert.equal(planned.planned.length, 25);
  const call = client(env, { pace: async () => {}, dryRun: false, budget: deleteBudget(planned.planned.length) });
  const result = await remove(env, { call, clock: () => NOW, loadConfig: () => ({}), append: () => {}, list: planned.list, log: () => {} });
  assert.equal(result.deleted.length, 25);
  assert.equal(w.writes.length, 25);
  assert.ok(600 - planCall.remaining() + (deleteBudget(25) - call.remaining()) <= 600);
  for (const write of w.writes) assert.equal(write.beforeOid, branches.find((b) => b.name === write.name).sha);
});

// #8976 review: kept branches ahead of the deletable ones spent the
// evaluation share every run, so the branches after them were never read.
test("493 kept branches ahead of 8 deletable: successive runs reach and delete all 8", async (t) => {
  const branches = [];
  const pulls = {};
  for (let i = 1; i <= 501; i += 1) {
    const name = `feat/b-${i}`;
    const tip = i.toString(16).padStart(40, "0");
    branches.push({ name, sha: tip });
    // A kept branch costs two reads: its pull requests and its open linked issue.
    pulls[name] = [mergedPull(i, tip, OLD, i <= 493 ? "Closes #7000" : "")];
  }
  const w = world({ branches, pulls, issues: { 7000: openIssue } });
  stubFetch(t, w, (_answer, _path, body) => {
    const name = body.variables.name.slice("refs/heads/".length);
    branches.splice(branches.findIndex((b) => b.name === name), 1);
  });
  for (let runNumber = 1; runNumber <= 5; runNumber += 1) {
    const env = {
      REPOSITORY: REPO,
      DRY_RUN: "false",
      CALL_BUDGET: "600",
      GITHUB_API_URL: "https://api.test",
      GITHUB_RUN_NUMBER: String(runNumber),
    };
    const planned = await plan(env, { call: client(env, { pace: async () => {}, dryRun: true }), loadConfig: () => ({}), log: () => {} });
    const call = client(env, { pace: async () => {}, dryRun: false, budget: deleteBudget(planned.planned.length) });
    await remove(env, { call, clock: () => NOW, loadConfig: () => ({}), append: () => {}, list: planned.list, log: () => {} });
  }
  assert.equal(w.writes.length, 8);
  assert.equal(branches.length, 493);
});

test("the delete sends one updateRefs per branch, beforeOid the listed tip and afterOid all zeros", async () => {
  const w = world({ branches: [{ name: "feat/merged", sha: sha("2") }], pulls: { "feat/merged": [mergedPull(4, sha("2"), OLD)] } });
  const r = await run(w);
  assert.deepEqual(w.writes, [{ method: "POST", path: "/graphql", name: "feat/merged", beforeOid: sha("2") }]);
  assert.equal(r.deleted.length, 1);
});

// #8958 item 1: the re-read and the delete are no longer two steps a push can
// land between.
test("a tip that moved after the delete-time re-read is not deleted and is reported as skipped", async () => {
  const w = world({
    branches: [{ name: "feat/raced", sha: sha("2") }],
    pulls: { "feat/raced": [mergedPull(4, sha("2"), OLD)] },
    movesAtDelete: { "feat/raced": sha("7") },
  });
  const r = await run(w);
  assert.deepEqual(r.deletes, []);
  assert.deepEqual(r.deleted, []);
  assert.equal(r.skipped.length, 1);
  assert.equal(r.skipped[0].name, "feat/raced");
  assert.match(r.skipped[0].reason, /^the tip moved to 7{40} before the delete/);
  // The write-ahead line stays; a second line records that the branch was not deleted.
  assert.deepEqual(r.ledger, [
    { repo: REPO, branch: "feat/raced", sha: sha("2"), rule: "pr-merged", issue: null, pr: 4, deletedAt: NOW },
    { repo: REPO, branch: "feat/raced", sha: sha("2"), notDeletedAt: NOW, reason: r.skipped[0].reason },
  ]);
});

test("the client throws on a GraphQL errors list answered with HTTP 200", async (t) => {
  t.mock.method(globalThis, "fetch", async () => Response.json({ errors: [{ message: "refused" }] }));
  const call = client({ GITHUB_API_URL: "https://api.test" }, { pace: async () => {}, dryRun: false, budget: 1 });
  await assert.rejects(call("POST", "/graphql", { query: DELETE_REF, variables: {} }), /POST \/graphql: refused/);
});

test("the plan stage's client refuses a write", async () => {
  const call = client({}, { pace: async () => {}, dryRun: true });
  await assert.rejects(call("POST", "/graphql", {}), /dry-run refuses POST/);
});

test("the delete stage refuses a list for another repository, over the cap, or with a bad entry", () => {
  const good = { name: "feat/x", sha: sha("a"), rule: "pr-merged", issue: null, pr: 4 };
  const ctx = { repo: REPO, cap: 2, defaultBranch: "main" };
  assert.deepEqual(readList({ repo: REPO, planned: [good] }, ctx), [good]);
  assert.throws(() => readList({ repo: "other/repo", planned: [good] }, ctx), /another repository/);
  assert.throws(() => readList({ repo: REPO, planned: [good, { ...good, name: "b" }, { ...good, name: "c" }] }, ctx), /over the cap/);
  for (const bad of [
    { ...good, name: "main" },
    { ...good, name: "release/plugins" },
    { ...good, sha: "abc" },
    { ...good, rule: "anything" },
    { ...good, issue: "#4" },
  ]) {
    assert.throws(() => readList({ repo: REPO, planned: [bad] }, ctx), /refuses/, JSON.stringify(bad));
  }
  assert.throws(() => readList({ repo: REPO, planned: [good, good] }, ctx), /refuses/);
});
