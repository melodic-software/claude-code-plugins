// collect's reads against a fake API whose responses follow the REST shapes
// seen on this repository's runs (workflow_runs, jobs with steps, check-run
// annotations, artifacts, pulls) and githubstatus.com's v2 API.
import assert from "node:assert/strict";
import { test } from "node:test";

import { collect } from "./collect.mjs";

const repo = "o/r";
const now = new Date("2026-10-19T16:41:00Z");
const windowStart = new Date("2026-10-19T15:36:00Z");
const run = (id, extra = {}) => ({
  id,
  html_url: `https://github.com/o/r/actions/runs/${id}`,
  name: "pr-merge",
  event: "schedule",
  head_branch: "main",
  head_repository: { full_name: repo },
  ...extra,
});
const prMergeRun = (id, extra = {}) => run(id, { path: ".github/workflows/pr-merge.yml", ...extra });
const artifact = (id, created_at, runId, extra = {}) => ({
  id,
  expired: false,
  created_at,
  workflow_run: { id: runId, head_branch: "main" },
  ...extra,
});

function fakeApi(routes) {
  const calls = [];
  const get = async (path) => {
    calls.push(path);
    for (const [pattern, value] of routes) {
      if (pattern.test(path)) {
        if (value instanceof Error) throw value;
        return typeof value === "function" ? value(path) : value;
      }
    }
    throw new Error(`no route for ${path}`);
  };
  return { get, calls };
}

const status = {
  "https://www.githubstatus.com/api/v2/summary.json": {
    components: [{ name: "Actions", status: "operational" }],
    incidents: [],
  },
  "https://www.githubstatus.com/api/v2/incidents.json": {
    incidents: [
      {
        id: "8tzbpcnl75jp",
        name: "Degraded availability",
        status: "resolved",
        created_at: "2026-10-19T15:49:25.828Z",
        components: [{ name: "Actions" }, { name: "Webhooks" }],
      },
      { id: "later", name: "Later", status: "investigating", created_at: "2026-10-19T18:00:00Z", components: [] },
    ],
  },
};

const routes = () => [
  [/workflows\/pr-merge\.yml\/runs/, { workflow_runs: [run(10)] }],
  [/runs\/10\/jobs/, { jobs: [{ id: 100, name: "merge", conclusion: "success" }, { id: 101, name: "post-merge-dispatch" }] }],
  [
    /check-runs\/100\/annotations/,
    [
      { annotation_level: "notice", title: "api-budget", message: "end lane core remaining=494 used=4706 limit=5200 reset=2026-10-19T17:00:00Z" },
      { annotation_level: "notice", title: "other", message: "end lane core remaining=0 used=5200 limit=5200 reset=x" },
    ],
  ],
  [/actions\/runs\?status=in_progress/, { workflow_runs: [run(20)] }],
  [/runs\/20\/jobs/, { jobs: [{ id: 200, status: "in_progress" }, { id: 201, status: "completed" }] }],
  [
    /actions\/runs\?status=failure/,
    { workflow_runs: [run(30, { name: "pr-unblock" }), run(31, { name: "pr-require-checks", event: "pull_request" })] },
  ],
  [/runs\/30\/jobs/, { jobs: [{ id: 300, name: "fix", conclusion: "failure" }, { id: 301, name: "ok", conclusion: "success" }] }],
  [/check-runs\/300\/annotations/, [{ annotation_level: "failure", message: "lane-token-denied: the broker answered 500 with reason unknown" }]],
  [/pr-require-checks\.yml\/runs/, { workflow_runs: [run(40, { event: "workflow_dispatch", conclusion: "cancelled" }), run(41, { event: "workflow_dispatch", conclusion: "success", head_sha: "abc" })] }],
  [
    /event=merge_group/,
    {
      workflow_runs: [
        run(50, { name: "pr-require-checks", head_branch: "gh-readonly-queue/main/pr-8225-aaaa", created_at: "2026-10-19T15:00:00Z" }),
        run(51, { name: "pr-test-windows", head_branch: "gh-readonly-queue/main/pr-8225-aaaa", created_at: "2026-10-19T15:00:00Z" }),
        run(52, { name: "pr-require-checks", head_branch: "gh-readonly-queue/main/pr-8031-bbbb", created_at: "2026-10-19T15:10:00Z" }),
      ],
    },
  ],
  [/runs\/50\/jobs/, { jobs: [{ id: 500, name: "test-bash (1/4)", conclusion: "failure", steps: [{ name: "Run the suites", conclusion: "failure" }, { name: "Set up", conclusion: "success" }] }] }],
  [/runs\/52\/jobs/, { jobs: [{ id: 520, name: "lint", conclusion: "failure", steps: [] }] }],
  [
    /actions\/artifacts\?name=pr-merge-summary/,
    {
      artifacts: [artifact(2, "2026-10-19T17:00:00Z", 1002), artifact(1, "2026-10-19T16:31:00Z", 1001)],
    },
  ],
  [/actions\/runs\/(\d+)$/, (path) => prMergeRun(Number(/(\d+)$/.exec(path)[1]))],
  [/\/pulls\?state=closed/, [
    { merged_at: "2026-10-19T13:00:00Z", user: { login: "melodic-automation-lanes[bot]" } },
    { merged_at: "2026-10-19T16:00:00Z", user: { login: "dependabot[bot]" } },
    { merged_at: null, user: { login: "melodic-automation-lanes[bot]" } },
  ]],
  [/maintenance-audit-test-selection\.yml\/runs/, { workflow_runs: [run(60, { conclusion: "failure", created_at: "2026-10-19T10:43:00Z" })] }],
  [/runs\/60\/jobs/, { jobs: [{ id: 600, name: "audit-test-selection", conclusion: "failure" }] }],
  [/maintenance-check-upstream-drift\.yml\/runs/, { workflow_runs: [] }],
];

const input = (api, extra = {}) => ({
  get: api.get,
  getStatus: async (url) => status[url],
  readArtifact: async (id) => ({ run_id: 1000 + id, event: "schedule", live: true, started_at: "2026-10-19T16:30:00Z", candidates: 10, refusal_counts: {}, results: [] }),
  repo,
  now,
  windowStart,
  agentIdentity: "melodic-automation-lanes[bot]",
  ownRate: { used: 100, limit: 1000, remaining: 900 },
  ...extra,
});

test("collect reads every source into the signals' data shape", async () => {
  const data = await collect(input(fakeApi(routes())));
  assert.deepEqual(data.gaps, []);
  assert.deepEqual(
    data.budgetReadings.map((r) => [r.name, r.used, r.runId]),
    [
      ["lane", 4706, 10],
      ["github-token", 100, null],
    ],
  );
  assert.deepEqual(data.jobsInUse, { inProgress: 1, sampledRuns: 1, truncated: false });
  assert.deepEqual(
    data.failedRuns.map((r) => [r.id, r.annotations.length]),
    [[30, 1]],
  );
  assert.equal(data.mainRun.id, 41);
  assert.deepEqual(
    data.mergeGroupFailures.map((r) => [r.pr, r.failedSteps]),
    [
      [8225, ["test-bash (1/4) / Run the suites"]],
      [8031, ["lint"]],
    ],
  );
  assert.equal(data.sweep.runId, 1001);
  assert.deepEqual(data.laneMerges, { lastMergedAt: "2026-10-19T13:00:00Z" });
  assert.deepEqual(
    data.audits.map((a) => [a.workflow, a.run.failedJobs]),
    [["maintenance-audit-test-selection", ["audit-test-selection"]]],
  );
  assert.deepEqual(
    data.status.incidents.map((i) => [i.id, i.components]),
    [["8tzbpcnl75jp", ["Actions", "Webhooks"]]],
  );
});

test("a replay (no own rate reading) skips the live-only Actions sample", async () => {
  const api = fakeApi(routes());
  const data = await collect(input(api, { ownRate: null }));
  assert.equal(data.jobsInUse, undefined);
  assert.ok(!api.calls.some((p) => p.includes("status=in_progress")));
  assert.deepEqual(
    data.budgetReadings.map((r) => r.name),
    ["lane"],
  );
});

test("a failed source is a gap; the rest still read", async () => {
  const api = fakeApi([[/\/pulls\?state=closed/, new Error("GET /pulls: HTTP 502")], ...routes()]);
  const data = await collect(input(api));
  assert.deepEqual(data.gaps, ["lane merges: GET /pulls: HTTP 502"]);
  assert.equal(data.laneMerges, undefined);
  assert.equal(data.sweep.runId, 1001);
});

const sweepRoutes = (artifacts, runs) => [
  [/actions\/artifacts\?name=pr-merge-summary/, { artifacts }],
  [/actions\/runs\/(\d+)$/, (path) => runs[/(\d+)$/.exec(path)[1]]],
  ...routes(),
];

test("the sweep ignores a newer pr-merge-summary artifact from a fork, PR or branch run", async () => {
  const artifacts = [
    artifact(5, "2026-10-19T16:40:00Z", 905, { workflow_run: { id: 905, head_branch: "attacker" } }),
    artifact(4, "2026-10-19T16:39:00Z", 904),
    artifact(3, "2026-10-19T16:38:00Z", 903),
    artifact(2, "2026-10-19T16:37:00Z", 902),
    artifact(1, "2026-10-19T16:31:00Z", 901),
  ];
  const runs = {
    904: prMergeRun(904, { event: "pull_request_target" }),
    903: prMergeRun(903, { head_repository: { full_name: "fork/r" } }),
    902: run(902, { path: ".github/workflows/other.yml" }),
    901: prMergeRun(901, { event: "workflow_dispatch" }),
  };
  const data = await collect(input(fakeApi(sweepRoutes(artifacts, runs)), { readArtifact: async (id) => ({ run_id: 900 + id, live: true, candidates: 1, results: [] }) }));
  assert.deepEqual(data.gaps, []);
  assert.equal(data.sweep.runId, 901);
  assert.equal(data.sweep.url, "https://github.com/o/r/actions/runs/901");
});

test("fork artifacts on a branch named main cannot push main's summary out of the read cap", async () => {
  const fork = (id, at) =>
    artifact(id, at, 900 + id, { workflow_run: { id: 900 + id, head_branch: "main", repository_id: 1, head_repository_id: 2 } });
  const artifacts = [
    fork(9, "2026-10-19T16:45:00Z"),
    fork(8, "2026-10-19T16:44:00Z"),
    fork(7, "2026-10-19T16:43:00Z"),
    fork(6, "2026-10-19T16:42:00Z"),
    fork(5, "2026-10-19T16:41:00Z"),
    artifact(1, "2026-10-19T16:31:00Z", 901, { workflow_run: { id: 901, head_branch: "main", repository_id: 1, head_repository_id: 1 } }),
  ];
  const runs = { 901: prMergeRun(901) };
  const data = await collect(input(fakeApi(sweepRoutes(artifacts, runs)), { readArtifact: async () => ({ run_id: 901, live: true, candidates: 1, results: [] }) }));
  assert.equal(data.sweep?.runId, 901);
});

test("the sweep rejects a summary whose run_id is not its run's digits", async () => {
  for (const runId of ["901 @someone", "[x](https://evil.example)", "901\n", 902, null]) {
    const api = fakeApi(sweepRoutes([artifact(1, "2026-10-19T16:31:00Z", 901)], { 901: prMergeRun(901) }));
    const data = await collect(input(api, { readArtifact: async () => ({ run_id: runId, live: true, candidates: 1, results: [] }) }));
    assert.equal(data.sweep, null, String(runId));
    assert.equal(data.gaps.length, 1, String(runId));
    assert.ok(!JSON.stringify(data).includes("evil.example"));
  }
});

test("api-budget readings come only from main's scheduled or dispatched pr-merge runs", async () => {
  const api = fakeApi([
    [
      /workflows\/pr-merge\.yml\/runs/,
      { workflow_runs: [run(11, { event: "pull_request_target" }), run(12, { head_branch: "feature" }), run(10)] },
    ],
    ...routes(),
  ]);
  const data = await collect(input(api, { ownRate: null }));
  assert.ok(api.calls.some((p) => p.includes("pr-merge.yml/runs") && p.includes("branch=main")));
  assert.ok(!api.calls.some((p) => /runs\/1[12]\/jobs/.test(p)));
  assert.deepEqual(
    data.budgetReadings.map((r) => r.runId),
    [10],
  );
});

test("failed runs from a fork head are skipped", async () => {
  const api = fakeApi([
    [
      /actions\/runs\?status=failure/,
      {
        workflow_runs: [
          run(32, { name: "pr-unblock", event: "workflow_run", head_repository: { full_name: "fork/r" } }),
          run(33, { name: "pr-unblock", event: "issue_comment", head_repository: null }),
          run(30, { name: "pr-unblock" }),
        ],
      },
    ],
    ...routes(),
  ]);
  const data = await collect(input(api));
  assert.deepEqual(
    data.failedRuns.map((r) => r.id),
    [30],
  );
  assert.ok(!api.calls.some((p) => /runs\/3[23]\/jobs/.test(p)));
});
