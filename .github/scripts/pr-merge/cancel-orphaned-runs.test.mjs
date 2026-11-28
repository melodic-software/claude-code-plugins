// test-scope: .github/scripts/pr-merge/fixtures/cancel-orphaned-runs-*.json
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { createGitHub } from "../lib/github-client.mjs";
import { main } from "./cancel-orphaned-runs.mjs";

const REPO = "melodic-software/claude-code-plugins";
const capture = (name) => JSON.parse(readFileSync(new URL(`./fixtures/cancel-orphaned-runs-${name}.json`, import.meta.url), "utf8"));
const recorded = (name) => capture(name).response;
const RUNS = recorded("merge-group-runs");
const listing = (runs, all = runs) => ({ ...structuredClone(RUNS), total_count: RUNS.total_count - RUNS.workflow_runs.length + all.length, workflow_runs: runs });
const REFS = recorded("queue-refs");
const COMMITS = recorded("main-commits");
const NOW = Date.parse("2026-11-28T06:30:00Z");
const ago = (seconds) => new Date(NOW - seconds * 1000).toISOString();
const LIVE = RUNS.workflow_runs[0].head_branch;
const GONE = LIVE.replace("pr-19610-", "pr-19486-");
const sha = (id) => id.toString(16).padStart(40, "0");
const run = (id, head_branch, seconds = 300, event = "merge_group") => ({ ...structuredClone(RUNS.workflow_runs[0]), id, event, head_branch, head_sha: sha(id), created_at: ago(seconds) });
const refOf = (branch) => ({ ...structuredClone(REFS[0]), ref: `refs/heads/${branch}` });
const commitOf = (value) => ({ ...structuredClone(COMMITS[0]), sha: value });
const LIST_QUEUED = `GET /repos/${REPO}/actions/runs?event=merge_group&status=queued&per_page=100&page=1`;
const LIST_RUNNING = `GET /repos/${REPO}/actions/runs?event=merge_group&status=in_progress&per_page=100&page=1`;
const LIST_REFS = `GET /repos/${REPO}/git/matching-refs/heads/gh-readonly-queue/`;
const LIST_COMMITS = `GET /repos/${REPO}/commits?sha=main&per_page=100`;
const posts = (calls) => calls.filter((call) => call.startsWith("POST"));
const cancel = (id) => `POST /repos/${REPO}/actions/runs/${id}/cancel`;

async function sweep({ queued = [], running = [], branches = [], onMain = [], failRefs = false, failRuns = false, failCommits = false } = {}) {
  const calls = [];
  const github = async (method, path) => {
    calls.push(`${method} ${path}`);
    if (path.includes("/actions/runs?")) {
      if (failRuns) {
        throw new Error("GET runs failed with status 502");
      }
      return listing(path.includes("status=queued") ? queued : running);
    }
    if (path.includes("/git/matching-refs/")) {
      if (failRefs) {
        throw new Error("GET matching-refs failed with status 502");
      }
      return [...structuredClone(REFS), ...branches.map(refOf)];
    }
    if (path.includes("/commits?")) {
      if (failCommits) {
        throw new Error("GET commits failed with status 502");
      }
      return [...structuredClone(COMMITS), ...onMain.map(commitOf)];
    }
    return null;
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    const code = await main({ env: { GITHUB_REPOSITORY: REPO }, github, now: () => NOW });
    return { code, calls, out: lines.join("\n") };
  } finally {
    console.log = log;
  }
}

test("a queued run whose queue ref is gone is cancelled, after both listings and the ref read", async () => {
  const r = await sweep({ queued: [run(46110287663, GONE)], branches: [LIVE] });
  assert.equal(r.code, 0);
  assert.deepEqual(r.calls, [LIST_QUEUED, LIST_RUNNING, LIST_REFS, LIST_COMMITS, cancel(46110287663)]);
  assert.match(r.out, /::notice title=cancel-orphaned-runs::listed=1 cancelled=\[46110287663\] calls=5/);
});

test("an in-progress run whose queue ref is gone is cancelled too", async () => {
  const r = await sweep({ running: [run(7, GONE)] });
  assert.deepEqual(posts(r.calls), [cancel(7)]);
});

test("a run whose queue ref still exists is kept", async () => {
  const r = await sweep({ queued: [run(1, LIVE), run(2, GONE)], branches: [LIVE] });
  assert.deepEqual(posts(r.calls), [cancel(2)]);
});

test("a run 60 s old or younger is kept, one 61 s old is cancelled", async () => {
  const r = await sweep({ queued: [run(1, GONE, 30), run(2, `${GONE}-b`, 60), run(3, `${GONE}-c`, 61)] });
  assert.deepEqual(posts(r.calls), [cancel(3)]);
});

test("a run whose created_at does not parse is kept", async () => {
  const r = await sweep({ queued: [{ ...run(1, GONE), created_at: "soon" }] });
  assert.deepEqual(posts(r.calls), []);
});

test("a failed ref listing cancels nothing and ends green with a warning", async () => {
  const r = await sweep({ queued: [run(1, GONE)], failRefs: true });
  assert.equal(r.code, 0);
  assert.deepEqual(r.calls, [LIST_QUEUED, LIST_RUNNING, LIST_REFS]);
  assert.match(r.out, /::warning title=cancel-orphaned-runs::nothing more cancelled: GET matching-refs failed/);
});

test("a failed run listing cancels nothing and reads no refs", async () => {
  const r = await sweep({ branches: [], failRuns: true });
  assert.equal(r.code, 0);
  assert.deepEqual(r.calls, [LIST_QUEUED]);
});

test("with no merge_group runs queued or in progress, the two listings are the only calls", async () => {
  const r = await sweep();
  assert.deepEqual(r.calls, [LIST_QUEUED, LIST_RUNNING]);
  assert.match(r.out, /listed=0 cancelled=\[\] calls=2/);
});

test("a run on a branch outside gh-readonly-queue/, or from another event, is never cancelled", async () => {
  const r = await sweep({ queued: [run(1, "main"), run(2, "feature/gh-readonly-queue/x"), run(3, GONE, 300, "push")] });
  assert.deepEqual(posts(r.calls), []);
});

test("a run in another base's queue whose ref is gone is kept, while main's is cancelled", async () => {
  const OTHER = GONE.replace("gh-readonly-queue/main/", "gh-readonly-queue/release/x/");
  const r = await sweep({ queued: [run(1, OTHER), run(2, GONE)] });
  assert.deepEqual(posts(r.calls), [cancel(2)]);
});

test("with only another base's orphaned run, nothing is cancelled and main's commits are not read", async () => {
  const r = await sweep({ queued: [run(1, GONE.replace("gh-readonly-queue/main/", "gh-readonly-queue/release/x/"))] });
  assert.deepEqual(r.calls, [LIST_QUEUED, LIST_RUNNING, LIST_REFS]);
});

test("one sweep cancels at most 20 runs, the oldest first", async () => {
  const queued = Array.from({ length: 25 }, (_, i) => run(100 + i, `${GONE}-${i}`, 1000 - i));
  const r = await sweep({ queued });
  const posts = r.calls.filter((call) => call.startsWith("POST"));
  assert.equal(posts.length, 20);
  assert.deepEqual(posts.slice(0, 2), [cancel(100), cancel(101)]);
  assert.equal(posts.at(-1), cancel(119));
});

test("a run listed both queued and in progress is cancelled once", async () => {
  const r = await sweep({ queued: [run(5, GONE)], running: [run(5, GONE)] });
  assert.deepEqual(posts(r.calls), [cancel(5)]);
});

test("a cancel the API refuses is reported and the next one still goes", async () => {
  const calls = [];
  const github = async (method, path) => {
    calls.push(`${method} ${path}`);
    if (path.includes("status=queued")) return listing([run(1, GONE, 400), run(2, `${GONE}-b`, 300)]);
    if (path.includes("/actions/runs?")) return listing([]);
    if (path.includes("/git/matching-refs/")) return structuredClone(REFS);
    if (path.includes("/commits?")) return structuredClone(COMMITS);
    if (path.endsWith("/1/cancel")) throw new Error("POST cancel failed with status 409");
    return null;
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    assert.equal(await main({ env: { GITHUB_REPOSITORY: REPO }, github, now: () => NOW }), 0);
  } finally {
    console.log = log;
  }
  assert.deepEqual(posts(calls), [cancel(1), cancel(2)]);
  assert.match(lines.join("\n"), /run 1 not cancelled: POST cancel failed with status 409[\s\S]*cancelled=\[2\]/);
});

test("a ref listing whose Link header names a next page cancels nothing", async () => {
  const next = `<https://api.github.com${capture("queue-refs").request.replace(/^GET /, "")}?page=2>; rel="next"`;
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push(`${init.method} ${new URL(url).pathname}`);
    if (url.includes("/git/matching-refs/")) return new Response(JSON.stringify(REFS), { headers: { link: next } });
    if (url.includes("/commits?")) return new Response(JSON.stringify(COMMITS));
    if (init.method === "POST") return new Response(null, { status: 202 });
    return new Response(JSON.stringify(listing(url.includes("status=queued") ? [run(1, GONE)] : [])));
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    await main({ env: { GITHUB_REPOSITORY: REPO }, github: createGitHub({ token: "t", fetchImpl }), now: () => NOW });
  } finally {
    console.log = log;
  }
  assert.deepEqual(posts(calls), []);
  assert.match(lines.join("\n"), /nothing more cancelled: the queue ref listing is paged/);
});

test("a full page of queued runs reads the next page, up to three", async () => {
  const calls = [];
  const captured = RUNS.workflow_runs;
  const all = Array.from({ length: 450 }, (_, i) => ({ ...structuredClone(captured[i % captured.length]), id: 1000 + i }));
  const github = async (method, path) => {
    calls.push(`${method} ${path}`);
    const page = Number(/&page=(\d+)/.exec(path)?.[1]);
    if (path.includes("status=queued")) return listing(all.slice((page - 1) * 100, page * 100), all);
    if (path.includes("/actions/runs?")) return listing([]);
    return structuredClone(REFS);
  };
  const log = console.log;
  console.log = () => {};
  try {
    await main({ env: { GITHUB_REPOSITORY: REPO }, github, now: () => NOW });
  } finally {
    console.log = log;
  }
  assert.equal(calls.filter((call) => call.includes("status=queued")).length, 3);
  assert.equal(calls.length, 5);
});

test("a run whose head commit is on main belongs to a merged group and is kept", async () => {
  const r = await sweep({ queued: [{ ...run(1, GONE), head_sha: COMMITS[0].sha }, run(2, `${GONE}-b`), run(3, `${GONE}-c`)], onMain: [sha(3)] });
  assert.deepEqual(posts(r.calls), [cancel(2)]);
});

test("a failed read of main's commits cancels nothing", async () => {
  const r = await sweep({ queued: [run(1, GONE)], failCommits: true });
  assert.equal(r.code, 0);
  assert.deepEqual(r.calls, [LIST_QUEUED, LIST_RUNNING, LIST_REFS, LIST_COMMITS]);
  assert.match(r.out, /nothing more cancelled: GET commits failed/);
});

test("with runs but no orphan candidate, main's commits are not read", async () => {
  const r = await sweep({ queued: [run(1, LIVE)], branches: [LIVE] });
  assert.deepEqual(r.calls, [LIST_QUEUED, LIST_RUNNING, LIST_REFS]);
});

test("a candidate with no readable head commit is kept", async () => {
  const r = await sweep({ queued: [{ ...run(1, GONE), head_sha: undefined }] });
  assert.deepEqual(posts(r.calls), []);
});

test("the captured responses, every run's queue ref still listed, cancel nothing and read no commits", async () => {
  const r = await sweep({ running: structuredClone(RUNS.workflow_runs) });
  assert.deepEqual(r.calls, [LIST_QUEUED, LIST_RUNNING, LIST_REFS]);
  assert.match(r.out, /listed=4 cancelled=\[\] calls=3/);
});

test("a captured run whose group ref was deleted is cancelled", async () => {
  const [kept, ...rest] = structuredClone(RUNS.workflow_runs);
  const orphan = { ...kept, head_branch: GONE };
  const r = await sweep({ running: [orphan, ...rest] });
  assert.deepEqual(posts(r.calls), [cancel(kept.id)]);
});
