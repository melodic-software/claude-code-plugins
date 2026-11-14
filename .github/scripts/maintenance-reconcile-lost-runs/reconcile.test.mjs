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
import { CI_WORKFLOWS, GITHUB_STATUS_URL, JUDGE_PREDECESSOR, JUDGE_STEP, KILL_SWITCH_NOTE, main, NPM_STATUS_URL, MISSING_REVIEW_NOTE, PENDING_BACKOFF_MINUTES, PENDING_REVIEW_NOTE, prefilterSpec, REVIEW_STEP, REVIEW_STOP_NOTE, REVIEW_STOP_STEP, REVIEW_SWITCHES, SETTLED_VERSION, TOO_OLD_DAYS, UPSTREAM_STOP_STEP, VERDICT_STOP_STEP, WRITE_STEP } from "./reconcile.mjs";
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
    const byWorkflow = /^\/repos\/[^/]+\/[^/]+\/actions\/workflows\/([a-z0-9-]+\.yml)\/runs\?created=%3E%3D([0-9-]+T[0-9]{2}%3A[0-9]{2}%3A[0-9]{2}Z)(?:&status=([a-z_]+))?&per_page=100(?:&page=([0-9]+))?$/.exec(path);
    if (method === "GET" && byWorkflow) {
      // Like GitHub, `status` matches a run's status or its conclusion, and
      // `created` takes the runs created at or after it.
      const after = Date.parse(decodeURIComponent(byWorkflow[2]));
      const found = runs.filter(
        (r) =>
          r.path === `.github/workflows/${byWorkflow[1]}` &&
          Date.parse(r.created_at) >= after &&
          (byWorkflow[3] === undefined || r.status === byWorkflow[3] || r.conclusion === byWorkflow[3]),
      );
      const page = Number(byWorkflow[4] ?? 1);
      return { total_count: found.length, workflow_runs: found.slice((page - 1) * 100, page * 100) };
    }
    const byStatus = /^\/repos\/[^/]+\/[^/]+\/actions\/runs\?created=%3E%3D2026-10-18T20%3A00%3A00Z&status=([a-z_]+)&per_page=100$/.exec(path);
    if (method === "GET" && byStatus) {
      const found = runs.filter((r) => r.status === byStatus[1] || r.conclusion === byStatus[1]);
      return { total_count: found.length, workflow_runs: found.slice(0, 100) };
    }
    const jobs = /^\/repos\/[^/]+\/[^/]+\/actions\/runs\/([0-9]+)\/attempts\/1\/jobs\?per_page=100$/.exec(path);
    if (method === "GET" && jobs) {
      const found = byId.get(Number(jobs[1]))?.jobs ?? [];
      return { total_count: byId.get(Number(jobs[1]))?.jobsTotal ?? found.length, jobs: found };
    }
    const latest = /^\/repos\/[^/]+\/[^/]+\/actions\/runs\/([0-9]+)\/jobs\?filter=latest&per_page=100$/.exec(path);
    if (method === "GET" && latest) {
      // A run with no jobs named is a ready pull request's: its ci-status
      // skipped the draft step resolve-pr's draftRun reads.
      const ready = [{ id: 1, name: "ci-status", conclusion: "success", steps: [{ name: "Note a draft", conclusion: "skipped" }] }];
      const found = byId.get(Number(latest[1]))?.jobs ?? ready;
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
const CARRY_ARTIFACT = 4242;
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
      return { total_count: 1, artifacts: [{ id: CARRY_ARTIFACT, name: "reconcile-settled-runs", expired: false }] };
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
            assert.equal(id, CARRY_ARTIFACT, "the carry is downloaded by the artifact id its listing gave");
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

test("verify re-runs share the cap of 3 with PR CI sets, CI first, then the oldest verify run", async () => {
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
  assert.deepEqual(reruns, [101, 201]);
  assert.deepEqual(records(outputs), [`reconcile-rerun-101-2-${sha(1)}`, `reconcile-rerun-201-2-${MAIN_TIP}`, ""]);
});

test("verify re-runs go before flake re-runs, oldest first, since nothing else re-runs them", async () => {
  const flake = (id, n) => failed(id, sha(n), { jobs: MIXED_JOBS, updated: "2026-10-19T19:00:00Z" });
  const { reruns, failedJobReruns, outputs } = await reconcile({
    pulls: [pr(1), pr(2), pr(3)],
    runs: [flake(101, 1), flake(102, 2), flake(103, 3), verifyRun(201, { created: "2026-10-19T19:10:00Z" }), verifyRun(202, { created: "2026-10-19T19:20:00Z" })],
  });
  assert.deepEqual(reruns, [201, 202]);
  assert.deepEqual(failedJobReruns, [101]);
  assert.deepEqual(records(outputs), [`reconcile-rerun-201-2-${MAIN_TIP}`, `reconcile-rerun-202-2-${MAIN_TIP}`, `reconcile-rerun-101-2-${sha(1)}`]);
});

test("at most 3 verify runs are recorded and re-run in one run", async () => {
  const { reruns, outputs } = await reconcile({
    pulls: [],
    runs: [verifyRun(201), verifyRun(202), verifyRun(203), verifyRun(204)].map((r, i) => ({ ...r, created_at: `2026-10-19T19:0${i}:00Z` })),
  });
  assert.deepEqual(reruns, [201, 202, 203]);
  assert.deepEqual(records(outputs), [201, 202, 203].map((id) => `reconcile-rerun-${id}-2-${MAIN_TIP}`));
});

// A lane workflow's jobs (pr-verify's legs by default), as name and body.
const verifyLegs = (file = "pr-verify.yml") => {
  const workflow = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
  const jobs = workflow.slice(workflow.search(/^jobs:$/m));
  // pr-verify's wake-pr-merge job judges nothing: it only starts pr-merge
  // after the legs, and never fails the run (its one step continues on error).
  return [...jobs.matchAll(/^ {2}([a-z][a-z0-9-]*):\n((?: {4,}.*\n|\s*\n)+)/gm)].map(([, name, body]) => ({ name, body })).filter(({ name }) => name !== "wake-pr-merge");
};
// A leg's steps, each its first line and the lines under it.
const legSteps = (body) => body.split(/^(?= {6}- name: )/m).filter((s) => s.startsWith("      - name: "));

// The reconciler reads every job's steps by name, so a leg whose judge step
// another name hid would hide a lost run.
// pr-verify's judging legs; its other job, the credit gate, runs no model
// and writes nothing, so it holds no step the reconciler reads.
const judgingLegs = () => {
  const jobs = verifyLegs();
  const legs = jobs.filter(({ body }) => /^ {8}id: judge$/m.test(body));
  for (const { name, body } of jobs.filter((job) => !legs.includes(job))) {
    assert.doesNotMatch(body, /run-claude-cli|secrets\.|upload-artifact/, name);
    for (const step of [JUDGE_STEP, JUDGE_PREDECESSOR, WRITE_STEP]) assert.ok(!legSteps(body).some((s) => s.startsWith(`      - name: ${step}\n`)), `${name}: ${step}`);
  }
  assert.equal(legs.length, 3);
  return legs;
};

test("pr-verify still names its judge step as the reconciler reads it, in every leg", () => {
  const legs = judgingLegs();
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
    name: "Check Intent Fallback",
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

// With the key out of credit, check-intent's credit gate skips its key leg and
// the subscription leg judges: its own steps tell a write held from a run lost.
test("a verify run whose credit gate skipped the key is read on the subscription leg", async () => {
  const key = {
    name: "Check Intent",
    status: "completed",
    conclusion: "success",
    steps: [
      { name: "Set up job", status: "completed", conclusion: "success" },
      { name: "Hand the reads on", status: "completed", conclusion: "success" },
      { name: "Read the key's credit history", status: "completed", conclusion: "success" },
      { name: JUDGE_PREDECESSOR, status: "completed", conclusion: "skipped" },
      { name: JUDGE_STEP, status: "completed", conclusion: "skipped" },
      { name: "Complete job", status: "completed", conclusion: "success" },
    ],
  };
  const subscription = (write, upload) => ({
    name: "Check Intent Subscription",
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
  const held = await reconcile({ pulls: [], runs: [{ ...verifyRun(201, { conclusion: "failure" }), jobs: [key, subscription("success", "failure")] }] });
  assert.deepEqual(held.reruns, []);
  const lost = await reconcile({ pulls: [], runs: [{ ...verifyRun(201, { conclusion: "failure" }), jobs: [key, subscription("skipped", "skipped")] }] });
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

// A pr-verify check-intent job whose resolver held green on a GitHub fault: it
// ran pr-verify.yml's "Note the hold" step, and its check run carries the
// resolver's notice (resolve-pr.mjs closing), as GitHub lists a
// `::notice title=pr-verify::held: ...` line. `marked` false is a run the
// resolver skipped, whose marker step skipped too.
const heldJob = ({ marked = true, notes = [{ annotation_level: "notice", title: "pr-verify", message: "held: pr-verify could not resolve the pull request: GET /repos/x failed with status 502" }] } = {}) => [
  {
    id: 7001,
    name: "Check Intent",
    status: "completed",
    conclusion: "success",
    steps: [
      { name: "Set up job", status: "completed", conclusion: "success" },
      { name: "Resolve the pull request", status: "completed", conclusion: "success" },
      { name: "Note the hold", status: "completed", conclusion: marked ? "success" : "skipped" },
      { name: "Check the trigger", status: "completed", conclusion: "skipped" },
      { name: "Complete job", status: "completed", conclusion: "success" },
    ],
    notes,
  },
];
const heldRun = (id, opts = {}, job = {}) => ({ ...verifyRun(id, { conclusion: "success", created: "2026-10-19T19:40:00Z", ...opts }), jobs: heldJob(job) });

test("a verify run held green on a GitHub fault is recorded and re-run once on the next pass", async () => {
  const { code, reruns, outputs } = await reconcile({ pulls: [], runs: [heldRun(301)] });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [301]);
  assert.deepEqual(records(outputs), [`reconcile-rerun-301-2-${MAIN_TIP}`, "", ""]);
});

test("a succeeded verify run with no hold is not re-run, its annotations are not read, and it is settled", async () => {
  const { code, reruns, calls, settled } = await reconcile({ pulls: [], runs: [heldRun(302, {}, { marked: false })], carry: null });
  assert.equal(code, 0);
  assert.deepEqual(reruns, []);
  assert.ok(calls.every((c) => !c.includes("/check-runs/")));
  assert.deepEqual(settled.runs, [{ id: 302, reason: "" }]);
});

test("a held verify run is not re-run without the resolver's held notice, at attempt 2, past the window, or while Actions is not operational", async () => {
  const cases = {
    "no notice": { runs: [heldRun(303, {}, { notes: [{ annotation_level: "notice", message: "api calls: 12" }] })] },
    "attempt 2": { runs: [heldRun(304, { attempt: 2 })] },
    "past the window": { runs: [heldRun(305, { created: "2026-10-19T13:30:00Z" })] },
    "Actions degraded": { runs: [heldRun(306)], status: statusWith("degraded_performance") },
  };
  for (const [label, options] of Object.entries(cases)) {
    const { code, reruns } = await reconcile({ pulls: [], ...options });
    assert.equal(code, 0, label);
    assert.deepEqual(reruns, [], label);
  }
});

// A pass idle through an outage reads and carries nothing, so the held runs
// the outage left are listed from the last pass that read, not 6 hours back.
test("after a 10-hour outage, a run held 9 hours ago is re-run, listed from the last pass that read", async () => {
  const lastRead = carryOf([]).replace(/}$/, `,"held_since":"2026-10-19T04:00:00.000Z"}`);
  const { code, reruns, calls, settled } = await reconcile({ pulls: [], runs: [heldRun(307, { created: "2026-10-19T11:00:00Z" })], carry: lastRead });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [307]);
  assert.ok(calls.some((c) => c.includes("/workflows/pr-verify.yml/runs?created=%3E%3D2026-10-19T04%3A00%3A00Z&status=success&")));
  // Until its re-run takes a place, the next pass still lists it.
  assert.equal(settled.held_since, "2026-10-19T11:00:00.000Z");
});

// pr-verify's three jobs run in turn, each up to 346 minutes, so a run can
// hold in its last job long after FAULT_HELD_HOURS from its creation.
test("a run created 10 hours ago, still going at one pass and held at the next, is re-run once", async () => {
  const going = { ...verifyRun(501, { status: "in_progress", created: "2026-10-19T10:00:00Z" }), jobs: [] };
  const first = await reconcile({ pulls: [], runs: [going], carry: null });
  assert.equal(first.code, 0);
  assert.deepEqual(first.reruns, []);
  assert.equal(first.settled.held_since, "2026-10-19T10:00:00.000Z");
  const held = heldRun(501, { created: "2026-10-19T10:00:00Z" });
  const second = await reconcile({ pulls: [], runs: [held], carry: JSON.stringify(first.settled) });
  assert.equal(second.code, 0);
  assert.deepEqual(second.reruns, [501]);
  // Without the carry, the 6-hour window alone misses it.
  const alone = await reconcile({ pulls: [], runs: [held], carry: null });
  assert.deepEqual(alone.reruns, []);
});

test("a pass reads at most 100 succeeded runs' jobs for a hold, oldest first, and the next pass starts at the first it left", async () => {
  // Left from an outage: 120 runs from 05:00, a minute apart, with the last
  // reading pass at 04:00.
  const runs = Array.from({ length: 120 }, (_, i) =>
    heldRun(400 + i, { created: new Date(Date.parse("2026-10-19T05:00:00Z") + i * 60_000).toISOString().replace(/\.\d{3}Z$/, "Z") }, { marked: false }),
  );
  const lastRead = carryOf([]).replace(/}$/, `,"held_since":"2026-10-19T04:00:00.000Z"}`);
  const { code, calls, settled } = await reconcile({ pulls: [], runs, carry: lastRead });
  assert.equal(code, 0);
  assert.equal(calls.filter((c) => /\/actions\/runs\/4[0-9]{2}\/attempts\/1\/jobs/.test(c)).length, 100);
  assert.equal(settled.runs.length, 100);
  // The 101st run, created 100 minutes after 05:00.
  assert.equal(settled.held_since, "2026-10-19T06:40:00.000Z");
});

test("a verify run the kill switch stopped is re-run once the switch is off", async () => {
  const stopped = [
    {
      name: "Check Intent",
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
  const legs = judgingLegs();
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
  assert.deepEqual(reruns, [201, 202]);
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

// A pr-review-main run whose file list did not read: the select held green,
// with the notice the workflow prints (read from it, so producer and reader
// are one contract) and its Note the hold step, in `holder`. `wrote` adds a
// key leg that wrote the other lane's verdict before a later leg held.
const MAIN_HELD_NOTE = /echo "::notice title=pr-review-main::(held: [^"]*)"/
  .exec(readFileSync(new URL("../../workflows/pr-review-main.yml", import.meta.url), "utf8"))[1]
  .replace("$retry_call_unknown", "failed 3 times");
const mainHeldJobs = ({ holder = "Trigger", marked = true, notes = [{ annotation_level: "notice", title: "pr-review-main", message: MAIN_HELD_NOTE }], wrote = false } = {}) => [
  ...(wrote
    ? [
        {
          id: 8000,
          name: "Review (claude-security-review)",
          status: "completed",
          conclusion: "success",
          steps: [
            { name: "Set up job", status: "completed", conclusion: "success" },
            { name: REVIEW_STEP, status: "completed", conclusion: "success" },
            { name: WRITE_STEP, status: "completed", conclusion: "success" },
            { name: "Complete job", status: "completed", conclusion: "success" },
          ],
        },
      ]
    : []),
  {
    id: 8001,
    name: holder,
    status: "completed",
    conclusion: "success",
    steps: [
      { name: "Set up job", status: "completed", conclusion: "success" },
      { name: "Check the trigger", status: "completed", conclusion: "success" },
      { name: "Select a lane-source pull request", status: "completed", conclusion: "success" },
      { name: "Note the hold", status: "completed", conclusion: marked ? "success" : "skipped" },
      { name: "Complete job", status: "completed", conclusion: "success" },
    ],
    notes,
  },
];
const mainHeldRun = (id, job = {}, opts = {}) => mainReviewRun(id, { conclusion: "success", created: "2026-10-19T19:40:00Z", ...opts }, mainHeldJobs(job));

test("a main-run review held green on an unread file list is recorded and re-run once", async () => {
  const { code, reruns, outputs } = await reconcile({ pulls: [], runs: [mainHeldRun(311)] });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [311]);
  assert.deepEqual(records(outputs), [`reconcile-rerun-311-2-${MAIN_TIP}`, "", ""]);
  // A later leg's hold is read the same way.
  assert.deepEqual((await reconcile({ pulls: [], runs: [mainHeldRun(311, { holder: "Review Subscription (claude-review)" })] })).reruns, [311]);
});

test("a succeeded main-run review with no hold, or with no held notice, is not re-run, and one with no marker is settled", async () => {
  const unmarked = await reconcile({ pulls: [], runs: [mainHeldRun(312, { marked: false })], carry: null });
  assert.equal(unmarked.code, 0);
  assert.deepEqual(unmarked.reruns, []);
  assert.ok(unmarked.calls.every((c) => !c.includes("/check-runs/")));
  assert.deepEqual(unmarked.settled.runs, [{ id: 312, reason: "" }]);
  const unnoted = await reconcile({ pulls: [], runs: [mainHeldRun(313, { notes: [{ annotation_level: "notice", message: "lane source changed: true" }] })] });
  assert.deepEqual(unnoted.reruns, []);
  assert.deepEqual((await reconcile({ pulls: [], runs: [mainHeldRun(314, {}, { attempt: 2 })] })).reruns, []);
});

// One lane's leg wrote its verdict before the other's later leg held: a
// re-run of the whole run would review the written lane's head again.
test("a held main-run review where a verdict write started in another job is held for good with its reason", async () => {
  const dir = tempDir("reconcile-summary-");
  try {
    const summary = path.join(dir, "summary.md");
    writeFileSync(summary, "");
    const { code, reruns, outputs, settled } = await reconcile({ pulls: [], runs: [mainHeldRun(315, { holder: "Review Subscription (claude-review)", wrote: true })], carry: null, env: { GITHUB_STEP_SUMMARY: summary } });
    assert.equal(code, 0);
    assert.deepEqual(reruns, []);
    assert.deepEqual(records(outputs), ["", "", ""]);
    assert.deepEqual(settled.runs, [{ id: 315, reason: "after its verdict write started, so a re-run would judge the head again" }]);
    assert.match(readFileSync(summary, "utf8"), /lane run 315 \(\.github\/workflows\/pr-review-main\.yml\) ended success after its verdict write started/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a held main-run review waits out the upstream gate and is listed again next pass, while a held pr-verify run is re-run", async () => {
  const upstream = { ...UPSTREAM_OK, [NPM_COMPONENTS]: NPM_OUTAGE };
  const runs = [mainHeldRun(316)];
  const { code, reruns, outputs, settled } = await reconcile({ pulls: [], runs, upstream, carry: null });
  assert.equal(code, 0);
  assert.deepEqual(reruns, []);
  assert.deepEqual(records(outputs), ["", "", ""]);
  // Not settled, so the next pass reads it again and, with the gate clear, re-runs it.
  assert.deepEqual(settled.runs, []);
  assert.deepEqual((await reconcile({ pulls: [], runs, carry: JSON.stringify(settled) })).reruns, [316]);
  assert.deepEqual((await reconcile({ pulls: [], runs: [heldRun(317)], upstream })).reruns, [317]);
});

test("a main-run review re-run shares the cap of 3 with pr-verify re-runs, oldest first", async () => {
  const { reruns, outputs } = await reconcile({
    pulls: [],
    runs: [
      verifyRun(201, { created: "2026-10-19T19:00:00Z" }),
      mainReviewRun(301, { created: "2026-10-19T18:00:00Z" }),
      verifyRun(202, { created: "2026-10-19T19:10:00Z" }),
      mainReviewRun(302, { created: "2026-10-19T19:20:00Z" }),
    ],
  });
  assert.deepEqual(reruns, [301, 201, 202]);
  assert.deepEqual(records(outputs), [301, 201, 202].map((id) => `reconcile-rerun-${id}-2-${MAIN_TIP}`));
});

// A lane run is matched to an open head when it was created between 60 s
// before and 15 minutes after the head's newest checks run completed; the
// recorded pair is a checks run done at 04:13:36Z and its pr-verify run
// created at 04:13:40Z, 4 s later.
const doneChecks = (id, n, done) => run(id, sha(n), { conclusion: "success", created: "2026-10-19T16:50:00Z", updated: done });
const deferredLanes = (log) => log.mock.calls.map((c) => c.arguments[0]).filter((line) => / deferred, /.test(line)).map((line) => Number(/lane run ([0-9]+) /.exec(line)?.[1]));

test("lane runs of open heads go first, oldest first, ahead of an older run whose PR is gone and of newer runs", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const { code, reruns } = await reconcile({
    pulls: [pr(1), pr(2)],
    runs: [
      doneChecks(101, 1, "2026-10-19T17:00:00Z"),
      doneChecks(102, 2, "2026-10-19T17:30:00Z"),
      verifyRun(210, { created: "2026-10-19T16:00:00Z" }),
      verifyRun(211, { created: "2026-10-19T17:00:04Z" }),
      verifyRun(212, { created: "2026-10-19T17:30:04Z" }),
      verifyRun(221, { created: "2026-10-19T19:00:00Z" }),
      verifyRun(222, { created: "2026-10-19T19:10:00Z" }),
      verifyRun(223, { created: "2026-10-19T19:20:00Z" }),
    ],
  });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [211, 212, 210], "the two matched runs, then the oldest unmatched one");
  assert.deepEqual(deferredLanes(log), [221, 222, 223], "every lane run not re-run is named as deferred");
});

test("a second lane run for one head goes behind every matched run, while each lane matches the head once", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const { code, reruns } = await reconcile({
    pulls: [pr(1), pr(2)],
    runs: [
      doneChecks(101, 1, "2026-10-19T17:00:00Z"),
      doneChecks(102, 2, "2026-10-19T17:30:00Z"),
      verifyRun(231, { created: "2026-10-19T17:00:04Z" }),
      verifyRun(232, { created: "2026-10-19T17:00:30Z" }),
      mainReviewRun(331, { created: "2026-10-19T17:00:05Z" }),
      verifyRun(233, { created: "2026-10-19T17:30:04Z" }),
    ],
  });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [231, 331, 233], "head 1's closest verify and review runs, then head 2's verify run");
  assert.deepEqual(deferredLanes(log), [232], "the duplicate waits and is named");
});

test("a lane run created more than 60 s before or 15 minutes after a head's checks completion is not matched", async () => {
  const { code, reruns } = await reconcile({
    pulls: [pr(1)],
    runs: [
      doneChecks(101, 1, "2026-10-19T17:00:00Z"),
      verifyRun(240, { created: "2026-10-19T16:00:00Z" }),
      verifyRun(241, { created: "2026-10-19T16:58:59Z" }),
      verifyRun(242, { created: "2026-10-19T17:15:01Z" }),
      verifyRun(244, { created: "2026-10-19T17:14:59Z" }),
    ],
  });
  assert.equal(code, 0);
  // 241 is 61 s before the completion and 242 is 15 min 1 s after; 244, at
  // 14 min 59 s after, is the one match, and the rest go oldest first.
  assert.deepEqual(reruns, [244, 240, 241]);
});

test("a non-operational Actions status records nothing", async () => {
  const { outputs, calls } = await reconcile({ pulls: [], runs: [verifyRun(201)], status: statusWith("major_outage") });
  assert.deepEqual(calls, []);
  assert.deepEqual(records(outputs), ["", "", ""]);
});

// A day of pr-verify runs: succeeded ones, with the given runs among them.
// A day of pr-verify runs, spread evenly over the lookback, as they start.
const verifyDay = (count, lost) =>
  Array.from(
    { length: count },
    (_, i) =>
      lost.get(i) ?? {
        ...run(10_000 + i, MAIN_TIP, { path: VERIFY, event: "workflow_run", conclusion: "success", created: new Date(NOW - ((count - i) * 24 * 3_600_000) / count).toISOString().replace(/\.\d{3}Z$/, "Z") }),
        head_branch: "main",
      },
  );

// Lost pr-verify runs, oldest first.
const lostDay = (count) =>
  Array.from({ length: count }, (_, i) => verifyRun(1000 + i, { created: new Date(Date.parse("2026-10-19T00:00:00Z") + i * 60_000).toISOString().replace(/\.\d{3}Z$/, "Z") }));
const lostQueries = (calls) => calls.filter((c) => c.includes("/workflows/pr-verify.yml/runs?") && c.includes("&status=cancelled&"));

test("a lost-run listing of 150 runs over 2 pages is read in full", async () => {
  const { code, reruns, calls } = await reconcile({ pulls: [], runs: lostDay(150) });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [1000, 1001, 1002]);
  assert.equal(lostQueries(calls).length, 2);
});

test("700 succeeded verify runs and 2 lost ones plan the 2 lost runs without hitting the page cap", async () => {
  const { code, reruns, outputs, calls } = await reconcile({
    pulls: [],
    runs: [...verifyDay(700, new Map()), verifyRun(201), verifyRun(202, { created: "2026-10-19T19:00:00Z" })],
  });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [201, 202]);
  assert.deepEqual(records(outputs), [`reconcile-rerun-201-2-${MAIN_TIP}`, `reconcile-rerun-202-2-${MAIN_TIP}`, ""]);
  // The lost-run listings; the held-run listing of the last 6 hours' 175 runs is its own.
  assert.ok(calls.filter((c) => !c.includes("&status=success&")).every((c) => !c.includes("&page=2")));
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
  assert.deepEqual(reruns, [201]);
});

test("verify re-runs that start while the listing is read still take places", async () => {
  const queued = [209, 210, 211].map((id) => verifyRun(id, { status: "queued", attempt: 2 }));
  const { code, reruns } = await reconcile({
    pulls: [],
    runs: [...queued, verifyRun(201)],
    github: (g) => async (method, path, body) => {
      if (path.startsWith(`/repos/${REPO}/actions/runs?created=`) && path.includes("&status=queued&")) {
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

// Two lane re-runs already in flight leave one of MAX_IN_FLIGHT's 3 places,
// which the oldest lost run (201, created 18:59:43) takes; a CI run in progress
// belongs to neither lane.
const laneMix = () => [
  verifyRun(201),
  verifyRun(202, { created: "2026-10-19T19:00:00Z" }),
  verifyRun(209, { status: "in_progress", attempt: 2 }),
  mainReviewRun(309, { status: "queued", attempt: 2 }),
  run(500, sha(5), { path: CHECKS, status: "in_progress" }),
];
const repoWide = (calls) => calls.filter((c) => c.startsWith(`GET /repos/${REPO}/actions/runs?created=`));
// The lost-run listings per lane; pr-verify's held-run listing is its own.
const perLane = (calls) => calls.filter((c) => /\/actions\/workflows\/pr-(verify|review-main)\.yml\/runs\?/.test(c) && !c.includes("&status=success&"));
// Every repository-wide listing answers a total past one page.
const overfull = (g) => async (method, apiPath, body) => {
  const answer = await g(method, apiPath, body);
  return apiPath.startsWith(`/repos/${REPO}/actions/runs?created=`) ? { ...answer, total_count: 101 } : answer;
};

test("the near-empty statuses are listed once repository-wide and split by lane, deciding as the per-lane listings do", async () => {
  const shared = await reconcile({ pulls: [], runs: laneMix(), carry: null });
  const fallback = await reconcile({ pulls: [], runs: laneMix(), carry: null, github: overfull });
  for (const [label, result] of Object.entries({ shared, fallback })) {
    assert.equal(result.code, 0, label);
    assert.deepEqual(result.reruns, [201], label);
    assert.deepEqual(records(result.outputs), [`reconcile-rerun-201-2-${MAIN_TIP}`, "", ""], label);
  }
  assert.deepEqual(shared.settled, fallback.settled);
  assert.equal(repoWide(shared.calls).length, 7, "one listing per shared status");
  assert.equal(perLane(shared.calls).length, 4, "cancelled and failure for each of 2 lanes");
  assert.equal(repoWide(fallback.calls).length, 7);
  assert.equal(perLane(fallback.calls).length, 18, "a listing past one page is read per lane, 9 statuses for each of 2 lanes");
});

test("a repository-wide listing that fails is read per lane, and a rate limit on it stops the run", async () => {
  const failing = (error) => (g) => async (method, apiPath, body) => {
    if (apiPath.startsWith(`/repos/${REPO}/actions/runs?created=`) && apiPath.includes("&status=in_progress&")) {
      throw error;
    }
    return g(method, apiPath, body);
  };
  const failed = await reconcile({ pulls: [], runs: laneMix(), github: failing(new GitHubError(502, "bad gateway")) });
  assert.equal(failed.code, 0);
  assert.deepEqual(failed.reruns, [201]);
  assert.equal(perLane(failed.calls).filter((c) => c.includes("&status=in_progress&")).length, 2);
  const limited = await reconcile({ pulls: [], runs: laneMix(), github: failing(new GitHubError(429, "rate limited")) });
  assert.equal(limited.code, 1);
  assert.deepEqual(limited.reruns, []);
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
    const jobs = [{ name: "Lint Repo", conclusion: "failure", runner_id: 7, steps }];
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
  const lost = { id: 77, name: "Lint Repo", status: "completed", conclusion: "failure", runner_id: 7, steps };
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
    { name: "Lint Repo", conclusion: "success", steps: [] },
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
  intakeJob("Kill Switch", "success"),
  intakeJob("Born Triaged", "success"),
  intakeJob("Intake Triage / triage", "success"),
  intakeJob("Intake Label Needs Triage / label", "failure"),
];
const intakeRun = (id, opts = {}) => run(id, MAIN_TIP, { path: INTAKE, event: "issues", conclusion: "failure", jobs: LABEL_FAILED, ...opts });

test("a failed first attempt of an intake run whose only failed job is the floor label has its failed jobs re-run once", async () => {
  const { code, failedJobReruns, reruns } = await reconcile({ pulls: [], runs: [intakeRun(301)] });
  assert.equal(code, 0);
  assert.deepEqual(failedJobReruns, [301]);
  assert.deepEqual(reruns, []);
});

test("an intake run from before the job rename, its floor label named intake-label-needs-triage, is re-run the same way", async () => {
  const jobs = [intakeJob("kill-switch", "success"), intakeJob("intake-triage / triage", "success"), intakeJob("intake-label-needs-triage / label", "failure")];
  const { code, failedJobReruns } = await reconcile({ pulls: [], runs: [intakeRun(301, { jobs })] });
  assert.equal(code, 0);
  assert.deepEqual(failedJobReruns, [301]);
});

// rerun-failed-jobs re-runs every failed job, so a run where any other job
// failed (the model triage, a gate) would start that job again as
// github-actions[bot]: only the floor label is re-run here.
test("an intake run where any job but the floor label failed, or none did, is left alone", async () => {
  const runs = [
    intakeRun(301, { jobs: [intakeJob("Kill Switch", "success"), intakeJob("Intake Triage / triage", "failure"), intakeJob("Intake Label Needs Triage / label", "success")] }),
    intakeRun(302, { jobs: [intakeJob("Intake Triage / triage", "failure"), intakeJob("Intake Label Needs Triage / label", "failure")] }),
    intakeRun(303, { jobs: [intakeJob("Born Triaged", "cancelled"), intakeJob("Intake Label Needs Triage / label", "failure")] }),
    intakeRun(304, { jobs: [intakeJob("Apply Verdict", "timed_out"), intakeJob("Intake Label Needs Triage / label", "failure")] }),
    intakeRun(305, { jobs: [] }),
    intakeRun(306, { jobs: [intakeJob("Intake Label Needs Triage Extra / label", "failure")] }),
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
const verdictJob = (failedStep = VERDICT_STOP_STEP, { name = "Post Verify Notes", conclusion = "failure" } = {}) => ({
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
const SWITCHED = [verdictJob(), { id: 4008, name: "Dispatch", status: "completed", conclusion: "skipped", steps: [] }];
const verdictRun = (id, opts = {}) => run(id, MAIN_TIP, { path: FEEDBACK, event: "workflow_run", conclusion: "failure", jobs: SWITCHED, ...opts });

test("a verdict the kill switch kept from its PR is applied once the switch lifts", async () => {
  const { code, failedJobReruns, reruns } = await reconcile({ pulls: [], runs: [verdictRun(401)] });
  assert.equal(code, 0);
  assert.deepEqual(failedJobReruns, [401]);
  assert.deepEqual(reruns, []);
});

test("a stopped verdict from before the job rename, its job named post-verify-notes, is applied the same way", async () => {
  const jobs = [verdictJob(VERDICT_STOP_STEP, { name: "post-verify-notes" }), { id: 4008, name: "dispatch", status: "completed", conclusion: "skipped", steps: [] }];
  const { code, failedJobReruns } = await reconcile({ pulls: [], runs: [verdictRun(401, { jobs })] });
  assert.equal(code, 0);
  assert.deepEqual(failedJobReruns, [401]);
});

// The re-run leaves a pr-feedback-deferred record, so the plan names the
// marker the dispatch tick lists first (feedback-dispatch.mjs DEFERRAL_MARKER).
test("a plan that re-runs a stopped verdict asks for the deferral marker, and one that does not leaves it", async () => {
  assert.equal((await reconcile({ pulls: [], runs: [verdictRun(401)] })).outputs.deferral, "true");
  assert.equal((await reconcile({ pulls: [pr(1)], runs: [run(101, sha(1))] })).outputs.deferral, "");
});

// The burn-rate pacer paces the next scheduled tick only after the workflow's
// `Mark this tick's work done`, which waits on clean (log-api-budget/pace.mjs).
test("only a plan that read every listing writes clean", async (t) => {
  t.mock.method(console, "log", () => {});
  assert.equal((await reconcile({ pulls: [pr(1)], runs: [run(101, sha(1))] })).outputs.clean, "true");
  assert.equal((await reconcile({ pulls: [], runs: lostDay(501) })).outputs.clean, "", "a listing past the page cap");
  assert.equal((await reconcile({ pulls: [pr(1)], runs: [run(101, sha(1))], env: { KILL_SWITCH: "" } })).outputs.clean, "", "the kill switch");
  assert.equal((await reconcile({ pulls: [], runs: [verifyRun(201)], status: statusWith("major_outage") })).outputs.clean, "", "an Actions outage");
});

test("the marker upload comes after the plan and before the act step, kept longer than the record", () => {
  const text = readFileSync(new URL("../../workflows/maintenance-reconcile-lost-runs.yml", import.meta.url), "utf8");
  const mark = text.indexOf("      - name: Mark the deferred verdicts\n");
  assert.ok(text.indexOf("      - name: Find lost runs\n") < mark && mark < text.indexOf("      - name: Re-run lost runs\n"));
  const step = text.slice(mark, text.indexOf("\n\n", mark));
  assert.match(step, /if: steps\.plan\.outputs\.deferral == 'true'\n/);
  assert.match(step, /name: pr-feedback-deferral\n/);
  assert.match(step, /retention-days: 2$/);
  // A failed upload skips the act step (no status function there), so no
  // record is written without its marker.
  assert.match(text, /- name: Re-run lost runs\n {8}if: steps\.pace\.outputs\.paced != 'true' && steps\.recent\.outputs\.skip != 'true'\n/);
});

test("while the kill switch is on, no stopped verdict is read or re-run", async () => {
  const { code, calls } = await reconcile({ pulls: [], runs: [verdictRun(401)], env: { KILL_SWITCH: "" } });
  assert.equal(code, 0);
  assert.deepEqual(calls, []);
});

test("a verdict run that failed anywhere but the kill-switch step, or at attempt 2, is left alone", async () => {
  const runs = [
    verdictRun(401, { jobs: [verdictJob("Download the verdict")] }),
    verdictRun(402, { jobs: [verdictJob(), { id: 4009, name: "Dispatch", status: "completed", conclusion: "failure", steps: [] }] }),
    verdictRun(403, { jobs: [verdictJob(VERDICT_STOP_STEP, { name: "Rerun CI Status" })] }),
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
const PASS_EXPIRES = "2026-10-20T19:30:00.000Z";
// The first 16 hex digits of `printf %s fix/1 | sha256sum`, pr(1)'s head ref.
const FIX_1_DIGEST = "fe65f143bd3d5845";
// The pre-filter's batched answer holds the issues' comment pages only when its
// query asks for them, as GitHub answers only the fields a query names.
const COMMENT_PAGE = "comments(first: 100)";
const prefilterIssue = (query, { comments = [], ...issue }) => (query.includes(COMMENT_PAGE) ? { ...issue, comments: { totalCount: comments.length, nodes: comments } } : issue);

// `updated` is the issue's updatedAt: the edit time by default, else a time
// before the pass. PR `number` is the head under check.
// `started` is the checks run's latest attempt's start: before the pass at
// 19:30 by default, so that pass judged it.
function specChanged({ edited, updated = edited ?? "2026-10-19T00:00:00Z", attempt = 1, started = "2026-10-19T19:10:00Z", pass = true, digest = false, number = 1, extra = 0 } = {}) {
  const head = sha(number);
  const checks = { ...run(601, head, { conclusion: "success", attempt }), run_started_at: started, repository: { full_name: REPO } };
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
    if (named) {
      const artifacts = pass && decodeURIComponent(named[1]) === name ? [{ name, expired: false, expires_at: PASS_EXPIRES, workflow_run: { id: PASS_RUN } }] : [];
      // `extra` artifacts counted but not on the page: a listing that is not whole.
      return { total_count: artifacts.length + extra, artifacts };
    }
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

// A spec that changed again after the recorded re-run's pass: the checks run
// at attempt 2 is re-run once more, recorded at attempt 3, and one at attempt
// 3, the cap, is named for a person instead.
test("a pass the spec changed under at attempt 2 re-runs the checks again, recorded at attempt 3", async () => {
  await withTrustedList(async (env) => {
    const { code, outputs, reruns } = await reconcile({ ...specChanged({ edited: "2026-10-19T19:45:00Z", attempt: 2 }).setup, env });
    assert.equal(code, 0);
    assert.deepEqual(reruns, [601]);
    assert.equal(outputs["record-1"], `reconcile-rerun-601-3-${sha(1)}`);
  });
});

// The reconciler's attempt-2 re-run completed and its pr-verify run is still
// queued or judging: the only pass is the one from before that attempt, so
// the spec still reads changed. Nothing is re-run until that verdict lands.
test("a pass from before the checks run's attempt 2 started re-runs nothing while pr-verify judges it", async () => {
  await withTrustedList(async (env) => {
    const dir = tempDir("reconcile-summary-");
    try {
      const summary = path.join(dir, "summary.md");
      writeFileSync(summary, "");
      const { setup, specReads } = specChanged({ edited: "2026-10-19T19:45:00Z", attempt: 2, started: "2026-10-19T19:40:00Z" });
      const { code, outputs, reruns } = await reconcile({ ...setup, env: { ...env, GITHUB_STEP_SUMMARY: summary } });
      assert.equal(code, 0);
      assert.deepEqual(reruns, []);
      assert.equal(outputs["record-1"] ?? "", "");
      assert.deepEqual(specReads, [], "no full spec read for a head still being judged");
      assert.match(readFileSync(summary, "utf8"), /#1: run 601 \(\.github\/workflows\/pr-require-checks\.yml\) attempt 2 has no pass since it started; waiting for pr-verify's verdict on it/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

test("a pass the spec changed under at attempt 3, the cap, re-runs nothing and is named for a person", async () => {
  await withTrustedList(async (env) => {
    const dir = tempDir("reconcile-summary-");
    try {
      const summary = path.join(dir, "summary.md");
      writeFileSync(summary, "");
      const { code, outputs, reruns } = await reconcile({ ...specChanged({ edited: "2026-10-19T19:45:00Z", attempt: 3 }).setup, env: { ...env, GITHUB_STEP_SUMMARY: summary } });
      assert.equal(code, 0);
      assert.deepEqual(reruns, []);
      assert.equal(outputs["record-1"] ?? "", "");
      assert.match(readFileSync(summary, "utf8"), /#1: run 601 \(\.github\/workflows\/pr-require-checks\.yml\) is at attempt 3, the most this workflow records, and its spec changed after the pass; a person re-runs it/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

test("a pass judged after the spec's last change, or no pass, re-runs nothing", async () => {
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
      "past the cap at attempt 4": [{ edited: "2026-10-19T19:45:00Z", attempt: 4 }, [], 0, 0],
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

// The pass read the settled carry holds for pr(1)'s head: run 701 started at
// `started`, its pass expiring at `expires`.
const passCarry = (started = PASS_STARTED, expires = PASS_EXPIRES) => ({ pr: 1, head: sha(1), runs: [{ id: PASS_RUN, started_at: started }], expires_at: expires });
const passRunReads = (calls) => calls.filter((c) => c === `GET /repos/${REPO}/actions/runs/${PASS_RUN}`).length;
// The checks run was created at 18:59:43 and the pass started at 19:30; a
// spec edited at 19:15 moved after the checks run but not after the pass.
const EDITED_BEFORE_PASS = "2026-10-19T19:15:00Z";

test("a whole pass read is carried, and the next pass pre-filters the head on it without reading its passes", async () => {
  await withTrustedList(async (env) => {
    const first = specChanged({ edited: EDITED_BEFORE_PASS });
    const read = await reconcile({ ...first.setup, env, carry: null });
    assert.equal(read.code, 0);
    assert.deepEqual(read.reruns, []);
    assert.equal(first.passReads.length, 2, "the pass and pass-notes listings");
    assert.equal(passRunReads(read.calls), 1);
    assert.deepEqual(read.settled.passes, [passCarry()]);
    const second = specChanged({ edited: EDITED_BEFORE_PASS });
    const carried = await reconcile({ ...second.setup, env, carry: carryOf([], SETTLED_VERSION, [], [passCarry()]) });
    assert.equal(carried.code, 0);
    assert.deepEqual(carried.reruns, []);
    assert.equal(second.passReads.length, 0, "no pass listing");
    assert.equal(passRunReads(carried.calls), 0, "no pass run read");
    assert.deepEqual(second.specReads, []);
    assert.deepEqual(carried.settled.passes, [passCarry()], "the carried read is carried again");
  });
});

test("a carried pass read the pre-filter keeps is read again live and decides as a live read does", async () => {
  await withTrustedList(async (env) => {
    // The spec moved after the carried pass: read live, and re-run as with no carry.
    const moved = specChanged({ edited: "2026-10-19T19:45:00Z" });
    const rerun = await reconcile({ ...moved.setup, env, carry: carryOf([], SETTLED_VERSION, [], [passCarry()]) });
    assert.deepEqual(rerun.reruns, [601]);
    assert.equal(moved.passReads.length, 2);
    const uncarried = await reconcile({ ...specChanged({ edited: "2026-10-19T19:45:00Z" }).setup, env, carry: null });
    assert.deepEqual(uncarried.reruns, [601]);
    assert.equal(passRunReads(rerun.calls), passRunReads(uncarried.calls), "the live read reads run 701 as a pass with no carry does");
    // A carry from before a newer pass (19:00, live 19:30): its start keeps
    // the head, the live read drops it, and resolve-pr is never asked.
    const stale = specChanged({ edited: EDITED_BEFORE_PASS });
    const dropped = await reconcile({ ...stale.setup, env, carry: carryOf([], SETTLED_VERSION, [], [passCarry("2026-10-19T19:00:00Z")]) });
    assert.deepEqual(dropped.reruns, []);
    assert.deepEqual(stale.specReads, []);
    assert.equal(stale.passReads.length, 2);
    assert.deepEqual(dropped.settled.passes, [passCarry()], "the live read replaces the stale one");
  });
});

test("an expired carried pass, no carried passes, or a listing that is not whole reads the passes as before", async () => {
  await withTrustedList(async (env) => {
    // Expired at 19:59, before NOW (20:00): listed again, but run 701's carried start is not read again.
    const expired = specChanged({ edited: EDITED_BEFORE_PASS });
    const listed = await reconcile({ ...expired.setup, env, carry: carryOf([], SETTLED_VERSION, [], [passCarry(PASS_STARTED, "2026-10-19T19:59:00.000Z")]) });
    assert.deepEqual(listed.reruns, []);
    assert.equal(expired.passReads.length, 2);
    assert.equal(passRunReads(listed.calls), 0);
    const none = specChanged({ edited: EDITED_BEFORE_PASS });
    const plain = await reconcile({ ...none.setup, env, carry: carryOf([]) });
    assert.deepEqual(plain.reruns, []);
    assert.equal(none.passReads.length, 2);
    assert.equal(passRunReads(plain.calls), 1);
    const partial = specChanged({ edited: EDITED_BEFORE_PASS, extra: 1 });
    const cut = await reconcile({ ...partial.setup, env, carry: null });
    assert.deepEqual(cut.reruns, []);
    assert.deepEqual(cut.settled.passes, [], "a listing that is not whole is not carried");
  });
});

// The gate refuses a pull request past TOO_OLD_DAYS with no counted verdict
// at its head `verify:too-old` until a fresh pass there: the head's passed
// checks run is re-run once, recorded, so pr-verify judges it.
test("a pull request past TOO_OLD_DAYS whose head has no verdict re-runs its passed checks once, with a record", async () => {
  await withTrustedList(async (env) => {
    const old = (created, pass = false) => {
      const { setup } = specChanged({ edited: null, pass });
      return { ...setup, pulls: [{ ...pr(1), created_at: created }] };
    };
    // NOW is 2026-10-19T20:00Z: 84 days after 07-27, 79 after 08-01.
    const { code, outputs, reruns } = await reconcile({ ...old("2026-07-27T23:00:00Z"), env });
    assert.equal(code, 0);
    assert.deepEqual(reruns, [601]);
    assert.equal(outputs["record-1"], `reconcile-rerun-601-2-${sha(1)}`);
    assert.deepEqual((await reconcile({ ...old("2026-08-01T00:00:00Z"), env })).reruns, [], "79 days old");
    assert.deepEqual((await reconcile({ ...old("2026-07-27T23:00:00Z", true), env })).reruns, [], "a pass at the head");
  });
});

// After the too-old re-run makes attempt 2, the head has no counted verdict
// until pr-verify judges that attempt, so too-old never takes a re-run attempt:
// a second re-run in that window would spend the reconciler's cap.
test("a pull request past TOO_OLD_DAYS whose checks run is at attempt 2 re-runs nothing", async () => {
  await withTrustedList(async (env) => {
    const { setup } = specChanged({ edited: null, pass: false, attempt: 2, started: "2026-10-19T19:40:00Z" });
    const { code, outputs, reruns } = await reconcile({ ...setup, pulls: [{ ...pr(1), created_at: "2026-07-27T23:00:00Z" }], env });
    assert.equal(code, 0);
    assert.deepEqual(reruns, []);
    assert.equal(outputs["record-1"] ?? "", "");
  });
});

test("TOO_OLD_DAYS is the gate's", () => {
  const gate = readFileSync(new URL("../../../plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py", import.meta.url), "utf8");
  assert.equal(Number(/^TOO_OLD_DAYS = ([0-9]+)$/m.exec(gate)?.[1]), TOO_OLD_DAYS);
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
    // The pulls page, one run listing per head, the cancelled and failure
    // listings for each of pr-verify and pr-review-main, one repository-wide
    // listing for each of the other seven statuses, one held-run listing
    // for each of pr-verify and pr-review-main, one intake listing, one
    // stopped-verdict listing and the one pre-filter query.
    assert.equal(reads.length, 1 + numbers.length + 2 * 2 + 7 + 2 + 1 + 1 + 1);
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
  { id: 501, name: "Lint Repo", status: "completed", conclusion: lane, steps: [] },
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

test("the re-run reads CI Status's kill-switch note, not its alias's", async () => {
  await withLaneList(async (env) => {
    const [lane, gate] = switchJobs();
    const jobs = [lane, { id: 503, name: "ci-status", status: "completed", conclusion: "failure", steps: [], notes: [] }, { ...gate, name: "CI Status" }];
    const { code, failedJobReruns } = await reconcile({ pulls: [lanePr(1)], runs: [failed(101, sha(1), { jobs })], env });
    assert.equal(code, 0);
    assert.deepEqual(failedJobReruns, [101]);
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
      { id: 511, name: "Lint Repo", status: "completed", conclusion: "skipped", steps: [] },
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
  const step = /- name: Fail a lanes App pull request on kill switch, hold path, verifier or veto\n(?:(?:[ ]{8,}.*)?\n)+/.exec(workflow)?.[0] ?? "";
  assert.match(step, /LANES_DISABLED: \$\{\{ vars\.CLAUDE_LANES_DISABLED \}\}/);
  // The step prints merge-holds.mjs switchHold's reason as its error.
  assert.match(step, /const \{ switchHold \} = await import\(/);
  const fail = step.split("\n").findIndex((line) => line.includes('echo "::error::${reason//%/%25}"'));
  assert.ok(fail > 0, "the kill-switch error line is in the step");
  assert.match(step.split("\n")[fail + 1], /^[ ]+exit 1$/);
  const lanes = { number: 1, user: { type: "Bot", id: 7 } };
  assert.ok(switchHold(lanes, { appId: "7", disabled: "true", repoDisabled: "false" }).startsWith(`#1: ${KILL_SWITCH_NOTE} (`));
});

// A ci-status that failed on a pr-unblock stop note (the step ci-status no
// longer has) is not re-run: the reconciler has no stop kind.
const STOP_LINE = (context = "pr-unblock/address-feedback", head = sha(1)) =>
  `'${context}' is failure on ${head}: Lane stopped: feedback-untaken-threads; checked again on a new head. The lane that stopped clears it by running again on this head, or a new head carries none.`;
const stopJobs = ({ notes = [STOP_LINE()] } = {}) => [
  { id: 501, name: "Lint Repo", status: "completed", conclusion: "success", steps: [] },
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

test("a ci-status that failed on a pr-unblock stop note is not re-run, even once the stop cleared", async () => {
  const { code, calls } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: stopJobs() })], statuses: cleared() });
  assert.equal(code, 0);
  assert.deepEqual(calls.filter((c) => c.startsWith("POST ")), []);
  assert.ok(!calls.some((c) => c.includes("/statuses")));
});

// A hosted review run the upstream-status gate stopped: its kill-switch job
// failed at the callers' `Stop on upstream status` step (pr-review-hosted.yml,
// pr-review-security-hosted.yml) and the review job was skipped.
const SECURITY_REVIEW = ".github/workflows/pr-review-security-hosted.yml";
const NPM_COMPONENTS = "https://status.npmjs.org/api/v2/components.json";
// The hosted callers' job names, and the ids a head tested before the rename shows.
const NEW_NAMES = { model: "Resolve Model", kill: "Kill Switch", review: "PR Review" };
const OLD_NAMES = { model: "resolve-model", kill: "kill-switch", review: "pr-review" };
const gatedJobs = ({ stop = "failure", kill = "failure", review = "skipped", names = NEW_NAMES } = {}) => [
  { id: 301, name: names.model, status: "completed", conclusion: "success", steps: [] },
  {
    id: 302,
    name: names.kill,
    status: "completed",
    conclusion: kill,
    steps: [
      { name: "Check the kill switch", status: "completed", conclusion: "success" },
      { name: "Check upstream status", status: "completed", conclusion: "success" },
      { name: "Report the kill switch", status: "completed", conclusion: "skipped" },
      { name: UPSTREAM_STOP_STEP, status: "completed", conclusion: stop },
    ],
  },
  { id: 303, name: `${names.review} / claude-review-status`, status: "completed", conclusion: review, steps: [] },
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

test("a hosted review run from before the job rename, its gate named kill-switch, is re-run the same way", async () => {
  const { code, failedJobReruns } = await reconcile({ pulls: [pr(1)], runs: [gated(201, sha(1), {}, gatedJobs({ names: OLD_NAMES }))] });
  assert.equal(code, 0);
  assert.deepEqual(failedJobReruns, [201]);
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
const stoppedJobs = ({ report = "success", kill = "success", review = "skipped", names = NEW_NAMES } = {}) => [
  { id: 311, name: names.model, status: "completed", conclusion: "success", steps: [] },
  {
    id: 312,
    name: names.kill,
    status: "completed",
    conclusion: kill,
    steps: [
      { name: "Check the kill switch", status: "completed", conclusion: "success" },
      { name: REVIEW_STOP_STEP, status: "completed", conclusion: report },
    ],
  },
  { id: 313, name: names.review, status: "completed", conclusion: review, steps: [] },
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

test("a stopped review run from before the job rename is read by its old job names: re-run when skipped, never when it reviewed", async () => {
  const stopped = await reconcile({ pulls: [pr(1)], runs: [redChecks(101, sha(1)), stoppedRun(201, sha(1), {}, stoppedJobs({ names: OLD_NAMES }))] });
  assert.deepEqual(stopped.reruns, [201]);
  const reviewed = await reconcile({ pulls: [pr(1)], runs: [redChecks(101, sha(1)), stoppedRun(201, sha(1), {}, stoppedJobs({ names: OLD_NAMES, review: "success" }))] });
  assert.deepEqual(reviewed.reruns, []);
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

test("the security lane's own switch keeps its stopped run from a re-run, with no read, once the code review lane has had its", async () => {
  const runs = [redChecks(101, sha(1)), stoppedRun(201, sha(1), { attempt: 2 }), stoppedRun(301, sha(1), { path: SECURITY_REVIEW })];
  const { code, reruns, calls } = await reconcile({ pulls: [pr(1)], runs, env: { CLAUDE_SECURITY_REVIEW_DISABLED: "true" } });
  assert.equal(code, 0);
  assert.deepEqual(reruns, []);
  assert.ok(!calls.some((c) => c.includes("/runs/301/jobs")), JSON.stringify(calls));
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
    [redChecks(101, sha(1)), stoppedRun(201, sha(1), {}, [stoppedJobs()[1], { id: 314, name: "PR Review / claude-review-status", status: "completed", conclusion: "success", steps: [] }])],
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
const carryOf = (runs, version = SETTLED_VERSION, jobs = [], passes = undefined) => JSON.stringify({ version, repository: REPO, runs, jobs, passes });

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
  for (const carry of [
    "not json",
    JSON.stringify({ version: SETTLED_VERSION, repository: "other/repo", runs: SETTLED, jobs: [] }),
    carryOf(SETTLED, SETTLED_VERSION - 1),
    carryOf([202, 302, 401, 402]),
    JSON.stringify({ version: SETTLED_VERSION, repository: REPO, runs: SETTLED }),
    carryOf(SETTLED, SETTLED_VERSION, [{ id: 101, attempt: 1, head: "main", updated_at: "x", jobs: [] }]),
    carryOf(SETTLED, SETTLED_VERSION, [], {}),
    carryOf(SETTLED, SETTLED_VERSION, [], [{ pr: 1, head: sha(1), runs: [], expires_at: PASS_EXPIRES }]),
    carryOf(SETTLED, SETTLED_VERSION, [], [{ pr: 1, head: sha(1), runs: [{ id: PASS_RUN, started_at: null }], expires_at: PASS_EXPIRES }]),
  ]) {
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

test("the carry's run artifacts are listed once, and a listing that gives the carry no id reads every run", async () => {
  const downloads = [];
  const download = (id) => {
    downloads.push(id);
    return carryOf(SETTLED);
  };
  const listed = await reconcile({ pulls: [], runs: settledRuns(), carry: carryOf(SETTLED), download });
  assert.equal(listed.code, 0);
  assert.deepEqual(jobReads(listed.calls), [], "the carried runs are not read again");
  assert.equal(listed.calls.filter((c) => c.includes("/actions/runs/900/artifacts")).length, 1, "one artifact listing of the carry's run");
  assert.deepEqual(downloads, [CARRY_ARTIFACT], "plan downloads artifact 4242 by id");
  const noId = (github) => async (method, apiPath, body) =>
    apiPath === `/repos/${REPO}/actions/runs/900/artifacts?per_page=100` ? { total_count: 1, artifacts: [{ name: "reconcile-settled-runs", expired: false }] } : github(method, apiPath, body);
  const unread = await reconcile({ pulls: [], runs: settledRuns(), carry: carryOf(SETTLED), github: noId, download: () => assert.fail("no id, no download") });
  assert.equal(unread.code, 0);
  assert.deepEqual(jobReads(unread.calls), [202, 302, 401, 402]);
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

test("a lane run deferred for want of a place is not read again while it stays at attempt 1", async () => {
  const lostJob = (id) => [
    {
      id,
      name: "verify",
      status: "completed",
      conclusion: "failure",
      runner_id: 3,
      steps: [
        { name: "Set up job", status: "completed", conclusion: "success" },
        { name: "Check the trigger", status: "completed", conclusion: "failure" },
        { name: "Judge the pull request", status: "completed", conclusion: "skipped" },
        { name: "Upload the verdict", status: "completed", conclusion: "skipped" },
        { name: "Complete job", status: "completed", conclusion: "success" },
      ],
    },
  ];
  // 205 is the oldest and 201 the newest, so oldest first places 205 to 203.
  const lost = (id) => ({ ...verifyRun(id, { conclusion: "failure", created: `2026-10-19T19:0${206 - id}:00Z` }), jobs: lostJob(id * 10) });
  const first = await reconcile({ pulls: [], runs: [201, 202, 203, 204, 205].map(lost), carry: null });
  assert.equal(first.code, 0);
  assert.deepEqual(first.reruns, [205, 204, 203]);
  assert.deepEqual(jobReads(first.calls), [201, 202, 203, 204, 205]);
  // The next pass: the three re-runs finished at attempt 2; 201 and 202 are
  // still lost first attempts and now get their places, from the carried read.
  const rerun = (id) => ({ ...lost(id), conclusion: "success", run_attempt: 2, updated_at: "2026-10-19T19:50:00Z" });
  const second = await reconcile({ pulls: [], runs: [lost(201), lost(202), rerun(203), rerun(204), rerun(205)], carry: JSON.stringify(first.settled) });
  assert.equal(second.code, 0);
  assert.deepEqual(jobReads(second.calls), []);
  assert.deepEqual(second.reruns, [202, 201]);
  // A run deferred twice: the three re-runs are still in flight on the next
  // pass, so 201 and 202 stay deferred, are not read, and keep their carried
  // entries, so the pass after that reads nothing either.
  const running = (id) => ({ ...lost(id), status: "in_progress", conclusion: null, run_attempt: 2, updated_at: "2026-10-19T19:50:00Z" });
  const held = await reconcile({ pulls: [], runs: [lost(201), lost(202), running(203), running(204), running(205)], carry: JSON.stringify(first.settled) });
  assert.equal(held.code, 0);
  assert.deepEqual(jobReads(held.calls), []);
  assert.deepEqual(held.reruns, []);
  assert.deepEqual(
    held.settled.jobs.filter((e) => e.attempt === 1).map((e) => e.id).sort(),
    [201, 202],
    "a run deferred again keeps its carried read",
  );
  const third = await reconcile({ pulls: [], runs: [lost(201), lost(202), running(203), running(204), running(205)], carry: JSON.stringify(held.settled) });
  assert.deepEqual(jobReads(third.calls), []);
  // A run whose listing changed is read again.
  const changed = await reconcile({ pulls: [], runs: [{ ...lost(201), updated_at: "2026-10-19T19:55:00Z" }, lost(202)], carry: JSON.stringify(first.settled) });
  assert.deepEqual(jobReads(changed.calls), [201]);
  assert.deepEqual(changed.reruns, [202, 201]);
});

// An open PR's latest-attempt job reads ride the same carry, keyed on run id
// and attempt, while the head's listing shows that run completed at the same
// attempt, head and updated_at. Each pin compares a pass with the carry
// against the same pass without it (the old path); the call counts are the
// requirement this carry exists for. Jobs follow the REST job shape: a whole
// step list opening with "Set up job" and ending with "Complete job".
const jobStep = (number, name, conclusion) => ({ name, number, status: "completed", conclusion });
const finalJob = (id, name, conclusion, middle) => ({
  id,
  name,
  status: "completed",
  conclusion,
  run_attempt: 1,
  runner_id: 3,
  steps: [jobStep(1, "Set up job", "success"), ...middle.map(([n, c], i) => jobStep(i + 2, n, c)), jobStep(middle.length + 2, "Complete job", "success")],
});
const realJobs = [
  finalJob(8001, "lint-repo", "success", [["Run the linters", "success"]]),
  finalJob(8002, "test-node", "failure", [["Install dependencies", "success"], ["Run the tests", "failure"]]),
  finalJob(8003, "ci-status", "failure", [["Check the lanes", "failure"]]),
];
const infraJobs = [
  finalJob(8001, "lint-repo", "success", [["Run the linters", "success"]]),
  finalJob(8002, "test-node", "failure", [["Install dependencies", "cancelled"], ["Run the tests", "skipped"]]),
  finalJob(8003, "ci-status", "failure", [["Check the lanes", "failure"]]),
];
const latestReads = (calls) => calls.filter((c) => /\/jobs\?filter=latest/.test(c)).map((c) => Number(/runs\/([0-9]+)\//.exec(c)[1]));

test("a red head's job read is carried, and the next pass makes the same plan without reading it", async () => {
  const runs = [failed(101, sha(1), { jobs: realJobs })];
  const first = await reconcile({ pulls: [pr(1)], runs, carry: null });
  assert.equal(first.code, 0);
  assert.deepEqual(latestReads(first.calls), [101]);
  assert.deepEqual(first.failedJobReruns, [101]);
  assert.deepEqual(
    first.settled.jobs.map((e) => [e.id, e.attempt, e.head, e.updated_at, e.jobs.length]),
    [[101, 1, sha(1), "2026-10-19T19:30:00Z", 3]],
  );
  const second = await reconcile({ pulls: [pr(1)], runs, carry: JSON.stringify(first.settled) });
  assert.equal(second.code, 0);
  assert.deepEqual(latestReads(second.calls), []);
  assert.deepEqual(second.failedJobReruns, first.failedJobReruns);
  assert.deepEqual(second.reruns, first.reruns);
  assert.deepEqual(second.settled.jobs, first.settled.jobs);
});

test("a carried job read still waits on the status pages each pass", async () => {
  const runs = [failed(101, sha(1), { jobs: infraJobs })];
  const held = await reconcile({ pulls: [pr(1)], runs, carry: null, upstream: { [NPM_STATUS_URL]: NPM_DOWN, [GITHUB_STATUS_URL]: GITHUB_OK } });
  assert.deepEqual(held.failedJobReruns, []);
  const live = await reconcile({ pulls: [pr(1)], runs, carry: null });
  const carried = await reconcile({ pulls: [pr(1)], runs, carry: JSON.stringify(held.settled) });
  assert.deepEqual(live.failedJobReruns, [101]);
  assert.deepEqual(carried.failedJobReruns, live.failedJobReruns);
  assert.deepEqual(latestReads(carried.calls), []);
});

test("a new attempt, a new run, a changed run or a carry for another head reads the jobs again", async () => {
  const first = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: realJobs })], carry: null });
  const carry = JSON.stringify(first.settled);
  const otherHead = JSON.stringify({ ...first.settled, jobs: first.settled.jobs.map((e) => ({ ...e, head: sha(9) })) });
  const cases = [
    [[failed(101, sha(1), { jobs: realJobs, attempt: 2 })], carry, [101]],
    [[failed(101, sha(1), { jobs: realJobs, updated: "2026-10-19T19:45:00Z" })], carry, [101]],
    [[failed(101, sha(1), { jobs: realJobs }), failed(102, sha(1), { jobs: realJobs, created: "2026-10-19T19:10:00Z" })], carry, [102]],
    [[failed(101, sha(1), { jobs: realJobs })], otherHead, [101]],
  ];
  for (const [runs, given, read] of cases) {
    const live = await reconcile({ pulls: [pr(1)], runs, carry: null });
    const withCarry = await reconcile({ pulls: [pr(1)], runs, carry: given });
    assert.deepEqual(latestReads(withCarry.calls), read);
    assert.deepEqual(withCarry.failedJobReruns, live.failedJobReruns);
    assert.deepEqual(withCarry.reruns, live.reruns);
  }
});

test("a job read that is not whole and final, or is empty, is not carried", async () => {
  const cut = realJobs.map((j) => (j.name === "test-node" ? { ...j, steps: j.steps.slice(0, -1) } : j));
  const unfinished = realJobs.map((j) => (j.name === "lint-repo" ? { ...j, status: "in_progress", conclusion: null } : j));
  for (const jobs of [cut, unfinished, MIXED_JOBS, []]) {
    const { code, settled } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs })], carry: null });
    assert.equal(code, 0);
    assert.deepEqual(settled.jobs, []);
  }
});

// Any PR whose newest pr-require-checks run failed only in ci-status, on its
// first attempt, on the review-lane step's notes that a review had not
// finished or had no run yet: once the newest run of each hosted review on the
// head has completed, PENDING_BACKOFF_MINUTES ago or more, that ci-status is
// re-run, recorded as attempt 2. The notes are the ones pr-require-checks.yml
// writes (pinned below).
const RERUN_NOTE = "ci-status re-runs when the review finishes.";
const PENDING_LINE = (check = "pr-review / claude-review-status", head = sha(1), tail = RERUN_NOTE) =>
  `'${check}' has not finished on ${head} (https://github.com/${REPO}/actions/runs/201). ${tail}`;
const MISSING_NOTE = "ci-status does not wait for a lane with no run; pr-feedback-dispatch re-runs ci-status a few minutes after the review finishes, so no manual re-run is needed.";
const MISSING_LINE = (check = "pr-review / claude-review-status", file = "pr-review-hosted.yml", head = sha(1), tail = MISSING_NOTE) =>
  `'${check}' is missing: no ${file} run on ${head} yet. ${tail}`;
const pendingJobs = (notes = [PENDING_LINE()]) => stopJobs({ notes });
// Both hosted reviews' runs on the head, completed at `updated` unless `status` says otherwise.
const reviewRuns = ({ updated = "2026-10-19T19:30:00Z", status = "completed" } = {}) => [
  run(201, sha(1), { path: REVIEW, conclusion: "success", updated }),
  run(202, sha(1), { path: SECURITY_REVIEW, conclusion: status === "completed" ? "success" : null, status, updated }),
];

test("a ci-status a running or missing review failed is re-run once both reviews finished past the backoff, recorded, for any PR", async () => {
  const notes = [[PENDING_LINE()], [PENDING_LINE(), PENDING_LINE("pr-review-security / security-review")], [MISSING_LINE()], [PENDING_LINE(), MISSING_LINE("pr-review-security / security-review", "pr-review-security-hosted.yml")]];
  for (const lines of notes) {
    const { code, outputs, reruns, failedJobReruns } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: pendingJobs(lines) }), ...reviewRuns()] });
    assert.equal(code, 0);
    assert.deepEqual(failedJobReruns, [101]);
    assert.deepEqual(reruns, []);
    assert.deepEqual(records(outputs), [`reconcile-rerun-101-2-${sha(1)}`, "", ""]);
  }
});

test("a pending-only red on a lanes App PR is a Pending re-run", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  await withLaneList(async (env) => {
    const { code, outputs, failedJobReruns } = await reconcile({ pulls: [lanePr(1)], runs: [failed(101, sha(1), { jobs: pendingJobs() }), ...reviewRuns()], env });
    assert.equal(code, 0);
    assert.deepEqual(failedJobReruns, [101]);
    assert.deepEqual(records(outputs), [`reconcile-rerun-101-2-${sha(1)}`, "", ""]);
  });
  const lines = log.mock.calls.map((c) => String(c.arguments[0]));
  assert.ok(lines.includes("reconcile: #1: re-ran the failed jobs of run 101 (.github/workflows/pr-require-checks.yml) attempt 1: ci-status failed on a review that has since finished"));
  assert.ok(!lines.some((l) => l.includes("kill switch")));
});

test("the pending backoff ends exactly PENDING_BACKOFF_MINUTES after the last review completed", async () => {
  const at = (ms) => new Date(NOW - ms).toISOString().replace(".000Z", "Z");
  const edge = PENDING_BACKOFF_MINUTES * 60_000;
  const ready = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: pendingJobs() }), ...reviewRuns({ updated: at(edge) })] });
  assert.deepEqual(ready.failedJobReruns, [101]);
  const early = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: pendingJobs() }), ...reviewRuns({ updated: at(edge - 1000) })] });
  assert.deepEqual(early.failedJobReruns, []);
  // The last review to finish sets the edge: one lane at it, the other inside it.
  const [code, security] = reviewRuns({ updated: at(edge) });
  const mixed = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { jobs: pendingJobs() }), code, { ...security, updated_at: at(edge - 1000) }] });
  assert.deepEqual(mixed.failedJobReruns, []);
});

test("a pending-review ci-status is not re-run inside the backoff, while a review runs or never ran, at attempt 2, or beside another failure", async () => {
  // 19:50 is ten minutes before NOW, inside the twenty-minute backoff.
  const cases = [
    { runs: [failed(101, sha(1), { jobs: pendingJobs() }), ...reviewRuns({ updated: "2026-10-19T19:50:00Z" })] },
    { runs: [failed(101, sha(1), { jobs: pendingJobs() }), ...reviewRuns({ status: "in_progress" })] },
    { runs: [failed(101, sha(1), { jobs: pendingJobs([MISSING_LINE("pr-review-security / security-review", "pr-review-security-hosted.yml")]) }), reviewRuns()[0]] },
    { runs: [failed(101, sha(1), { jobs: pendingJobs(), attempt: 2 }), ...reviewRuns()] },
    { runs: [failed(101, sha(1), { jobs: pendingJobs([PENDING_LINE(), "the pull request title is not in Conventional Commits form"]) }), ...reviewRuns()] },
    { runs: [failed(101, sha(1), { jobs: pendingJobs([PENDING_LINE(), STOP_LINE()]) }), ...reviewRuns()], statuses: cleared() },
  ];
  for (const setup of cases) {
    const { code, calls } = await reconcile({ pulls: [pr(1)], ...setup });
    assert.equal(code, 0);
    assert.deepEqual(calls.filter((c) => c.startsWith("POST ")), []);
  }
});

test("a lanes App PR's ci-status the kill switch failed at attempt 2 is named for a person, not re-run", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  await withLaneList(async (env) => {
    const { code, calls } = await reconcile({ pulls: [lanePr(1)], runs: [failed(101, sha(1), { jobs: switchJobs(), attempt: 2 })], env });
    assert.equal(code, 0);
    assert.deepEqual(calls.filter((c) => c.startsWith("POST ")), []);
  });
  const lines = log.mock.calls.map((c) => String(c.arguments[0]));
  assert.ok(lines.includes("reconcile: #1: ci-status failed on the kill switch at attempt 2; a re-run needs a person on the trusted-actor list"));
});

test("ci-status's review-lane step still writes the pending and missing notes the reconciler matches", () => {
  const workflow = readFileSync(new URL("../../workflows/pr-require-checks.yml", import.meta.url), "utf8");
  const step = /- name: Require both review lanes on this head\n(?:(?:[ ]{8,}.*)?\n)+/.exec(workflow)?.[0] ?? "";
  const line = step.split("\n").find((l) => l.includes(`has not finished on $HEAD_SHA ($url)`));
  assert.ok(line, "the pending error line is in the step");
  const text = /echo "::error::(.*)"$/.exec(line.trim())?.[1] ?? "";
  const note = /\n[ ]+rerun_note="(.*)"\n/.exec(step)?.[1] ?? "";
  const written = text.replace("$check", "pr-review / claude-review-status").replace("$HEAD_SHA", sha(1)).replace("$url", `https://github.com/${REPO}/actions/runs/201`).replace("$rerun_note", note);
  assert.match(written, PENDING_REVIEW_NOTE);
  assert.equal(written, PENDING_LINE());
  const missing = step.split("\n").find((l) => l.includes("is missing: no $file run on $HEAD_SHA yet."));
  assert.ok(missing, "the missing error line is in the step");
  const absent = (/echo "::error::(.*)"$/.exec(missing.trim())?.[1] ?? "").replace("$check", "pr-review / claude-review-status").replace("$file", "pr-review-hosted.yml").replace("$HEAD_SHA", sha(1)).replace("$missing_note", /\n[ ]+missing_note="(.*)"\n/.exec(step)?.[1] ?? "");
  assert.match(absent, MISSING_REVIEW_NOTE);
  assert.equal(absent, MISSING_LINE());
  // A run from while ci-status waited for running reviews wrote this tail, which still matches.
  const waited = "ci-status waited 480s for it; pr-feedback-dispatch re-runs ci-status a few minutes after the review finishes, so no manual re-run is needed.";
  assert.match(PENDING_LINE(undefined, undefined, waited), PENDING_REVIEW_NOTE);
  assert.match(MISSING_LINE(undefined, undefined, undefined, RERUN_NOTE), MISSING_REVIEW_NOTE);
  assert.match(step, /\n[ ]+exit "\$failed"\n/);
});

test("the pending backoff is at least rerun-ci-status's time limit", () => {
  const workflow = readFileSync(new URL("../../workflows/pr-feedback-dispatch.yml", import.meta.url), "utf8");
  const job = /\n {2}rerun-ci-status:\n(?:(?: {4}.*)?\n)+/.exec(workflow)?.[0] ?? "";
  const limit = Number(/\n {4}timeout-minutes: ([0-9]+)\n/.exec(job)?.[1]);
  assert.ok(limit > 0, "rerun-ci-status sets timeout-minutes");
  assert.ok(PENDING_BACKOFF_MINUTES >= limit);
});
