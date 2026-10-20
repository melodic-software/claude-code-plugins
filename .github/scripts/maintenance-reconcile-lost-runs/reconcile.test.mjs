// Expected values come from the reconciler's spec: a CI run on a PR's current
// head whose newest attempt ended cancelled, timed_out or startup_failure,
// with no newer run of that workflow on the head, is re-run once; at most 3
// PR CI sets are in flight; mutating calls are at least 1 s apart; nothing is
// re-run while githubstatus.com shows Actions as anything but operational.
// Run and PR shapes follow a recorded REST response (a cancelled
// pr-require-checks run, an open PR); fixtures/components.json is a recorded
// githubstatus.com components response, trimmed.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { createGitHub, GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { main } from "./reconcile.mjs";

const REPO = "melodic-software/claude-code-plugins";
const NOW = Date.parse("2026-10-19T20:00:00Z");
const STATUS = JSON.parse(readFileSync(new URL("./fixtures/components.json", import.meta.url), "utf8"));
const CHECKS = ".github/workflows/pr-require-checks.yml";
const WINDOWS = ".github/workflows/pr-test-windows.yml";
const REVIEW = ".github/workflows/pr-review-hosted.yml";
const sha = (n) => String(n).padStart(40, "0");

const statusWith = (actions) => ({
  ...STATUS,
  components: STATUS.components.map((c) => (c.name === "Actions" ? { ...c, status: actions } : c)),
});
const pr = (number, { draft = false, repo = REPO, autoMerge = null } = {}) => ({
  number,
  state: "open",
  draft,
  auto_merge: autoMerge,
  base: { ref: "main" },
  head: { sha: sha(number), ref: `fix/${number}`, repo: { full_name: repo } },
});
const run = (id, head, { path = CHECKS, conclusion = "cancelled", status = "completed", attempt = 1, created = "2026-10-19T18:59:43Z", event = "pull_request" } = {}) => ({
  id,
  path,
  event,
  status,
  conclusion: status === "completed" ? conclusion : null,
  run_attempt: attempt,
  workflow_id: path.length,
  head_sha: head,
  created_at: created,
  updated_at: created,
  head_repository: { full_name: REPO },
});

function fakeGitHub({ pulls, runs = [], fail = {} }) {
  const calls = [];
  const byId = new Map(runs.map((r) => [r.id, r]));
  const github = async (method, path) => {
    calls.push(`${method} ${path}`);
    if (fail[`${method} ${path}`]) {
      throw fail[`${method} ${path}`];
    }
    if (method === "GET" && path.startsWith(`/repos/${REPO}/pulls?`)) {
      return path.includes("page=1") ? pulls : [];
    }
    const pull = /^\/repos\/[^/]+\/[^/]+\/pulls\/([0-9]+)$/.exec(path);
    if (method === "GET" && pull) {
      return pulls.find((p) => p.number === Number(pull[1]));
    }
    const listing = /^\/repos\/[^/]+\/[^/]+\/actions\/runs\?head_sha=([0-9a-f]{40})&per_page=100$/.exec(path);
    if (method === "GET" && listing) {
      const found = runs.filter((r) => r.head_sha === listing[1]);
      return { total_count: found.length, workflow_runs: found };
    }
    const one = /^\/repos\/[^/]+\/[^/]+\/actions\/runs\/([0-9]+)(\/rerun)?$/.exec(path);
    if (one && method === "GET") {
      return byId.get(Number(one[1]));
    }
    if (one && method === "POST" && one[2]) {
      return {};
    }
    throw new Error(`unexpected call ${method} ${path}`);
  };
  return { github, calls };
}

async function reconcile({ pulls, runs, status = STATUS, env = {}, fail } = {}) {
  const { github, calls } = fakeGitHub({ pulls, runs, fail });
  const sleeps = [];
  const order = [];
  const tracked = async (method, path, body) => {
    order.push(method === "GET" ? "read" : "write");
    return github(method, path, body);
  };
  const code = await main({
    env: { GITHUB_REPOSITORY: REPO, KILL_SWITCH: "proceed", ...env },
    github: tracked,
    fetchStatus: async () => {
      if (status instanceof Error) {
        throw status;
      }
      return status;
    },
    sleep: async (ms) => {
      sleeps.push(ms);
      order.push(`sleep ${ms}`);
    },
    now: NOW,
  });
  const reruns = calls.filter((c) => c.startsWith("POST ")).map((c) => Number(/runs\/([0-9]+)\/rerun$/.exec(c)[1]));
  return { code, calls, reruns, sleeps, order };
}

test("a cancelled CI run on a PR's head is re-run once", async () => {
  const { code, reruns } = await reconcile({ pulls: [pr(1)], runs: [run(101, sha(1))] });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [101]);
});

test("timed_out and startup_failure count as lost; failure does not", async () => {
  const { reruns } = await reconcile({
    pulls: [pr(1), pr(2), pr(3)],
    runs: [run(101, sha(1), { conclusion: "timed_out" }), run(102, sha(2), { conclusion: "startup_failure" }), run(103, sha(3), { conclusion: "failure" })],
  });
  assert.deepEqual(reruns.sort(), [101, 102]);
});

test("a run already re-fired is not re-fired again", async () => {
  // Attempt 2 is the one re-run; it ended cancelled too.
  const { reruns, calls } = await reconcile({ pulls: [pr(1)], runs: [run(101, sha(1), { attempt: 2 })] });
  assert.deepEqual(reruns, []);
  assert.equal(calls.filter((c) => c.startsWith("POST ")).length, 0);
});

test("a run re-fired between the listing and the write is left alone", async () => {
  const listed = run(101, sha(1));
  const { github, calls } = fakeGitHub({ pulls: [pr(1)], runs: [listed] });
  let reads = 0;
  const code = await main({
    env: { GITHUB_REPOSITORY: REPO, KILL_SWITCH: "proceed" },
    github: async (method, path, body) => {
      if (method === "GET" && path.endsWith("/actions/runs/101")) {
        reads += 1;
        return { ...listed, run_attempt: 2, status: "queued", conclusion: null };
      }
      return github(method, path, body);
    },
    fetchStatus: async () => STATUS,
    sleep: async () => {},
    now: NOW,
  });
  assert.equal(code, 0);
  assert.equal(reads, 1);
  assert.equal(calls.filter((c) => c.startsWith("POST ")).length, 0);
});

test("a degraded Actions status produces no dispatch and reads nothing from GitHub", async () => {
  for (const actions of ["degraded_performance", "partial_outage", "major_outage", "under_maintenance"]) {
    const { code, calls } = await reconcile({ pulls: [pr(1)], runs: [run(101, sha(1))], status: statusWith(actions) });
    assert.equal(code, 0, actions);
    assert.deepEqual(calls, [], actions);
  }
});

test("an unreadable status page, or one with no Actions component, produces no dispatch", async () => {
  const noActions = { ...STATUS, components: STATUS.components.filter((c) => c.name !== "Actions") };
  for (const status of [new Error("fetch failed"), noActions, { components: "x" }, null]) {
    const { calls } = await reconcile({ pulls: [pr(1)], runs: [run(101, sha(1))], status });
    assert.deepEqual(calls, []);
  }
});

test("the kill switch stops the run before any read", async () => {
  const { code, calls } = await reconcile({ pulls: [pr(1)], runs: [run(101, sha(1))], env: { KILL_SWITCH: "" } });
  assert.equal(code, 0);
  assert.deepEqual(calls, []);
});

test("a newer run of the same workflow on the head means nothing was lost", async () => {
  const { reruns } = await reconcile({
    pulls: [pr(1)],
    runs: [run(101, sha(1)), run(102, sha(1), { conclusion: "success", created: "2026-10-19T19:10:00Z" })],
  });
  assert.deepEqual(reruns, []);
});

test("each lost CI workflow on the head is re-run, and other workflows do not hide them", async () => {
  const { reruns } = await reconcile({
    pulls: [pr(1)],
    runs: [run(101, sha(1)), run(102, sha(1), { path: WINDOWS, conclusion: "timed_out" }), run(103, sha(1), { path: REVIEW, conclusion: "success", created: "2026-10-19T19:30:00Z" })],
  });
  assert.deepEqual(reruns.sort(), [101, 102]);
});

test("a lost lane run is reported, not re-run", async () => {
  const { reruns, code } = await reconcile({ pulls: [pr(1)], runs: [run(103, sha(1), { path: REVIEW })] });
  assert.equal(code, 0);
  assert.deepEqual(reruns, []);
});

test("draft PRs, fork PRs and runs older than the lookback are left alone", async () => {
  const { reruns } = await reconcile({
    pulls: [pr(1, { draft: true }), pr(2, { repo: "someone/fork" }), pr(3)],
    runs: [run(101, sha(1)), run(102, sha(2)), run(103, sha(3), { created: "2026-10-17T19:00:00Z" })],
  });
  assert.deepEqual(reruns, []);
});

test("at most 3 PR CI sets are in flight, merge-critical PRs first", async () => {
  // PR 9 already has a re-run in flight; PRs 4 and 7 wait for auto-merge.
  const pulls = [pr(1), pr(2), pr(4, { autoMerge: { merge_method: "squash" } }), pr(5), pr(7, { autoMerge: { merge_method: "squash" } }), pr(9)];
  const runs = [
    run(101, sha(1)),
    run(102, sha(2)),
    run(104, sha(4)),
    run(105, sha(5)),
    run(107, sha(7)),
    run(109, sha(9), { status: "in_progress", attempt: 2 }),
  ];
  const { reruns } = await reconcile({ pulls, runs });
  assert.deepEqual(reruns, [104, 107]);
});

test("mutating calls are at least 1 s apart", async () => {
  const { reruns, order } = await reconcile({
    pulls: [pr(1), pr(2)],
    runs: [run(101, sha(1)), run(102, sha(1), { path: WINDOWS }), run(103, sha(2))],
  });
  assert.equal(reruns.length, 3);
  const writes = order.flatMap((step, i) => (step === "write" ? [i] : []));
  for (let k = 1; k < writes.length; k += 1) {
    const between = order.slice(writes[k - 1] + 1, writes[k]);
    const slept = between.filter((s) => s.startsWith("sleep ")).reduce((sum, s) => sum + Number(s.slice(6)), 0);
    assert.ok(slept >= 1000, `slept ${slept} ms between writes ${k - 1} and ${k}`);
  }
});

test("the first rate-limit error stops the run", async () => {
  const { code, calls } = await reconcile({
    pulls: [pr(1), pr(2)],
    runs: [run(101, sha(1)), run(102, sha(2))],
    fail: { [`GET /repos/${REPO}/actions/runs?head_sha=${sha(1)}&per_page=100`]: new GitHubError(429, "rate limited") },
  });
  assert.equal(code, 1);
  assert.equal(calls.filter((c) => c.includes(`head_sha=${sha(2)}`)).length, 0);
  assert.equal(calls.filter((c) => c.startsWith("POST ")).length, 0);
});

test("a refused re-run is reported and the rest go ahead", async () => {
  const { code, calls } = await reconcile({
    pulls: [pr(1), pr(2)],
    runs: [run(101, sha(1)), run(102, sha(2))],
    fail: { [`POST /repos/${REPO}/actions/runs/101/rerun`]: new GitHubError(403, "cannot be rerun") },
  });
  assert.equal(code, 1);
  assert.ok(calls.includes(`POST /repos/${REPO}/actions/runs/102/rerun`));
});

test("a re-run GitHub accepts with its empty 201 response counts as done", async () => {
  // The re-run endpoint answers 201 with no body; the real client parses it.
  const { github: fake, calls } = fakeGitHub({ pulls: [pr(1)], runs: [run(101, sha(1))] });
  const fetchImpl = async (url, init) => {
    const answer = await fake(init.method, url.slice("https://api.example".length));
    return init.method === "POST" ? new Response(null, { status: 201 }) : Response.json(answer);
  };
  const code = await main({
    env: { GITHUB_REPOSITORY: REPO, KILL_SWITCH: "proceed" },
    github: createGitHub({ token: "t", apiUrl: "https://api.example", fetchImpl }),
    fetchStatus: async () => STATUS,
    sleep: async () => {},
    now: NOW,
  });
  assert.equal(code, 0);
  assert.ok(calls.includes(`POST /repos/${REPO}/actions/runs/101/rerun`));
});

test("a PR whose head moved, or that closed or went draft, after the listing is left alone", async () => {
  for (const now of [{ head: { ...pr(1).head, sha: sha(2) } }, { state: "closed" }, { draft: true }]) {
    const { github, calls } = fakeGitHub({ pulls: [pr(1)], runs: [run(101, sha(1))] });
    const code = await main({
      env: { GITHUB_REPOSITORY: REPO, KILL_SWITCH: "proceed" },
      github: async (method, path, body) =>
        method === "GET" && path === `/repos/${REPO}/pulls/1` ? { ...pr(1), ...now } : github(method, path, body),
      fetchStatus: async () => STATUS,
      sleep: async () => {},
      now: NOW,
    });
    assert.equal(code, 0, JSON.stringify(now));
    assert.equal(calls.filter((c) => c.startsWith("POST ")).length, 0, JSON.stringify(now));
  }
});
