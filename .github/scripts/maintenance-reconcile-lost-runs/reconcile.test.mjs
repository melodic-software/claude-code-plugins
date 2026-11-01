// Expected values come from the reconciler's spec: a CI run on a PR's current
// head whose newest attempt ended cancelled, timed_out or startup_failure,
// with no newer run of that workflow on the head, is re-run once; at most 3
// PR CI sets are in flight; mutating calls are at least 1 s apart; nothing is
// re-run while githubstatus.com shows Actions as anything but operational.
// Run and PR shapes follow a recorded REST response (a cancelled
// pr-require-checks run, an open PR); fixtures/components.json is a recorded
// githubstatus.com components response, trimmed. A pr-verify run whose first
// attempt ended cancelled, timed_out, startup_failure or failure is re-run
// once, only after the plan names its record
// reconcile-rerun-<run id>-2-<head sha> for the upload steps, only when a
// job of that attempt started, and never when its verdict write started;
// pr-verify run shapes follow a recorded workflow_run run (head_branch main,
// head_sha the main tip, no pull_requests).
import assert from "node:assert/strict";
import { readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";

import { createGitHub, GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { createRateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { CI_WORKFLOWS, GITHUB_STATUS_URL, JUDGE_PREDECESSOR, JUDGE_STEP, KILL_SWITCH_NOTE, main, NPM_STATUS_URL, PR_UNBLOCK_STOP_NOTE, prefilterSpec, REVIEW_STEP, REVIEW_STOP_NOTE, REVIEW_STOP_STEP, REVIEW_SWITCHES, SETTLED_VERSION, UPSTREAM_STOP_STEP, VERDICT_STOP_STEP, WRITE_STEP } from "./reconcile.mjs";
import { switchHold } from "../pr-merge/merge-holds.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const REPO = "melodic-software/claude-code-plugins";
const NOW = Date.parse("2026-10-19T20:00:00Z");
const STATUS = JSON.parse(readFileSync(new URL("./fixtures/components.json", import.meta.url), "utf8"));
const CHECKS = ".github/workflows/pr-require-checks.yml";
const WINDOWS = ".github/workflows/pr-test-platforms.yml";
const REVIEW = ".github/workflows/pr-review-hosted.yml";
const VERIFY = ".github/workflows/pr-verify.yml";
const MAIN_REVIEW = ".github/workflows/pr-review-main.yml";
const MAIN_TIP = "e".repeat(40);
const sha = (n) => String(n).padStart(40, "0");

const fixture = (name) => JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8"));
// Recorded status.json pages: npm's during its 2026-10-22 install incident
// (indicator minor) and GitHub's with nothing open (indicator none).
const NPM_DOWN = fixture("npm-status.json");
const GITHUB_OK = fixture("github-status.json");
const NPM_OK = { ...NPM_DOWN, status: { indicator: "none", description: "All Systems Operational" } };
const UPSTREAM_OK = { [NPM_STATUS_URL]: NPM_OK, [GITHUB_STATUS_URL]: GITHUB_OK };
// pr-require-checks run 39710654665's latest jobs: two time-limit cancels and a
// real lint-shell failure. Without lint-shell, its failures are infra only.
const MIXED_JOBS = fixture("jobs-39710654665.json").jobs;
const INFRA_JOBS = MIXED_JOBS.filter((j) => j.name !== "lint-shell");

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
const run = (id, head, { path = CHECKS, conclusion = "cancelled", status = "completed", attempt = 1, created = "2026-10-19T18:59:43Z", updated = created, event = "pull_request", jobs } = {}) => ({
  id,
  path,
  event,
  status,
  conclusion: status === "completed" ? conclusion : null,
  run_attempt: attempt,
  workflow_id: path.length,
  head_sha: head,
  created_at: created,
  updated_at: updated,
  head_repository: { full_name: REPO },
  jobs,
});

function fakeGitHub({ pulls, runs = [], fail = {}, statuses = {} }) {
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
    const byWorkflow = /^\/repos\/[^/]+\/[^/]+\/actions\/workflows\/([a-z0-9-]+\.yml)\/runs\?created=%3E%3D2026-10-18T20%3A00%3A00Z(?:&status=([a-z_]+))?&per_page=100(?:&page=([0-9]+))?$/.exec(path);
    if (method === "GET" && byWorkflow) {
      // Like GitHub, `status` matches a run's status or its conclusion.
      const found = runs.filter(
        (r) => r.path === `.github/workflows/${byWorkflow[1]}` && (byWorkflow[2] === undefined || r.status === byWorkflow[2] || r.conclusion === byWorkflow[2]),
      );
      const page = Number(byWorkflow[3] ?? 1);
      return { total_count: found.length, workflow_runs: found.slice((page - 1) * 100, page * 100) };
    }
    const jobs = /^\/repos\/[^/]+\/[^/]+\/actions\/runs\/([0-9]+)\/attempts\/1\/jobs\?per_page=100$/.exec(path);
    if (method === "GET" && jobs) {
      const found = byId.get(Number(jobs[1]))?.jobs ?? [];
      return { total_count: byId.get(Number(jobs[1]))?.jobsTotal ?? found.length, jobs: found };
    }
    const latest = /^\/repos\/[^/]+\/[^/]+\/actions\/runs\/([0-9]+)\/jobs\?filter=latest&per_page=100$/.exec(path);
    if (method === "GET" && latest) {
      const found = byId.get(Number(latest[1]))?.jobs ?? [];
      return { total_count: found.length, jobs: found };
    }
    const notes = /^\/repos\/[^/]+\/[^/]+\/check-runs\/([0-9]+)\/annotations\?per_page=100$/.exec(path);
    if (method === "GET" && notes) {
      return runs.flatMap((r) => r.jobs ?? []).find((j) => j.id === Number(notes[1]))?.notes ?? [];
    }
    const listed = /^\/repos\/[^/]+\/[^/]+\/commits\/([0-9a-f]{40})\/statuses\?per_page=100&page=([0-9]+)$/.exec(path);
    if (method === "GET" && listed) {
      return (statuses[listed[1]] ?? []).slice((Number(listed[2]) - 1) * 100, Number(listed[2]) * 100);
    }
    const one = /^\/repos\/[^/]+\/[^/]+\/actions\/runs\/([0-9]+)(\/rerun|\/rerun-failed-jobs)?$/.exec(path);
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

// Runs the workflow's two steps: plan, then, when the plan step succeeds,
// act. The upload steps between them read the plan's record-N outputs.
// `carry`, when set, is the settled-runs file the last pass uploaded (null:
// no trusted pass holds one), in run 900 after `carryRuns` in this workflow's
// listing; the pass then writes its own, returned as `settled`.
const LAST_PASS = { id: 900, path: ".github/workflows/maintenance-reconcile-lost-runs.yml", event: "schedule", head_branch: "main" };
async function reconcile({ pulls, runs, status = STATUS, upstream = UPSTREAM_OK, env = {}, fail, statuses, github: wrap = (g) => g, carry, carryRuns = [], download } = {}) {
  const { github, calls } = fakeGitHub({ pulls, runs, fail, statuses });
  const sleeps = [];
  const order = [];
  const tracked = wrap(async (method, path, body) => {
    order.push(method === "GET" ? "read" : "write");
    if (carry !== undefined && path === `/repos/${REPO}/actions/workflows/maintenance-reconcile-lost-runs.yml/runs?branch=main&exclude_pull_requests=true&per_page=100&page=1`) {
      calls.push(`${method} ${path}`);
      return { workflow_runs: carry === null ? [] : [...carryRuns, LAST_PASS] };
    }
    const artifacts = /^\/repos\/[^/]+\/[^/]+\/actions\/runs\/([0-9]+)\/artifacts\?per_page=100$/.exec(path);
    if (carry !== undefined && artifacts) {
      calls.push(`${method} ${path}`);
      return { total_count: 1, artifacts: [{ name: "reconcile-settled-runs", expired: false }] };
    }
    return github(method, path, body);
  });
  const dir = tempDir("reconcile-");
  try {
    const files = {
      PLAN_PATH: path.join(dir, "plan.json"),
      RECORD_PATH: path.join(dir, "record.json"),
      GITHUB_OUTPUT: path.join(dir, "output"),
    };
    writeFileSync(files.GITHUB_OUTPUT, "");
    if (carry !== undefined) {
      files.SETTLED_PATH = path.join(dir, "settled.json");
    }
    const step = (mode) =>
      main({
        env: { GITHUB_REPOSITORY: REPO, KILL_SWITCH: "proceed", ...files, ...env, MODE: mode },
        github: tracked,
        fetchStatus: async (url) => {
          const page = upstream[url] ?? status;
          if (page instanceof Error) {
            throw page;
          }
          return page;
        },
        sleep: async (ms) => {
          sleeps.push(ms);
          order.push(`sleep ${ms}`);
        },
        now: NOW,
        download:
          download ??
          ((id) => {
            assert.equal(id, 900);
            return carry;
          }),
      });
    const planCode = await step("plan");
    const planWrites = calls.filter((c) => c.startsWith("POST ")).length;
    const outputs = Object.fromEntries(
      [...readFileSync(files.GITHUB_OUTPUT, "utf8").matchAll(/^([a-z0-9-]+)<<(\S+)\n([^\n]*)\n\2$/gm)].map((m) => [m[1], m[3]]),
    );
    const code = planCode === 0 ? await step("act") : planCode;
    const posted = (suffix) => calls.filter((c) => c.startsWith("POST ") && c.endsWith(suffix)).map((c) => Number(/runs\/([0-9]+)\//.exec(c)[1]));
    const reruns = posted("/rerun");
    const failedJobReruns = posted("/rerun-failed-jobs");
    const settled = files.SETTLED_PATH ? JSON.parse(readFileSync(files.SETTLED_PATH, "utf8")) : undefined;
    return { code, planCode, planWrites, outputs, calls, reruns, failedJobReruns, sleeps, order, settled };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// A first-attempt job of pr-verify, lost before (null) or after its judge step
// started; by default it was lost in the trigger check, before the judge step.
// A finished job lists every step completed, the ones it never reached as
// skipped, and ends with "Complete job".
const verifyJob = (judgeConclusion = null) => [
  {
    name: "verify",
    status: "completed",
    steps: [
      { name: "Set up job", status: "completed", conclusion: "success" },
      { name: "Check the trigger", status: "completed", conclusion: judgeConclusion === null ? "cancelled" : "success" },
      { name: "Judge the pull request", status: "completed", conclusion: judgeConclusion ?? "skipped" },
      { name: "Upload the verdict", status: "completed", conclusion: "skipped" },
      { name: "Complete job", status: "completed", conclusion: "success" },
    ],
  },
];
const verifyRun = (id, opts = {}) => ({ ...run(id, MAIN_TIP, { path: VERIFY, event: "workflow_run", ...opts }), head_branch: "main", jobs: verifyJob() });
const records = (outputs) => [outputs["record-1"], outputs["record-2"], outputs["record-3"]];

test("a cancelled CI run on a PR's head is re-run once", async () => {
  const { code, reruns } = await reconcile({ pulls: [pr(1)], runs: [run(101, sha(1))] });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [101]);
});

// A fork PR that pushed the same commit lists its runs under the same head
// SHA. Its newer run is neither re-run nor allowed to hide this repository's.
test("a fork's newer run at the same head SHA is not re-run and does not hide the head's own run", async () => {
  const fork = (id, opts) => ({ ...run(id, sha(1), { created: "2026-10-19T19:10:00Z", ...opts }), head_repository: { full_name: "someone/claude-code-plugins" } });
  for (const [what, forkRun, own, expected] of [
    ["a lost fork run", fork(102), run(101, sha(1)), { reruns: [101], failedJobReruns: [] }],
    ["a passed fork run", fork(102, { conclusion: "success" }), run(101, sha(1)), { reruns: [101], failedJobReruns: [] }],
    [
      "a fork run going at attempt 2",
      fork(102, { status: "in_progress", attempt: 2 }),
      run(101, sha(1), { conclusion: "failure", jobs: INFRA_JOBS, updated: "2026-10-19T19:30:00Z" }),
      { reruns: [], failedJobReruns: [101] },
    ],
  ]) {
    const { code, reruns, failedJobReruns } = await reconcile({ pulls: [pr(1)], runs: [own, forkRun] });
    assert.equal(code, 0, what);
    assert.deepEqual({ reruns, failedJobReruns }, expected, what);
  }
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

// #9828: pr-require-checks run 40118648493 ended cancelled at attempt 2 too
// (test-bash (3) past its 9-minute limit both times). It is not re-run again,
// and the summary names the head, the run, the attempt and who takes it.
test("a CI run lost again at attempt 2 is named in the summary, not re-run", async () => {
  const dir = tempDir("reconcile-summary-");
  try {
    const summary = path.join(dir, "summary.md");
    writeFileSync(summary, "");
    const { code, reruns } = await reconcile({ pulls: [pr(1)], runs: [run(40118648493, sha(1), { attempt: 2 })], env: { GITHUB_STEP_SUMMARY: summary } });
    assert.equal(code, 0);
    assert.deepEqual(reruns, []);
    assert.match(
      readFileSync(summary, "utf8"),
      /#1: run 40118648493 \(\.github\/workflows\/pr-require-checks\.yml\) ended cancelled again at attempt 2; not re-run: fix-ci takes a job past its time limit, any other cause waits for a push or a person's re-run/,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// The fresh read before the write sees the run already re-run.
const rerunSinceListing = (id) => (github) => async (method, apiPath, body) => {
  if (method === "GET" && apiPath.endsWith(`/actions/runs/${id}`)) {
    const listed = await github(method, apiPath, body);
    return { ...listed, run_attempt: 2, status: "queued", conclusion: null };
  }
  return github(method, apiPath, body);
};

test("a run re-fired between the listing and the write is left alone", async () => {
  const { code, calls, reruns } = await reconcile({ pulls: [pr(1)], runs: [run(101, sha(1))], github: rerunSinceListing(101) });
  assert.equal(code, 0);
  assert.equal(calls.filter((c) => c.endsWith("/actions/runs/101")).length, 1);
  assert.deepEqual(reruns, []);
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

// The rate guard's refusal carries status 429: it stops the run like a 429
// answer, with no request sent and no wait taken.
test("a call the rate guard refuses stops the run without a request or a wait", async () => {
  const dir = tempDir("reconcile-stop-");
  try {
    const stopFile = path.join(dir, "stop");
    writeFileSync(stopFile, `* ${Math.floor(Date.now() / 1000) + 3600}\n`);
    const latch = createRateLimitLatch({ log: () => {}, fail: () => {}, limits: () => ({}), stopFile });
    let sent = 0;
    const { code, sleeps } = await reconcile({
      pulls: [pr(1)],
      runs: [run(101, sha(1))],
      github: () =>
        createGitHub({
          token: "t",
          apiUrl: "https://api.example",
          latch,
          fetchImpl: async () => {
            sent += 1;
            return Response.json({});
          },
        }),
    });
    assert.equal(code, 1);
    assert.equal(sent, 0);
    assert.deepEqual(sleeps, []);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
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
  const { code, reruns } = await reconcile({
    pulls: [pr(1)],
    runs: [run(101, sha(1))],
    github: (fake) =>
      createGitHub({
        token: "t",
        apiUrl: "https://api.example",
        fetchImpl: async (url, init) => {
          const answer = await fake(init.method, url.slice("https://api.example".length));
          return init.method === "POST" ? new Response(null, { status: 201 }) : Response.json(answer);
        },
      }),
  });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [101]);
});

test("a PR whose head moved, or that closed or went draft, after the listing is left alone", async () => {
  for (const now of [{ head: { ...pr(1).head, sha: sha(2) } }, { state: "closed" }, { draft: true }]) {
    const { code, reruns } = await reconcile({
      pulls: [pr(1)],
      runs: [run(101, sha(1))],
      github: (fake) => async (method, p, body) =>
        method === "GET" && p === `/repos/${REPO}/pulls/1` ? { ...pr(1), ...now } : fake(method, p, body),
    });
    assert.equal(code, 0, JSON.stringify(now));
    assert.deepEqual(reruns, [], JSON.stringify(now));
  }
});

test("a lost verify run is re-run after the plan names its record, and the plan writes nothing", async () => {
  const { code, planWrites, outputs, reruns } = await reconcile({ pulls: [pr(1)], runs: [verifyRun(201)] });
  assert.equal(code, 0);
  assert.equal(planWrites, 0);
  assert.deepEqual(records(outputs), [`reconcile-rerun-201-2-${MAIN_TIP}`, "", ""]);
  assert.deepEqual(reruns, [201]);
});

test("a verify run already at attempt 2 is never re-run or recorded", async () => {
  const { outputs, reruns } = await reconcile({ pulls: [], runs: [verifyRun(201, { attempt: 2 })] });
  assert.deepEqual(reruns, []);
  assert.deepEqual(records(outputs), ["", "", ""]);
});

test("a verify run re-run between the plan and the write is left alone", async () => {
  const { code, reruns } = await reconcile({ pulls: [], runs: [verifyRun(201)], github: rerunSinceListing(201) });
  assert.equal(code, 0);
  assert.deepEqual(reruns, []);
});

test("verify runs that succeeded, are older than the lookback, or ran off main are left alone", async () => {
  const { reruns, outputs } = await reconcile({
    pulls: [],
    runs: [
      verifyRun(201, { conclusion: "success" }),
      verifyRun(203, { created: "2026-10-17T19:00:00Z" }),
      { ...verifyRun(204), head_branch: "fix/x" },
      verifyRun(205, { event: "workflow_dispatch" }),
    ],
  });
  assert.deepEqual(reruns, []);
  assert.deepEqual(records(outputs), ["", "", ""]);
});

test("verify re-runs share the cap of 3 with PR CI sets, CI first, then the newest verify run", async () => {
  // One verify re-run is already in flight, so two places are left.
  const { reruns, outputs } = await reconcile({
    pulls: [pr(1)],
    runs: [
      run(101, sha(1)),
      verifyRun(209, { status: "in_progress", attempt: 2 }),
      verifyRun(202, { created: "2026-10-19T19:20:00Z" }),
      verifyRun(201, { created: "2026-10-19T19:10:00Z" }),
    ],
  });
  assert.deepEqual(reruns, [101, 202]);
  assert.deepEqual(records(outputs), [`reconcile-rerun-101-2-${sha(1)}`, `reconcile-rerun-202-2-${MAIN_TIP}`, ""]);
});

test("verify re-runs go before flake re-runs, newest first, since nothing else re-runs them", async () => {
  const flake = (id, n) => failed(id, sha(n), { jobs: MIXED_JOBS, updated: "2026-10-19T19:00:00Z" });
  const { reruns, failedJobReruns, outputs } = await reconcile({
    pulls: [pr(1), pr(2), pr(3)],
    runs: [flake(101, 1), flake(102, 2), flake(103, 3), verifyRun(201, { created: "2026-10-19T19:10:00Z" }), verifyRun(202, { created: "2026-10-19T19:20:00Z" })],
  });
  assert.deepEqual(reruns, [202, 201]);
  assert.deepEqual(failedJobReruns, [101]);
  assert.deepEqual(records(outputs), [`reconcile-rerun-202-2-${MAIN_TIP}`, `reconcile-rerun-201-2-${MAIN_TIP}`, `reconcile-rerun-101-2-${sha(1)}`]);
});

test("at most 3 verify runs are recorded and re-run in one run", async () => {
  const { reruns, outputs } = await reconcile({
    pulls: [],
    runs: [verifyRun(201), verifyRun(202), verifyRun(203), verifyRun(204)].map((r, i) => ({ ...r, created_at: `2026-10-19T19:0${i}:00Z` })),
  });
  assert.deepEqual(reruns, [204, 203, 202]);
  assert.deepEqual(records(outputs), [204, 203, 202].map((id) => `reconcile-rerun-${id}-2-${MAIN_TIP}`));
});

// A lane workflow's jobs (pr-verify's legs by default), as name and body.
const verifyLegs = (file = "pr-verify.yml") => {
  const workflow = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
  const jobs = workflow.slice(workflow.search(/^jobs:$/m));
  return [...jobs.matchAll(/^ {2}([a-z][a-z0-9-]*):\n((?: {4,}.*\n|\s*\n)+)/gm)].map(([, name, body]) => ({ name, body }));
};
// A leg's steps, each its first line and the lines under it.
const legSteps = (body) => body.split(/^(?= {6}- name: )/m).filter((s) => s.startsWith("      - name: "));

// The reconciler reads every job's steps by name, so a leg whose judge step
// another name hid would hide a lost run.
test("pr-verify still names its judge step as the reconciler reads it, in every leg", () => {
  const legs = verifyLegs();
  assert.ok(legs.length > 1);
  for (const { name, body } of legs) {
    const steps = legSteps(body);
    const names = steps.map((s) => s.match(/^ {6}- name: (.+)$/m)[1]);
    const judge = steps.findIndex((s) => /^ {8}id: judge$/m.test(s));
    assert.ok(judge >= 0, name);
    assert.equal(names[judge], JUDGE_STEP, name);
    assert.equal(names[judge - 1], JUDGE_PREDECESSOR, name);
    assert.ok(judge < names.indexOf("Upload the verdict"), name);
    // The verdict is written only once a judgment finished.
    const writes = steps.filter((s) => s.startsWith(`      - name: ${WRITE_STEP}\n`));
    assert.equal(writes.length, 1, name);
    assert.match(writes[0], /\n[ ]+if: \$\{\{ !cancelled\(\) && \(steps\.chunk-fail\.outputs\.fail == 'true' \|\| /, name);
  }
});

// A review leg whose step names drifted would lose its hold, and one whose
// trigger check took no reconciler record would refuse every re-run.
test("pr-review-main still names its review and write steps as the reconciler reads them, and takes its record, in every review leg", () => {
  const legs = verifyLegs("pr-review-main.yml").filter(({ body }) => new RegExp(`^ {6}- name: ${REVIEW_STEP}$`, "m").test(body));
  assert.equal(legs.length, 3);
  for (const { name, body } of legs) {
    const steps = legSteps(body);
    const names = steps.map((s) => s.match(/^ {6}- name: (.+)$/m)[1]);
    const review = steps.findIndex((s) => /^ {8}id: review-1$/m.test(s));
    assert.equal(names[review], REVIEW_STEP, name);
    assert.equal(names[review - 1], JUDGE_PREDECESSOR, name);
    const writes = steps.filter((s) => s.startsWith(`      - name: ${WRITE_STEP}\n`));
    assert.equal(writes.length, 1, name);
    assert.match(writes[0], /\n[ ]+if: steps\.review-1\.outcome == 'success' && /, name);
    const trigger = steps.find((s) => s.startsWith("      - name: Check the trigger\n"));
    assert.match(trigger, /\n[ ]+reconciler-workflow: \.github\/workflows\/maintenance-reconcile-lost-runs\.yml\n/, name);
  }
});

test("a verify run lost during its judge step is recorded and re-run once", async () => {
  for (const conclusion of ["failure", "cancelled"]) {
    const { code, reruns, outputs } = await reconcile({ pulls: [], runs: [{ ...verifyRun(201), jobs: verifyJob(conclusion) }] });
    assert.equal(code, 0, conclusion);
    assert.deepEqual(reruns, [201], conclusion);
    assert.deepEqual(records(outputs), [`reconcile-rerun-201-2-${MAIN_TIP}`, "", ""], conclusion);
  }
});

// The judge step is continue-on-error, so the jobs API lists it as success
// even when it broke; only the verdict write, which runs on its true outcome,
// shows that the judgment finished.
test("a verify run whose judge step lists success but whose verdict write was skipped is re-run once", async () => {
  const [job] = verifyJob("success");
  const steps = job.steps.flatMap((s) => (s.name === "Upload the verdict" ? [{ name: WRITE_STEP, status: "completed", conclusion: "skipped" }, s] : [s]));
  const { code, reruns, outputs } = await reconcile({
    pulls: [],
    runs: [{ ...verifyRun(201, { conclusion: "failure" }), jobs: [{ ...job, conclusion: "failure", steps }] }],
  });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [201]);
  assert.deepEqual(records(outputs), [`reconcile-rerun-201-2-${MAIN_TIP}`, "", ""]);
});

// A judgment that finished may hold a FAIL its run then failed to write or
// upload; a re-run would judge the head a second time.
test("a verify run whose verdict write started is held with its reason, not re-run, even when the upload failed", async () => {
  const [job] = verifyJob("success");
  const steps = job.steps.flatMap((s) =>
    s.name === "Upload the verdict"
      ? [
          { name: WRITE_STEP, status: "completed", conclusion: "success" },
          { ...s, conclusion: "failure" },
        ]
      : [s],
  );
  const dir = tempDir("reconcile-summary-");
  try {
    const summary = path.join(dir, "summary.md");
    writeFileSync(summary, "");
    const { code, reruns, outputs } = await reconcile({
      pulls: [],
      runs: [{ ...verifyRun(201, { conclusion: "failure" }), jobs: [{ ...job, conclusion: "failure", steps }] }],
      env: { GITHUB_STEP_SUMMARY: summary },
    });
    assert.equal(code, 0);
    assert.deepEqual(reruns, []);
    assert.deepEqual(records(outputs), ["", "", ""]);
    assert.match(readFileSync(summary, "utf8"), /lane run 201 \(\.github\/workflows\/pr-verify\.yml\) ended failure after its verdict write started/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// A leg that hands off ends its judge step on a lane class, which fails the
// launcher, so its verdict write skips (run-claude-cli lane.cjs handoffReason
// needs a class; a class throws); the judge step lists success, being
// continue-on-error. Only the fallback leg's own steps tell the runs apart.
test("a verify run is read across all three legs: a fallback write held, a fallback loss re-run", async () => {
  const handedOff = (name) => ({
    name,
    status: "completed",
    conclusion: "success",
    steps: [
      { name: "Set up job", status: "completed", conclusion: "success" },
      { name: JUDGE_PREDECESSOR, status: "completed", conclusion: "success" },
      { name: JUDGE_STEP, status: "completed", conclusion: "success" },
      { name: WRITE_STEP, status: "completed", conclusion: "skipped" },
      { name: "Upload the verdict", status: "completed", conclusion: "skipped" },
      { name: "Complete job", status: "completed", conclusion: "success" },
    ],
  });
  const fallback = (write, upload) => ({
    name: "check-intent-fallback",
    status: "completed",
    conclusion: "failure",
    steps: [
      { name: "Set up job", status: "completed", conclusion: "success" },
      { name: JUDGE_PREDECESSOR, status: "completed", conclusion: "success" },
      { name: JUDGE_STEP, status: "completed", conclusion: "success" },
      { name: WRITE_STEP, status: "completed", conclusion: write },
      { name: "Upload the verdict", status: "completed", conclusion: upload },
      { name: "Complete job", status: "completed", conclusion: "success" },
    ],
  });
  const jobs = (last) => [handedOff("check-intent"), handedOff("check-intent-subscription"), last];
  const held = await reconcile({ pulls: [], runs: [{ ...verifyRun(201, { conclusion: "failure" }), jobs: jobs(fallback("success", "failure")) }] });
  assert.equal(held.code, 0);
  assert.deepEqual(held.reruns, []);
  assert.deepEqual(records(held.outputs), ["", "", ""]);
  const lost = await reconcile({ pulls: [], runs: [{ ...verifyRun(201, { conclusion: "failure" }), jobs: jobs(fallback("skipped", "skipped")) }] });
  assert.equal(lost.code, 0);
  assert.deepEqual(lost.reruns, [201]);
  assert.deepEqual(records(lost.outputs), [`reconcile-rerun-201-2-${MAIN_TIP}`, "", ""]);
});

test("a verify run that failed on its first attempt is recorded and re-run once", async () => {
  const { code, reruns, outputs } = await reconcile({
    pulls: [],
    runs: [{ ...verifyRun(201, { conclusion: "failure" }), jobs: verifyJob("failure") }],
  });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [201]);
  assert.deepEqual(records(outputs), [`reconcile-rerun-201-2-${MAIN_TIP}`, "", ""]);
});

test("a verify run the kill switch stopped is re-run once the switch is off", async () => {
  const stopped = [
    {
      name: "check-intent",
      steps: [
        { name: "Set up job", status: "completed", conclusion: "success" },
        { name: "Check the kill switch", status: "completed", conclusion: "success" },
        { name: "Report the kill switch", status: "completed", conclusion: "failure" },
        { name: "Check the trigger", status: "completed", conclusion: "skipped" },
      ],
    },
  ];
  const { reruns } = await reconcile({ pulls: [], runs: [{ ...verifyRun(201, { conclusion: "failure" }), jobs: stopped }] });
  assert.deepEqual(reruns, [201]);
});

test("a failed verify run's second attempt is never re-run", async () => {
  const { reruns, outputs } = await reconcile({
    pulls: [],
    runs: [{ ...verifyRun(201, { conclusion: "failure", attempt: 2 }), jobs: verifyJob("failure") }],
  });
  assert.deepEqual(reruns, []);
  assert.deepEqual(records(outputs), ["", "", ""]);
});

test("pr-verify fails a run the kill switch stopped in every leg, so the reconciler sees it", () => {
  const legs = verifyLegs();
  assert.ok(legs.length > 1);
  for (const { name, body } of legs) {
    const reports = legSteps(body).filter((s) => s.startsWith("      - name: Report the kill switch\n"));
    assert.equal(reports.length, 1, name);
    assert.match(reports[0], /\n[ ]+if: steps\.kill\.outputs\.proceed != 'true'\n/, name);
    assert.match(reports[0], /::error::/, name);
    assert.match(reports[0], /\n[ ]+exit 1\n/, name);
  }
});

test("a verify run lost after it started but before its judge step is re-run", async () => {
  const { reruns } = await reconcile({
    pulls: [],
    runs: [
      { ...verifyRun(201), jobs: verifyJob(null) },
      { ...verifyRun(202), jobs: verifyJob("skipped"), created_at: "2026-10-19T19:00:00Z" },
    ],
  });
  assert.deepEqual(reruns, [202, 201]);
});

test("a verify run none of whose first-attempt jobs started is never re-run or recorded", async () => {
  // A pending run concurrency cancelled for a newer one on the same PR head.
  for (const jobs of [[], [{ name: "verify", status: "completed", conclusion: "cancelled", steps: [] }]]) {
    const { code, reruns, outputs } = await reconcile({ pulls: [], runs: [{ ...verifyRun(201), jobs }] });
    assert.equal(code, 0);
    assert.deepEqual(reruns, []);
    assert.deepEqual(records(outputs), ["", "", ""]);
  }
});

// The jobs API can list a job that ran with no steps, or cut short before its
// judge step; neither shows whether the judge step started.
test("a verify run whose job's steps did not list is not re-run or recorded, and is read again next pass", async () => {
  const cut = [{ name: "Check the trigger", status: "completed", conclusion: "cancelled" }];
  // Opens with "Set up job" but skips the judge step's number.
  const midCut = [
    { number: 1, name: "Set up job", status: "completed", conclusion: "success" },
    { number: 2, name: "Check the trigger", status: "completed", conclusion: "success" },
    { number: 4, name: "Upload the verdict", status: "pending", conclusion: null },
  ];
  // Opens with "Set up job", every listed step done, the rest cut off.
  const tailCut = [
    { number: 1, name: "Set up job", status: "completed", conclusion: "success" },
    { number: 2, name: "Check the trigger", status: "completed", conclusion: "success" },
  ];
  // Whole, but stale: the judge step still in progress in a finished job.
  const stale = [
    { number: 1, name: "Set up job", status: "completed", conclusion: "success" },
    { number: 2, name: "Check the trigger", status: "completed", conclusion: "success" },
    { number: 3, name: "Judge the pull request", status: "in_progress", conclusion: null },
    { number: 4, name: "Upload the verdict", status: "pending", conclusion: null },
    { number: 9, name: "Complete job", status: "completed", conclusion: "success" },
  ];
  for (const [label, steps] of Object.entries({ empty: [], cut, midCut, tailCut, stale })) {
    const { code, reruns, outputs } = await reconcile({
      pulls: [],
      runs: [{ ...verifyRun(201), jobs: [{ name: "verify", status: "completed", conclusion: "cancelled", runner_id: 7, steps }] }],
    });
    assert.equal(code, 1, label);
    assert.deepEqual(reruns, [], label);
    assert.deepEqual(records(outputs), ["", "", ""], label);
  }
});

// A runner that dies cuts its job's list at the running step, with no
// "Complete job"; GitHub's runner-loss annotation on the job's check run tells
// that cut from one the API made.
test("a verify run whose job lost its runner is re-run when its cut list stops before the judge step, from the job's annotations", async () => {
  const lostAt = (running) => ({
    id: 88,
    name: "verify",
    status: "completed",
    conclusion: "failure",
    runner_id: 7,
    steps: [
      { number: 1, name: "Set up job", status: "completed", conclusion: "success" },
      { number: 2, name: "Check the trigger", status: "completed", conclusion: "success" },
      { number: 3, name: running, status: "in_progress", conclusion: null },
    ],
    notes: [{ annotation_level: "failure", message: "The hosted runner: GitHub Actions 7 lost communication with the server." }],
  });
  const before = await reconcile({ pulls: [], runs: [{ ...verifyRun(201), jobs: [lostAt("Read the spec")] }] });
  assert.equal(before.code, 0);
  assert.deepEqual(before.reruns, [201]);
  assert.deepEqual(records(before.outputs), [`reconcile-rerun-201-2-${MAIN_TIP}`, "", ""]);
  assert.ok(before.calls.includes(`GET /repos/${REPO}/check-runs/88/annotations?per_page=100`));
  const during = await reconcile({ pulls: [], runs: [{ ...verifyRun(201), jobs: [lostAt(JUDGE_STEP)] }] });
  assert.equal(during.code, 0);
  assert.deepEqual(during.reruns, []);
  assert.deepEqual(records(during.outputs), ["", "", ""]);
  const unnoted = await reconcile({ pulls: [], runs: [{ ...verifyRun(201), jobs: [{ ...lostAt("Read the spec"), notes: [] }] }] });
  assert.equal(unnoted.code, 1);
  assert.deepEqual(unnoted.reruns, []);
  assert.deepEqual(records(unnoted.outputs), ["", "", ""]);
});

// The judge step's log can echo model or PR text, so a failure annotation that
// reads as a runner loss proves one only on a cut list that stops before the
// judge step's predecessor, in a job that failed.
test("a runner-loss annotation counts only on a failed job whose cut list stops before the judge step's predecessor", async () => {
  const cutAt = (names, conclusion = "failure") => ({
    id: 88,
    name: "verify",
    status: "completed",
    conclusion,
    runner_id: 7,
    steps: names.map((name, i) => ({ number: i + 1, name, status: i === names.length - 1 ? "in_progress" : "completed", conclusion: i === names.length - 1 ? null : "success" })),
    notes: [{ annotation_level: "failure", message: "The hosted runner lost communication with the server." }],
  });
  const early = ["Set up job", "Check the trigger", "Read the spec"];
  const run201 = (job) => reconcile({ pulls: [], runs: [{ ...verifyRun(201), jobs: [job] }] });
  const genuine = await run201(cutAt(early));
  assert.equal(genuine.code, 0);
  assert.deepEqual(genuine.reruns, [201]);
  for (const reached of [JUDGE_PREDECESSOR, JUDGE_STEP]) {
    const echoed = await run201(cutAt([...early, reached]));
    assert.equal(echoed.code, 0, reached);
    assert.deepEqual(echoed.reruns, [], reached);
    assert.deepEqual(records(echoed.outputs), ["", "", ""], reached);
  }
  const notFailed = await run201(cutAt(early, "cancelled"));
  assert.equal(notFailed.code, 1);
  assert.deepEqual(notFailed.reruns, []);
  assert.deepEqual(records(notFailed.outputs), ["", "", ""]);
  const judgeNotFailed = await run201(cutAt([...early, JUDGE_STEP], "cancelled"));
  assert.equal(judgeNotFailed.code, 1);
  assert.deepEqual(judgeNotFailed.reruns, []);
});

// A judge step that started holds nothing: the first attempt is re-run once.
test("a verify run whose judge step is listed with no conclusion is re-run once", async () => {
  const [job] = verifyJob(null);
  const steps = job.steps.map((s) => (s.name === "Judge the pull request" ? { ...s, status: "completed", conclusion: null } : s));
  const { reruns, outputs } = await reconcile({ pulls: [], runs: [{ ...verifyRun(201), jobs: [{ ...job, steps }] }] });
  assert.deepEqual(reruns, [201]);
  assert.deepEqual(records(outputs), [`reconcile-rerun-201-2-${MAIN_TIP}`, "", ""]);
});

test("a verify run whose jobs cannot be read is not re-run", async () => {
  const { code, reruns, outputs } = await reconcile({
    pulls: [],
    runs: [verifyRun(201)],
    fail: { [`GET /repos/${REPO}/actions/runs/201/attempts/1/jobs?per_page=100`]: new GitHubError(500, "boom") },
  });
  assert.equal(code, 1);
  assert.deepEqual(reruns, []);
  assert.deepEqual(records(outputs), ["", "", ""]);
});

// pr-review-main run 40892239796's first-attempt jobs: both lanes reviewed and
// stopped on a credit stop, so the verdict write skipped and "Fail without a
// verdict" failed each job; the run ended failure with no verdict.
const MAIN_REVIEW_JOBS = fixture("jobs-40892239796.json").jobs;
const mainReviewRun = (id, opts = {}, jobs = MAIN_REVIEW_JOBS) => ({
  ...run(id, MAIN_TIP, { path: MAIN_REVIEW, event: "workflow_run", conclusion: "failure", ...opts }),
  head_branch: "main",
  jobs,
});

test("a main-run review that ended failure with no verdict is recorded and re-run once", async () => {
  const { code, reruns, outputs } = await reconcile({ pulls: [], runs: [mainReviewRun(301)] });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [301]);
  assert.deepEqual(records(outputs), [`reconcile-rerun-301-2-${MAIN_TIP}`, "", ""]);
});

test("a main-run review at attempt 2, or none of whose jobs started, is never re-run or recorded", async () => {
  const notStarted = MAIN_REVIEW_JOBS.map((job) => ({ ...job, conclusion: "cancelled", steps: [] }));
  for (const lost of [mainReviewRun(301, { attempt: 2 }), mainReviewRun(301, { conclusion: "cancelled" }, notStarted)]) {
    const { code, reruns, outputs } = await reconcile({ pulls: [], runs: [lost] });
    assert.equal(code, 0);
    assert.deepEqual(reruns, []);
    assert.deepEqual(records(outputs), ["", "", ""]);
  }
});

// One lane wrote its verdict before the run failed: a re-run would review the
// head again, so the run is held, as a pr-verify run is.
test("a main-run review whose verdict write started in any lane is held with its reason", async () => {
  const [first, ...rest] = MAIN_REVIEW_JOBS;
  const wrote = { ...first, steps: first.steps.map((s) => (s.name === WRITE_STEP ? { ...s, conclusion: "success" } : s)) };
  const dir = tempDir("reconcile-summary-");
  try {
    const summary = path.join(dir, "summary.md");
    writeFileSync(summary, "");
    const { code, reruns, outputs } = await reconcile({ pulls: [], runs: [mainReviewRun(301, {}, [wrote, ...rest])], env: { GITHUB_STEP_SUMMARY: summary } });
    assert.equal(code, 0);
    assert.deepEqual(reruns, []);
    assert.deepEqual(records(outputs), ["", "", ""]);
    assert.match(readFileSync(summary, "utf8"), /lane run 301 \(\.github\/workflows\/pr-review-main\.yml\) ended failure after its verdict write started/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a main-run review re-run shares the cap of 3 with pr-verify re-runs, newest first", async () => {
  const { reruns, outputs } = await reconcile({
    pulls: [],
    runs: [
      verifyRun(201, { created: "2026-10-19T19:00:00Z" }),
      mainReviewRun(301, { created: "2026-10-19T18:00:00Z" }),
      verifyRun(202, { created: "2026-10-19T19:10:00Z" }),
      mainReviewRun(302, { created: "2026-10-19T19:20:00Z" }),
    ],
  });
  assert.deepEqual(reruns, [302, 202, 201]);
  assert.deepEqual(records(outputs), [302, 202, 201].map((id) => `reconcile-rerun-${id}-2-${MAIN_TIP}`));
});

test("a non-operational Actions status records nothing", async () => {
  const { outputs, calls } = await reconcile({ pulls: [], runs: [verifyRun(201)], status: statusWith("major_outage") });
  assert.deepEqual(calls, []);
  assert.deepEqual(records(outputs), ["", "", ""]);
});

// A day of pr-verify runs: succeeded ones, with the given runs among them.
const verifyDay = (count, lost) =>
  Array.from({ length: count }, (_, i) => lost.get(i) ?? { ...run(10_000 + i, MAIN_TIP, { path: VERIFY, event: "workflow_run", conclusion: "success" }), head_branch: "main" });

// Lost pr-verify runs, oldest first.
const lostDay = (count) =>
  Array.from({ length: count }, (_, i) => verifyRun(1000 + i, { created: new Date(Date.parse("2026-10-19T00:00:00Z") + i * 60_000).toISOString().replace(/\.\d{3}Z$/, "Z") }));
const lostQueries = (calls) => calls.filter((c) => c.includes("/workflows/pr-verify.yml/runs?") && c.includes("&status=cancelled&"));

test("a lost-run listing of 150 runs over 2 pages is read in full", async () => {
  const { code, reruns, calls } = await reconcile({ pulls: [], runs: lostDay(150) });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [1149, 1148, 1147]);
  assert.equal(lostQueries(calls).length, 2);
});

test("700 succeeded verify runs and 2 lost ones plan the 2 lost runs without hitting the page cap", async () => {
  const { code, reruns, outputs, calls } = await reconcile({
    pulls: [],
    runs: [...verifyDay(700, new Map()), verifyRun(201), verifyRun(202, { created: "2026-10-19T19:00:00Z" })],
  });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [202, 201]);
  assert.deepEqual(records(outputs), [`reconcile-rerun-202-2-${MAIN_TIP}`, `reconcile-rerun-201-2-${MAIN_TIP}`, ""]);
  assert.ok(calls.every((c) => !c.includes("&page=2")));
});

test("with 700 succeeded runs listed, verify re-runs already queued or in progress still take places", async () => {
  const { code, reruns } = await reconcile({
    pulls: [],
    runs: [
      ...verifyDay(700, new Map()),
      verifyRun(209, { status: "in_progress", attempt: 2 }),
      verifyRun(210, { status: "queued", attempt: 2 }),
      verifyRun(201),
      verifyRun(202, { created: "2026-10-19T19:00:00Z" }),
    ],
  });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [202]);
});

test("verify re-runs that start while the listing is read still take places", async () => {
  const queued = [209, 210, 211].map((id) => verifyRun(id, { status: "queued", attempt: 2 }));
  const { code, reruns } = await reconcile({
    pulls: [],
    runs: [...queued, verifyRun(201)],
    github: (g) => async (method, path, body) => {
      if (path.includes("/workflows/pr-verify.yml/runs?") && path.includes("&status=queued&")) {
        for (const r of queued) {
          r.status = "in_progress";
        }
      }
      return g(method, path, body);
    },
  });
  assert.equal(code, 0);
  assert.deepEqual(reruns, []);
});

test("a lane listing past the page cap is a failure, and nothing is called lost", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const { code, reruns } = await reconcile({ pulls: [], runs: lostDay(501) });
  const lines = log.mock.calls.map((c) => String(c.arguments[0]));
  assert.equal(code, 1);
  assert.deepEqual(reruns, []);
  assert.ok(lines.some((l) => l.startsWith("::error title=reconcile::.github/workflows/pr-verify.yml:") && l.includes("has more than 5 pages")));
  assert.ok(!lines.includes("reconcile: nothing lost"));
  assert.ok(lines.includes("reconcile: 1 listings failed; what was lost is unknown"));
});

test("act says why it exits 1 when the plan recorded listing failures", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const { code } = await reconcile({ pulls: [], runs: lostDay(501) });
  const errors = log.mock.calls.map((c) => String(c.arguments[0])).filter((l) => l.startsWith("::error title=reconcile::the plan step"));
  assert.equal(code, 1);
  assert.deepEqual(errors, ["::error title=reconcile::the plan step recorded 1 listing failures and 0 re-runs failed; see the Find lost runs step"]);
});

// A failed CI run whose failures are infra only: its failed jobs are re-run,
// once per head, 15 minutes after attempt 1 ended, while npm and GitHub both
// report indicator none.
const failed = (id, head, { jobs = INFRA_JOBS, attempt = 1, updated = "2026-10-19T19:30:00Z", ...opts } = {}) =>
  run(id, head, { conclusion: "failure", jobs, attempt, updated, ...opts });

test("an infra-only failed run has its failed jobs re-run", async () => {
  const { code, reruns, failedJobReruns } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1))] });
  assert.equal(code, 0);
  assert.deepEqual(failedJobReruns, [101]);
  assert.deepEqual(reruns, []);
});

// A failed CI run with a real failure (a flaky test the diff did not cause, as
// pr-test-platforms run 39867317913's macOS test_tunnel) has its failed jobs
// re-run once, at attempt 1, whatever the status pages show; a second failure
// is fix-ci's.
test("a run with a real failure at attempt 1 has its failed jobs re-run once", async () => {
  const runs = [failed(101, sha(1), { jobs: MIXED_JOBS, updated: "2026-10-19T19:59:00Z" }), failed(102, sha(2), { path: WINDOWS, jobs: MIXED_JOBS })];
  const { code, reruns, failedJobReruns } = await reconcile({ pulls: [pr(1), pr(2)], runs, upstream: { [NPM_STATUS_URL]: NPM_DOWN, [GITHUB_STATUS_URL]: GITHUB_OK } });
  assert.equal(code, 0);
  assert.deepEqual(failedJobReruns, [101, 102]);
  assert.deepEqual(reruns, []);
});

test("a run with a real failure at attempt 2, or older than the lookback, is not re-run", async () => {
  const runs = [failed(101, sha(1), { jobs: MIXED_JOBS, attempt: 2 }), failed(102, sha(2), { jobs: MIXED_JOBS, created: "2026-10-18T19:00:00Z" })];
  const { code, calls } = await reconcile({ pulls: [pr(1), pr(2)], runs });
  assert.equal(code, 0);
  assert.deepEqual(calls.filter((c) => c.startsWith("POST ")), []);
});

test("a failed run at attempt 2 whose failed job's steps did not list is not re-run as infra", async () => {
  const cut = [{ name: "Check out", status: "completed", conclusion: "success" }];
  for (const steps of [[], cut]) {
    const jobs = [{ name: "lint-repo", conclusion: "failure", runner_id: 7, steps }];
    const { code, calls } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs, attempt: 2 })] });
    assert.equal(code, 0);
    assert.deepEqual(calls.filter((c) => c.startsWith("POST ")), []);
  }
});

test("a failed run whose cut job lost its runner is re-run as infra, from the job's annotations", async () => {
  const steps = [
    { name: "Set up job", status: "completed", conclusion: "success" },
    { name: "Run the suites", status: "in_progress", conclusion: null },
  ];
  const lost = { id: 77, name: "lint-repo", status: "completed", conclusion: "failure", runner_id: 7, steps };
  const message = "The hosted runner: GitHub Actions 7 lost communication with the server.";
  // npm down holds an infra re-run back, not a flake re-run, so it tells the two apart.
  const upstream = { [NPM_STATUS_URL]: NPM_DOWN, [GITHUB_STATUS_URL]: GITHUB_OK };
  const { failedJobReruns, calls } = await reconcile({
    pulls: [pr(1)],
    runs: [failed(101, sha(1), { jobs: [{ ...lost, notes: [{ annotation_level: "failure", message }] }], updated: "2026-10-19T19:00:00Z" })],
    upstream,
  });
  assert.deepEqual(failedJobReruns, []);
  assert.ok(calls.includes(`GET /repos/${REPO}/check-runs/77/annotations?per_page=100`));
  const { failedJobReruns: plain } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: [lost], updated: "2026-10-19T19:00:00Z" })], upstream });
  assert.deepEqual(plain, [101]);
});

test("a run where only ci-status failed is not re-run", async () => {
  const jobs = [
    { name: "lint-repo", conclusion: "success", steps: [] },
    { name: "ci-status", conclusion: "failure", steps: [{ name: "Check the pull request contract", conclusion: "failure" }] },
  ];
  const { calls } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs })] });
  assert.deepEqual(calls.filter((c) => c.startsWith("POST ")), []);
});

test("a run with a real failure re-run since the listing is left alone", async () => {
  const { failedJobReruns } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: MIXED_JOBS })], github: rerunSinceListing(101) });
  assert.deepEqual(failedJobReruns, []);
});

test("an infra-only run already at attempt 2 is not re-run again", async () => {
  for (const attempt of [2, 3]) {
    const { calls } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { attempt, updated: "2026-10-19T19:00:00Z" })] });
    assert.deepEqual(calls.filter((c) => c.startsWith("POST ")), [], `attempt ${attempt}`);
  }
});

test("an infra-only run waits 15 minutes after attempt 1", async () => {
  const cases = [
    ["2026-10-19T19:50:00Z", []],
    ["2026-10-19T19:44:00Z", [101]],
  ];
  for (const [updated, expected] of cases) {
    const { failedJobReruns } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { updated })] });
    assert.deepEqual(failedJobReruns, expected, `attempt 1 ended ${updated}`);
  }
});

test("an infra-only run waits while npm or GitHub reports an incident, or either page is unreadable", async () => {
  const upstreams = [
    { [NPM_STATUS_URL]: NPM_DOWN, [GITHUB_STATUS_URL]: GITHUB_OK },
    { [NPM_STATUS_URL]: NPM_OK, [GITHUB_STATUS_URL]: { ...GITHUB_OK, status: { indicator: "minor" } } },
    { [NPM_STATUS_URL]: new Error("fetch failed"), [GITHUB_STATUS_URL]: GITHUB_OK },
    { [NPM_STATUS_URL]: NPM_OK, [GITHUB_STATUS_URL]: {} },
  ];
  for (const upstream of upstreams) {
    const { code, calls } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1))], upstream });
    assert.equal(code, 0);
    assert.deepEqual(calls.filter((c) => c.startsWith("POST ")), []);
  }
});

// The status page's indicator reaches the log through `say`: a newline in it
// must not start a line the runner reads as a workflow command.
test("a status-page indicator holding a newline and a workflow command logs no command line", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const injected = "minor\n::set-output name=plan::x\r::warning::y";
  const upstream = { [NPM_STATUS_URL]: { ...NPM_OK, status: { indicator: injected } }, [GITHUB_STATUS_URL]: GITHUB_OK };
  const { code, calls } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1))], upstream });
  const lines = log.mock.calls.flatMap((c) => String(c.arguments[0]).split(/\r\n|\r|\n/));
  assert.equal(code, 0);
  assert.deepEqual(calls.filter((c) => c.startsWith("POST ")), []);
  assert.deepEqual(lines.filter((l) => l.startsWith("::")), []);
  assert.ok(lines.includes("reconcile: #1: run 101 (.github/workflows/pr-require-checks.yml) failed on infra only; waiting, status.npmjs.org shows minor ::set-output name=plan::x ::warning::y"));
});

test("an upstream incident does not hold back a lost run's re-run", async () => {
  const upstream = { [NPM_STATUS_URL]: NPM_DOWN, [GITHUB_STATUS_URL]: GITHUB_OK };
  const { reruns, failedJobReruns } = await reconcile({ pulls: [pr(1), pr(2)], runs: [run(101, sha(1)), failed(102, sha(2))], upstream });
  assert.deepEqual(reruns, [101]);
  assert.deepEqual(failedJobReruns, []);
});

test("an infra-only run re-run since the listing is left alone", async () => {
  const { failedJobReruns } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1))], github: rerunSinceListing(101) });
  assert.deepEqual(failedJobReruns, []);
});

test("a failed contract-only run on top of an infra-only run does not hide it", async () => {
  // Head 60eae294 on 2026-10-22: run 39710654665 hit its time limits and
  // contract-only run 39710676298 failed 14 seconds after it was created.
  const contract = failed(102, sha(1), { jobs: fixture("jobs-39716948399.json").jobs, created: "2026-10-19T18:59:57Z" });
  const { failedJobReruns } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1)), contract] });
  assert.deepEqual(failedJobReruns, [101]);
});

test("a re-run still going under a newer failed contract-only run takes a place under the cap", async () => {
  // PR 1's attempt-2 run is in progress; a contract-only run failed on top of it.
  const contract = failed(102, sha(1), { jobs: fixture("jobs-39716948399.json").jobs, created: "2026-10-19T18:59:57Z" });
  const runs = [run(101, sha(1), { status: "in_progress", attempt: 2 }), contract, run(201, sha(2)), run(202, sha(3)), run(203, sha(4))];
  const { reruns, failedJobReruns } = await reconcile({ pulls: [pr(1), pr(2), pr(3), pr(4)], runs });
  assert.deepEqual(reruns, [201, 202]);
  assert.deepEqual(failedJobReruns, []);
});

// An issue's floor-label run whose first attempt failed (a rate limit left
// the issue unlabeled) has its failed jobs re-run once.
const INTAKE = ".github/workflows/intake-triage.yml";
// An intake-triage run's jobs as the API names them: a job that calls a
// reusable workflow is listed as `<caller job> / <called job>`.
const intakeJob = (name, conclusion) => ({ id: name.length * 1000 + 7, name, status: "completed", conclusion, steps: [] });
const LABEL_FAILED = [
  intakeJob("kill-switch", "success"),
  intakeJob("born-triaged", "success"),
  intakeJob("intake-triage / triage", "success"),
  intakeJob("intake-label-needs-triage / label", "failure"),
];
const intakeRun = (id, opts = {}) => run(id, MAIN_TIP, { path: INTAKE, event: "issues", conclusion: "failure", jobs: LABEL_FAILED, ...opts });

test("a failed first attempt of an intake run whose only failed job is the floor label has its failed jobs re-run once", async () => {
  const { code, failedJobReruns, reruns } = await reconcile({ pulls: [], runs: [intakeRun(301)] });
  assert.equal(code, 0);
  assert.deepEqual(failedJobReruns, [301]);
  assert.deepEqual(reruns, []);
});

// rerun-failed-jobs re-runs every failed job, so a run where any other job
// failed (the model triage, a gate) would start that job again as
// github-actions[bot]: only the floor label is re-run here.
test("an intake run where any job but the floor label failed, or none did, is left alone", async () => {
  const runs = [
    intakeRun(301, { jobs: [intakeJob("kill-switch", "success"), intakeJob("intake-triage / triage", "failure"), intakeJob("intake-label-needs-triage / label", "success")] }),
    intakeRun(302, { jobs: [intakeJob("intake-triage / triage", "failure"), intakeJob("intake-label-needs-triage / label", "failure")] }),
    intakeRun(303, { jobs: [intakeJob("born-triaged", "cancelled"), intakeJob("intake-label-needs-triage / label", "failure")] }),
    intakeRun(304, { jobs: [intakeJob("apply-verdict", "timed_out"), intakeJob("intake-label-needs-triage / label", "failure")] }),
    intakeRun(305, { jobs: [] }),
    intakeRun(306, { jobs: [intakeJob("intake-label-needs-triage-extra / label", "failure")] }),
  ];
  const { failedJobReruns, calls } = await reconcile({ pulls: [], runs });
  assert.deepEqual(failedJobReruns, []);
  assert.equal(calls.filter((c) => c.startsWith("POST ")).length, 0);
});

// A run left alone stays a failed first attempt for the whole lookback, so
// its jobs are listed only while it is recent, not on every half-hourly pass.
test("an intake run that ended over 2 hours ago gets no job listing and no re-run", async () => {
  const { failedJobReruns, calls } = await reconcile({ pulls: [], runs: [intakeRun(301, { created: "2026-10-19T17:00:00Z", updated: "2026-10-19T17:59:00Z" })] });
  assert.deepEqual(failedJobReruns, []);
  assert.equal(calls.filter((c) => c.includes("/actions/runs/301/")).length, 0);
});

test("an intake run whose job listing cannot be read is left alone and the failure reported", async () => {
  const { code, failedJobReruns } = await reconcile({
    pulls: [],
    runs: [intakeRun(301), intakeRun(302, { created: "2026-10-19T19:00:00Z" })],
    fail: { [`GET /repos/${REPO}/actions/runs/301/attempts/1/jobs?per_page=100`]: new GitHubError(500, "boom") },
  });
  assert.notEqual(code, 0);
  assert.deepEqual(failedJobReruns, [302]);
});

test("floor-label runs at attempt 2, older than the lookback, or from another event are left alone", async () => {
  const runs = [
    intakeRun(301, { attempt: 2 }),
    intakeRun(302, { created: "2026-10-18T19:00:00Z" }),
    intakeRun(303, { event: "workflow_dispatch" }),
    intakeRun(304, { conclusion: "success" }),
  ];
  const { failedJobReruns, calls } = await reconcile({ pulls: [], runs });
  assert.deepEqual(failedJobReruns, []);
  assert.equal(calls.filter((c) => c.startsWith("POST ")).length, 0);
});

test("a floor-label run re-run since the listing is left alone", async () => {
  const { failedJobReruns } = await reconcile({ pulls: [], runs: [intakeRun(301)], github: rerunSinceListing(301) });
  assert.deepEqual(failedJobReruns, []);
});

// A pr-verify verdict whose pr-feedback-dispatch run found the kill switch on:
// post-verify-notes fails at its kill-switch step, posting nothing, and the
// first pass after the switch lifts re-runs that job, which applies the verdict.
const FEEDBACK = ".github/workflows/pr-feedback-dispatch.yml";
const verdictJob = (failedStep = VERDICT_STOP_STEP, { name = "post-verify-notes", conclusion = "failure" } = {}) => ({
  id: 4007,
  name,
  status: "completed",
  conclusion,
  steps: [
    { name: "Set up job", status: "completed", conclusion: "success" },
    { name: "Check the kill switch", status: "completed", conclusion: "success" },
    { name: VERDICT_STOP_STEP, status: "completed", conclusion: failedStep === VERDICT_STOP_STEP ? "failure" : "skipped" },
    { name: "Download the verdict", status: "completed", conclusion: failedStep === "Download the verdict" ? "failure" : "skipped" },
    { name: "Complete job", status: "completed", conclusion: "success" },
  ],
});
const SWITCHED = [verdictJob(), { id: 4008, name: "dispatch", status: "completed", conclusion: "skipped", steps: [] }];
const verdictRun = (id, opts = {}) => run(id, MAIN_TIP, { path: FEEDBACK, event: "workflow_run", conclusion: "failure", jobs: SWITCHED, ...opts });

test("a verdict the kill switch kept from its PR is applied once the switch lifts", async () => {
  const { code, failedJobReruns, reruns } = await reconcile({ pulls: [], runs: [verdictRun(401)] });
  assert.equal(code, 0);
  assert.deepEqual(failedJobReruns, [401]);
  assert.deepEqual(reruns, []);
});

test("while the kill switch is on, no stopped verdict is read or re-run", async () => {
  const { code, calls } = await reconcile({ pulls: [], runs: [verdictRun(401)], env: { KILL_SWITCH: "" } });
  assert.equal(code, 0);
  assert.deepEqual(calls, []);
});

test("a verdict run that failed anywhere but the kill-switch step, or at attempt 2, is left alone", async () => {
  const runs = [
    verdictRun(401, { jobs: [verdictJob("Download the verdict")] }),
    verdictRun(402, { jobs: [verdictJob(), { id: 4009, name: "dispatch", status: "completed", conclusion: "failure", steps: [] }] }),
    verdictRun(403, { jobs: [verdictJob(VERDICT_STOP_STEP, { name: "rerun-ci-status" })] }),
    verdictRun(404, { attempt: 2 }),
    verdictRun(405, { created: "2026-10-18T19:00:00Z" }),
    verdictRun(406, { jobs: [] }),
  ];
  const { failedJobReruns, calls } = await reconcile({ pulls: [], runs });
  assert.deepEqual(failedJobReruns, []);
  assert.equal(calls.filter((c) => c.startsWith("POST ")).length, 0);
});

test("post-verify-notes still fails at the kill-switch step the reconciler matches, before any read", () => {
  const job = verifyLegs("pr-feedback-dispatch.yml").find(({ name }) => name === "post-verify-notes");
  const steps = legSteps(job?.body ?? "");
  const stop = steps.findIndex((s) => s.startsWith(`      - name: ${VERDICT_STOP_STEP}\n`));
  assert.ok(stop > 0, "the kill-switch stop step is in the job");
  assert.match(steps[stop - 1], /^ {6}- name: Check the kill switch\n/);
  assert.match(steps[stop], /if: steps\.kill\.outputs\.proceed != 'true' && github\.event\.workflow_run\.conclusion == 'success'\n/);
  assert.match(steps[stop], /\n {10}exit 1\n/);
  assert.match(steps[stop + 1], /^ {6}- name: Download the verdict\n/);
});

test("a stopped verdict re-run since the listing is left alone", async () => {
  const { failedJobReruns } = await reconcile({ pulls: [], runs: [verdictRun(401)], github: rerunSinceListing(401) });
  assert.deepEqual(failedJobReruns, []);
});

test("a floor-label re-run takes no place under the cap of 3", async () => {
  const runs = [run(201, sha(1)), run(202, sha(2)), run(203, sha(3)), intakeRun(301)];
  const { reruns, failedJobReruns } = await reconcile({ pulls: [pr(1), pr(2), pr(3)], runs });
  assert.deepEqual(reruns.sort(), [201, 202, 203]);
  assert.deepEqual(failedJobReruns, [301]);
});

// pr-verify runs after pr-require-checks and trusts that run's attempt 2 by
// github-actions[bot] only through a reconcile-rerun-<run id>-2-<head sha>
// record, so each re-run that makes that attempt is recorded before it is
// made. Its head is the PR's head, the run's own head_sha.
test("each re-run that makes attempt 2 of pr-require-checks is recorded before it is made", async () => {
  const runs = [run(101, sha(1)), failed(102, sha(2), { jobs: MIXED_JOBS }), failed(103, sha(3))];
  const { code, outputs, reruns, failedJobReruns, planWrites } = await reconcile({ pulls: [pr(1), pr(2), pr(3)], runs });
  assert.equal(code, 0);
  assert.equal(planWrites, 0);
  assert.deepEqual(records(outputs), [`reconcile-rerun-101-2-${sha(1)}`, `reconcile-rerun-103-2-${sha(3)}`, `reconcile-rerun-102-2-${sha(2)}`]);
  assert.deepEqual(reruns, [101]);
  assert.deepEqual(failedJobReruns, [103, 102]);
});

test("a pr-test-platforms re-run is not recorded", async () => {
  const { code, outputs, reruns } = await reconcile({ pulls: [pr(1)], runs: [run(101, sha(1), { path: WINDOWS })] });
  assert.equal(code, 0);
  assert.deepEqual(records(outputs), ["", "", ""]);
  assert.deepEqual(reruns, [101]);
});

test("a CI set with no stopped review carries one record, so the cap of 3 bounds the records at 3", async () => {
  const runs = [1, 2, 3, 4].flatMap((n) => [run(100 + n, sha(n)), run(200 + n, sha(n), { path: WINDOWS })]);
  const { code, outputs, reruns } = await reconcile({ pulls: [pr(1), pr(2), pr(3), pr(4)], runs: [...runs, verifyRun(301)] });
  assert.equal(code, 0);
  assert.deepEqual(records(outputs), [1, 2, 3].map((n) => `reconcile-rerun-${100 + n}-2-${sha(n)}`));
  assert.deepEqual(reruns.sort(), [101, 102, 103, 201, 202, 203]);
});

// A head whose pr-verify pass the spec changed under after the pass: resolve-pr
// (pr-verify's own resolver) answers `spec-changed`, and the head's passed
// checks run is re-run once, recorded, so pr-verify judges the head again.
// Shapes follow resolve-pr.test.mjs: GET /commits/{sha}/pulls,
// /actions/artifacts?name=, and the closingIssuesReferences GraphQL field.
const LANE = "melodic-automation-lanes[bot]";
const PASS_RUN = 701;
const PASS_STARTED = "2026-10-19T19:30:00Z";
// The first 16 hex digits of `printf %s fix/1 | sha256sum`, pr(1)'s head ref.
const FIX_1_DIGEST = "fe65f143bd3d5845";
// The pre-filter's batched answer holds the issues' comment pages only when its
// query asks for them, as GitHub answers only the fields a query names.
const COMMENT_PAGE = "comments(first: 100)";
const prefilterIssue = (query, { comments = [], ...issue }) => (query.includes(COMMENT_PAGE) ? { ...issue, comments: { totalCount: comments.length, nodes: comments } } : issue);

// `updated` is the issue's updatedAt: the edit time by default, else a time
// before the pass. PR `number` is the head under check.
function specChanged({ edited, updated = edited ?? "2026-10-19T00:00:00Z", attempt = 1, pass = true, digest = false, number = 1 } = {}) {
  const head = sha(number);
  const checks = { ...run(601, head, { conclusion: "success", attempt }), repository: { full_name: REPO } };
  const judged = { ...verifyRun(PASS_RUN, { conclusion: "success" }), repository: { full_name: REPO }, run_started_at: PASS_STARTED, jobs: [] };
  const name = `pr-verify-${number}-${head}-pass${digest ? `-${FIX_1_DIGEST}` : ""}`;
  const issue = {
    number: 7,
    repository: { nameWithOwner: REPO },
    body: "the spec",
    lastEditedAt: edited,
    author: { __typename: "User", login: "maintainer", databaseId: 100 },
    editor: edited ? { __typename: "User", login: "maintainer", databaseId: 100 } : null,
    comments: { totalCount: 0, nodes: [] },
  };
  const pull = { ...pr(number), user: { id: 9, login: LANE, type: "Bot" }, base: { ref: "main", sha: "b".repeat(40) } };
  // The pull requests whose spec was read.
  const specReads = [];
  const prefilterReads = [];
  // The reconciler's own pass reads (passStarts), which page nothing.
  const passReads = [];
  const wrap = (github) => async (method, apiPath, body) => {
    if (apiPath === `/repos/${REPO}/commits/${head}/pulls?per_page=100&page=1`) return [pull];
    const named = /\/actions\/artifacts\?name=([^&]+)&per_page=100(&page=1)?$/.exec(apiPath);
    if (named && !named[2]) passReads.push(apiPath);
    if (named) return { artifacts: pass && decodeURIComponent(named[1]) === name ? [{ name, expired: false, workflow_run: { id: PASS_RUN } }] : [] };
    if (apiPath === `/repos/${REPO}/compare/${MAIN_TIP}...main`) return { status: "ahead" };
    if (apiPath === "/graphql" && !body.variables) {
      // The pre-filter's batched read: one alias per candidate.
      prefilterReads.push(body.query);
      const node = prefilterIssue(body.query, { updatedAt: updated, lastEditedAt: edited ?? null, repository: { nameWithOwner: REPO } });
      return { data: { repository: { p0: { body: "", lastEditedAt: null, closingIssuesReferences: { totalCount: 1, nodes: [node] } } } } };
    }
    if (apiPath === "/graphql") {
      specReads.push(body.variables.number);
      return { data: { repository: { pullRequest: { body: "", createdAt: "2026-10-19T00:00:00Z", lastEditedAt: null, editor: null, closingIssuesReferences: { totalCount: 1, nodes: [issue] } } } } };
    }
    return github(method, apiPath, body);
  };
  return { setup: { pulls: [pr(number)], runs: [checks, judged], github: wrap }, specReads, prefilterReads, passReads };
}

async function withTrustedList(fn) {
  const dir = tempDir("reconcile-actors-");
  try {
    const actors = path.join(dir, "trusted-actors.json");
    writeFileSync(actors, JSON.stringify({ version: 1, actors: [{ id: 100, login: "maintainer", kind: "human" }] }));
    return await fn({ TRUSTED_ACTORS_PATH: actors, LANE_IDENTITY: LANE });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("a pass the spec changed under re-runs the head's passed checks once, with a record", async () => {
  await withTrustedList(async (env) => {
    const { code, outputs, reruns } = await reconcile({ ...specChanged({ edited: "2026-10-19T19:45:00Z" }).setup, env });
    assert.equal(code, 0);
    assert.deepEqual(reruns, [601]);
    assert.equal(outputs["record-1"], `reconcile-rerun-601-2-${sha(1)}`);
    // write-verdict.mjs writes no head-ref digest, so a pass named with one is
    // not looked up, here or by resolve-pr, and re-runs nothing.
    const digested = specChanged({ edited: "2026-10-19T19:45:00Z", digest: true });
    assert.deepEqual((await reconcile({ ...digested.setup, env })).reruns, []);
    assert.ok(digested.passReads.every((apiPath) => !apiPath.includes(FIX_1_DIGEST)));
  });
});

test("a pass judged after the spec's last change, a second attempt, or no pass re-runs nothing", async () => {
  await withTrustedList(async (env) => {
    // The checks run was created at 18:59:43 and the pass started at 19:30.
    // [options, full reads, pre-filter reads, pass artifact reads: pass and
    // pass-notes]
    const cases = {
      // Touched after the checks run but not after the pass: the pass is read,
      // and the second pre-filter skips the full read.
      "edited before the pass": [{ edited: "2026-10-19T19:15:00Z" }, [], 2, 2],
      // Untouched since the checks run: the first pre-filter skips the pass read.
      "never edited": [{ edited: null }, [], 1, 0],
      // An issue updatedAt after the pass with no spec time after it (as a
      // label change might leave it): the full read runs, and specChanged
      // still says no.
      "updated, but no spec change": [{ edited: "2026-10-19T19:15:00Z", updated: "2026-10-19T19:45:00Z" }, [1], 2, 2],
      "already at attempt 2": [{ edited: "2026-10-19T19:45:00Z", attempt: 2 }, [], 0, 0],
      "no pass at the head": [{ edited: "2026-10-19T19:45:00Z", pass: false }, [], 1, 2],
    };
    for (const [label, [options, read, prefiltered, artifacts]] of Object.entries(cases)) {
      const { setup, specReads, prefilterReads, passReads } = specChanged(options);
      const { code, reruns } = await reconcile({ ...setup, env });
      assert.equal(code, 0, label);
      assert.deepEqual(reruns, [], label);
      assert.deepEqual(specReads, read, label);
      assert.equal(prefilterReads.length, prefiltered, label);
      assert.equal(passReads.length, artifacts, label);
    }
  });
});

test("a spec edited after a pass is caught when a label or body edit started a newer checks run after the edit", async () => {
  await withTrustedList(async (env) => {
    // Pass at 19:30 from checks run 601, spec edited at 19:45, then a newer
    // passed checks run 602 at 19:50 that pr-verify skips as already judged.
    const { setup, specReads } = specChanged({ edited: "2026-10-19T19:45:00Z" });
    const newer = { ...run(602, sha(1), { conclusion: "success", created: "2026-10-19T19:50:00Z" }), repository: { full_name: REPO } };
    const { code, reruns } = await reconcile({ ...setup, runs: [...setup.runs, newer], env });
    assert.equal(code, 0);
    assert.deepEqual(specReads, [1]);
    assert.deepEqual(reruns, [602]);
  });
});

test("passed heads whose spec nobody touched since their checks ran cost one GraphQL query and no pass reads", async () => {
  await withTrustedList(async (env) => {
    const numbers = [1, 2, 3, 4, 5];
    const untouched = { updatedAt: "2026-10-19T00:00:00Z", lastEditedAt: null, repository: { nameWithOwner: REPO } };
    const reads = [];
    const wrap = (github) => async (method, apiPath, body) => {
      reads.push(`${method} ${apiPath}`);
      if (apiPath.includes("/actions/artifacts?")) return { artifacts: [] };
      if (apiPath === "/graphql") {
        const node = prefilterIssue(body.query, untouched);
        return { data: { repository: Object.fromEntries(numbers.map((_, i) => [`p${i}`, { body: "", lastEditedAt: null, closingIssuesReferences: { totalCount: 1, nodes: [node] } }])) } };
      }
      return github(method, apiPath, body);
    };
    const runs = numbers.map((n) => run(600 + n, sha(n), { conclusion: "success" }));
    const { code, reruns } = await reconcile({ pulls: numbers.map((n) => pr(n)), runs, github: wrap, env });
    assert.equal(code, 0);
    assert.deepEqual(reruns, []);
    const count = (part) => reads.filter((r) => r.includes(part)).length;
    assert.equal(count("/actions/artifacts?"), 0);
    assert.equal(count("POST /graphql"), 1);
    // The pulls page, one run listing per head, nine status listings for each
    // of pr-verify and pr-review-main, one intake listing, one stopped-verdict
    // listing and the one pre-filter query.
    assert.equal(reads.length, 1 + numbers.length + 2 * 9 + 1 + 1 + 1);
  });
});

test("the pre-filter reads every candidate in one GraphQL query and keeps only a spec that moved", async () => {
  const PASS = "2026-10-19T19:30:00Z";
  const before = "2026-10-19T19:00:00Z";
  const after = "2026-10-19T20:00:00Z";
  const answers = (query) => {
    const closes = (updatedAt, comments) => ({
      body: "",
      lastEditedAt: null,
      closingIssuesReferences: { totalCount: 1, nodes: [prefilterIssue(query, { updatedAt, lastEditedAt: null, comments, repository: { nameWithOwner: REPO } })] },
    });
    return {
      p0: closes(before),
      p1: closes(after),
      p2: { body: "Refs: #9", lastEditedAt: null, closingIssuesReferences: { totalCount: 0, nodes: [] } },
      p3: { body: "", lastEditedAt: after, closingIssuesReferences: { totalCount: 0, nodes: [] } },
      p4: closes(before),
      p5: closes(before, [{ updatedAt: before }, { updatedAt: after }]),
      p6: { body: "Refs: #8", lastEditedAt: null, closingIssuesReferences: { totalCount: 0, nodes: [] } },
    };
  };
  const queries = [];
  const call = async (method, apiPath, body) => {
    assert.equal(`${method} ${apiPath}`, "POST /graphql");
    queries.push(body.query);
    if (body.query.includes("r0: issue(number: 9)")) {
      return { data: { repository: { r0: prefilterIssue(body.query, { updatedAt: after, lastEditedAt: null }), r1: prefilterIssue(body.query, { updatedAt: before, lastEditedAt: null, comments: [{ updatedAt: after }] }) } } };
    }
    return { data: { repository: answers(body.query) } };
  };
  const candidates = [10, 11, 12, 13, 14, 15, 16].map((number, i) => ({ pull: { number }, starts: i === 4 ? [null] : [PASS] }));
  const kept = (await prefilterSpec(call, REPO, candidates)).map((c) => c.pull.number);
  // 10: issue unchanged. 11: issue updated after the pass. 12: its Refs issue
  // updated after. 13: its own body edited after. 14: a pass start unreadable.
  // 15: issue updatedAt before the pass, a comment edited after. 16: its Refs
  // issue the same.
  assert.deepEqual(kept, [11, 12, 13, 14, 15, 16]);
  assert.equal(queries.length, 2, "one batched query, plus one for the Refs issues");
  assert.deepEqual(await prefilterSpec(call, REPO, []), []);
});

test("the pre-filter keeps a candidate whose issue has more comments than the page read", async () => {
  const before = "2026-10-19T19:00:00Z";
  // GitHub's totalCount counts every comment; the page holds the first 100.
  const page = Array.from({ length: 100 }, () => ({ updatedAt: before }));
  const call = async (_method, _apiPath, body) => {
    const issue = prefilterIssue(body.query, { updatedAt: before, lastEditedAt: null, comments: page, repository: { nameWithOwner: REPO } });
    if (issue.comments) issue.comments = { ...issue.comments, totalCount: 101 };
    return { data: { repository: { p0: { body: "", lastEditedAt: null, closingIssuesReferences: { totalCount: 1, nodes: [issue] } } } } };
  };
  const kept = await prefilterSpec(call, REPO, [{ pull: { number: 10 }, starts: ["2026-10-19T19:30:00Z"] }]);
  assert.deepEqual(kept.map((c) => c.pull.number), [10]);
});

test("an auto-merge PR's spec re-run wins the last place under the cap over another PR's CI set", async () => {
  await withTrustedList(async (env) => {
    // PRs 3 and 4 have re-runs in flight, so one place is left. PR 2 has a
    // lost CI run and a lower number; PR 5 waits for auto-merge and its pass
    // the spec changed under.
    const { setup } = specChanged({ edited: "2026-10-19T19:45:00Z", number: 5 });
    const pulls = [pr(2), pr(3), pr(4), pr(5, { autoMerge: { merge_method: "squash" } })];
    const runs = [...setup.runs, run(102, sha(2)), run(103, sha(3), { status: "in_progress", attempt: 2 }), run(104, sha(4), { status: "in_progress", attempt: 2 })];
    const { code, reruns } = await reconcile({ ...setup, pulls, runs, env });
    assert.equal(code, 0);
    assert.deepEqual(reruns, [601]);
  });
});

test("a spec read that fails re-runs nothing and leaves the run green", async (t) => {
  t.mock.method(console, "log", () => {});
  await withTrustedList(async (env) => {
    const { setup } = specChanged({ edited: "2026-10-19T19:45:00Z" });
    const inner = setup.github;
    const failing = (github) => async (method, apiPath, body) => {
      if (apiPath === "/graphql") throw new Error("GraphQL failed with status 502");
      return inner(github)(method, apiPath, body);
    };
    const { code, reruns } = await reconcile({ ...setup, github: failing, env });
    assert.equal(code, 0);
    assert.deepEqual(reruns, []);
  });
});

test("without the trusted list no spec is checked", async () => {
  const { code, reruns } = await reconcile(specChanged({ edited: "2026-10-19T19:45:00Z" }).setup);
  assert.equal(code, 0);
  assert.deepEqual(reruns, []);
});

test("act re-runs no CI run whose plan names another record", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls } = fakeGitHub({ pulls: [pr(1)], runs: [run(101, sha(1))] });
  const dir = tempDir("reconcile-");
  try {
    const PLAN_PATH = path.join(dir, "plan.json");
    const item = { kind: "ci", pr: 1, id: 101, path: CHECKS, conclusion: "cancelled", head: sha(1), record: `reconcile-rerun-101-2-${sha(2)}` };
    writeFileSync(PLAN_PATH, JSON.stringify({ items: [item], failed: 0 }));
    const code = await main({ env: { GITHUB_REPOSITORY: REPO, MODE: "act", PLAN_PATH }, github, sleep: async () => {}, now: NOW });
    assert.equal(code, 1);
    assert.deepEqual(calls.filter((c) => c.startsWith("POST ")), []);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// A lanes App PR whose newest pr-require-checks run failed only in ci-status,
// whose lanes-hold step noted the kill switch: once the switch is off, that
// ci-status is re-run, recorded as attempt 2, whatever the run's age. The
// annotation text is the one pr-require-checks.yml writes (pinned below).
const LANE_ID = 9;
const lanePr = (number, opts) => ({ ...pr(number, opts), user: { id: LANE_ID, login: LANE, type: "Bot" } });
const switchJobs = ({ message = `#1: ${KILL_SWITCH_NOTE} (CLAUDE_LANES_DISABLED or CLAUDE_LANES_REPO_DISABLED is not 'false')`, lane = "success" } = {}) => [
  { id: 501, name: "lint-repo", status: "completed", conclusion: lane, steps: [] },
  { id: 502, name: "ci-status", status: "completed", conclusion: "failure", steps: [], notes: [{ annotation_level: "failure", message }] },
];
async function withLaneList(fn) {
  const dir = tempDir("reconcile-actors-");
  try {
    const actors = path.join(dir, "trusted-actors.json");
    writeFileSync(
      actors,
      JSON.stringify({
        version: 1,
        actors: [
          { id: 100, login: "maintainer", kind: "human" },
          { id: LANE_ID, login: LANE, kind: "bot" },
        ],
      }),
    );
    return await fn({ TRUSTED_ACTORS_PATH: actors, LANE_IDENTITY: LANE });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("a lanes App PR whose ci-status the kill switch failed has it re-run once the switch is off, recorded, past the lookback", async () => {
  await withLaneList(async (env) => {
    for (const created of ["2026-10-19T19:00:00Z", "2026-10-12T19:00:00Z"]) {
      const runs = [failed(101, sha(1), { jobs: switchJobs(), created })];
      const { code, outputs, reruns, failedJobReruns } = await reconcile({ pulls: [lanePr(1)], runs, env });
      assert.equal(code, 0);
      assert.deepEqual(failedJobReruns, [101]);
      assert.deepEqual(reruns, []);
      assert.deepEqual(records(outputs), [`reconcile-rerun-101-2-${sha(1)}`, "", ""]);
    }
  });
});

test("while the kill switch is on, no lanes App PR is read", async () => {
  await withLaneList(async (env) => {
    const { code, calls } = await reconcile({ pulls: [lanePr(1)], runs: [failed(101, sha(1), { jobs: switchJobs() })], env: { ...env, KILL_SWITCH: "" } });
    assert.equal(code, 0);
    assert.deepEqual(calls, []);
  });
});

test("a ci-status failure with no kill-switch note, another author's PR, a second attempt or no lane identity is not re-run", async () => {
  await withLaneList(async (env) => {
    const cases = [
      { pulls: [lanePr(1)], runs: [failed(101, sha(1), { jobs: switchJobs({ message: "#1: the PR body holds it" }) })], env },
      { pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: switchJobs() })], env },
      { pulls: [{ ...lanePr(1), user: { id: LANE_ID, login: LANE, type: "User" } }], runs: [failed(101, sha(1), { jobs: switchJobs() })], env },
      { pulls: [lanePr(1)], runs: [failed(101, sha(1), { jobs: switchJobs(), attempt: 2 })], env },
      { pulls: [lanePr(1)], runs: [failed(101, sha(1), { jobs: switchJobs() })], env: { TRUSTED_ACTORS_PATH: env.TRUSTED_ACTORS_PATH } },
      { pulls: [lanePr(1)], runs: [failed(101, sha(1), { jobs: switchJobs() })] },
    ];
    for (const setup of cases) {
      const { code, calls } = await reconcile(setup);
      assert.equal(code, 0);
      assert.deepEqual(calls.filter((c) => c.startsWith("POST ")), []);
    }
  });
});

test("a kill-switch stop on a newer failed contract-only run is re-run, not hidden by the tested run below it", async () => {
  await withLaneList(async (env) => {
    const contract = [
      { id: 511, name: "lint-repo", status: "completed", conclusion: "skipped", steps: [] },
      { ...switchJobs()[1], id: 512 },
    ];
    const runs = [run(100, sha(1), { conclusion: "success", created: "2026-10-19T18:00:00Z" }), failed(101, sha(1), { jobs: contract })];
    const { failedJobReruns } = await reconcile({ pulls: [lanePr(1)], runs, env });
    assert.deepEqual(failedJobReruns, [101]);
  });
});

test("a kill-switch stop with a lane that also failed takes the one flake re-run, not a second", async () => {
  await withLaneList(async (env) => {
    const jobs = [...MIXED_JOBS, switchJobs()[1]];
    const { failedJobReruns, outputs } = await reconcile({ pulls: [lanePr(1)], runs: [failed(101, sha(1), { jobs, updated: "2026-10-19T19:59:00Z" })], env });
    assert.deepEqual(failedJobReruns, [101]);
    assert.deepEqual(records(outputs), [`reconcile-rerun-101-2-${sha(1)}`, "", ""]);
  });
});

test("a kill-switch re-run shares the cap of 3, and one re-run since the listing is left alone", async () => {
  await withLaneList(async (env) => {
    const runs = [1, 2, 3, 4].map((n) => failed(100 + n, sha(n), { jobs: switchJobs().map((j) => ({ ...j, id: j.id * 10 + n })) }));
    const capped = await reconcile({ pulls: [1, 2, 3, 4].map((n) => lanePr(n)), runs, env });
    assert.deepEqual(capped.failedJobReruns, [101, 102, 103]);
    const moved = await reconcile({ pulls: [lanePr(1)], runs: [failed(101, sha(1), { jobs: switchJobs() })], env, github: rerunSinceListing(101) });
    assert.deepEqual(moved.failedJobReruns, []);
  });
});

test("ci-status's lanes-hold step still fails a lanes App PR with the kill-switch note the reconciler matches", () => {
  const workflow = readFileSync(new URL("../../workflows/pr-require-checks.yml", import.meta.url), "utf8");
  const step = /- name: Fail a lanes App pull request its body or a member holds\n(?:(?:[ ]{8,}.*)?\n)+/.exec(workflow)?.[0] ?? "";
  assert.match(step, /LANES_DISABLED: \$\{\{ vars\.CLAUDE_LANES_DISABLED \}\}/);
  // The step prints merge-holds.mjs switchHold's reason as its error.
  assert.match(step, /const \{ switchHold \} = await import\(/);
  const fail = step.split("\n").findIndex((line) => line.includes('echo "::error::${reason//%/%25}"'));
  assert.ok(fail > 0, "the kill-switch error line is in the step");
  assert.match(step.split("\n")[fail + 1], /^[ ]+exit 1$/);
  const lanes = { number: 1, user: { type: "Bot", id: 7 } };
  assert.ok(switchHold(lanes, { appId: "7", disabled: "true", repoDisabled: "false" }).startsWith(`#1: ${KILL_SWITCH_NOTE} (`));
});

// Any PR whose newest pr-require-checks run failed only in ci-status, on its
// first attempt, on the pr-unblock step's notes: once no pr-unblock/* status
// by github-actions[bot] fails the head (the lane's clear posted success over
// its stop), that ci-status is re-run, recorded as attempt 2. The notes are
// the ones ci-status wrote on #10828's head (check run 123256890668), and the
// step's line is pinned below.
const STOP_LINE = (context = "pr-unblock/address-feedback", head = sha(1)) =>
  `'${context}' is failure on ${head}: Lane stopped: feedback-untaken-threads; checked again on a new head. The lane that stopped clears it by running again on this head, or a new head carries none.`;
const stopJobs = ({ notes = [STOP_LINE()] } = {}) => [
  { id: 501, name: "lint-repo", status: "completed", conclusion: "success", steps: [] },
  {
    id: 502,
    name: "ci-status",
    status: "completed",
    conclusion: "failure",
    steps: [],
    notes: [
      { annotation_level: "notice", message: "github-token=17 not-modified=0 graphql=0" },
      { annotation_level: "failure", message: "Process completed with exit code 1." },
      ...notes.map((message) => ({ annotation_level: "failure", message })),
    ],
  },
];
const BOT = { login: "github-actions[bot]" };
const unblockStatus = (state, { context = "pr-unblock/address-feedback", creator = BOT } = {}) => ({ context, state, creator });
// Newest first, as GitHub lists them: the clear over the stop.
const cleared = (head = sha(1)) => ({ [head]: [unblockStatus("success"), unblockStatus("failure")] });

test("a ci-status a pr-unblock stop failed is re-run once after the lane clears the stop, recorded, past the lookback", async () => {
  for (const created of ["2026-10-19T19:00:00Z", "2026-10-12T19:00:00Z"]) {
    const { code, outputs, reruns, failedJobReruns, calls } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: stopJobs(), created })], statuses: cleared() });
    assert.equal(code, 0);
    assert.deepEqual(failedJobReruns, [101]);
    assert.deepEqual(reruns, []);
    assert.deepEqual(records(outputs), [`reconcile-rerun-101-2-${sha(1)}`, "", ""]);
    assert.ok(calls.includes(`GET /repos/${REPO}/commits/${sha(1)}/statuses?per_page=100&page=1`));
  }
  const again = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: stopJobs(), attempt: 2 })], statuses: cleared() });
  assert.equal(again.code, 0);
  assert.deepEqual(again.failedJobReruns, []);
});

test("a ci-status re-run waits for every pr-unblock stop on the head to clear, and reads only github-actions[bot]'s statuses", async () => {
  const notes = [STOP_LINE(), STOP_LINE("pr-unblock/fix-ci")];
  const statuses = { [sha(1)]: [unblockStatus("success"), unblockStatus("error", { context: "pr-unblock/fix-ci" }), unblockStatus("failure")] };
  const standing = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: stopJobs({ notes }) })], statuses });
  assert.deepEqual(standing.failedJobReruns, []);
  const other = { [sha(1)]: [unblockStatus("success", { creator: { login: "someone" } }), unblockStatus("failure")] };
  const forged = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: stopJobs() })], statuses: other });
  assert.deepEqual(forged.failedJobReruns, []);
});

test("a ci-status with no pr-unblock stop note, or another failure beside it, is not re-run and its statuses are not read", async () => {
  const cases = [
    stopJobs({ notes: ["#1: the PR body holds it"] }),
    stopJobs({ notes: [] }),
    stopJobs({ notes: [STOP_LINE(), "the pull request title is not in Conventional Commits form"] }),
    stopJobs().map((j) => (j.name === "ci-status" ? { ...j, notes: [...j.notes, { annotation_level: "failure", message: "Process completed with exit code 1." }] } : j)),
  ];
  for (const jobs of cases) {
    const { code, calls } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs })], statuses: cleared() });
    assert.equal(code, 0);
    assert.deepEqual(calls.filter((c) => c.startsWith("POST ")), []);
    assert.ok(!calls.some((c) => c.includes("/statuses")));
  }
  const passed = await reconcile({ pulls: [pr(1)], runs: [run(101, sha(1), { conclusion: "success" })], statuses: cleared() });
  assert.deepEqual(passed.calls.filter((c) => c.startsWith("POST ") || c.includes("/statuses")), []);
});

test("an unreadable status list re-runs nothing and fails no listing", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const fail = { [`GET /repos/${REPO}/commits/${sha(1)}/statuses?per_page=100&page=1`]: new Error("HTTP 502") };
  const { code, calls } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: stopJobs() })], statuses: cleared(), fail });
  assert.equal(code, 0);
  assert.deepEqual(calls.filter((c) => c.startsWith("POST ")), []);
  assert.ok(log.mock.calls.some((c) => String(c.arguments[0]).includes("#1: its pr-unblock statuses could not be read (HTTP 502)")));
});

test("a failed ci-status re-run after a cleared stop is a warning, and the run still passes", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const fail = { [`POST /repos/${REPO}/actions/runs/101/rerun-failed-jobs`]: new Error("HTTP 500") };
  const { code, calls } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: stopJobs() })], statuses: cleared(), fail });
  const lines = log.mock.calls.map((c) => String(c.arguments[0]));
  assert.equal(code, 0);
  assert.ok(calls.includes(`POST /repos/${REPO}/actions/runs/101/rerun-failed-jobs`));
  assert.ok(lines.includes("::warning title=reconcile::#1 run 101: HTTP 500"));
  assert.ok(!lines.some((l) => l.startsWith("::error")));
});

test("ci-status's pr-unblock step still writes the stop note the reconciler matches", () => {
  const workflow = readFileSync(new URL("../../workflows/pr-require-checks.yml", import.meta.url), "utf8");
  const step = /- name: Fail a head a pr-unblock lane stopped\n(?:(?:[ ]{8,}.*)?\n)+/.exec(workflow)?.[0] ?? "";
  const line = step.split("\n").find((l) => l.includes(`echo "::error::'$context' is $state on $head: `));
  assert.ok(line, "the stop error line is in the step");
  assert.match(step, /done <<<"\$failing"\n[ ]+exit 1\n/);
  assert.match(STOP_LINE("pr-unblock/conflict"), PR_UNBLOCK_STOP_NOTE);
  assert.doesNotMatch(STOP_LINE("ci-lanes"), PR_UNBLOCK_STOP_NOTE);
});

// A hosted review run the upstream-status gate stopped: its kill-switch job
// failed at the callers' `Stop on upstream status` step (pr-review-hosted.yml,
// pr-review-security-hosted.yml) and the review job was skipped.
const SECURITY_REVIEW = ".github/workflows/pr-review-security-hosted.yml";
const NPM_COMPONENTS = "https://status.npmjs.org/api/v2/components.json";
const gatedJobs = ({ stop = "failure", kill = "failure", review = "skipped" } = {}) => [
  { id: 301, name: "resolve-model", status: "completed", conclusion: "success", steps: [] },
  {
    id: 302,
    name: "kill-switch",
    status: "completed",
    conclusion: kill,
    steps: [
      { name: "Check the kill switch", status: "completed", conclusion: "success" },
      { name: "Check upstream status", status: "completed", conclusion: "success" },
      { name: "Report the kill switch", status: "completed", conclusion: "skipped" },
      { name: UPSTREAM_STOP_STEP, status: "completed", conclusion: stop },
    ],
  },
  { id: 303, name: "pr-review / claude-review-status", status: "completed", conclusion: review, steps: [] },
];
const gated = (id, head, opts = {}, jobs = gatedJobs()) => run(id, head, { path: REVIEW, conclusion: "failure", updated: "2026-10-19T19:00:00Z", jobs, ...opts });

test("the reconciler takes the hosted review lanes among its CI workflows", () => {
  for (const file of [REVIEW, SECURITY_REVIEW]) {
    assert.ok(CI_WORKFLOWS.has(file), file);
  }
});

test("a hosted review run the upstream gate stopped has its failed jobs re-run once, after the plan names its record", async () => {
  for (const path of [REVIEW, SECURITY_REVIEW]) {
    const { failedJobReruns, reruns, code, outputs, planWrites } = await reconcile({ pulls: [pr(1)], runs: [gated(201, sha(1), { path })] });
    assert.equal(code, 0, path);
    assert.equal(planWrites, 0, path);
    assert.deepEqual(failedJobReruns, [201], path);
    assert.deepEqual(reruns, [], path);
    assert.deepEqual(records(outputs), [`reconcile-rerun-201-2-${sha(1)}`, "", ""], path);
  }
});

// An outage stops both review lanes at one head, so one PR's set can hold more
// records than the workflow's upload steps have room for beside another PR's.
const bothStopped = (n) => [gated(200 + n, sha(n)), gated(300 + n, sha(n), { path: SECURITY_REVIEW })];

test("a PR's two stopped reviews share one place, and a set past the record uploads waits for a later pass", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const runs = [...bothStopped(1), ...bothStopped(2), gated(203, sha(3))];
  const { code, outputs, failedJobReruns } = await reconcile({ pulls: [pr(1), pr(2), pr(3)], runs });
  assert.equal(code, 0);
  assert.deepEqual(records(outputs), [`reconcile-rerun-201-2-${sha(1)}`, `reconcile-rerun-301-2-${sha(1)}`, `reconcile-rerun-203-2-${sha(3)}`]);
  assert.deepEqual(failedJobReruns, [201, 301, 203]);
  assert.ok(log.mock.calls.some((c) => c.arguments[0] === "reconcile: #2: deferred, no record upload left this pass"));
});

test("a set holding three records fills the uploads, so the items after it wait", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const runs = [run(101, sha(1)), ...bothStopped(1), gated(202, sha(2)), verifyRun(401)];
  const { code, outputs, reruns, failedJobReruns } = await reconcile({ pulls: [pr(1), pr(2)], runs });
  assert.equal(code, 0);
  assert.deepEqual(records(outputs), [`reconcile-rerun-101-2-${sha(1)}`, `reconcile-rerun-201-2-${sha(1)}`, `reconcile-rerun-301-2-${sha(1)}`]);
  assert.deepEqual(reruns, [101]);
  assert.deepEqual(failedJobReruns, [201, 301]);
  const lines = log.mock.calls.map((c) => c.arguments[0]);
  assert.ok(lines.includes("reconcile: #2: deferred, no record upload left this pass"));
  assert.ok(lines.includes(`reconcile: lane run 401 (${VERIFY}): deferred, no record upload left this pass`));
});

test("a hosted review run that failed any other way is never re-run", async () => {
  for (const jobs of [
    gatedJobs({ stop: "skipped" }),
    gatedJobs({ review: "failure" }),
    gatedJobs({ kill: "success", stop: "skipped", review: "failure" }),
  ]) {
    const { failedJobReruns, reruns } = await reconcile({ pulls: [pr(1)], runs: [gated(201, sha(1), {}, jobs)] });
    assert.deepEqual([...failedJobReruns, ...reruns], []);
  }
});

test("a hosted review run the upstream gate stopped again at attempt 2 is never re-run", async () => {
  const { failedJobReruns, reruns } = await reconcile({ pulls: [pr(1)], runs: [gated(201, sha(1), { attempt: 2 })] });
  assert.deepEqual([...failedJobReruns, ...reruns], []);
});

test("a lost hosted review run is still reported, not re-run", async () => {
  const { failedJobReruns, reruns } = await reconcile({ pulls: [pr(1)], runs: [run(201, sha(1), { path: SECURITY_REVIEW, conclusion: "timed_out" })] });
  assert.deepEqual([...failedJobReruns, ...reruns], []);
});

test("an upstream-stopped review waits while the gate would still skip it", async () => {
  const npmDown = { components: [{ name: "Package installation", status: "partial_outage", group: false }] };
  const { failedJobReruns } = await reconcile({ pulls: [pr(1)], runs: [gated(201, sha(1))], upstream: { ...UPSTREAM_OK, [NPM_COMPONENTS]: npmDown } });
  assert.deepEqual(failedJobReruns, []);
  const slow = { components: [{ name: "Package installation", status: "degraded_performance", group: false }] };
  const { failedJobReruns: ran } = await reconcile({ pulls: [pr(1)], runs: [gated(201, sha(1))], upstream: { ...UPSTREAM_OK, [NPM_COMPONENTS]: slow } });
  assert.deepEqual(ran, [201]);
});

test("the hosted callers still name the stop step as the reconciler reads it", () => {
  for (const file of [REVIEW, SECURITY_REVIEW]) {
    const text = readFileSync(new URL(`../../../${file}`, import.meta.url), "utf8");
    assert.ok(text.includes(`      - name: ${UPSTREAM_STOP_STEP}\n`), file);
  }
});

const NPM_OUTAGE = { components: [{ name: "Package installation", status: "partial_outage", group: false }] };

test("a main-run review is not re-run or recorded while the upstream gate reads an npm outage", async () => {
  const upstream = { ...UPSTREAM_OK, [NPM_COMPONENTS]: NPM_OUTAGE };
  const { reruns, outputs } = await reconcile({ pulls: [], runs: [mainReviewRun(301)], upstream });
  assert.deepEqual(reruns, []);
  assert.deepEqual(records(outputs), ["", "", ""]);
});

// pr-verify.yml runs no upstream-status gate, so an outage does not hold its re-run.
test("a pr-verify run is recorded and re-run while the upstream gate reads an npm outage", async () => {
  const { reruns, outputs } = await reconcile({ pulls: [], runs: [verifyRun(201)], upstream: { ...UPSTREAM_OK, [NPM_COMPONENTS]: NPM_OUTAGE } });
  assert.deepEqual(reruns, [201]);
  assert.deepEqual(records(outputs), [`reconcile-rerun-201-2-${MAIN_TIP}`, "", ""]);
});

test("a hosted review re-run in flight takes none of the CI slots and does not hold the PR's CI back", async () => {
  const going = run(202, sha(1), { path: REVIEW, status: "in_progress", attempt: 2 });
  const { reruns } = await reconcile({ pulls: [pr(1)], runs: [going, run(101, sha(1))] });
  assert.deepEqual(reruns, [101]);
});

// A hosted review run a kill switch stopped ends success, with its review job
// skipped. ci-status fails the head with REVIEW_STOP_NOTE; rerun-ci-status
// re-runs ci-status when the stopped run completes, so the checks run is often
// past attempt 1. The text is the one pr-require-checks.yml writes (pinned below).
const stoppedJobs = ({ report = "success", kill = "success", review = "skipped" } = {}) => [
  { id: 311, name: "resolve-model", status: "completed", conclusion: "success", steps: [] },
  {
    id: 312,
    name: "kill-switch",
    status: "completed",
    conclusion: kill,
    steps: [
      { name: "Check the kill switch", status: "completed", conclusion: "success" },
      { name: REVIEW_STOP_STEP, status: "completed", conclusion: report },
    ],
  },
  { id: 313, name: "pr-review", status: "completed", conclusion: review, steps: [] },
];
const stoppedRun = (id, head, opts = {}, jobs = stoppedJobs()) => run(id, head, { path: REVIEW, conclusion: "success", jobs, ...opts });
const redChecks = (id, head, opts = {}) =>
  failed(id, head, {
    jobs: switchJobs({ message: `'pr-review / claude-review-status' did not run on ${head} (https://github.com/o/r/actions/runs/1): ${REVIEW_STOP_NOTE}.` }),
    ...opts,
  });

test("a review run a kill switch stopped is re-run whole once, recorded, at any ci-status attempt and past the lookback", async () => {
  for (const opts of [{}, { attempt: 3 }]) {
    for (const created of ["2026-10-19T19:00:00Z", "2026-10-12T19:00:00Z"]) {
      const runs = [redChecks(101, sha(1), opts), stoppedRun(201, sha(1), { created })];
      const { code, outputs, reruns, failedJobReruns, planWrites } = await reconcile({ pulls: [pr(1)], runs });
      assert.equal(code, 0);
      assert.equal(planWrites, 0);
      assert.deepEqual(reruns, [201]);
      assert.deepEqual(failedJobReruns, []);
      assert.deepEqual(records(outputs), [`reconcile-rerun-201-2-${sha(1)}`, "", ""]);
    }
  }
});

test("both stopped lanes of a head go one per pass, so three heads stay inside the record uploads", async () => {
  const runs = [1, 2, 3].flatMap((n) => [redChecks(100 + n, sha(n)), stoppedRun(200 + n, sha(n)), stoppedRun(300 + n, sha(n), { path: SECURITY_REVIEW })]);
  const { code, outputs, reruns } = await reconcile({ pulls: [pr(1), pr(2), pr(3)], runs });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [201, 202, 203]);
  assert.deepEqual(records(outputs), [201, 202, 203].map((id) => `reconcile-rerun-${id}-2-${sha(id - 200)}`));
});

test("the second stopped lane goes on the next pass, after the first has its re-run", async () => {
  const runs = [redChecks(101, sha(1)), stoppedRun(201, sha(1), { attempt: 2 }), stoppedRun(301, sha(1), { path: SECURITY_REVIEW })];
  const { reruns } = await reconcile({ pulls: [pr(1)], runs });
  assert.deepEqual(reruns, [301]);
});

test("a lane's own switch keeps its re-run, with no read, and leaves the other lane's", async () => {
  const runs = [redChecks(101, sha(1)), stoppedRun(201, sha(1)), stoppedRun(301, sha(1), { path: SECURITY_REVIEW })];
  const { code, reruns, calls } = await reconcile({ pulls: [pr(1)], runs, env: { CLAUDE_REVIEW_DISABLED: "true" } });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [301]);
  assert.ok(!calls.some((c) => c.includes("/runs/201/jobs")), JSON.stringify(calls));
});

test("a lane's switch stops at true in any case, as its caller's expression compares it", async () => {
  for (const value of ["true", "TRUE", "True"]) {
    const runs = [redChecks(101, sha(1)), stoppedRun(201, sha(1))];
    const { reruns } = await reconcile({ pulls: [pr(1)], runs, env: { CLAUDE_REVIEW_DISABLED: value } });
    assert.deepEqual(reruns, [], value);
  }
});

test("each lane's switch stops only at true, as its caller reads it", async () => {
  for (const value of ["", "false", "1"]) {
    const env = { CLAUDE_REVIEW_DISABLED: value };
    const { reruns } = await reconcile({ pulls: [pr(1)], runs: [redChecks(101, sha(1)), stoppedRun(201, sha(1))], env });
    assert.deepEqual(reruns, [201], value);
  }
  for (const [file, name] of REVIEW_SWITCHES) {
    const caller = readFileSync(new URL(`../../workflows/${file.slice(file.lastIndexOf("/") + 1)}`, import.meta.url), "utf8");
    assert.ok(caller.includes(`vars.${name} != 'true'`), name);
    assert.ok(caller.includes(`- name: ${REVIEW_STOP_STEP}`), file);
  }
  const reconciler = readFileSync(new URL("../../workflows/maintenance-reconcile-lost-runs.yml", import.meta.url), "utf8");
  for (const name of REVIEW_SWITCHES.values()) {
    assert.ok(reconciler.includes(`${name}: \${{ vars.${name} }}`), name);
  }
});

test("the lanes switch keeps every stopped review from being read or re-run", async () => {
  const { code, calls } = await reconcile({ pulls: [pr(1)], runs: [redChecks(101, sha(1)), stoppedRun(201, sha(1))], env: { KILL_SWITCH: "" } });
  assert.equal(code, 0);
  assert.deepEqual(calls, []);
});

test("an upstream outage keeps the one re-run for later", async () => {
  const npmDown = { components: [{ name: "Package installation", status: "partial_outage", group: false }] };
  const { reruns } = await reconcile({ pulls: [pr(1)], runs: [redChecks(101, sha(1)), stoppedRun(201, sha(1))], upstream: { ...UPSTREAM_OK, [NPM_COMPONENTS]: npmDown } });
  assert.deepEqual(reruns, []);
});

test("only a stopped review on a head ci-status names is re-run", async () => {
  const cases = [
    // A real review, whatever ci-status says: never traded for another.
    [redChecks(101, sha(1)), stoppedRun(201, sha(1), {}, stoppedJobs({ review: "success" }))],
    [redChecks(101, sha(1)), stoppedRun(201, sha(1), {}, [stoppedJobs()[1], { id: 314, name: "pr-review / claude-review-status", status: "completed", conclusion: "success", steps: [] }])],
    // No stop step that ran, or a list cut short.
    [redChecks(101, sha(1)), stoppedRun(201, sha(1), {}, stoppedJobs({ report: "skipped" }))],
    [redChecks(101, sha(1)), stoppedRun(201, sha(1), {}, stoppedJobs({ kill: "failure" }))],
    // Its one re-run is spent, or GitHub's window is past.
    [redChecks(101, sha(1)), stoppedRun(201, sha(1), { attempt: 2 })],
    [redChecks(101, sha(1)), stoppedRun(201, sha(1), { created: "2026-09-19T19:00:00Z" })],
    // ci-status does not name a stop, or passed.
    [failed(101, sha(1), { jobs: switchJobs({ message: "'x' has not finished" }) }), stoppedRun(201, sha(1))],
    [run(101, sha(1), { conclusion: "success" }), stoppedRun(201, sha(1))],
    // Another job failed too, so the head is not waiting on the review alone.
    [failed(101, sha(1), { jobs: switchJobs({ message: REVIEW_STOP_NOTE, lane: "failure" }), attempt: 2 }), stoppedRun(201, sha(1))],
  ];
  for (const runs of cases) {
    const { code, reruns, failedJobReruns } = await reconcile({ pulls: [pr(1)], runs });
    assert.equal(code, 0, JSON.stringify(runs));
    assert.deepEqual(reruns, [], JSON.stringify(runs));
    assert.deepEqual(failedJobReruns, [], JSON.stringify(runs));
  }
});

test("a review run that changed since the plan is left alone", async () => {
  const stopped = stoppedRun(201, sha(1));
  const { reruns } = await reconcile({
    pulls: [pr(1)],
    runs: [redChecks(101, sha(1)), stopped],
    github: (g) => async (method, path, body) => (method === "GET" && path.endsWith("/actions/runs/201") ? { ...stopped, run_attempt: 2 } : g(method, path, body)),
  });
  assert.deepEqual(reruns, []);
});

test("the review-stop note is the text ci-status writes", () => {
  const workflow = readFileSync(new URL("../../workflows/pr-require-checks.yml", import.meta.url), "utf8");
  assert.ok(workflow.includes(`did not run on $HEAD_SHA ($url): ${REVIEW_STOP_NOTE}.`));
});

test("a ci-status past attempt 1 with no review stop stays with a person", async () => {
  await withLaneList(async (env) => {
    const { reruns, failedJobReruns } = await reconcile({ pulls: [lanePr(1)], runs: [failed(101, sha(1), { jobs: switchJobs(), attempt: 2 })], env });
    assert.deepEqual([...reruns, ...failedJobReruns], []);
  });
});

test("a hosted review run that is not a failed first attempt has no jobs read", async () => {
  for (const r of [run(203, sha(1), { path: REVIEW, conclusion: "success" }), gated(203, sha(1), { attempt: 2 })]) {
    const { calls } = await reconcile({ pulls: [pr(1)], runs: [r] });
    assert.ok(!calls.some((c) => c.includes("/runs/203/jobs")), JSON.stringify(calls));
  }
});

// A run's attempt-1 jobs never change once it completed, so a run the last
// pass settled (a held lane run, a failed verdict or floor-label run that is
// not one to re-run) is not read again; every run to re-run still is. Only a
// whole, final listing is settled.
const notStarted = (id) => ({ ...verifyRun(id), jobs: [{ name: "verify", status: "completed", conclusion: "cancelled", steps: [] }] });
const settledRuns = () => [
  notStarted(202),
  verdictRun(401, { jobs: [verdictJob("Download the verdict")] }),
  verdictRun(402, { jobs: [verdictJob(), { id: 4009, name: "dispatch", status: "completed", conclusion: "failure", steps: [] }] }),
  intakeRun(302, { jobs: [intakeJob("apply-verdict", "failure")] }),
];
const SETTLED = [
  { id: 202, reason: "before any of its jobs started" },
  { id: 302, reason: "" },
  { id: 401, reason: "" },
  { id: 402, reason: "" },
];
const jobReads = (calls) => calls.filter((c) => /\/attempts\/1\/jobs\?/.test(c)).map((c) => Number(/runs\/([0-9]+)\//.exec(c)[1])).sort();
const ids = (settled) => settled.runs.map((r) => r.id).sort();
const carryOf = (runs, version = SETTLED_VERSION) => JSON.stringify({ version, repository: REPO, runs });

test("a pass reads the attempt-1 jobs only of runs the last pass did not settle", async () => {
  const toRerun = [verifyRun(201), verdictRun(403)];
  const first = await reconcile({ pulls: [], runs: [...settledRuns(), ...toRerun], carry: null });
  assert.equal(first.code, 0);
  assert.deepEqual(jobReads(first.calls), [201, 202, 302, 401, 402, 403]);
  assert.deepEqual([...first.settled.runs].sort((a, b) => a.id - b.id), SETTLED);
  assert.deepEqual(first.reruns, [201]);
  assert.deepEqual(first.failedJobReruns, [403]);
  // The next pass: the same runs, one new verdict run that is not a stop, and
  // a carried id no longer listed, which is dropped.
  const carry = carryOf([...first.settled.runs, { id: 999, reason: "" }]);
  const second = await reconcile({ pulls: [], runs: [...settledRuns(), ...toRerun, verdictRun(404, { jobs: [verdictJob("Download the verdict")] })], carry });
  assert.equal(second.code, 0);
  assert.deepEqual(jobReads(second.calls), [201, 403, 404]);
  assert.deepEqual(ids(second.settled), [202, 302, 401, 402, 404]);
  assert.deepEqual(second.reruns, [201]);
  assert.deepEqual(second.failedJobReruns, [403]);
});

test("a carried lane hold is still named in the summary with its reason", async () => {
  const dir = tempDir("reconcile-summary-");
  try {
    const summary = path.join(dir, "summary.md");
    writeFileSync(summary, "");
    const held = { id: 202, reason: "after its verdict write started, so a re-run would judge the head again" };
    const { calls } = await reconcile({ pulls: [], runs: [notStarted(202)], carry: carryOf([held]), env: { GITHUB_STEP_SUMMARY: summary } });
    assert.deepEqual(jobReads(calls), []);
    const text = readFileSync(summary, "utf8");
    assert.match(text, /lane run 202 \(\.github\/workflows\/pr-verify\.yml\) ended cancelled after its verdict write started, so a re-run would judge the head again; not re-run/);
    assert.doesNotMatch(text, /nothing lost/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a short or unfinished listing, or a cut step list, is not settled", async () => {
  const cut = { ...verdictJob("Download the verdict"), steps: verdictJob("Download the verdict").steps.slice(0, -1) };
  const runs = [
    { ...notStarted(202), jobs: [], jobsTotal: 1 },
    { ...notStarted(203), jobsTotal: 2 },
    { ...notStarted(204), jobs: [{ name: "verify", status: "completed", conclusion: null, steps: [] }] },
    verdictRun(401, { jobs: [cut] }),
    verdictRun(402, { jobs: [] }),
    verdictRun(403, { jobs: [verdictJob("Download the verdict", { conclusion: null })] }),
    intakeRun(302, { jobs: [] }),
    intakeRun(303, { jobs: [intakeJob("apply-verdict", null)] }),
  ];
  const { code, settled, reruns, failedJobReruns } = await reconcile({ pulls: [], runs, carry: null });
  assert.equal(code, 0);
  assert.deepEqual(settled.runs, []);
  // Held, not re-run, all the same.
  assert.deepEqual(reruns, []);
  assert.deepEqual(failedJobReruns, []);
});

test("a carry that cannot be read, names another repository or has another version reads every run", async () => {
  for (const carry of ["not json", JSON.stringify({ version: SETTLED_VERSION, repository: "other/repo", runs: SETTLED }), carryOf(SETTLED, SETTLED_VERSION - 1), carryOf([202, 302, 401, 402])]) {
    const { code, calls, settled } = await reconcile({ pulls: [], runs: settledRuns(), carry });
    assert.equal(code, 0);
    assert.deepEqual(jobReads(calls), [202, 302, 401, 402]);
    assert.deepEqual(ids(settled), [202, 302, 401, 402]);
  }
});

test("a carry is taken from the newest trusted pass, past a pull_request run or another branch's run", async () => {
  const carryRuns = [
    { ...LAST_PASS, id: 901, event: "pull_request" },
    { ...LAST_PASS, id: 902, head_branch: "feat/x" },
  ];
  const { code, calls } = await reconcile({ pulls: [], runs: settledRuns(), carry: carryOf(SETTLED), carryRuns });
  assert.equal(code, 0);
  assert.deepEqual(jobReads(calls), []);
  assert.ok(!calls.some((c) => /runs\/90[12]\/artifacts/.test(c)));
});

test("a carry whose download fails reads every run", async () => {
  const download = () => {
    throw new Error("gh run download failed");
  };
  const { code, calls } = await reconcile({ pulls: [], runs: settledRuns(), carry: carryOf(SETTLED), download });
  assert.equal(code, 0);
  assert.deepEqual(jobReads(calls), [202, 302, 401, 402]);
});

test("a lane run listing no job settles only once its last change is a pass interval old", async () => {
  const empty = (id, updated) => ({ ...verifyRun(id, { conclusion: "startup_failure", updated }), jobs: [] });
  const fresh = new Date(NOW - 5 * 60_000).toISOString();
  const old = new Date(NOW - 60 * 60_000).toISOString();
  const { code, settled, reruns } = await reconcile({ pulls: [], runs: [empty(205, fresh), empty(206, old)], carry: null });
  assert.equal(code, 0);
  assert.deepEqual(ids(settled), [206]);
  assert.deepEqual(reruns, []);
});

test("a failed job that lost its runner with no steps listed is held but not settled", async () => {
  const lost = {
    id: 5001,
    name: "verify",
    status: "completed",
    conclusion: "failure",
    runner_id: 7,
    steps: [],
    notes: [{ annotation_level: "failure", message: "The self-hosted runner lost communication with the server." }],
  };
  const { code, settled, reruns } = await reconcile({ pulls: [], runs: [{ ...verifyRun(207), jobs: [lost] }], carry: null });
  assert.equal(code, 0);
  assert.deepEqual(settled.runs, []);
  assert.deepEqual(reruns, []);
});
