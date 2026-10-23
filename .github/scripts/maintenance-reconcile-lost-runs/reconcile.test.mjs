// Expected values come from the reconciler's spec: a CI run on a PR's current
// head whose newest attempt ended cancelled, timed_out or startup_failure,
// with no newer run of that workflow on the head, is re-run once; at most 3
// PR CI sets are in flight; mutating calls are at least 1 s apart; nothing is
// re-run while githubstatus.com shows Actions as anything but operational.
// Run and PR shapes follow a recorded REST response (a cancelled
// pr-require-checks run, an open PR); fixtures/components.json is a recorded
// githubstatus.com components response, trimmed. A lost pr-verify run is
// re-run only after the plan names its record
// reconcile-rerun-<run id>-2-<head sha> for the upload steps; pr-verify run
// shapes follow a recorded workflow_run run (head_branch main, head_sha the
// main tip, no pull_requests), and only when a job of its first attempt started
// but none started the judge step.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import { createGitHub, GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { GITHUB_STATUS_URL, JUDGE_STEP, main, NPM_STATUS_URL } from "./reconcile.mjs";

const REPO = "melodic-software/claude-code-plugins";
const NOW = Date.parse("2026-10-19T20:00:00Z");
const STATUS = JSON.parse(readFileSync(new URL("./fixtures/components.json", import.meta.url), "utf8"));
const CHECKS = ".github/workflows/pr-require-checks.yml";
const WINDOWS = ".github/workflows/pr-test-windows.yml";
const REVIEW = ".github/workflows/pr-review-hosted.yml";
const VERIFY = ".github/workflows/pr-verify.yml";
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
      return { total_count: found.length, jobs: found };
    }
    const latest = /^\/repos\/[^/]+\/[^/]+\/actions\/runs\/([0-9]+)\/jobs\?filter=latest&per_page=100$/.exec(path);
    if (method === "GET" && latest) {
      const found = byId.get(Number(latest[1]))?.jobs ?? [];
      return { total_count: found.length, jobs: found };
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
async function reconcile({ pulls, runs, status = STATUS, upstream = UPSTREAM_OK, env = {}, fail, github: wrap = (g) => g } = {}) {
  const { github, calls } = fakeGitHub({ pulls, runs, fail });
  const sleeps = [];
  const order = [];
  const tracked = wrap(async (method, path, body) => {
    order.push(method === "GET" ? "read" : "write");
    return github(method, path, body);
  });
  const dir = mkdtempSync(path.join(tmpdir(), "reconcile-"));
  try {
    const files = {
      PLAN_PATH: path.join(dir, "plan.json"),
      RECORD_PATH: path.join(dir, "record.json"),
      GITHUB_OUTPUT: path.join(dir, "output"),
    };
    writeFileSync(files.GITHUB_OUTPUT, "");
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
    return { code, planCode, planWrites, outputs, calls, reruns, failedJobReruns, sleeps, order };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// A first-attempt job of pr-verify, lost before (null) or after its judge step
// started; by default it was lost in the trigger check, before the judge step.
const verifyJob = (judgeConclusion = null) => [
  {
    name: "verify",
    steps: [
      { name: "Set up job", status: "completed", conclusion: "success" },
      { name: "Check the trigger", status: "completed", conclusion: judgeConclusion === null ? "cancelled" : "success" },
      { name: "Judge the pull request", status: judgeConclusion === null ? "pending" : "completed", conclusion: judgeConclusion },
      { name: "Upload the verdict", status: "pending", conclusion: null },
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

test("verify runs that succeeded, failed, are older than the lookback, or ran off main are left alone", async () => {
  const { reruns, outputs } = await reconcile({
    pulls: [],
    runs: [
      verifyRun(201, { conclusion: "success" }),
      verifyRun(202, { conclusion: "failure" }),
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

test("at most 3 verify runs are recorded and re-run in one run", async () => {
  const { reruns, outputs } = await reconcile({
    pulls: [],
    runs: [verifyRun(201), verifyRun(202), verifyRun(203), verifyRun(204)].map((r, i) => ({ ...r, created_at: `2026-10-19T19:0${i}:00Z` })),
  });
  assert.deepEqual(reruns, [201, 202, 203]);
  assert.deepEqual(records(outputs), [201, 202, 203].map((id) => `reconcile-rerun-${id}-2-${MAIN_TIP}`));
});

test("pr-verify still names its judge step as the reconciler reads it", () => {
  const workflow = readFileSync(new URL("../../workflows/pr-verify.yml", import.meta.url), "utf8");
  const stepAt = (name) => {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return workflow.search(new RegExp(`^[ ]*- name: ${escaped}$`, "m"));
  };
  const judge = stepAt(JUDGE_STEP);
  assert.ok(judge >= 0);
  assert.ok(judge < stepAt("Upload the verdict"));
});

test("a verify run whose judge step started is never re-run or recorded", async () => {
  for (const conclusion of ["success", "failure", "cancelled"]) {
    const { code, reruns, outputs } = await reconcile({ pulls: [], runs: [{ ...verifyRun(201), jobs: verifyJob(conclusion) }] });
    assert.equal(code, 0, conclusion);
    assert.deepEqual(reruns, [], conclusion);
    assert.deepEqual(records(outputs), ["", "", ""], conclusion);
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
  assert.deepEqual(reruns, [201]);
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
// at most twice per head, 15 then 30 minutes after the attempt ended, while
// npm and GitHub both report indicator none.
const failed = (id, head, { jobs = INFRA_JOBS, attempt = 1, updated = "2026-10-19T19:30:00Z", ...opts } = {}) =>
  run(id, head, { conclusion: "failure", jobs, attempt, updated, ...opts });

test("an infra-only failed run has its failed jobs re-run", async () => {
  const { code, reruns, failedJobReruns } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1))] });
  assert.equal(code, 0);
  assert.deepEqual(failedJobReruns, [101]);
  assert.deepEqual(reruns, []);
});

// A failed CI run with a real failure (a flaky test the diff did not cause, as
// pr-test-windows run 39867317913's macOS test_tunnel) has its failed jobs
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

test("an infra-only run already at attempt 3 is not re-run again", async () => {
  const { calls } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { attempt: 3 })] });
  assert.deepEqual(calls.filter((c) => c.startsWith("POST ")), []);
});

test("an infra-only run waits 15 minutes after attempt 1 and 30 after attempt 2", async () => {
  const cases = [
    [1, "2026-10-19T19:50:00Z", []],
    [1, "2026-10-19T19:44:00Z", [101]],
    [2, "2026-10-19T19:40:00Z", []],
    [2, "2026-10-19T19:29:00Z", [101]],
  ];
  for (const [attempt, updated, expected] of cases) {
    const { failedJobReruns } = await reconcile({ pulls: [pr(1)], runs: [failed(101, sha(1), { attempt, updated })] });
    assert.deepEqual(failedJobReruns, expected, `attempt ${attempt} ended ${updated}`);
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
const INTAKE = ".github/workflows/intake-label-needs-triage.yml";
const intakeRun = (id, opts = {}) => run(id, MAIN_TIP, { path: INTAKE, event: "issues", conclusion: "failure", ...opts });

test("a failed first attempt of the floor-label run has its failed jobs re-run once", async () => {
  const { code, failedJobReruns, reruns } = await reconcile({ pulls: [], runs: [intakeRun(301)] });
  assert.equal(code, 0);
  assert.deepEqual(failedJobReruns, [301]);
  assert.deepEqual(reruns, []);
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
  assert.deepEqual(records(outputs), [`reconcile-rerun-101-2-${sha(1)}`, `reconcile-rerun-102-2-${sha(2)}`, `reconcile-rerun-103-2-${sha(3)}`]);
  assert.deepEqual(reruns, [101]);
  assert.deepEqual(failedJobReruns, [102, 103]);
});

test("a pr-test-windows re-run and an infra re-run to attempt 3 are not recorded", async () => {
  const runs = [run(101, sha(1), { path: WINDOWS }), failed(102, sha(2), { attempt: 2 })];
  const { code, outputs, reruns, failedJobReruns } = await reconcile({ pulls: [pr(1), pr(2)], runs });
  assert.equal(code, 0);
  assert.deepEqual(records(outputs), ["", "", ""]);
  assert.deepEqual(reruns, [101]);
  assert.deepEqual(failedJobReruns, [102]);
});

test("a PR's CI set carries one record, so the cap of 3 bounds the records at 3", async () => {
  const runs = [1, 2, 3, 4].flatMap((n) => [run(100 + n, sha(n)), run(200 + n, sha(n), { path: WINDOWS })]);
  const { code, outputs, reruns } = await reconcile({ pulls: [pr(1), pr(2), pr(3), pr(4)], runs: [...runs, verifyRun(301)] });
  assert.equal(code, 0);
  assert.deepEqual(records(outputs), [1, 2, 3].map((n) => `reconcile-rerun-${100 + n}-2-${sha(n)}`));
  assert.deepEqual(reruns.sort(), [101, 102, 103, 201, 202, 203]);
});

test("act re-runs no CI run whose plan names another record", async (t) => {
  t.mock.method(console, "log", () => {});
  const { github, calls } = fakeGitHub({ pulls: [pr(1)], runs: [run(101, sha(1))] });
  const dir = mkdtempSync(path.join(tmpdir(), "reconcile-"));
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
