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
