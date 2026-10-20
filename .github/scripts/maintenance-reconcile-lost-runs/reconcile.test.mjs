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
import { JUDGE_STEP, main } from "./reconcile.mjs";

const REPO = "melodic-software/claude-code-plugins";
const NOW = Date.parse("2026-10-19T20:00:00Z");
const STATUS = JSON.parse(readFileSync(new URL("./fixtures/components.json", import.meta.url), "utf8"));
const CHECKS = ".github/workflows/pr-require-checks.yml";
const WINDOWS = ".github/workflows/pr-test-windows.yml";
const REVIEW = ".github/workflows/pr-review-hosted.yml";
const VERIFY = ".github/workflows/pr-verify.yml";
const MAIN_TIP = "e".repeat(40);
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
    const byWorkflow = /^\/repos\/[^/]+\/[^/]+\/actions\/workflows\/([a-z0-9-]+\.yml)\/runs\?created=%3E%3D2026-10-18T20%3A00%3A00Z&per_page=100(?:&page=([0-9]+))?$/.exec(path);
    if (method === "GET" && byWorkflow) {
      const found = runs.filter((r) => r.path === `.github/workflows/${byWorkflow[1]}`);
      const page = Number(byWorkflow[2] ?? 1);
      return { total_count: found.length, workflow_runs: found.slice((page - 1) * 100, page * 100) };
    }
    const jobs = /^\/repos\/[^/]+\/[^/]+\/actions\/runs\/([0-9]+)\/attempts\/1\/jobs\?per_page=100$/.exec(path);
    if (method === "GET" && jobs) {
      const found = byId.get(Number(jobs[1]))?.jobs ?? [];
      return { total_count: found.length, jobs: found };
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

// Runs the workflow's two steps: plan, then, when the plan step succeeds,
// act. The upload steps between them read the plan's record-N outputs.
async function reconcile({ pulls, runs, status = STATUS, env = {}, fail, github: wrap = (g) => g } = {}) {
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
    const planCode = await step("plan");
    const planWrites = calls.filter((c) => c.startsWith("POST ")).length;
    const outputs = Object.fromEntries(
      [...readFileSync(files.GITHUB_OUTPUT, "utf8").matchAll(/^([a-z0-9-]+)<<(\S+)\n([^\n]*)\n\2$/gm)].map((m) => [m[1], m[3]]),
    );
    const code = planCode === 0 ? await step("act") : planCode;
    const reruns = calls.filter((c) => c.startsWith("POST ")).map((c) => Number(/runs\/([0-9]+)\/rerun$/.exec(c)[1]));
    return { code, planCode, planWrites, outputs, calls, reruns, sleeps, order };
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
  assert.deepEqual(records(outputs), [`reconcile-rerun-201-2-${MAIN_TIP}`, "", ""]);
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

test("a lane listing of 150 runs over 2 pages finds a lost run on page 2", async () => {
  const lost = verifyRun(201);
  const { code, reruns, calls, outputs } = await reconcile({ pulls: [], runs: verifyDay(150, new Map([[120, lost]])) });
  assert.equal(code, 0);
  assert.deepEqual(reruns, [201]);
  assert.deepEqual(records(outputs).slice(0, 1), [`reconcile-rerun-201-2-${MAIN_TIP}`]);
  assert.equal(calls.filter((c) => c.includes("/workflows/pr-verify.yml/runs?")).length, 2);
});

test("a lane listing past the page cap is a failure, and nothing is called lost", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const { code, reruns } = await reconcile({ pulls: [], runs: verifyDay(501, new Map([[0, verifyRun(201)]])) });
  const lines = log.mock.calls.map((c) => String(c.arguments[0]));
  assert.equal(code, 1);
  assert.deepEqual(reruns, []);
  assert.ok(lines.some((l) => l.startsWith("::error title=reconcile::.github/workflows/pr-verify.yml:") && l.includes("has more than 5 pages")));
  assert.ok(!lines.includes("reconcile: nothing lost"));
  assert.ok(lines.includes("reconcile: 1 listings failed; what was lost is unknown"));
});

test("act says why it exits 1 when the plan recorded listing failures", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const { code } = await reconcile({ pulls: [], runs: verifyDay(501, new Map()) });
  const errors = log.mock.calls.map((c) => String(c.arguments[0])).filter((l) => l.startsWith("::error title=reconcile::the plan step"));
  assert.equal(code, 1);
  assert.deepEqual(errors, ["::error title=reconcile::the plan step recorded 1 listing failures and 0 re-runs failed; see the Find lost runs step"]);
});
