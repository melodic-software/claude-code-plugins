// collect's reads against a fake API whose responses follow the REST shapes
// seen on this repository's runs (workflow_runs, jobs with steps, check-run
// annotations, artifacts, pulls) and githubstatus.com's v2 API.
import assert from "node:assert/strict";
import { test } from "node:test";

import { collect, LIMITS, listFiled } from "./collect.mjs";
import { ceilingFindings } from "./signals.mjs";

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
  status: "completed",
  created_at: "2026-10-19T15:50:00Z",
  updated_at: "2026-10-19T16:00:00Z",
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

// GraphQL answers come from the same REST routes: the open pull request
// list (newest update first) and each PR's comments, oldest first, as
// GraphQL shapes them: a Bot's login without [bot], pages of 100 from the
// newest back, a cursor being the index the page starts at.
const GRAPHQL = "POST /graphql";
const node = (c) => ({
  author: c.user && { __typename: /\[bot\]$/.test(c.user.login) ? "Bot" : "User", login: c.user.login.replace(/\[bot\]$/, "") },
  body: c.body,
  createdAt: c.created_at,
  updatedAt: c.updated_at ?? c.created_at,
  url: c.html_url,
});
const commentPage = (all, before = all.length) => {
  const start = Math.max(0, before - 100);
  return { pageInfo: { hasPreviousPage: start > 0, startCursor: String(start) }, nodes: all.slice(start, before).map(node) };
};

function fakeApi(routes) {
  const calls = [];
  const queries = [];
  const resolve = (path) => {
    for (const [pattern, value] of routes) {
      if (pattern instanceof RegExp && pattern.test(path)) {
        if (value instanceof Error) throw value;
        return typeof value === "function" ? value(path) : value;
      }
    }
    throw new Error(`no route for ${path}`);
  };
  const get = async (path) => {
    calls.push(path);
    return resolve(path);
  };
  const comments = (number) => resolve(`/repos/${repo}/issues/${number}/comments`);
  const graphql = async (query, variables) => {
    calls.push(GRAPHQL);
    queries.push({ query, variables });
    const value = routes.find(([pattern]) => pattern === GRAPHQL)?.[1];
    if (value instanceof Error) throw value;
    const first = /pullRequests\(states: OPEN, baseRefName: "main", first: (\d+)/.exec(query);
    if (first) {
      const pulls = resolve(`/repos/${repo}/pulls?state=open&base=main&sort=updated&direction=desc&per_page=10000&page=1`);
      const nodes = pulls.slice(0, Number(first[1])).map((pull) => ({ number: pull.number, isDraft: pull.draft === true, headRefOid: pull.head.sha, comments: commentPage(comments(pull.number)) }));
      return { data: { repository: { pullRequests: { totalCount: pulls.length, nodes } } } };
    }
    const repository = {};
    for (const [, alias, number, before] of query.matchAll(/(a\d+): pullRequest\(number: (\d+)\) \{ comments\(last: 100, before: "(\d+)"\)/g)) {
      repository[alias] = { comments: commentPage(comments(number), Number(before)) };
    }
    return { data: { repository } };
  };
  return { get, graphql, calls, queries };
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

const laneComment = (id, body, extra = {}) => ({
  id,
  body,
  user: { login: "melodic-automation-lanes[bot]" },
  created_at: "2026-10-19T16:10:00Z",
  issue_url: "https://api.github.com/repos/o/r/issues/7677",
  html_url: `https://github.com/o/r/issues/7677#issuecomment-${id}`,
  ...extra,
});

// report-escalation.sh's lane-stopped comment for `activity` at `head`, last
// edited at `at`.
const sha = (c) => c.repeat(40);
const stopComment = (pr, head, at, { activity = "fix-ci", reason = "ci-fix-invalid", login = "melodic-automation-lanes[bot]" } = {}) => ({
  id: pr * 10,
  body: `<!-- pr-unblock:lane-stopped activity=${activity} -->\nThe pr-unblock lane stopped.\n\n- Reason: \`${reason}\`\n- Head: \`${head}\`\n`,
  user: { login },
  created_at: "2026-10-18T09:00:00Z",
  updated_at: at,
  html_url: `https://github.com/o/r/pull/${pr}#issuecomment-${pr * 10}`,
});
// Open PRs: #8301 stalled (stopped at 12:00, no attempt since); #8302 stopped
// 20 minutes ago; #8303 stopped long ago but retried since; #8304
// Dependabot's, stalled on resolve-conflicts; #8305's comment names an
// older head; #8306's marker is a person's.
const stallRoutes = () => [
  [/\/pulls\?state=open/, [8301, 8302, 8303, 8304, 8305, 8306].map((number) => ({ number, head: { sha: sha(String(number % 10)) } }))],
  [/\/issues\/8301\/comments/, [stopComment(8301, sha("1"), "2026-10-19T12:00:00Z")]],
  [/\/issues\/8302\/comments/, [stopComment(8302, sha("2"), "2026-10-19T16:20:00Z")]],
  [/\/issues\/8303\/comments/, [stopComment(8303, sha("3"), "2026-10-19T12:00:00Z")]],
  [/\/issues\/8304\/comments/, [stopComment(8304, sha("4"), "2026-10-19T11:30:00Z", { activity: "resolve-conflicts", reason: "conflict-patch-invalid" })]],
  [/\/issues\/8305\/comments/, [stopComment(8305, sha("9"), "2026-10-19T10:00:00Z")]],
  [/\/issues\/8306\/comments/, [stopComment(8306, sha("6"), "2026-10-19T10:00:00Z", { login: "someone" })]],
  [/\/commits\/3{40}\/check-runs/, { check_runs: [{ started_at: "2026-10-19T12:30:00Z" }] }],
  [/\/commits\/[0-9a-f]{40}\/check-runs/, { check_runs: [{ started_at: "2026-10-19T11:00:00Z" }] }],
];

const routes = () => [
  ...stallRoutes(),
  [/workflows\/pr-merge\.yml\/runs/, { workflow_runs: [run(10)] }],
  [/runs\/10\/jobs/, { jobs: [{ id: 100, name: "merge", conclusion: "success" }, { id: 101, name: "post-merge-dispatch" }] }],
  [
    /check-runs\/100\/annotations/,
    [
      { annotation_level: "notice", title: "api-budget", message: "end lane core remaining=494 used=4706 limit=5200 reset=2026-10-19T17:00:00Z" },
      { annotation_level: "notice", title: "other", message: "end lane core remaining=0 used=5200 limit=5200 reset=x" },
    ],
  ],
  [/actions\/runs\?status=completed/, { workflow_runs: [] }],
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
        run(51, { name: "pr-test-platforms", head_branch: "gh-readonly-queue/main/pr-8225-aaaa", created_at: "2026-10-19T15:00:00Z" }),
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
  [/actions\/artifacts\?name=pr-merge-post-merge-report/, { artifacts: [artifact(70, "2026-10-19T16:01:00Z", 10)] }],
  [/\/pulls\?state=closed/, [
    { merged_at: "2026-10-19T13:00:00Z", user: { login: "melodic-automation-lanes[bot]" } },
    { merged_at: "2026-10-19T16:00:00Z", user: { login: "dependabot[bot]" } },
    { merged_at: null, user: { login: "melodic-automation-lanes[bot]" } },
  ]],
  [/maintenance-audit-test-selection\.yml\/runs/, { workflow_runs: [run(60, { conclusion: "failure", created_at: "2026-10-19T10:43:00Z" })] }],
  [/runs\/60\/jobs/, { jobs: [{ id: 600, name: "audit-test-selection", conclusion: "failure" }] }],
  [/maintenance-check-upstream-drift\.yml\/runs/, { workflow_runs: [] }],
  [
    /\/issues\/comments\?since=/,
    [
      laneComment(901, "<!-- work-resolve-issue outcome=limited resets=2026-10-19T20:00:00Z run=5 -->\nStopped on the usage limit."),
      laneComment(902, "<!-- work-resolve-issue outcome=done run=6 -->"),
      laneComment(903, "<!-- work-resolve-issue outcome=funding run=7 -->", { user: { login: "someone" } }),
      laneComment(904, "<!-- work-resolve-issue outcome=turn-cap cap=75 run=8 -->", { created_at: "2026-10-19T15:00:00Z" }),
      laneComment(905, "Quoting <!-- work-resolve-issue outcome=funding run=9 -->"),
    ],
  ],
];

// A pr-merge-post-merge-report artifact's two files, as post-merge-dispatch
// writes them: the exit code with a newline, and the check's JSON.
// The reason a real exit-3 report carried (pr-merge run 41067582241, 2026-10-30).
const CAP = "unreadable: post-merge-detect-silent-revert.yml push runs: total_count 1239, 1000 returned, at the 1000-run search cap";
const reportFiles = (code, reason = code === "3" ? CAP : null) => ({
  "post-merge-code": `${code}\n`,
  "post-merge.json": JSON.stringify({ ok: code === "0", readable: code !== "3", reason }),
});

const input = (api, extra = {}) => ({
  get: api.get,
  graphql: api.graphql,
  getStatus: async (url) => status[url],
  readArtifact: async (id, files) =>
    files
      ? reportFiles(id === 70 ? "0" : "3")
      : { run_id: 1000 + id, event: "schedule", live: true, started_at: "2026-10-19T16:30:00Z", candidates: 10, refusal_counts: {}, results: [] },
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
  assert.deepEqual(data.postMergeReports, [
    { runId: 10, url: "https://github.com/o/r/actions/runs/10", code: "0", reason: null, createdAt: "2026-10-19T16:01:00Z" },
  ]);
  assert.deepEqual(data.laneMerges, { lastMergedAt: "2026-10-19T13:00:00Z" });
  assert.deepEqual(
    data.audits.map((a) => [a.workflow, a.run.failedJobs]),
    [["maintenance-audit-test-selection", ["audit-test-selection"]]],
  );
  assert.deepEqual(
    data.status.incidents.map((i) => [i.id, i.components]),
    [["8tzbpcnl75jp", ["Actions", "Webhooks"]]],
  );
  // A stop with no attempt since, past STALLED_HOURS, on any author's PR.
  assert.deepEqual(
    data.stalledStops.map((s) => [s.pr, s.activity, s.reason]),
    [
      [8301, "fix-ci", "ci-fix-invalid"],
      [8304, "resolve-conflicts", "conflict-patch-invalid"],
    ],
  );
  // Only the lanes App's markers created in the window, at the comment's start.
  assert.deepEqual(
    data.laneStops.map((s) => [s.id, s.outcome, s.issue]),
    [
      [901, "limited", 7677],
      [902, "done", 7677],
    ],
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

test("lane stops: full pages inside the window are a gap; a page reaching before it stops the paging", async () => {
  const page = (createdAt) => Array.from({ length: 100 }, (_, i) => laneComment(1000 + i, "", { created_at: createdAt }));
  const full = fakeApi([[/\/issues\/comments\?since=/, page("2026-10-19T16:00:00Z")], ...routes()]);
  const data = await collect(input(full));
  assert.equal(full.calls.filter((p) => p.includes("/issues/comments?")).length, 5);
  assert.ok(data.gaps.some((g) => g.startsWith("lane stops: over 500 comments")));
  const older = fakeApi([[/\/issues\/comments\?since=/, page("2026-10-19T15:00:00Z")], ...routes()]);
  const quiet = await collect(input(older));
  assert.equal(older.calls.filter((p) => p.includes("/issues/comments?")).length, 1);
  assert.ok(!quiet.gaps.some((g) => g.startsWith("lane stops")));
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

const summaryOf = (runId, held) =>
  held
    ? { run_id: runId, event: "schedule", live: true, candidates: null, listing_held: true, listing_held_reason: "failed 3 times", results: [] }
    : { run_id: runId, event: "schedule", live: true, candidates: 3, listing_held: false, listing_held_reason: null, results: [] };
const sweepsOf = (ids) => ({
  artifacts: ids.map((id, i) => artifact(id, `2026-10-19T16:${String(40 - i).padStart(2, "0")}:00Z`, 900 + id)),
  runs: Object.fromEntries(ids.map((id) => [900 + id, prMergeRun(900 + id)])),
});

test("held sweeps are counted newest first, and signals 5 and 8 read the newest sweep that listed", async () => {
  const { artifacts, runs } = sweepsOf([4, 3, 2, 1]);
  const read = [];
  const readArtifact = async (id, files) => {
    if (files) return reportFiles("0");
    read.push(id);
    return summaryOf(900 + id, id > 2);
  };
  const data = await collect(input(fakeApi(sweepRoutes(artifacts, runs)), { readArtifact }));
  assert.deepEqual(data.gaps, []);
  assert.equal(data.sweep.runId, 902);
  assert.equal(data.sweep.candidates, 3);
  assert.deepEqual(data.heldSweeps, [
    { runId: 904, url: "https://github.com/o/r/actions/runs/904", reason: "failed 3 times", createdAt: "2026-10-19T16:40:00Z" },
    { runId: 903, url: "https://github.com/o/r/actions/runs/903", reason: "failed 3 times", createdAt: "2026-10-19T16:39:00Z" },
  ]);
  // The walk stops at the sweep that listed: an older held streak is over.
  assert.deepEqual(read, [4, 3, 2]);
});

test("a held summary from a pull request event neither counts nor resets the streak", async () => {
  const { artifacts, runs } = sweepsOf([4, 3, 2]);
  runs[903] = prMergeRun(903, { event: "pull_request_target" });
  const data = await collect(input(fakeApi(sweepRoutes(artifacts, runs)), { readArtifact: async (id) => summaryOf(900 + id, id !== 2) }));
  assert.deepEqual(data.heldSweeps.map((s) => s.runId), [904]);
  assert.equal(data.sweep.runId, 902);
});

test("a hold that outlasts the sweep age leaves no sweep and a gap for signals 5 and 8; a fresh listed sweep leaves none", async () => {
  const { artifacts, runs } = sweepsOf([7, 6, 5, 4, 3, 2, 1]);
  const readArtifact = async (id, files) => (files ? reportFiles("0") : summaryOf(900 + id, id > 1));
  const fresh = await collect(input(fakeApi(sweepRoutes(artifacts, runs)), { readArtifact }));
  assert.deepEqual(fresh.gaps, []);
  assert.equal(fresh.sweep.runId, 901);
  // 6 held sweeps at the 15-minute cron put the sweep that listed 90 minutes back.
  artifacts[6].created_at = "2026-10-19T15:11:00Z";
  const stale = await collect(input(fakeApi(sweepRoutes(artifacts, runs)), { readArtifact }));
  assert.equal(stale.heldSweeps.length, 6);
  assert.equal(stale.sweep, null);
  assert.deepEqual(stale.gaps, ["pr-merge listed sweep: the newest is over 70 minutes old"]);
});

test("a stale listed sweep with no hold is the same gap: the lane may have stopped writing summaries", async () => {
  const { artifacts, runs } = sweepsOf([1]);
  artifacts[0].created_at = "2026-10-19T15:11:00Z";
  const data = await collect(input(fakeApi(sweepRoutes(artifacts, runs)), { readArtifact: async (id, files) => (files ? reportFiles("0") : summaryOf(900 + id, false)) }));
  assert.equal(data.sweep, null);
  assert.deepEqual(data.heldSweeps, []);
  assert.deepEqual(data.gaps, ["pr-merge listed sweep: the newest is over 70 minutes old"]);
});

test("a hold longer than the read keeps its streak and leaves a gap for signals 5 and 8 alone", async () => {
  const ids = Array.from({ length: LIMITS.sweepArtifacts + 2 }, (_, i) => 20 - i);
  const { artifacts, runs } = sweepsOf(ids);
  const data = await collect(input(fakeApi(sweepRoutes(artifacts, runs)), { readArtifact: async (id) => summaryOf(900 + id, true) }));
  assert.equal(data.sweep, null);
  assert.equal(data.heldSweeps.length, LIMITS.sweepArtifacts);
  assert.deepEqual(data.gaps, [`pr-merge listed sweep: none in the ${LIMITS.sweepArtifacts} newest summaries`]);
});

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

// request-lane-token's notice from a lane run's mint step, as the action
// writes it, and the job carrying that step.
const mintNotice = (remaining, limit = 5200) => ({
  annotation_level: "notice",
  title: "api-budget",
  message: `mint lanes-app core remaining=${remaining} used=${limit - remaining} limit=${limit} reset=2026-10-19T17:00:00Z`,
});
const mintJob = (id, conclusion = "success", name = "run") => ({ id, name, conclusion: "success", steps: [{ name: "Set up job", conclusion: "success" }, { name: "Request the lane token", conclusion }] });
const laneRun = (id, extra = {}) => run(id, { name: "pr-unblock", event: "workflow_run", path: ".github/workflows/pr-unblock.yml", ...extra });

test("a lane run's lanes-app mint notice over 90% becomes a reading the ceiling signal flags", async () => {
  const api = fakeApi([
    [/actions\/runs\?status=completed/, { workflow_runs: [laneRun(80)] }],
    [/runs\/80\/jobs/, { jobs: [mintJob(800), { id: 801, name: "report", conclusion: "success", steps: [] }] }],
    [/check-runs\/800\/annotations/, [mintNotice(494), { annotation_level: "notice", title: "api-budget", message: "end lane core remaining=1 used=5199 limit=5200 reset=x" }]],
    ...routes(),
  ]);
  const data = await collect(input(api, { ownRate: null }));
  assert.deepEqual(data.gaps, []);
  assert.deepEqual(
    data.budgetReadings.map((r) => [r.phase, r.name, r.used, r.limit, r.runId]),
    [
      ["end", "lane", 4706, 5200, 10],
      ["mint", "lanes-app", 4706, 5200, 80],
    ],
  );
  // Only the job whose mint step ran is read.
  assert.ok(!api.calls.some((p) => p.includes("check-runs/801/")));
  const only = ceilingFindings({ now, budgetReadings: data.budgetReadings.filter((r) => r.runId === 80) });
  assert.deepEqual(only.map((f) => f.key), ["ceiling:lanes-app-rest"]);
  assert.match(only[0].facts[0], /^mint lanes-app: used 4706 of 5200 \(90\.5%\) https:\/\/github\.com\/o\/r\/actions\/runs\/80$/);
});

test("a lane run's mint reading at or under 90% is read and not flagged", async () => {
  const api = fakeApi([
    [/actions\/runs\?status=completed/, { workflow_runs: [laneRun(80)] }],
    [/runs\/80\/jobs/, { jobs: [mintJob(800)] }],
    [/check-runs\/800\/annotations/, [mintNotice(520)]],
    ...routes(),
  ]);
  const data = await collect(input(api, { ownRate: null }));
  const readings = data.budgetReadings.filter((r) => r.runId === 80);
  assert.deepEqual(readings.map((r) => r.used), [4680]);
  assert.deepEqual(ceilingFindings({ now, budgetReadings: readings }), []);
});

test("lane quota readings skip branch-code, fork and test-suite runs, failed mint steps, and a trusted pr-merge run's merge job", async () => {
  const api = fakeApi([
    [
      /actions\/runs\?status=completed/,
      {
        workflow_runs: [
          laneRun(81, { event: "pull_request" }),
          laneRun(82, { head_repository: { full_name: "fork/r" } }),
          laneRun(83, { path: ".github/workflows/pr-require-checks.yml" }),
          laneRun(85, { event: "push", head_branch: "feature" }),
          laneRun(86, { event: "pull_request_review" }),
          laneRun(84),
          prMergeRun(10),
        ],
      },
    ],
    [/runs\/84\/jobs/, { jobs: [mintJob(840, "failure")] }],
    [/runs\/10\/jobs/, { jobs: [mintJob(100, "success", "merge")] }],
    [/check-runs\/100\/annotations/, [mintNotice(494), { annotation_level: "notice", title: "api-budget", message: "end lane core remaining=494 used=4706 limit=5200 reset=x" }]],
    ...routes(),
  ]);
  const data = await collect(input(api, { ownRate: null }));
  assert.deepEqual(data.gaps, []);
  assert.ok(!api.calls.some((p) => /runs\/8[12356]\/jobs|check-runs\/840\//.test(p)));
  // pr-merge's merge job counts once, through its own source.
  assert.deepEqual(data.budgetReadings.map((r) => [r.name, r.runId]), [["lanes-app", 10], ["lane", 10]]);
});

test("lane quota readings stop at the run and mint-job caps", async () => {
  const many = Array.from({ length: LIMITS.laneRuns + 5 }, (_, i) => laneRun(3000 + i));
  const api = fakeApi([
    [/actions\/runs\?status=completed/, { workflow_runs: many }],
    [/runs\/3\d{3}\/jobs/, (path) => ({ jobs: [mintJob(Number(/runs\/(\d+)/.exec(path)[1]) * 10), mintJob(Number(/runs\/(\d+)/.exec(path)[1]) * 10 + 1)] })],
    [/check-runs\/3\d{4}\/annotations/, [mintNotice(100)]],
    ...routes(),
  ]);
  const data = await collect(input(api, { ownRate: null }));
  assert.ok(api.calls.filter((p) => /runs\/3\d{3}\/jobs/.test(p)).length <= LIMITS.laneRuns);
  assert.equal(api.calls.filter((p) => /check-runs\/3\d{4}\/annotations/.test(p)).length, LIMITS.laneMintJobs);
  assert.equal(data.budgetReadings.filter((r) => r.name === "lanes-app").length, LIMITS.laneMintJobs);
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

// The failed-runs list served a page at a time, from `pages` (an array of run arrays).
const failedPages = (pages) => [
  /actions\/runs\?status=failure/,
  (path) => ({ workflow_runs: pages[Number(/[?&]page=(\d+)/.exec(path)[1]) - 1] ?? [] }),
];
const forkRuns = (from) =>
  Array.from({ length: 100 }, (_, i) => run(from + i, { name: "pr-unblock", event: "workflow_run", head_repository: { full_name: "fork/r" } }));
const failedCalls = (api) => api.calls.filter((p) => p.includes("/actions/runs?status=failure"));

test("a page of 100 failed fork runs does not hide this repository's failed run on the next page", async () => {
  const api = fakeApi([failedPages([forkRuns(1000), [run(30, { name: "pr-unblock" })]]), ...routes()]);
  const data = await collect(input(api));
  assert.deepEqual(
    data.failedRuns.map((r) => r.id),
    [30],
  );
  assert.equal(failedCalls(api).length, 2);
  assert.deepEqual(data.gaps, []);
});

test("a failed run shifted onto the next page mid-read is kept once", async () => {
  const own = run(30, { name: "pr-unblock" });
  const api = fakeApi([failedPages([[...forkRuns(1000).slice(0, 99), own], [own]]), ...routes()]);
  const data = await collect(input(api));
  assert.deepEqual(
    data.failedRuns.map((r) => r.id),
    [30],
  );
});

test("failed runs: full pages up to the page cap are a gap; enough kept runs stop the paging", async () => {
  const flood = fakeApi([failedPages(Array.from({ length: 10 }, (_, p) => forkRuns(1000 + p * 100))), ...routes()]);
  const data = await collect(input(flood));
  assert.equal(failedCalls(flood).length, 5);
  assert.deepEqual(data.failedRuns, []);
  assert.ok(data.gaps.some((g) => g.startsWith("failed runs: over 500 failed runs")));
  const own = Array.from({ length: 100 }, (_, i) => run(2000 + i, { name: "pr-unblock" }));
  const busy = fakeApi([failedPages([own, own]), [/runs\/2\d{3}\/jobs/, { jobs: [] }], ...routes()]);
  const kept = await collect(input(busy));
  assert.equal(failedCalls(busy).length, 1);
  assert.equal(kept.failedRuns.length, 12);
  assert.deepEqual(kept.gaps, []);
});

test("failed test-suite runs on main are not read as lane runs, so a test named for a 429 files nothing", async () => {
  const api = fakeApi([
    [
      /actions\/runs\?status=failure/,
      {
        workflow_runs: [
          run(35, { name: "pr-require-checks", path: ".github/workflows/pr-require-checks.yml" }),
          run(36, { name: "pr-test-platforms", path: ".github/workflows/pr-test-platforms.yml", event: "workflow_dispatch" }),
          run(30, { name: "pr-unblock" }),
        ],
      },
    ],
    [/runs\/3[56]\/jobs/, { jobs: [{ id: 350, name: "test-bash (1/4)", conclusion: "failure" }] }],
    [/check-runs\/350\/annotations/, [{ annotation_level: "failure", message: "not ok 7 - retries on 429" }]],
    ...routes(),
  ]);
  const data = await collect(input(api));
  assert.deepEqual(
    data.failedRuns.map((r) => r.id),
    [30],
  );
});

// GitHub's `created` range filter, applied the way the runs list applies it.
const createdIn = (path, runs) => {
  const m = /created=([^&.]+)\.\.([^&]+)/.exec(path);
  return { workflow_runs: m ? runs.filter((r) => r.created_at >= m[1] && r.created_at <= m[2]) : runs };
};

test("a run created before the window that completed inside it is read; one completed before it is not", async () => {
  const early = { created_at: "2026-10-19T14:50:00Z", updated_at: "2026-10-19T15:45:00Z" };
  const stale = { created_at: "2026-10-19T14:00:00Z", updated_at: "2026-10-19T14:20:00Z" };
  const api = fakeApi([
    [/workflows\/pr-merge\.yml\/runs/, (path) => createdIn(path, [run(10, early), run(13, stale)])],
    [/actions\/runs\?status=failure/, (path) => createdIn(path, [run(30, { name: "pr-unblock", ...early }), run(34, { name: "pr-unblock", ...stale })])],
    ...routes(),
  ]);
  const data = await collect(input(api, { ownRate: null }));
  assert.deepEqual(data.budgetReadings.map((r) => r.runId), [10]);
  assert.deepEqual(data.failedRuns.map((r) => r.id), [30]);
});

test("listFiled keeps an issue the lane has not touched for over 30 days", async () => {
  const old = { number: 7, updated_at: "2026-08-01T00:00:00Z", body: "x" };
  const api = fakeApi([
    [/\/issues\?/, (path) => {
      const since = /since=([^&]+)/.exec(path)?.[1];
      return since ? [old].filter((i) => i.updated_at >= since) : [old];
    }],
  ]);
  assert.deepEqual((await listFiled({ get: api.get, repo, now })).map((i) => i.number), [7]);
});

test("listFiled reads past 500 newer bot issues to an older muted one", async () => {
  const muted = { number: 1, state: "closed", state_reason: "not_planned", body: "<!-- factory-monitor key=k fp=f -->" };
  const issues = [...Array.from({ length: 500 }, (_, i) => ({ number: 1000 + i, body: "unrelated" })), muted];
  const api = fakeApi([
    [/\/issues\?/, (path) => {
      const page = Number(/[?&]page=(\d+)/.exec(path)[1]);
      return issues.slice((page - 1) * 100, page * 100);
    }],
  ]);
  const filed = await listFiled({ get: api.get, repo });
  assert.equal(filed.length, 501);
  assert.ok(filed.some((i) => i.number === 1));
});

// Only the lane's own issues can be adopted, rewritten, reopened or closed:
// the listing names github-actions[bot] as creator.
test("listFiled lists only github-actions[bot]'s issues", async () => {
  const api = fakeApi([[/\/issues\?/, []]]);
  await listFiled({ get: api.get, repo });
  assert.deepEqual(api.calls.map((path) => new URL(path, "https://x").searchParams.get("creator")), ["github-actions[bot]"]);
});

// GitHub's open pull request list, honoring sort direction, page and per_page.
const openPulls = (pulls) => (path) => {
  const q = new URL(path, "https://x").searchParams;
  const sorted = [...pulls].sort((a, b) => a.updated_at.localeCompare(b.updated_at) * (q.get("direction") === "desc" ? -1 : 1));
  const per = Number(q.get("per_page") ?? 30);
  const page = Number(q.get("page") ?? 1);
  return sorted.slice((page - 1) * per, page * per);
};
const idle = (number, day) => ({ number, head: { sha: sha("e") }, updated_at: `2026-10-${String(day).padStart(2, "0")}T00:00:00Z` });

test("stalled stops: more open PRs than the read covers is a gap naming the true count, and the most recently updated are read", async () => {
  const many = Array.from({ length: 145 }, (_, i) => idle(9000 + i, 1 + (i % 17)));
  const api = fakeApi([[/\/pulls\?state=open/, openPulls(many)], [/\/issues\/9\d{3}\/comments/, []], ...routes()]);
  const data = await collect(input(api));
  assert.ok(data.gaps.some((g) => g === "stalled stops: 145 open pull requests, only the 40 most recently updated read"), data.gaps.join("\n"));
  // One query lists them, newest update first, with their comments.
  assert.equal(api.calls.filter((p) => p === GRAPHQL).length, 1);
  assert.match(api.queries[0].query, /pullRequests\(states: OPEN, baseRefName: "main", first: 40, orderBy: \{ field: UPDATED_AT, direction: DESC \}\)/);
  assert.match(api.queries[0].query, /comments\(last: 100\)/);
  assert.ok(!api.calls.some((p) => /\/pulls\?state=open|\/issues\/\d+\/comments/.test(p)));
});

// Review finding on #10252: the read spent up to 3 + 40 + 20 calls of the
// run's CALL_BUDGET. Worst case now: 145 open PRs, every one stopped long ago
// with no attempt, each with 350 comments so every comment round runs.
test("stalled stops: the worst case spends at most 1 + 2 + 20 calls", async () => {
  const many = Array.from({ length: 145 }, (_, i) => idle(9000 + i, 1 + (i % 17)));
  const chatter = Array.from({ length: 350 }, (_, i) => ({ id: i, body: "chatter", user: { login: "someone" }, created_at: "2026-10-17T00:00:00Z" }));
  const api = fakeApi([
    [/\/pulls\?state=open/, openPulls(many)],
    [/\/issues\/9\d{3}\/comments/, (path) => [...chatter, stopComment(Number(/issues\/(\d+)/.exec(path)[1]), sha("e"), "2026-10-19T10:00:00Z")]],
    [/\/commits\/e{40}\/check-runs/, { check_runs: [] }],
    ...routes(),
  ]);
  const data = await collect(input(api));
  const spent = api.calls.filter((p) => p === GRAPHQL || /\/pulls\?state=open|\/issues\/\d+\/comments|check-runs\?check_name/.test(p)).length;
  assert.ok(spent <= 1 + 2 + 20, `${spent} calls`);
  assert.equal(data.stalledStops.length, 20);
});

// Review finding on #10252: an older head's lane-stopped comment among the
// newest 100 hid the current head's stop in an older comment (edited in place
// at the new stop) and recorded no gap. Only a current-head marker ends the
// read; past the comment rounds, the PR is a gap.
test("stalled stops: an older head's marker does not stop the read before the current head's stop", async () => {
  const chatter = (n) => Array.from({ length: n }, (_, i) => ({ id: i, body: "chatter", user: { login: "someone" }, created_at: "2026-10-18T10:00:00Z" }));
  const current = stopComment(8501, sha("1"), "2026-10-19T12:00:00Z");
  const stale = { ...stopComment(8501, sha("9"), "2026-10-18T12:00:00Z", { activity: "address-feedback", reason: "feedback-partial" }), id: 2 };
  const api = fakeApi([
    [/\/pulls\?state=open/, [{ number: 8501, head: { sha: sha("1") } }, { number: 8502, head: { sha: sha("2") } }]],
    [/\/issues\/8501\/comments/, [current, ...chatter(150), stale, ...chatter(20)]],
    [/\/issues\/8502\/comments/, [stopComment(8502, sha("2"), "2026-10-19T12:00:00Z"), ...chatter(320), { ...stopComment(8502, sha("8"), "2026-10-18T12:00:00Z"), id: 3 }]],
    [/\/commits\/[12]{40}\/check-runs/, { check_runs: [] }],
    ...routes(),
  ]);
  const data = await collect(input(api));
  assert.deepEqual(data.stalledStops.map((s) => [s.pr, s.activity]), [[8501, "fix-ci"]]);
  assert.ok(data.gaps.includes("stalled stops: #8502 has over 300 comments and none names a stop on its head; older ones not read"), data.gaps.join("\n"));
});

// A pull request stopped three hours ago sorts ahead of older idle ones, so
// more than 20 idle pull requests no longer hide it.
test("stalled stops: a freshly stopped PR behind more than 20 idle ones is read and listed", async () => {
  const idlePulls = Array.from({ length: 25 }, (_, i) => idle(9100 + i, 1 + i));
  const fresh = { number: 9200, head: { sha: sha("f") }, updated_at: "2026-10-19T13:30:00Z" };
  const api = fakeApi([
    [/\/pulls\?state=open/, openPulls([...idlePulls, fresh])],
    [/\/issues\/9200\/comments/, [stopComment(9200, sha("f"), "2026-10-19T13:30:00Z")]],
    [/\/issues\/91\d{2}\/comments/, []],
    [/\/commits\/f+\/check-runs/, { check_runs: [] }],
    ...routes(),
  ]);
  const data = await collect(input(api));
  assert.deepEqual(data.stalledStops.map((s) => s.pr), [9200]);
  assert.ok(!data.gaps.some((g) => g.startsWith("stalled stops:")), data.gaps.join("\n"));
});

// Shapes a skip-blind attempt rule missed: a select job's lane-stopped check
// posted after the comment's edit, and a draft's feedback skip (not-applicable
// from the slot's draft predicate). Neither ran the activity, so both stay
// stalled. A label clear-escalations took off for a reason now routed to a
// failing status (#10136's shape: no stop comment on that head) is a stop too,
// except feedback-not-landed, which clears only once its cause is gone.
test("stalled stops: a skip is no attempt, and a cleared fail-routed label is a stop", async () => {
  const skip = (title, at) => ({ conclusion: "neutral", output: { title }, started_at: at });
  const cleared = (pr, head, reason) => ({
    id: pr,
    body: `<!-- pr-pipeline needs-human-cleared reason=${reason} head=${head} -->\nThe pr-unblock lane escalated this pull request.`,
    user: { login: "melodic-automation-lanes[bot]" },
    created_at: "2026-10-19T10:00:00Z",
    html_url: `https://github.com/o/r/pull/${pr}#c`,
  });
  const api = fakeApi([
    [/\/pulls\?state=open/, [8401, 8402, 8403, 8404, 8405, 8406].map((number) => ({ number, draft: number === 8402, head: { sha: sha(String(number % 10)) } }))],
    [/\/issues\/8401\/comments/, [stopComment(8401, sha("1"), "2026-10-19T12:00:00Z", { activity: "resolve-conflicts", reason: "repeat-cap" })]],
    [/\/issues\/8402\/comments/, [stopComment(8402, sha("2"), "2026-10-19T12:00:00Z", { activity: "address-feedback", reason: "feedback-partial" })]],
    [/\/issues\/8403\/comments/, [cleared(8403, sha("3"), "ci-fix-escalated")]],
    [/\/issues\/8404\/comments/, [cleared(8404, sha("4"), "feedback-uncertain")]],
    [/\/issues\/8405\/comments/, Array.from({ length: 350 }, (_, i) => ({ id: i, body: "chatter", user: { login: "someone" } }))],
    [/\/issues\/8406\/comments/, [cleared(8406, sha("6"), "feedback-not-landed")]],
    [/\/commits\/1{40}\/check-runs/, { check_runs: [skip("Skipped: lane-stopped", "2026-10-19T12:00:05Z")] }],
    [/\/commits\/2{40}\/check-runs/, { check_runs: [skip("Skipped: not-applicable", "2026-10-19T12:40:00Z")] }],
    [/\/commits\/3{40}\/check-runs/, { check_runs: [{ conclusion: "success", output: { title: "Fixed" }, started_at: "2026-10-19T09:00:00Z" }] }],
    ...routes(),
  ]);
  const data = await collect(input(api));
  assert.deepEqual(
    data.stalledStops.map((s) => [s.pr, s.activity, s.reason]),
    [
      [8401, "resolve-conflicts", "repeat-cap"],
      [8402, "address-feedback", "feedback-partial"],
      [8403, "fix-ci", "ci-fix-escalated"],
    ],
    "a held reason's clear, and a feedback-not-landed one, is no stop",
  );
  assert.ok(data.gaps.includes("stalled stops: #8405 has over 300 comments and none names a stop on its head; older ones not read"), data.gaps.join("\n"));
});

// A select job that finds the stop gone skips stop-resolved and posts success
// over the failing status, which the monitor cannot read. That skip ends the
// stop when it started after the stop's comment. A not-applicable skip ends
// none: it also covers an owner's untaken threads and a fix-ci skip before
// checks settled. The head's whole listing is never read.
test("stalled stops: only a stop-resolved skip ends an address-feedback or fix-ci stop", async () => {
  const skip = (title, at) => ({ conclusion: "neutral", output: { title }, started_at: at });
  const RESOLVED = "Skipped: stop-resolved";
  const OTHER = "Skipped: not-applicable";
  const stops = { 8601: "address-feedback", 8602: "address-feedback", 8603: "fix-ci", 8604: "fix-ci", 8605: "fix-ci" };
  const seen = {
    8601: skip(RESOLVED, "2026-10-19T12:30:00Z"),
    8602: skip(OTHER, "2026-10-19T12:30:00Z"),
    8603: skip(RESOLVED, "2026-10-19T12:30:00Z"),
    8604: skip(OTHER, "2026-10-19T12:30:00Z"),
    8605: skip(RESOLVED, "2026-10-19T11:30:00Z"),
  };
  const pulls = Object.keys(stops).map(Number);
  const api = fakeApi([
    [/\/pulls\?state=open/, pulls.map((number) => ({ number, draft: false, head: { sha: sha(String(number % 10)) } }))],
    ...pulls.map((pr) => [new RegExp(`/issues/${pr}/comments`), [stopComment(pr, sha(String(pr % 10)), "2026-10-19T12:00:00Z", { activity: stops[pr], reason: "repeat-cap" })]]),
    [/\/commits\/([0-9a-f])\1{39}\/check-runs/, (path) => {
      assert.match(path, /check_name=/, "the head's whole listing is not read");
      return { check_runs: [seen[pulls.find((number) => path.includes(sha(String(number % 10))))]] };
    }],
    ...routes(),
  ]);
  const data = await collect(input(api));
  assert.deepEqual(
    data.stalledStops.map((s) => [s.pr, s.activity]),
    [
      [8602, "address-feedback"],
      [8604, "fix-ci"],
      [8605, "fix-ci"],
    ],
  );
  assert.ok(!data.gaps.some((g) => g.startsWith("stalled stops:")), data.gaps.join("\n"));
});

// Trusted pr-merge runs 10-14 (14 a fork's on its own main, 15 a
// pull_request_target run), each with one post-merge report; runs 11-15
// completed before the window, so the budget source reads no jobs for them.
const reportRoutes = (artifacts) => [
  [
    /workflows\/pr-merge\.yml\/runs/,
    {
      workflow_runs: [
        run(10),
        ...[11, 12, 13].map((id) => run(id, { updated_at: "2026-10-19T15:00:00Z" })),
        run(14, { updated_at: "2026-10-19T15:00:00Z", head_repository: { full_name: "fork/r" } }),
        run(15, { updated_at: "2026-10-19T15:00:00Z", event: "pull_request_target" }),
      ],
    },
  ],
  [/actions\/artifacts\?name=pr-merge-post-merge-report/, { artifacts }],
  ...routes(),
];
const reportArtifact = (runId, minutesAgo) => artifact(runId + 60, new Date(now.getTime() - minutesAgo * 60_000).toISOString(), runId);

test("post-merge reports: four unreadable sweeps in a row are read, newest first, one download each", async () => {
  const api = fakeApi(reportRoutes([10, 11, 12, 13].map((id, i) => reportArtifact(id, 10 + 15 * i))));
  const downloads = [];
  const data = await collect(
    input(api, { readArtifact: async (id, files) => (files ? (downloads.push(id), reportFiles("3")) : { run_id: 1001, live: true, candidates: 1, results: [] }) }),
  );
  assert.deepEqual(data.gaps, []);
  assert.deepEqual(
    data.postMergeReports.map((r) => [r.runId, r.code, r.reason]),
    [10, 11, 12, 13].map((id) => [id, "3", CAP]),
  );
  assert.deepEqual(downloads, [70, 71, 72, 73]);
  // The pr-merge run list is read once for both sources that need it.
  assert.equal(api.calls.filter((p) => p.includes("pr-merge.yml/runs")).length, 1);
  assert.equal(api.calls.filter((p) => p.includes("name=pr-merge-post-merge-report")).length, 1);
});

test("post-merge reports: the read stops at the newest readable report", async () => {
  const api = fakeApi(reportRoutes([10, 11, 12, 13].map((id, i) => reportArtifact(id, 10 + 15 * i))));
  const downloads = [];
  const codes = { 70: "3", 71: "0" };
  const data = await collect(
    input(api, { readArtifact: async (id, files) => (files ? (downloads.push(id), reportFiles(codes[id] ?? "3")) : { run_id: 1001, live: true, candidates: 1, results: [] }) }),
  );
  assert.deepEqual(downloads, [70, 71]);
  assert.deepEqual(
    data.postMergeReports.map((r) => r.code),
    ["3", "0"],
  );
});

test("post-merge reports: a fork's, a pull-request run's or an unlisted run's report is never read", async () => {
  const artifacts = [
    reportArtifact(14, 1),
    reportArtifact(15, 2),
    artifact(99, "2026-10-19T16:39:00Z", 999),
    artifact(98, "2026-10-19T16:38:00Z", 10, { expired: true }),
    ...[10, 11, 12, 13].map((id, i) => reportArtifact(id, 10 + 15 * i)),
  ];
  const downloads = [];
  const data = await collect(
    input(fakeApi(reportRoutes(artifacts)), {
      readArtifact: async (id, files) => (files ? (downloads.push(id), reportFiles("3")) : { run_id: 1001, live: true, candidates: 1, results: [] }),
    }),
  );
  assert.deepEqual(downloads, [70, 71, 72, 73]);
  assert.deepEqual(
    data.postMergeReports.map((r) => r.runId),
    [10, 11, 12, 13],
  );
});

test("post-merge reports: none from the last 70 minutes is a gap, not a clear", async () => {
  for (const artifacts of [[], [reportArtifact(10, 71)]]) {
    const data = await collect(input(fakeApi(reportRoutes(artifacts))));
    assert.deepEqual(data.gaps, ["post-merge reports: no report from a trusted pr-merge run in the last 70 minutes"]);
    assert.deepEqual(data.postMergeReports, []);
  }
});

// post-merge-dispatch keeps its report before the merge and enable-auto-merge
// jobs that need it finish, so the newest report usually comes from a run
// still in progress (#11382 review).
test("post-merge reports: a still-running sweep's report is read first; the budget source waits for it to complete", async () => {
  const routes = reportRoutes([reportArtifact(9, 2), ...[10, 11, 12, 13].map((id, i) => reportArtifact(id, 10 + 15 * i))]);
  const list = routes[0][1].workflow_runs;
  list.unshift(run(9, { status: "in_progress", conclusion: null, updated_at: "2026-10-19T16:40:00Z" }));
  const api = fakeApi(routes);
  const downloads = [];
  const codes = { 69: "0" };
  const data = await collect(
    input(api, { readArtifact: async (id, files) => (files ? (downloads.push(id), reportFiles(codes[id] ?? "3")) : { run_id: 1001, live: true, candidates: 1, results: [] }) }),
  );
  assert.deepEqual(data.gaps, []);
  assert.deepEqual(downloads, [69]);
  assert.deepEqual(
    data.postMergeReports.map((r) => [r.runId, r.code]),
    [[9, "0"]],
  );
  assert.ok(!api.calls.some((p) => p.includes("runs/9/jobs")));
  assert.ok(api.calls.some((p) => p.includes("pr-merge.yml/runs") && !p.includes("status=")));
});
