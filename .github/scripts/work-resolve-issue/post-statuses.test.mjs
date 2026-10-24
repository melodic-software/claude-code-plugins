// Expected values come from D30: each step of the work lane posts a
// `pipeline/<activity>` commit status on the lane branch's head SHA. The
// statuses skip nothing (a failing one only holds the merge gate), so the run's own
// prep steps are posted as it reported them, the two lane jobs from their
// GitHub job results, and nothing is posted without a lane branch.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { main, plan } from "./post-statuses.mjs";

const BRANCH = "work-resolve-issue/issue-77-123-1";
const SHA = "c".repeat(40);
const SKIPPED = ["review", "verify", "checks"].map((activity) => ({ activity, result: "skipped" }));
const done = { exit: "done", steps: SKIPPED };

const byContext = (statuses) => Object.fromEntries(statuses.map((s) => [s.context, s.state]));

test("the two lane jobs post their own results", () => {
  const statuses = plan({ outcome: done, branch: BRANCH, resolveResult: "success", reportResult: "failure" });
  assert.deepEqual(byContext(statuses), {
    "pipeline/resolve-issue": "success",
    "pipeline/report-outcome": "failure",
  });
});

test("a run that pushed back or stopped is a failed resolve-issue", () => {
  for (const exit of ["pushback", "stopped"]) {
    const statuses = plan({ outcome: { exit, steps: [] }, branch: BRANCH, resolveResult: "success", reportResult: "success" });
    assert.equal(byContext(statuses)["pipeline/resolve-issue"], "failure", exit);
  }
});

// The plan's fixed text for a run that reached its turn cap: the cause, never
// the run's words, and only when the run left no outcome of its own.
test("a run stopped at its turn cap or time limit says so in the resolve-issue description", () => {
  const unread = { exit: "stopped", steps: [], unread: true };
  const status = (outcome, stop) =>
    plan({ outcome, branch: BRANCH, resolveResult: "failure", reportResult: "success", stop }).find(
      (s) => s.context === "pipeline/resolve-issue",
    );
  assert.deepEqual(status(unread, { cause: "turn-cap", cap: 75 }), {
    context: "pipeline/resolve-issue",
    state: "failure",
    description: "Stopped at the turn cap.",
  });
  assert.equal(status(unread, { cause: "timeout", cap: null }).description, "Stopped at the job's time limit.");
  assert.equal(status(unread, null).description, "Failed in the work lane run.");
  assert.equal(status({ exit: "stopped", steps: [] }, { cause: "turn-cap", cap: 75 }).description, "Failed in the work lane run.");
});

// A funding stop names its cause instead of a failure or the turn cap.
test("a run stopped on the lane's funding says so in the resolve-issue description", () => {
  const unread = { exit: "stopped", steps: [], unread: true };
  const status = plan({ outcome: unread, branch: BRANCH, resolveResult: "failure", reportResult: "success", stop: { cause: "turn-cap", cap: 75 }, funding: { regain: null } }).find(
    (s) => s.context === "pipeline/resolve-issue",
  );
  assert.equal(status.description, "Stopped on the lane's funding.");
});

test("a cancelled or skipped job posts error", () => {
  const statuses = plan({ outcome: done, branch: BRANCH, resolveResult: "cancelled", reportResult: "skipped" });
  assert.deepEqual(byContext(statuses), {
    "pipeline/resolve-issue": "error",
    "pipeline/report-outcome": "error",
  });
});

test("each prep step the run reported posts pass as success and fail as failure", () => {
  const outcome = {
    exit: "done",
    steps: [
      { activity: "review", result: "pass" },
      { activity: "verify", result: "fail" },
      { activity: "checks", result: "pass" },
    ],
  };
  const statuses = plan({ outcome, branch: BRANCH, resolveResult: "success", reportResult: "success" });
  assert.equal(byContext(statuses)["pipeline/review"], "success");
  assert.equal(byContext(statuses)["pipeline/verify"], "failure");
  assert.equal(byContext(statuses)["pipeline/checks"], "success");
});

test("a done run that never reports a prep step posts error for it, failing closed", () => {
  const outcome = {
    exit: "done",
    steps: [
      { activity: "ci-status", result: "pass" },
      { activity: "review/../x", result: "pass" },
      { activity: "verify", result: "skipped" },
      "review",
    ],
  };
  const statuses = plan({ outcome, branch: BRANCH, resolveResult: "success", reportResult: "success" });
  assert.deepEqual(byContext(statuses), {
    "pipeline/resolve-issue": "success",
    "pipeline/report-outcome": "success",
    "pipeline/review": "error",
    "pipeline/checks": "error",
  });
});

test("a step reported twice keeps its strictest result, so a later entry cannot hide a fail", () => {
  for (const later of ["skipped", "pass"]) {
    const outcome = {
      exit: "done",
      steps: [...SKIPPED, { activity: "verify", result: "fail" }, { activity: "verify", result: later }],
    };
    const statuses = plan({ outcome, branch: BRANCH, resolveResult: "success", reportResult: "success" });
    assert.equal(byContext(statuses)["pipeline/verify"], "failure", later);
  }
});

test("a run that did not finish posts no prep status", () => {
  const statuses = plan({ outcome: { exit: "stopped", steps: [] }, branch: BRANCH, resolveResult: "success", reportResult: "success" });
  assert.deepEqual(Object.keys(byContext(statuses)).sort(), ["pipeline/report-outcome", "pipeline/resolve-issue"]);
});

test("no lane branch posts nothing", () => {
  assert.deepEqual(plan({ outcome: done, branch: "", resolveResult: "success", reportResult: "success" }), []);
});

test("the description is fixed text, never the run's own words", () => {
  const outcome = { exit: "done", steps: [{ activity: "review", result: "pass", note: "@someone see #1" }] };
  for (const status of plan({ outcome, branch: BRANCH, resolveResult: "success", reportResult: "success" })) {
    assert.ok(!/[@#]/.test(status.description), status.description);
    assert.ok(status.description.length <= 140);
  }
});

// main against a fake GitHub API: the statuses it posts are the lane's effect
// on the repository, an unmanaged dependency, so they are what the test checks.
function fakeFetch(routes) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    const method = init.method ?? "GET";
    const path = new URL(url).pathname;
    calls.push({ method, path, body: init.body ? JSON.parse(init.body) : undefined });
    const route = routes.find(([m, p]) => m === method && p.test(path));
    const [, , status, body] = route ?? [method, /./, 404, { message: "Not Found" }];
    return { ok: status < 300, status, json: async () => body };
  };
  return { fetch, calls };
}

async function withOutcome(files, run) {
  const dir = mkdtempSync(join(tmpdir(), "statuses-"));
  try {
    for (const [name, text] of Object.entries(files)) {
      writeFileSync(join(dir, name), text);
    }
    return await run(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const env = (dir) => ({
  ISSUE_NUMBER: "77",
  WORK_OUTCOME_DIR: dir,
  GH_TOKEN: "t",
  GITHUB_REPOSITORY: "o/r",
  GITHUB_API_URL: "https://api.example",
  GITHUB_SERVER_URL: "https://example",
  GITHUB_RUN_ID: "123",
  RESOLVE_RESULT: "success",
  REPORT_RESULT: "success",
});

test("main posts each status on the lane branch's head SHA with the run as its target", async () => {
  const outcome = { ...done, steps: [...SKIPPED, { activity: "review", result: "pass" }] };
  await withOutcome(
    { "work-outcome.json": JSON.stringify(outcome), "lane.json": JSON.stringify({ branch: BRANCH }) },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/git\/ref\/heads\/work-resolve-issue\/issue-77-123-1$/, 200, { object: { sha: SHA } }],
        ["POST", new RegExp(`/statuses/${SHA}$`), 201, {}],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      const posted = calls.filter((c) => c.method === "POST");
      assert.deepEqual(posted.map((c) => c.path), Array(3).fill(`/repos/o/r/statuses/${SHA}`));
      assert.deepEqual(byContext(posted.map((c) => c.body)), {
        "pipeline/resolve-issue": "success",
        "pipeline/report-outcome": "success",
        "pipeline/review": "success",
      });
      assert.ok(posted.every((c) => c.body.target_url === "https://example/o/r/actions/runs/123"));
    },
  );
});

test("main posts nothing when lane.json names no lane branch of this issue", async () => {
  await withOutcome(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: "main" }) },
    async (dir) => {
      const { fetch, calls } = fakeFetch([]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      assert.deepEqual(calls, []);
    },
  );
});

// A branch resolve-issue reused from an earlier run whose report this run never
// read: the earlier run may already have posted its statuses on this head
// (its report-statuses ran, its report-outcome failed), and a later status
// with the same context replaces an earlier one, so this run posts only its
// own report-outcome. Its PR carries the hold line, so a human merges it.
const REUSED = "work-resolve-issue/issue-77-400-1";
const UNREPORTED = { "pipeline/report-outcome": "success" };

test("a reused branch with no report of its own posts only report-outcome, leaving the earlier run's statuses", () => {
  for (const reportResult of ["success", "failure"]) {
    const statuses = plan({ outcome: null, branch: REUSED, resolveResult: "success", reportResult });
    assert.deepEqual(byContext(statuses), { "pipeline/report-outcome": reportResult }, reportResult);
  }
});

test("main posts on the reused branch when lane.json names no branch, or another one", async () => {
  for (const files of [{}, { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: BRANCH }) }]) {
    await withOutcome(files, async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/git\/ref\/heads\/work-resolve-issue\/issue-77-400-1$/, 200, { object: { sha: SHA } }],
        ["POST", new RegExp(`/statuses/${SHA}$`), 201, {}],
      ]);
      assert.equal(await main({ env: { ...env(dir), REUSE_BRANCH: REUSED }, fetch }), 0);
      assert.deepEqual(byContext(calls.filter((c) => c.method === "POST").map((c) => c.body)), UNREPORTED);
    });
  }
});

test("main reads the run's own outcome for a reused branch lane.json names", async () => {
  await withOutcome({ "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: REUSED }) }, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/git\/ref\/heads\/work-resolve-issue\/issue-77-400-1$/, 200, { object: { sha: SHA } }],
      ["POST", new RegExp(`/statuses/${SHA}$`), 201, {}],
    ]);
    assert.equal(await main({ env: { ...env(dir), REUSE_BRANCH: REUSED }, fetch }), 0);
    assert.deepEqual(byContext(calls.filter((c) => c.method === "POST").map((c) => c.body)), {
      "pipeline/resolve-issue": "success",
      "pipeline/report-outcome": "success",
    });
  });
});

test("main posts only report-outcome on a reused branch lane.json names whose outcome cannot be read", async () => {
  for (const files of [{}, { "work-outcome.json": "{" }, { "work-outcome.json": JSON.stringify({ exit: "finished" }) }]) {
    await withOutcome({ ...files, "lane.json": JSON.stringify({ branch: REUSED }) }, async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/git\/ref\/heads\/work-resolve-issue\/issue-77-400-1$/, 200, { object: { sha: SHA } }],
        ["POST", new RegExp(`/statuses/${SHA}$`), 201, {}],
      ]);
      assert.equal(await main({ env: { ...env(dir), REUSE_BRANCH: REUSED }, fetch }), 0);
      assert.deepEqual(byContext(calls.filter((c) => c.method === "POST").map((c) => c.body)), UNREPORTED, JSON.stringify(files));
    });
  }
});

test("main refuses a reuse branch that is not this issue's lane branch", async () => {
  await withOutcome({}, async (dir) => {
    const { fetch, calls } = fakeFetch([]);
    assert.equal(await main({ env: { ...env(dir), REUSE_BRANCH: "main" }, fetch }), 1);
    assert.deepEqual(calls, []);
  });
});

test("main fails when the branch head cannot be read", async () => {
  await withOutcome(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: BRANCH }) },
    async (dir) => {
      const { fetch, calls } = fakeFetch([]);
      assert.equal(await main({ env: env(dir), fetch }), 1);
      assert.ok(!calls.some((c) => c.method === "POST"));
    },
  );
});

// A resumed run that committed nothing kept no branch, and report-outcome
// opens its PR from the branch it resumed at the tip run-checks checked, so
// this run's statuses go on that tip, replacing the earlier run's.
const RESUMED = "work-resolve-issue/issue-77-100-1";
const TIP = "e".repeat(40);
const resumedChecks = (branch = RESUMED, results = [{ check: "scripts/check-changelog-fragments.sh --check", exit: 0 }]) =>
  JSON.stringify({ version: 1, branch, tip: TIP, results });
const APP_COMMIT = {
  author: { login: "melodic-automation-lanes[bot]" },
  committer: { login: "web-flow" },
  commit: { verification: { verified: true } },
};
const resumedRoutes = (commits = [APP_COMMIT], refTip = TIP) => [
  ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
  ...(refTip ? [["GET", new RegExp(`/git/ref/heads/${RESUMED}$`), 200, { object: { sha: refTip } }]] : []),
  ["GET", new RegExp(`/compare/main\\.\\.\\.${TIP}$`), 200, { commits, total_commits: commits.length }],
  ["POST", new RegExp(`/statuses/${TIP}$`), 201, {}],
];

test("main posts a resumed run's statuses on the resumed branch's checked tip", async () => {
  await withOutcome(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: "", resume: RESUMED }) },
    async (dir) => {
      const { fetch, calls } = fakeFetch(resumedRoutes());
      const run = { ...env(dir), RESUME_BRANCH: RESUMED, RUNNER_CHECKS: resumedChecks() };
      assert.equal(await main({ env: run, fetch }), 0);
      const posted = calls.filter((c) => c.method === "POST");
      assert.ok(posted.length > 0, "no status was posted");
      assert.ok(posted.every((c) => c.path === `/repos/o/r/statuses/${TIP}`), JSON.stringify(posted.map((c) => c.path)));
      assert.equal(byContext(posted.map((c) => c.body))["pipeline/resolve-issue"], "success");
    },
  );
});

// lane.json can be rewritten by code the model started, so its resume counts
// only when it equals the runner's resume branch and the branch passed the
// gate report-outcome opens its PR on: a check ran, none failed, and every
// commit ahead of the default branch is the lanes App's.
test("main posts nothing for a resumed run whose resume or check results do not match the runner's", async () => {
  for (const [label, resume, runner, checks, commits] of [
    ["a failing check", RESUMED, RESUMED, resumedChecks(RESUMED, [{ check: "x", exit: 1 }])],
    ["no check ran", RESUMED, RESUMED, resumedChecks(RESUMED, [])],
    ["a commit not the App's", RESUMED, RESUMED, resumedChecks(), [APP_COMMIT, { ...APP_COMMIT, author: { login: "stranger" } }]],
    ["no runner resume branch", RESUMED, "", resumedChecks()],
    ["a lane.json resume that is not the runner's", "work-resolve-issue/issue-77-99-1", RESUMED, resumedChecks()],
    ["no check results", RESUMED, RESUMED, ""],
    ["check results for another branch", RESUMED, RESUMED, resumedChecks("work-resolve-issue/issue-77-99-1")],
  ]) {
    await withOutcome(
      { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: "", resume }) },
      async (dir) => {
        const { fetch, calls } = fakeFetch(resumedRoutes(commits));
        assert.equal(await main({ env: { ...env(dir), RESUME_BRANCH: runner, RUNNER_CHECKS: checks }, fetch }), 0, label);
        assert.deepEqual(calls.filter((c) => c.method === "POST"), [], label);
      },
    );
  }
});

// The statuses belong on the tip the PR opens from, so a resumed branch that
// moved past the checked tip, or whose ref cannot be read, gets none.
test("main posts nothing for a resumed branch no longer at the checked tip", async () => {
  for (const [label, refTip] of [
    ["a moved branch", "f".repeat(40)],
    ["an unreadable ref", null],
  ]) {
    await withOutcome(
      { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: "", resume: RESUMED }) },
      async (dir) => {
        const { fetch, calls } = fakeFetch(resumedRoutes([APP_COMMIT], refTip));
        const run = { ...env(dir), RESUME_BRANCH: RESUMED, RUNNER_CHECKS: resumedChecks() };
        assert.equal(await main({ env: run, fetch }), 0, label);
        assert.deepEqual(calls.filter((c) => c.method === "POST"), [], label);
      },
    );
  }
});
