// collect's reads against a fake API whose responses follow the REST shapes
// seen on this repository's runs (workflow_runs, jobs with steps, check-run
// annotations, artifacts, pulls) and githubstatus.com's v2 API.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { collect, jobsCarryFile, JOBS_VERSION, LIMITS, listFiled, parseEpisodeCarry, parseHeldCarry, parseJobsCarry, PUBLISH_LANE_LEVEL_JOB, restAnnotations, restJobs, VARIABLE_STEPS } from "./collect.mjs";
import { partlyReadSignals, planIssues, SIGNALS, unreadSignals } from "./issues.mjs";
import { ceilingFindings, detect, laneVariableFindings } from "./signals.mjs";

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

// A nodes(ids:) query answered from the same REST routes, as GraphQL shapes
// them (the recorded pair in "the GraphQL check-run and annotation readers"
// test below): a run's check runs newest first with upper-case enums and no
// steps, a check run's annotations with an upper-case level. An id in `nulls`,
// or one whose REST route fails, answers null with an error naming its index.
const upper = (value) => (typeof value === "string" ? value.toUpperCase() : null);
function nodesAnswer(resolve, query, ids, nulls) {
  const errors = [];
  const nodes = ids.map((id, i) => {
    try {
      if (nulls.has(id)) throw new Error("null");
      const [, kind, n] = /^(WFR|CR)_(\d+)$/.exec(id);
      if (kind === "WFR" && query.includes("... on WorkflowRun")) {
        const jobs = resolve(`/repos/${repo}/actions/runs/${n}/jobs?filter=latest&per_page=100`).jobs ?? [];
        const checkRuns = jobs.map((j) => ({ id: `CR_${j.id}`, databaseId: j.id, name: j.name, status: upper(j.status), conclusion: upper(j.conclusion) })).reverse();
        return { databaseId: Number(n), runAttempt: 1, checkSuite: { checkRuns: { totalCount: checkRuns.length, nodes: checkRuns } } };
      }
      const annotations = resolve(`/repos/${repo}/check-runs/${n}/annotations?per_page=100`) ?? [];
      return { databaseId: Number(n), annotations: { totalCount: annotations.length, nodes: annotations.map((a) => ({ annotationLevel: upper(a.annotation_level), title: a.title ?? null, message: a.message })) } };
    } catch {
      errors.push({ type: "NOT_FOUND", path: ["nodes", i], message: `Could not resolve to a node with the global id of '${id}'` });
      return null;
    }
  });
  return errors.length > 0 ? { data: { nodes }, errors } : { data: { nodes } };
}

// The routes with the ids the GraphQL readers need: each listed run's node id
// and first attempt, and each listed job's node id.
const withNodeIds = (routes) =>
  routes.map(([pattern, value]) => {
    const add = (v) =>
      v?.workflow_runs
        ? { ...v, workflow_runs: v.workflow_runs.map((r) => ({ node_id: `WFR_${r.id}`, run_attempt: 1, ...r })) }
        : v?.jobs
          ? { ...v, jobs: v.jobs.map((j) => ({ node_id: `CR_${j.id}`, ...j })) }
          : v;
    return [pattern, typeof value === "function" ? (path) => add(value(path)) : add(value)];
  });

function fakeApi(routes, { nulls = new Set() } = {}) {
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
    if (query.includes("nodes(ids: $ids)")) return nodesAnswer(resolve, query, variables.ids, nulls);
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
  [/runs\/10\/jobs/, { jobs: [{ id: 100, name: "Merge", conclusion: "success" }, { id: 101, name: "Post Merge Dispatch" }] }],
  [
    /check-runs\/100\/annotations/,
    [
      { annotation_level: "notice", title: "api-budget", message: "end lane core remaining=494 used=4706 limit=5200 reset=2026-10-19T17:00:00Z" },
      { annotation_level: "notice", title: "other", message: "end lane core remaining=0 used=5200 limit=5200 reset=x" },
    ],
  ],
  [/actions\/runs\?status=completed/, { workflow_runs: [] }],
  [/workflows\/work-unblock\.yml\/runs/, { workflow_runs: [] }],
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
  [/runs\/50\/jobs/, { jobs: [{ id: 500, name: "Test Bash (1/4)", conclusion: "failure", steps: [{ name: "Run the suites", conclusion: "failure" }, { name: "Set up", conclusion: "success" }] }] }],
  [/runs\/52\/jobs/, { jobs: [{ id: 520, name: "lint", conclusion: "failure", steps: [] }] }],
  [
    /actions\/artifacts\?name=pr-merge-summary/,
    {
      artifacts: [artifact(2, "2026-10-19T17:00:00Z", 1002), artifact(1, "2026-10-19T16:31:00Z", 1001)],
    },
  ],
  [/actions\/runs\/(\d+)$/, (path) => prMergeRun(Number(/(\d+)$/.exec(path)[1]))],
  [/actions\/artifacts\?name=pr-merge-post-merge-report/, { artifacts: [artifact(70, "2026-10-19T16:01:00Z", 10)] }],
  [/actions\/artifacts\?name=lane-hold-/, { artifacts: [] }],
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
      [8225, ["Test Bash (1/4) / Run the suites"]],
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
    [/runs\/10\/jobs/, { jobs: [mintJob(100, "success", "Merge")] }],
    [/check-runs\/100\/annotations/, [mintNotice(494), { annotation_level: "notice", title: "api-budget", message: "end lane core remaining=494 used=4706 limit=5200 reset=x" }]],
    ...routes(),
  ]);
  const data = await collect(input(api, { ownRate: null }));
  assert.deepEqual(data.gaps, []);
  assert.ok(!api.calls.some((p) => /runs\/8[12356]\/jobs|check-runs\/840\//.test(p)));
  // pr-merge's merge job counts once, through its own source.
  assert.deepEqual(data.budgetReadings.map((r) => [r.name, r.runId]), [["lanes-app", 10], ["lane", 10]]);
});

test("a pr-merge run from before the job rename has its merge job read by its id, once", async () => {
  const api = fakeApi([
    [/actions\/runs\?status=completed/, { workflow_runs: [prMergeRun(10)] }],
    [/runs\/10\/jobs/, { jobs: [mintJob(100, "success", "merge")] }],
    [/check-runs\/100\/annotations/, [mintNotice(494), { annotation_level: "notice", title: "api-budget", message: "end lane core remaining=494 used=4706 limit=5200 reset=x" }]],
    ...routes(),
  ]);
  const data = await collect(input(api, { ownRate: null }));
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
    [/runs\/3[56]\/jobs/, { jobs: [{ id: 350, name: "Test Bash (1/4)", conclusion: "failure" }] }],
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

test("the signal timers round-trip, and a stale, missing or misshapen carry reads as none or throws", () => {
  const signals = { "3 throttling": { onSince: "2026-10-19T15:00:00Z", clearSince: null } };
  const carried = (episodes) => jobsCarryFile(repo, [], undefined, episodes);
  assert.deepEqual(parseEpisodeCarry(carried({ at: "2026-10-19T15:52:00Z", signals }), repo, now), signals);
  assert.deepEqual(parseEpisodeCarry(carried({ at: "2026-10-19T08:00:00Z", signals }), repo, now), {}, "older than the run lookback");
  assert.deepEqual(parseEpisodeCarry(JSON.stringify({ version: 1, repository: repo, runs: [] }), repo, now), {}, "a file from before the carry held timers");
  assert.deepEqual(parseEpisodeCarry(carried(undefined), repo, now), {}, "no timers");
  assert.throws(() => parseEpisodeCarry(carried({ at: "2026-10-19T15:52:00Z", signals }), "other/repo", now), /unexpected shape/);
  assert.throws(() => parseEpisodeCarry(carried({ at: "not a time", signals }), repo, now), /unexpected shape/);
  assert.throws(() => parseEpisodeCarry(carried({ at: "2026-10-19T15:52:00Z", signals: { x: { onSince: "not a time", clearSince: null } } }), repo, now), /unexpected shape/);
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

// A completed run's job read is carried to the next run, keyed on run id and
// attempt, and used while the listing shows the same attempt and updated_at.
// Each pin compares a run with the carry against the same run without it (the
// old path); the call counts are the requirement the carry exists for. Jobs
// follow the REST job shape: a whole step list from "Set up job" to
// "Complete job", with total_count.
const jobStep = (number, name, conclusion) => ({ name, number, status: "completed", conclusion });
const queueJobs = (attempt = 1) => ({
  total_count: 1,
  jobs: [
    {
      id: 500,
      name: "Test Bash (1/4)",
      status: "completed",
      conclusion: "failure",
      run_attempt: attempt,
      steps: [jobStep(1, "Set up job", "success"), jobStep(2, "Run the suites", "failure"), jobStep(3, "Complete job", "success")],
    },
  ],
});
const queueRoutes = ({ attempt = 1, updated = "2026-10-19T15:20:00Z", jobs = queueJobs(attempt) } = {}) => [
  [
    /event=merge_group/,
    { workflow_runs: [run(50, { name: "pr-require-checks", head_branch: "gh-readonly-queue/main/pr-8225-aaaa", created_at: "2026-10-19T15:00:00Z", updated_at: updated, conclusion: "failure", run_attempt: attempt })] },
  ],
  [/runs\/50\/jobs/, jobs],
  [/actions\/runs\?status=in_progress/, { workflow_runs: [run(20, { status: "in_progress", run_attempt: 1 })] }],
  ...routes(),
];
const carried = (data) => parseJobsCarry(jobsCarryFile(repo, data.jobsCarry), repo);
const jobReads = (api) => api.calls.filter((p) => /runs\/\d+\/jobs/.test(p)).map((p) => Number(/runs\/(\d+)\/jobs/.exec(p)[1]));

test("a completed run's job read is carried, and the next run reads the same data without it", async () => {
  const firstApi = fakeApi(queueRoutes());
  const first = await collect(input(firstApi));
  assert.ok(jobReads(firstApi).includes(50));
  assert.deepEqual(
    first.jobsCarry.map((e) => [e.id, e.attempt, e.updated_at, e.jobs.length]),
    [[50, 1, "2026-10-19T15:20:00Z", 1]],
  );
  const api = fakeApi(queueRoutes());
  const second = await collect(input(api, { carriedJobs: carried(first) }));
  assert.ok(!jobReads(api).includes(50));
  assert.equal(api.calls.length, firstApi.calls.length - 1);
  assert.deepEqual(second.mergeGroupFailures, first.mergeGroupFailures);
  assert.deepEqual(second.mergeGroupFailures[0].failedSteps, ["Test Bash (1/4) / Run the suites"]);
  assert.deepEqual(second.jobsCarry, first.jobsCarry);
});

test("a new attempt or a changed run reads its jobs again, and an in-progress run is never carried", async () => {
  const first = await collect(input(fakeApi(queueRoutes())));
  const inProgress = { id: 20, attempt: 1, updated_at: "2026-10-19T16:00:00Z", jobs: [] };
  for (const changed of [{ attempt: 2 }, { updated: "2026-10-19T15:40:00Z" }]) {
    const live = await collect(input(fakeApi(queueRoutes(changed))));
    const api = fakeApi(queueRoutes(changed));
    const data = await collect(input(api, { carriedJobs: new Map([...carried(first), ["20:1", inProgress]]) }));
    assert.ok(jobReads(api).includes(50));
    assert.ok(jobReads(api).includes(20));
    assert.deepEqual(data.mergeGroupFailures, live.mergeGroupFailures);
    assert.deepEqual(data.jobsInUse, live.jobsInUse);
    assert.ok(!data.jobsCarry.some((e) => e.id === 20));
  }
});

test("a job read that is short, unfinished, empty or has a cut step list is not carried", async () => {
  const whole = queueJobs();
  const cases = [
    { ...whole, total_count: 2 },
    { ...whole, jobs: [{ ...whole.jobs[0], status: "in_progress", conclusion: null }] },
    { ...whole, jobs: [{ ...whole.jobs[0], steps: whole.jobs[0].steps.slice(0, -1) }] },
    { ...whole, total_count: 0, jobs: [] },
  ];
  for (const jobs of cases) {
    const data = await collect(input(fakeApi(queueRoutes({ jobs }))));
    assert.deepEqual(data.jobsCarry, []);
  }
});

test("a carried job reads file of another version or repository, or a malformed entry, is refused", () => {
  const entry = { id: 50, attempt: 1, updated_at: "2026-10-19T15:20:00Z", jobs: [] };
  assert.equal(parseJobsCarry(jobsCarryFile(repo, [entry]), repo).get("50:1").id, 50);
  for (const text of [
    JSON.stringify({ version: JOBS_VERSION + 1, repository: repo, runs: [entry] }),
    jobsCarryFile("other/repo", [entry]),
    jobsCarryFile(repo, [{ ...entry, attempt: 0 }]),
  ]) {
    assert.throws(() => parseJobsCarry(text, repo), /unexpected shape/);
  }
});

// Green runs of the three hold lanes: 81 a work-unblock sweep that held twice,
// 82 a pull_request run, never read, and 83 a hold that completed at 15:20,
// before the window, read only when the carry stops short of it; 84 already
// carried; 85 a fault hold; 86 a skipped report job; 87 a pr-refine run with
// no hold notice.
const notice = (title, message) => ({ annotation_level: "notice", title, message });
const holdRoutes = () => [
  [/workflows\/work-resolve-issue\.yml\/runs/, { workflow_runs: [run(84, { event: "issues" }), run(85, { event: "issues" }), run(86, { event: "issues" })] }],
  [/workflows\/work-unblock\.yml\/runs/, { workflow_runs: [run(81), run(82, { event: "pull_request" }), run(83, { updated_at: "2026-10-19T15:20:00Z" })] }],
  [/runs\/83\/jobs/, { jobs: [{ id: 830, name: "Label Unblocked", conclusion: "success" }] }],
  [/check-runs\/830\/annotations/, [notice("label-unblocked", "the agent-ready listing failed (HTTP 502); holding, and the next sweep reads it again")]],
  [/workflows\/pr-refine\.yml\/runs/, { workflow_runs: [run(87, { event: "workflow_dispatch" })] }],
  [/workflows\/intake-triage\.yml\/runs/, { workflow_runs: [] }],
  [/workflows\/pr-verify\.yml\/runs/, { workflow_runs: [] }],
  [/workflows\/pr-review-main\.yml\/runs/, { workflow_runs: [] }],
  [/workflows\/pr-merge\.yml\/runs\?status=/, { workflow_runs: [] }],
  [/runs\/84\/jobs/, { jobs: [] }],
  [/runs\/81\/jobs/, { jobs: [{ id: 810, name: "Label Unblocked", conclusion: "success" }, { id: 811, name: "wip-state", conclusion: "success" }] }],
  [/check-runs\/810\/annotations/, [
    notice("label-unblocked", "the open listing failed (HTTP 502); holding, and the next sweep reads it again"),
    notice("label-unblocked", "the closed-issue listing failed (HTTP 502); holding, and the next sweep reads it again"),
  ]],
  [/runs\/85\/jobs/, { jobs: [{ id: 850, name: "Report Outcome / Run", conclusion: "success" }, { id: 851, name: "Report Outcome / Report", conclusion: "success" }] }],
  [/check-runs\/850\/annotations/, [notice("report-outcome", "issue #812 stopped on a fault (outcome-unread), and every retry since a person last added agent-ready was one too; it keeps agent-ready and a later run tries again")]],
  [/runs\/86\/jobs/, { jobs: [{ id: 860, name: "Report Outcome / Run", conclusion: "skipped" }] }],
  [/runs\/87\/jobs/, { jobs: [{ id: 870, name: "Fix Docs Handoff", conclusion: "success" }] }],
  [/check-runs\/870\/annotations/, [notice("api-budget", "end github-token core remaining=1 used=1 limit=2 reset=x")]],
  ...routes(),
];
const carriedHold = (lane, runId, at) => ({ lane, runId, url: `https://github.com/o/r/actions/runs/${runId}`, item: null, reason: "closed-issue listing failed", at });
// Read without a break since a day and a half ago, through 15:40, after this
// window opened at 15:36.
const CARRIED = {
  runs: [
    carriedHold("work-resolve-issue", 84, "2026-10-19T15:50:00Z"),
    carriedHold("work-unblock", 70, "2026-10-19T09:00:00Z"),
    carriedHold("work-unblock", 71, "2026-10-18T10:00:00Z"),
  ],
  from: "2026-10-18T04:00:00Z",
  through: "2026-10-19T15:40:00Z",
};
const RULE = { threshold: 4, windowHours: 24 };
const SHORT = "lane holds partly read: held runs read only since 2026-10-19T15:36:00Z, short of the 24-hour window";

test("lane holds: green runs in the window add their holds to the carried ones inside the rule's window", async () => {
  const api = fakeApi(holdRoutes());
  const data = await collect(input(api, { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(data.gaps, []);
  assert.deepEqual(
    data.laneHolds.map((h) => [h.lane, h.runId, h.item, h.reason]),
    [
      ["work-resolve-issue", 85, "#812", "fault outcome-unread"],
      ["work-unblock", 81, null, "closed-issue listing failed; open listing failed"],
      ["work-resolve-issue", 84, null, "closed-issue listing failed"],
      ["work-unblock", 70, null, "closed-issue listing failed"],
    ],
  );
  assert.equal(data.laneHolds[0].at, "2026-10-19T16:00:00Z");
  assert.deepEqual(data.heldCarry, {
    runs: data.laneHolds,
    from: CARRIED.from,
    through: "2026-10-19T16:41:00Z",
    scanned: [
      { lane: "work-resolve-issue", runId: 86, at: "2026-10-19T16:00:00Z" },
      { lane: "pr-refine", runId: 87, at: "2026-10-19T16:00:00Z" },
    ],
  });
  assert.deepEqual(data.holdRule, RULE);
  for (const path of ["runs/82/jobs", "runs/83/jobs", "runs/84/jobs", "check-runs/811/", "check-runs/851/", "check-runs/860/"]) {
    assert.ok(!api.calls.some((c) => c.includes(path)), path);
  }
  assert.ok(api.calls.some((c) => c.includes("workflows/pr-refine.yml/runs?status=success")));
  assert.deepEqual(parseHeldCarry(jobsCarryFile(repo, data.jobsCarry, data.heldCarry), repo), data.heldCarry);
});

test("lane holds: a run from before the job rename lists its hold job by id, and its holds are read", async () => {
  const api = fakeApi([[/runs\/81\/jobs/, { jobs: [{ id: 810, name: "label-unblocked", conclusion: "success" }] }], ...holdRoutes()]);
  const data = await collect(input(api, { holds: { rule: RULE, carried: CARRIED } }));
  assert.ok(data.laneHolds.some((h) => h.lane === "work-unblock" && h.runId === 81), JSON.stringify(data.laneHolds));
});

test("lane holds: no carry, a stale one or an unread rule is a gap, and the carried runs still go on", async () => {
  // No carry: this window starts the span, which falls short of 24 hours.
  const uncarried = await collect(input(fakeApi(holdRoutes()), { holds: { rule: RULE, carried: null } }));
  assert.deepEqual(uncarried.gaps, [SHORT]);
  assert.deepEqual(uncarried.laneHolds.map((h) => h.runId), [85, 81]);
  assert.deepEqual([uncarried.heldCarry.from, uncarried.heldCarry.through], ["2026-10-19T15:36:00Z", "2026-10-19T16:41:00Z"]);
  // A late cron: the carry read through 15:00, so runs completed since then are read and the span holds.
  const late = await collect(input(fakeApi(holdRoutes()), { holds: { rule: RULE, carried: { ...CARRIED, through: "2026-10-19T15:00:00Z" } } }));
  assert.deepEqual(late.gaps, []);
  assert.deepEqual(late.laneHolds.map((h) => [h.runId, h.reason]).slice(0, 4), [
    [85, "fault outcome-unread"],
    [81, "closed-issue listing failed; open listing failed"],
    [84, "closed-issue listing failed"],
    [83, "agent-ready listing failed"],
  ]);
  assert.equal(late.heldCarry.from, CARRIED.from);
  // A carry read through 09:00, past the run list's 6-hour lookback: the span starts again.
  const stale = await collect(input(fakeApi(holdRoutes()), { holds: { rule: RULE, carried: { ...CARRIED, through: "2026-10-19T09:00:00Z" } } }));
  assert.deepEqual(stale.gaps, [SHORT]);
  assert.deepEqual(stale.laneHolds.map((h) => h.runId), [85, 81, 84, 70]);
  // An unread rule: this window is still read and carried, unpruned, over the same span.
  const unruled = await collect(input(fakeApi(holdRoutes()), { holds: { rule: new Error("the monitor.lane-holds rule was not read: yq failed"), carried: CARRIED } }));
  assert.deepEqual(unruled.gaps, ["lane holds: the monitor.lane-holds rule was not read: yq failed"]);
  assert.deepEqual(unruled.heldCarry.runs.map((h) => h.runId), [85, 81, 84, 70, 71]);
  assert.equal(unruled.heldCarry.from, CARRIED.from);
  assert.equal(unruled.holdRule, undefined);
  // A failed read keeps the carried runs and marks the span unknown, so the next run starts it again.
  const failed = await collect(
    input(fakeApi([[/work-unblock\.yml\/runs\?event=schedule&branch=main&status=(failure|timed_out)/, { workflow_runs: [] }], [/workflows\/work-unblock\.yml\/runs/, new Error("GET runs: HTTP 502")], ...holdRoutes()]), { holds: { rule: RULE, carried: CARRIED } }),
  );
  assert.deepEqual(failed.gaps, ["lane holds: GET runs: HTTP 502"]);
  assert.deepEqual([failed.heldCarry.runs.map((h) => h.runId), failed.heldCarry.from, failed.heldCarry.through], [[85, 84, 70, 71], null, null]);
  const off = await collect(input(fakeApi(routes())));
  assert.deepEqual([off.gaps, off.laneHolds], [[], []]);
});

// Eight green pr-refine runs completed 15:40 to 16:15, listed newest first,
// the two oldest held, after 908, already carried, at 15:38.
const REFINE_AT = ["15:40", "15:45", "15:50", "15:55", "16:00", "16:05", "16:10", "16:15"];
const refineRoutes = () => [
  [/workflows\/pr-refine\.yml\/runs/, {
    workflow_runs: [...REFINE_AT.map((t, i) => run(900 + i, { event: "workflow_dispatch", updated_at: `2026-10-19T${t}:00Z` })), run(908, { event: "workflow_dispatch", updated_at: "2026-10-19T15:38:00Z" })].reverse(),
  }],
  [/runs\/90[01]\/jobs/, (path) => ({ jobs: [{ id: Number(/runs\/(\d+)/.exec(path)[1]) * 10, name: "Fix Docs Handoff", conclusion: "success" }] })],
  [/check-runs\/90[01]0\/annotations/, [notice("Handoff evidence hold", "handoff evidence for fix-docs still missing after the read")]],
  [/runs\/90\d\/jobs/, { jobs: [] }],
  ...holdRoutes(),
];

test("lane holds: past the cap the oldest unread runs are read, a carried one takes no slot, and the span stops at the last read", async () => {
  const carried = { ...CARRIED, runs: [...CARRIED.runs, carriedHold("pr-refine", 908, "2026-10-19T15:38:00Z")] };
  const api = fakeApi(refineRoutes());
  const data = await collect(input(api, { holds: { rule: RULE, carried } }));
  assert.deepEqual(data.gaps, [`lane holds partly read: over the cap of unread green runs of pr-refine (cap 6); held runs read only through 2026-10-19T16:05:00Z`]);
  assert.deepEqual(data.laneHolds.filter((h) => h.lane === "pr-refine").map((h) => [h.runId, h.reason]), [
    [901, "fix-docs handoff evidence missing"],
    [900, "fix-docs handoff evidence missing"],
    [908, "closed-issue listing failed"],
  ]);
  assert.deepEqual([data.heldCarry.from, data.heldCarry.through], [CARRIED.from, "2026-10-19T16:05:00Z"]);
  for (const id of [906, 907, 908]) assert.ok(!api.calls.some((c) => c.includes(`runs/${id}/jobs`)), id);
  // The next run, an hour on, reads the rest from where this one stopped, and the span holds.
  const later = fakeApi(refineRoutes());
  const next = await collect(input(later, {
    now: new Date("2026-10-19T17:41:00Z"),
    windowStart: new Date("2026-10-19T16:36:00Z"),
    holds: { rule: RULE, carried: data.heldCarry },
  }));
  assert.deepEqual(next.gaps.filter((g) => g.startsWith("lane holds")), []);
  for (const id of [906, 907]) assert.ok(later.calls.some((c) => c.includes(`runs/${id}/jobs`)), id);
  assert.equal(next.heldCarry.through, "2026-10-19T17:41:00Z");
});

// Lane-hold markers: 86, whose report job skipped, so the scan found no hold,
// marked twice; 81, held by the scan; 82, a pull_request run the listing does
// not trust; 999, a run the listing does not hold; 85, marked but expired.
const marker = (id, runId, extra = {}) => ({ id, expired: false, created_at: "2026-10-19T16:00:00Z", workflow_run: { id: runId }, ...extra });
const markerRoutes = () => [
  [/artifacts\?name=lane-hold-work-resolve-issue&/, { artifacts: [marker(1, 86), marker(2, 86), marker(3, 85, { expired: true }), marker(4, 999)] }],
  [/artifacts\?name=lane-hold-work-unblock&/, { artifacts: [marker(5, 81), marker(6, 82)] }],
  ...holdRoutes(),
];

test("lane hold markers: a marked listed run the scan found no hold in counts once; an untrusted, unlisted or expired marker does not", async () => {
  const api = fakeApi(markerRoutes());
  const data = await collect(input(api, { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(data.gaps, []);
  assert.deepEqual(
    data.laneHolds.map((h) => [h.lane, h.runId, h.reason]),
    [
      ["work-resolve-issue", 85, "fault outcome-unread"],
      ["work-unblock", 81, "closed-issue listing failed; open listing failed"],
      ["work-resolve-issue", 86, "hold marker"],
      ["work-resolve-issue", 84, "closed-issue listing failed"],
      ["work-unblock", 70, "closed-issue listing failed"],
    ],
    "86 is added once; 81 keeps the scan's reason; 82, 999 and the expired 85 add nothing",
  );
  assert.ok(!data.heldCarry.scanned.some((s) => s.runId === 86), "a marked run is not carried as read with no hold");
  assert.ok(data.heldCarry.runs.some((h) => h.runId === 86), "a marker-only hold is carried, so it stays in the 24-hour count after the run listing's ~7 h reach");
  assert.ok(data.heldCarry.runs.some((h) => h.runId === 81), "a scan-found hold is carried");
  assert.equal(api.calls.filter((c) => c.includes("artifacts?name=lane-hold-")).length, 7, "one marker list per hold lane");
});

test("lane hold markers: a marker reaches a run past the scan's cap", async () => {
  const api = fakeApi([[/artifacts\?name=lane-hold-pr-refine&/, { artifacts: [marker(7, 907)] }], ...refineRoutes()]);
  const data = await collect(input(api, { holds: { rule: RULE, carried: CARRIED } }));
  assert.ok(!api.calls.some((c) => c.includes("runs/907/jobs")), "907 is past the cap, so the scan does not read it");
  assert.deepEqual(data.laneHolds.filter((h) => h.lane === "pr-refine").map((h) => [h.runId, h.reason]), [
    [907, "hold marker"],
    [901, "fix-docs handoff evidence missing"],
    [900, "fix-docs handoff evidence missing"],
  ]);
});

test("lane hold markers: a failed marker list is a gap that reads only signal 13 partly, and the markers read before it still count", async () => {
  const api = fakeApi([[/artifacts\?name=lane-hold-pr-verify&/, new Error("GET artifacts: HTTP 502")], ...markerRoutes()]);
  const data = await collect(input(api, { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(data.gaps, ["lane hold markers: GET artifacts: HTTP 502"]);
  assert.deepEqual([[...unreadSignals(data.gaps)], [...partlyReadSignals(data.gaps)]], [[], ["13 lane holds"]]);
  assert.ok(data.laneHolds.some((h) => h.runId === 86 && h.reason === "hold marker"), "work-resolve-issue's marker, listed first, stands");
  const off = fakeApi(routes());
  await collect(input(off));
  assert.ok(!off.calls.some((c) => c.includes("lane-hold-")), "no hold rule input, no marker read");
});

test("lane holds: a lane past the cap whose read runs reach the threshold still raises signal 13, and the incident files", async () => {
  const carried = {
    ...CARRIED,
    runs: [...CARRIED.runs, carriedHold("pr-refine", 908, "2026-10-19T15:38:00Z"), carriedHold("pr-refine", 909, "2026-10-19T10:00:00Z")],
  };
  const data = await collect(input(fakeApi(refineRoutes()), { holds: { rule: RULE, carried } }));
  assert.match(data.gaps[0], /^lane holds partly read: over the cap of unread green runs of pr-refine \(cap 6\)/);
  assert.deepEqual(data.holdRule, RULE);
  const findings = detect(data).filter((f) => f.signal === "13 lane holds");
  assert.deepEqual(findings.map((f) => f.key), ["lane-hold:pr-refine"]);
  const rules = Object.fromEntries(SIGNALS.map((s) => [s, { open: 0, close: 0 }]));
  const plan = planIssues({ findings, existing: [], unread: unreadSignals(data.gaps), partly: partlyReadSignals(data.gaps), rules, now });
  assert.deepEqual(plan.file.map((p) => p.family.signal), ["13 lane holds"]);
});

// A red pr-refine run, 950, whose record-passes job logged a failed pass, and
// a red run, 951, whose same line came at notice level, which no hold reads.
test("lane holds: pr-refine's red runs are read, and a refine-failed warning counts as its hold", async () => {
  const warning = (title, message) => ({ annotation_level: "warning", title, message });
  const api = fakeApi([
    [/workflows\/pr-refine\.yml\/runs\?status=failure/, { workflow_runs: [run(950, { event: "workflow_dispatch" }), run(951, { event: "workflow_dispatch" })] }],
    [/runs\/950\/jobs/, { jobs: [{ id: 9500, name: "Record Passes", conclusion: "success" }, { id: 9501, name: "Fix Docs / Run", conclusion: "failure" }] }],
    [/check-runs\/9500\/annotations/, [warning("refine-failed", "pass=fix-docs reason=fix-docs-failure")]],
    [/runs\/951\/jobs/, { jobs: [{ id: 9510, name: "Record Passes", conclusion: "success" }] }],
    [/check-runs\/9510\/annotations/, [notice("refine-failed", "pass=fix-docs reason=fix-docs-failure")]],
    ...holdRoutes(),
  ]);
  const data = await collect(input(api, { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(data.gaps, []);
  assert.deepEqual(data.laneHolds.filter((h) => h.lane === "pr-refine").map((h) => [h.runId, h.item, h.reason]), [[950, null, "fix-docs failed: fix-docs-failure"]]);
  assert.ok(!api.calls.some((c) => c.includes("check-runs/9501/")), "a failed job's annotations are not read");
  // Only pr-refine lists its red runs.
  assert.deepEqual(api.calls.filter((c) => /workflows\/[\w-]+\.yml\/runs\?status=failure/.test(c)).map((c) => /workflows\/([\w-]+)\.yml/.exec(c)[1]), ["pr-refine"]);
});

// intake-triage green runs 1000 on, one a minute from 15:37, each with an
// apply-verdict job; 1000 and 1001 held with the notices apply-verdict.mjs
// closing prints, the rest show only the api-budget notice.
const intakeRuns = (count, from = 1000) =>
  Array.from({ length: count }, (_, i) => run(from + i, { event: "issues", updated_at: `2026-10-19T${i < 23 ? "15" : "16"}:${String((37 + i) % 60).padStart(2, "0")}:00Z` })).reverse();
const intakeRoutes = (listing) => [
  [/workflows\/intake-triage\.yml\/runs/, listing],
  [/runs\/1\d{3}\/jobs/, (path) => ({ jobs: [{ id: Number(/runs\/(\d+)/.exec(path)[1]) * 10, name: "Apply Verdict", conclusion: "success" }] })],
  [/check-runs\/10000\/annotations/, [notice("apply-verdict", "held: admission failed: GET /repos/o/r/issues/7/timeline failed with status 503")]],
  [/check-runs\/10010\/annotations/, [notice("apply-verdict", "held: GET /repos/o/r/issues/7 failed with status 502")]],
  [/check-runs\/1\d{4}\/annotations/, [notice("api-budget", "end lanes-app core remaining=1 used=1 limit=2 reset=x")]],
  ...holdRoutes(),
];

test("lane holds: intake-triage reads past the default cap up to its own, and its holds count", async () => {
  const api = fakeApi(intakeRoutes({ workflow_runs: intakeRuns(8) }));
  const data = await collect(input(api, { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(data.gaps, []);
  assert.deepEqual(data.laneHolds.filter((h) => h.lane === "intake-triage").map((h) => [h.runId, h.item, h.reason]), [
    [1001, null, "fault HTTP 502"],
    [1000, null, "admission fault HTTP 503"],
  ]);
  for (let id = 1000; id < 1008; id += 1) assert.ok(api.calls.some((c) => c.includes(`runs/${id}/jobs`)), id);
  assert.equal(data.heldCarry.through, "2026-10-19T16:41:00Z");
});

test("lane holds: intake-triage past its own cap of 40 is a gap that stops at the 40th run", async () => {
  const api = fakeApi(intakeRoutes({ workflow_runs: intakeRuns(41) }));
  const data = await collect(input(api, { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(data.gaps, ["lane holds partly read: over the cap of unread green runs of intake-triage (cap 40); held runs read only through 2026-10-19T16:16:00Z"]);
  assert.ok(api.calls.some((c) => c.includes("runs/1039/jobs")));
  assert.ok(!api.calls.some((c) => c.includes("runs/1040/jobs")));
});

test("lane holds: work-unblock reads past the default cap of 6 up to its own of 20", async () => {
  const sweeps = (count) => Array.from({ length: count }, (_, i) => run(2100 + i, { event: "schedule", updated_at: `2026-10-19T16:${String(i + 10).padStart(2, "0")}:00Z` })).reverse();
  const routesFor = (count) => [
    [/workflows\/work-unblock\.yml\/runs/, { workflow_runs: sweeps(count) }],
    [/runs\/21\d{2}\/jobs/, (path) => ({ jobs: [{ id: Number(/runs\/(\d+)/.exec(path)[1]) * 10, name: "Label Unblocked", conclusion: "success" }] })],
    [/check-runs\/21\d{3}\/annotations/, []],
    ...holdRoutes(),
  ];
  const eight = fakeApi(routesFor(8));
  const data = await collect(input(eight, { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(data.gaps, []);
  for (let id = 2100; id < 2108; id += 1) assert.ok(eight.calls.some((c) => c.includes(`runs/${id}/jobs`)), id);
  const over = await collect(input(fakeApi(routesFor(21)), { holds: { rule: RULE, carried: CARRIED } }));
  assert.match(over.gaps[0], /^lane holds partly read: over the cap of unread green runs of work-unblock \(cap 20\)/);
});

// Two lanes over their caps in one window: work-resolve-issue runs 3000 to
// 3007 completed a minute apart from 15:37, cut at its 6th (15:42), and
// work-unblock runs 3100 to 3121 a minute apart from 15:38, cut at its 20th
// (15:57). None prints a hold. `later` adds work-unblock runs 3122 to 3125,
// completed 16:40 to 16:43.
const minute = (from, i) => {
  const at = from + i;
  return `2026-10-19T${String(Math.floor(at / 60)).padStart(2, "0")}:${String(at % 60).padStart(2, "0")}:00Z`;
};
const twoLaneRoutes = ({ later = false } = {}) => [
  [/workflows\/work-resolve-issue\.yml\/runs/, { workflow_runs: Array.from({ length: 8 }, (_, i) => run(3000 + i, { event: "issues", updated_at: minute(15 * 60 + 37, i) })).reverse() }],
  [/workflows\/work-unblock\.yml\/runs/, {
    workflow_runs: [
      ...Array.from({ length: 22 }, (_, i) => run(3100 + i, { updated_at: minute(15 * 60 + 38, i) })),
      ...(later ? Array.from({ length: 4 }, (_, i) => run(3122 + i, { updated_at: minute(16 * 60 + 40, i) })) : []),
    ].reverse(),
  }],
  [/runs\/3[01]\d{2}\/jobs/, (path) => {
    const id = Number(/runs\/(\d+)/.exec(path)[1]);
    return { jobs: [{ id: id * 10, name: id < 3100 ? "Report Outcome / Run" : "Label Unblocked", conclusion: "success" }] };
  }],
  [/check-runs\/3[01]\d{3}\/annotations/, []],
  ...holdRoutes(),
];
const NEXT_HOUR = { now: new Date("2026-10-19T17:41:00Z"), windowStart: new Date("2026-10-19T16:36:00Z") };
const readJobs = (api, ids) => ids.filter((id) => api.calls.some((c) => c.includes(`runs/${id}/jobs`)));
const readAnnotations = (api, ids) => ids.filter((id) => api.calls.some((c) => c.includes(`check-runs/${id * 10}/annotations`)));
const ids = (from, to) => Array.from({ length: to - from + 1 }, (_, i) => from + i);

test("lane holds: a run read with no hold is carried and not read again, so the span moves past it", async () => {
  const first = await collect(input(fakeApi(twoLaneRoutes()), { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(first.gaps, ["lane holds partly read: over the cap of unread green runs of work-resolve-issue (cap 6), work-unblock (cap 20); held runs read only through 2026-10-19T15:42:00Z"]);
  const scannedIds = first.heldCarry.scanned.map((s) => s.runId);
  assert.deepEqual(scannedIds, [...ids(3000, 3005), ...ids(3100, 3119), 87]);
  assert.equal(first.heldCarry.scanned.find((s) => s.runId === 3119).at, "2026-10-19T15:57:00Z");

  // An hour on, the 4 new work-unblock runs and the unread 3006, 3007, 3120
  // and 3121 fit both caps once the 26 runs already read are left out.
  const api = fakeApi(twoLaneRoutes({ later: true }));
  const next = await collect(input(api, { ...NEXT_HOUR, holds: { rule: RULE, carried: first.heldCarry } }));
  assert.deepEqual(next.gaps.filter((g) => g.startsWith("lane holds")), []);
  assert.equal(next.heldCarry.through, "2026-10-19T17:41:00Z");
  const readBefore = [...ids(3000, 3005), ...ids(3100, 3119)];
  assert.deepEqual(readAnnotations(api, readBefore), [], "no annotations of a run read last hour are read again");
  assert.deepEqual(readJobs(api, readBefore), [], "no jobs of a run read last hour are read again");
  assert.deepEqual(readJobs(api, [3006, 3007, ...ids(3120, 3125)]), [3006, 3007, ...ids(3120, 3125)]);
  assert.deepEqual(readAnnotations(api, [3006, 3007, ...ids(3120, 3125)]), [3006, 3007, ...ids(3120, 3125)]);
});

test("lane holds: a held run records as before beside carried clean runs, and a new attempt of a clean run is read again", async () => {
  const carried = {
    ...CARRIED,
    through: "2026-10-19T15:37:00Z",
    scanned: [
      { lane: "work-unblock", runId: 3100, at: "2026-10-19T15:38:00Z" },
      // Carried at its first attempt's completion; the listing now shows a later one.
      { lane: "work-unblock", runId: 3101, at: "2026-10-19T15:30:00Z" },
    ],
  };
  const api = fakeApi([
    // 3123 completed 16:41, in this window; 3100 and 3101 in the last.
    [/workflows\/work-unblock\.yml\/runs/, {
      workflow_runs: [run(3123, { updated_at: "2026-10-19T16:41:00Z" }), run(3101, { updated_at: "2026-10-19T15:39:00Z" }), run(3100, { updated_at: "2026-10-19T15:38:00Z" })],
    }],
    [/check-runs\/31010\/annotations/, [notice("label-unblocked", "the open listing failed (HTTP 502); holding, and the next sweep reads it again")]],
    [/check-runs\/31230\/annotations/, [notice("label-unblocked", "#44: GET failed with status 503; holding, and the next sweep reads it again")]],
    // Its jobs and annotations routes; holdRoutes lists work-resolve-issue's 84 to 86.
    ...twoLaneRoutes().slice(2),
  ]);
  const data = await collect(input(api, { ...NEXT_HOUR, holds: { rule: RULE, carried } }));
  assert.deepEqual(data.laneHolds.filter((h) => h.lane === "work-unblock").map((h) => [h.runId, h.item, h.reason, h.at]), [
    [3123, "#44", "read fault HTTP 503", "2026-10-19T16:41:00Z"],
    [3101, null, "open listing failed", "2026-10-19T15:39:00Z"],
    [70, null, "closed-issue listing failed", "2026-10-19T09:00:00Z"],
  ]);
  assert.deepEqual(readJobs(api, [3100, 3101]), [3101]);
  // 3101 and 3123 are carried as held, not as clean; 86 and 87 are holdRoutes' clean runs.
  assert.deepEqual(data.heldCarry.scanned.map((s) => s.runId), [3100, 86, 87]);
});

test("lane holds: a clean run that completed before the run list's lookback is no longer carried", async () => {
  // This window opens at 15:36, so the list reaches back to runs created from 09:36.
  const carried = {
    ...CARRIED,
    scanned: [
      { lane: "pr-verify", runId: 5000, at: "2026-10-19T09:35:00Z" },
      { lane: "pr-verify", runId: 5001, at: "2026-10-19T09:36:00Z" },
      { lane: "pr-verify", runId: 5002, at: "2026-10-19T16:42:00Z" },
    ],
  };
  const data = await collect(input(fakeApi(holdRoutes()), { holds: { rule: RULE, carried } }));
  assert.deepEqual(data.heldCarry.scanned.map((s) => s.runId), [5001, 86, 87]);
  // A failed read still carries the clean runs read so far.
  const failed = await collect(input(fakeApi([[/workflows\/work-unblock\.yml\/runs/, new Error("GET runs: HTTP 502")], ...holdRoutes()]), { holds: { rule: RULE, carried } }));
  assert.deepEqual([failed.heldCarry.scanned.map((s) => s.runId), failed.heldCarry.through], [[5001, 86], null]);
});

test("lane holds: a carry written before it held clean runs reads as none, and those runs are read again", async () => {
  const first = await collect(input(fakeApi(twoLaneRoutes()), { holds: { rule: RULE, carried: CARRIED } }));
  const { scanned, ...older } = first.heldCarry;
  assert.ok(scanned.length > 0);
  const carried = parseHeldCarry(JSON.stringify({ version: JOBS_VERSION, repository: repo, runs: [], held: older }), repo);
  assert.deepEqual(carried.scanned, []);
  const api = fakeApi(twoLaneRoutes());
  const next = await collect(input(api, { ...NEXT_HOUR, holds: { rule: RULE, carried } }));
  // From 15:42 the 2 work-resolve-issue runs from 3005 and the 18 work-unblock runs from 3104 are read.
  assert.deepEqual(readJobs(api, [...ids(3000, 3007), ...ids(3100, 3121)]), [...ids(3005, 3007), ...ids(3104, 3121)]);
  assert.deepEqual(next.gaps.filter((g) => g.startsWith("lane holds")), []);
});

test("lane holds: a run list past one page reads the next, and past three pages is a gap", async () => {
  // 150 listed: page 1 the 100 newest-created, none completed in the window;
  // page 2 holds the held run 1000, completed in it.
  const old = (from, n) => Array.from({ length: n }, (_, i) => run(from + i, { event: "issues", updated_at: "2026-10-19T12:00:00Z" }));
  const paged = fakeApi(intakeRoutes((path) => (/&page=2$/.test(path) ? { total_count: 150, workflow_runs: [...intakeRuns(1), ...old(2000, 49)] } : { total_count: 150, workflow_runs: old(3000, 100) })));
  const data = await collect(input(paged, { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(data.gaps, []);
  assert.deepEqual(data.laneHolds.filter((h) => h.lane === "intake-triage").map((h) => h.runId), [1000]);
  assert.equal(paged.calls.filter((c) => c.includes("intake-triage.yml/runs")).length, 2);
  const many = fakeApi(intakeRoutes((path) => ({ total_count: 400, workflow_runs: old(3000 + 100 * Number(/&page=(\d)$/.exec(path)?.[1] ?? 1), 100) })));
  const cut = await collect(input(many, { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(cut.gaps, ["lane holds: over 300 green runs of intake-triage listed; the oldest were not read"]);
  assert.equal(many.calls.filter((c) => c.includes("intake-triage.yml/runs")).length, 3);
});

// pr-verify green runs from 4000: 4000 held by the resolver, 4001 by the
// trigger gate (a later job), 4002 judged with no hold, and 4003 a green hold
// job listed with no steps whose only notice is no hold. Listed through REST,
// with steps, only 40000, 40011 and the stepless 40030 have their
// annotations read; listed through GraphQL, every green hold job's are.
const verifyJob = (id, name, held) => ({ id, name, conclusion: "success", steps: [{ name: "Resolve the pull request", conclusion: "success" }, { name: "Note the hold", conclusion: held ? "success" : "skipped" }] });
const verifyRoutes = (listing) => [
  [/workflows\/pr-verify\.yml\/runs/, listing],
  [/runs\/4000\/jobs/, { jobs: [verifyJob(40000, "Check Intent", true)] }],
  [/runs\/4001\/jobs/, { jobs: [verifyJob(40010, "Check Intent", false), verifyJob(40011, "Check Intent Subscription", true)] }],
  [/runs\/4002\/jobs/, { jobs: [verifyJob(40020, "Check Intent", false), verifyJob(40021, "Wake PR Merge", true)] }],
  [/runs\/4003\/jobs/, { jobs: [{ id: 40030, name: "Check Intent", conclusion: "success", steps: [] }] }],
  [/check-runs\/40000\/annotations/, [notice("pr-verify", "held: pr-verify could not resolve the pull request: GET /repos/o/r/pulls/7 failed with status 502")]],
  [/check-runs\/40011\/annotations/, [notice("pr-verify", "held: pr-verify's trigger gate met a GitHub fault (read-fault); nothing is judged")]],
  [/check-runs\/40030\/annotations/, [notice("api-budget", "end github-token core remaining=1 used=1 limit=2 reset=x")]],
  [/check-runs\/400[12]0\/annotations/, []],
  ...holdRoutes(),
];
const verifyRuns = (count, from = 4000) =>
  Array.from({ length: count }, (_, i) => run(from + i, { event: "workflow_run", updated_at: new Date(Date.parse("2026-10-19T15:40:00Z") + i * 30_000).toISOString().replace(".000Z", "Z") })).reverse();
// The check runs whose annotations were read through REST, among `ids`.
const restAnnotationReads = (api, ids) =>
  api.calls.map((c) => Number(/check-runs\/(\d+)\/annotations/.exec(c)?.[1])).filter((id) => ids.includes(id)).sort((a, b) => a - b);
const VERIFY_JOBS = [40000, 40010, 40011, 40020, 40021, 40030];

test("lane holds: pr-verify counts resolver and trigger-gate holds, reading REST-listed annotations only where Note the hold ran", async () => {
  const api = fakeApi(verifyRoutes({ workflow_runs: verifyRuns(4) }));
  const data = await collect(input(api, { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(data.gaps, []);
  assert.deepEqual(data.laneHolds.filter((h) => h.lane === "pr-verify").map((h) => [h.runId, h.item, h.reason]), [
    [4001, null, "trigger gate fault"],
    [4000, null, "resolver fault"],
  ]);
  assert.deepEqual(restAnnotationReads(api, VERIFY_JOBS), [40000, 40011, 40030]);
});

// The same routes read with and without node ids: the hold data each read
// finds, and the REST paths the GraphQL read made that match `lane`.
async function holdsBothWays(routes, lane) {
  const holds = { rule: RULE, carried: CARRIED };
  const before = await collect(input(fakeApi(routes), { holds }));
  const gql = fakeApi(withNodeIds(routes));
  const after = await collect(input(gql, { holds }));
  return { before, after, restLeft: gql.calls.filter((c) => c !== GRAPHQL && lane.test(c)), listed: gql.queries.flatMap((q) => q.variables?.ids ?? []) };
}

test("lane holds: pr-verify's runs are listed through GraphQL, with no REST jobs or annotations read, and find the same holds", async () => {
  const { before, after, restLeft, listed } = await holdsBothWays(verifyRoutes({ workflow_runs: verifyRuns(4) }), /runs\/400\d\/jobs|check-runs\/400\d\d\//);
  assert.deepEqual(after.laneHolds, before.laneHolds);
  assert.deepEqual(after.heldCarry, before.heldCarry);
  assert.equal(after.laneHolds.filter((h) => h.lane === "pr-verify").length, 2);
  assert.deepEqual(restLeft, []);
  // A GraphQL list has no steps, so every green hold job's annotations are read in the batch.
  for (const id of ["WFR_4000", "WFR_4003", "CR_40000", "CR_40010", "CR_40011", "CR_40020", "CR_40030"]) assert.ok(listed.includes(id), id);
});

test("lane holds: pr-verify reads up to its own cap of 80 runs and 5 list pages", async () => {
  const ok = fakeApi([[/workflows\/pr-verify\.yml\/runs/, { workflow_runs: verifyRuns(80, 5000) }], [/runs\/5\d{3}\/jobs/, { jobs: [] }], ...holdRoutes()]);
  const read = await collect(input(ok, { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(read.gaps, []);
  const over = fakeApi([[/workflows\/pr-verify\.yml\/runs/, { workflow_runs: verifyRuns(81, 5000) }], [/runs\/5\d{3}\/jobs/, { jobs: [] }], ...holdRoutes()]);
  const cut = await collect(input(over, { holds: { rule: RULE, carried: CARRIED } }));
  assert.match(cut.gaps[0], /^lane holds partly read: over the cap of unread green runs of pr-verify \(cap 80\)/);
  const old = (page) => Array.from({ length: 100 }, (_, i) => run(6000 + 100 * page + i, { event: "workflow_run", updated_at: "2026-10-19T12:00:00Z" }));
  const paging = (pages) => fakeApi([[/workflows\/pr-verify\.yml\/runs/, (path) => ({ total_count: pages * 100 + 1, workflow_runs: old(Number(/&page=(\d)$/.exec(path)?.[1] ?? 1)) })], ...holdRoutes()]);
  const four = paging(4);
  // 401 listed: past the default 3 pages, read whole in 5.
  assert.deepEqual((await collect(input(four, { holds: { rule: RULE, carried: CARRIED } }))).gaps, []);
  assert.equal(four.calls.filter((c) => c.includes("pr-verify.yml/runs")).length, 5);
  // 501 listed: past 5 pages is a gap.
  const six = paging(5);
  assert.deepEqual((await collect(input(six, { holds: { rule: RULE, carried: CARRIED } }))).gaps, ["lane holds: over 500 green runs of pr-verify listed; the oldest were not read"]);
  assert.equal(six.calls.filter((c) => c.includes("pr-verify.yml/runs")).length, 5);
});

// pr-review-main green runs: 7000 held in a matrix leg, 7001 held in the
// trigger job, 7002 reviewed with no hold. Listed through REST, only 70001
// and 70010 have their annotations read; Record (70021) is no hold job.
const reviewJob = (id, name, held) => ({ id, name, conclusion: "success", steps: [{ name: "Select a lane-source pull request", conclusion: "success" }, { name: "Note the hold", conclusion: held ? "success" : "skipped" }] });
const unreadList = "held: the file list did not read (HTTP 502); no review, and the lost-run reconciler re-runs this run once";
const reviewRoutes = () => [
  [/workflows\/pr-review-main\.yml\/runs/, { workflow_runs: [7000, 7001, 7002].map((id, i) => run(id, { event: "workflow_run", updated_at: `2026-10-19T16:0${i}:00Z` })).reverse() }],
  [/runs\/7000\/jobs/, { jobs: [reviewJob(70000, "Trigger", false), reviewJob(70001, "Review (claude-review, claude-review)", true), reviewJob(70002, "Review (claude-security-review, claude-security-review)", false)] }],
  [/runs\/7001\/jobs/, { jobs: [reviewJob(70010, "Trigger", true)] }],
  [/runs\/7002\/jobs/, { jobs: [reviewJob(70020, "Trigger", false), reviewJob(70021, "Record", true)] }],
  [/check-runs\/70001\/annotations/, [notice("pr-review-main", unreadList)]],
  [/check-runs\/70010\/annotations/, [notice("pr-review-main", unreadList)]],
  [/check-runs\/700[02][02]\/annotations/, []],
  ...holdRoutes(),
];

const REVIEW_JOBS = [70000, 70001, 70002, 70010, 70020, 70021];

test("lane holds: pr-review-main counts a held trigger job or matrix leg, reading REST-listed annotations only where Note the hold ran", async () => {
  const api = fakeApi(reviewRoutes());
  const data = await collect(input(api, { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(data.gaps, []);
  assert.deepEqual(data.laneHolds.filter((h) => h.lane === "pr-review-main").map((h) => [h.runId, h.reason]), [
    [7001, "file list unread"],
    [7000, "file list unread"],
  ]);
  assert.deepEqual(restAnnotationReads(api, REVIEW_JOBS), [70001, 70010]);
});

test("lane holds: pr-review-main's runs are listed through GraphQL, with no REST jobs or annotations read, and find the same holds", async () => {
  const { before, after, restLeft, listed } = await holdsBothWays(reviewRoutes(), /runs\/700\d\/jobs|check-runs\/700\d\d\//);
  assert.deepEqual(after.laneHolds, before.laneHolds);
  assert.deepEqual(after.heldCarry, before.heldCarry);
  assert.equal(after.laneHolds.filter((h) => h.lane === "pr-review-main").length, 2);
  assert.deepEqual(restLeft, []);
  for (const id of ["WFR_7000", "WFR_7002", "CR_70001", "CR_70010"]) assert.ok(listed.includes(id), id);
});

test("lane holds: a re-run of pr-verify is listed through REST and its hold still counts", async () => {
  const rerun = verifyRuns(4).map((r) => ({ ...r, run_attempt: 2 }));
  const api = fakeApi(withNodeIds(verifyRoutes({ workflow_runs: rerun })));
  const data = await collect(input(api, { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(data.laneHolds.filter((h) => h.lane === "pr-verify").map((h) => h.runId), [4001, 4000]);
  assert.ok(api.calls.some((c) => c.includes("runs/4000/jobs?filter=latest")));
  assert.ok(!api.queries.some((q) => q.variables?.ids?.includes("WFR_4000")));
});

test("lane holds: with GraphQL refused, pr-verify and pr-review-main list through REST and read annotations only where Note the hold ran", async () => {
  // Each lane's own routes, ahead of holdRoutes, which list every other lane empty.
  const own = (routes) => routes.slice(0, routes.length - holdRoutes().length);
  const routes = [...own(verifyRoutes({ workflow_runs: verifyRuns(4) })), ...own(reviewRoutes()), ...holdRoutes()];
  const api = fakeApi([[GRAPHQL, new Error("POST /graphql: HTTP 502")], ...withNodeIds(routes)]);
  const data = await collect(input(api, { holds: { rule: RULE, carried: CARRIED } }));
  assert.ok(api.queries.some((q) => q.variables?.ids?.includes("WFR_4000")), "the GraphQL list was tried");
  assert.ok(api.queries.some((q) => q.variables?.ids?.includes("CR_70001")), "the GraphQL annotations read was tried");
  for (const r of [4000, 4001, 4002, 4003, 7000, 7001, 7002]) assert.ok(api.calls.some((c) => c.includes(`runs/${r}/jobs?filter=latest`)), r);
  assert.deepEqual(data.laneHolds.filter((h) => h.lane === "pr-verify").map((h) => h.runId), [4001, 4000]);
  assert.deepEqual(data.laneHolds.filter((h) => h.lane === "pr-review-main").map((h) => h.runId), [7001, 7000]);
  assert.deepEqual(restAnnotationReads(api, VERIFY_JOBS), [40000, 40011, 40030]);
  assert.deepEqual(restAnnotationReads(api, REVIEW_JOBS), [70001, 70010]);
});

test("lane holds: with the GraphQL list answering and the annotation batch failing, pr-verify and pr-review-main list each run through REST and read annotations only where Note the hold ran", async () => {
  const own = (routes) => routes.slice(0, routes.length - holdRoutes().length);
  const routes = [...own(verifyRoutes({ workflow_runs: verifyRuns(4) })), ...own(reviewRoutes()), ...holdRoutes()];
  const api = fakeApi(withNodeIds(routes));
  const graphql = async (query, variables) => {
    if (query.includes("... on CheckRun")) {
      api.queries.push({ query, variables });
      throw new Error("POST /graphql: HTTP 502");
    }
    return api.graphql(query, variables);
  };
  const data = await collect({ ...input(api, { holds: { rule: RULE, carried: CARRIED } }), graphql });
  assert.ok(api.queries.some((q) => q.query.includes("... on WorkflowRun") && q.variables?.ids?.includes("WFR_7000")), "the GraphQL list was read");
  assert.ok(api.queries.some((q) => q.query.includes("... on CheckRun") && q.variables?.ids?.includes("CR_70001")), "the GraphQL annotations read was tried");
  assert.deepEqual(data.laneHolds.filter((h) => h.lane === "pr-verify").map((h) => h.runId), [4001, 4000]);
  assert.deepEqual(data.laneHolds.filter((h) => h.lane === "pr-review-main").map((h) => h.runId), [7001, 7000]);
  assert.deepEqual(restAnnotationReads(api, VERIFY_JOBS), [40000, 40011, 40030]);
  assert.deepEqual(restAnnotationReads(api, REVIEW_JOBS), [70001, 70010]);
  for (const r of [4000, 4001, 4002, 4003, 7000, 7001, 7002]) assert.equal(api.calls.filter((c) => c.includes(`runs/${r}/jobs?filter=latest`)).length, 1, `run ${r} listed through REST once`);
});

// pr-merge green runs: 7100 a sweep whose merge job held on its lane token,
// 7101 a verdict wake whose enable-auto-merge job held, 7102 a sweep with no
// hold. The notice is the action's own text.
const tokenHold = /^ +msg="(lane-token-held: [^"]*)"$/m
  .exec(readFileSync(new URL("../../actions/request-lane-token/action.yml", import.meta.url), "utf8"))[1]
  .replace("${rate_limit}", "");

test("lane holds: pr-merge counts a lane token hold in its merge or enable-auto-merge job", async () => {
  const runs = [
    run(7100, { event: "schedule", updated_at: "2026-10-19T16:00:00Z" }),
    run(7101, { event: "workflow_dispatch", updated_at: "2026-10-19T16:01:00Z" }),
    run(7102, { event: "schedule", updated_at: "2026-10-19T16:02:00Z" }),
  ];
  const job = (id, name) => ({ id, name, conclusion: "success" });
  const api = fakeApi([
    [/workflows\/pr-merge\.yml\/runs\?status=/, { workflow_runs: runs }],
    [/runs\/7100\/jobs/, { jobs: [job(71000, "Post Merge Dispatch"), job(71001, "Merge")] }],
    [/runs\/7101\/jobs/, { jobs: [job(71010, "Enable Auto Merge")] }],
    [/runs\/7102\/jobs/, { jobs: [job(71020, "Merge"), job(71021, "Enable Auto Merge")] }],
    [/check-runs\/71001\/annotations/, [notice("Lane token hold", tokenHold)]],
    [/check-runs\/71010\/annotations/, [notice("Lane token hold", tokenHold)]],
    [/check-runs\/7102[01]\/annotations/, [notice("api-budget", "end github-token core remaining=1 used=1 limit=2 reset=x")]],
    ...holdRoutes(),
  ]);
  const data = await collect(input(api, { holds: { rule: RULE, carried: CARRIED } }));
  assert.deepEqual(data.gaps, []);
  assert.deepEqual(data.laneHolds.filter((h) => h.lane === "pr-merge").map((h) => [h.runId, h.reason]), [
    [7101, "lane token rate-limited"],
    [7100, "lane token rate-limited"],
  ]);
  // A job outside the lane's two is never read.
  assert.ok(!api.calls.some((c) => c.includes("check-runs/71000/")));
});

test("a carried held run of another repository or an unknown lane, or a bad span, is refused", () => {
  assert.deepEqual(parseHeldCarry(JSON.stringify({ version: JOBS_VERSION, repository: repo, runs: [] }), repo), { runs: [], from: null, through: null, scanned: [] });
  const [first] = CARRIED.runs;
  const clean = { lane: "work-unblock", runId: 72, at: "2026-10-19T15:10:00Z" };
  for (const text of [
    jobsCarryFile(repo, [], { ...CARRIED, scanned: [{ ...clean, lane: "pr-unblock" }] }),
    jobsCarryFile(repo, [], { ...CARRIED, scanned: [{ ...clean, runId: "72" }] }),
    jobsCarryFile(repo, [], { ...CARRIED, scanned: [{ ...clean, at: "never" }] }),
    jobsCarryFile(repo, [], { ...CARRIED, scanned: {} }),
    jobsCarryFile("other/repo", [], CARRIED),
    jobsCarryFile(repo, [], { ...CARRIED, runs: [{ ...first, lane: "pr-unblock" }] }),
    jobsCarryFile(repo, [], { ...CARRIED, runs: [{ ...first, at: "never" }] }),
    jobsCarryFile(repo, [], { ...CARRIED, runs: [{ ...first, item: 812 }] }),
    jobsCarryFile(repo, [], { ...CARRIED, from: "never" }),
    jobsCarryFile(repo, [], { ...CARRIED, runs: null }),
  ]) {
    assert.throws(() => parseHeldCarry(text, repo), /unexpected shape/);
  }
});

// Signal 14's own source: main's failed scheduled work-unblock runs, and the
// annotations of their failed publish-lane-level job.
const unblockRun = (id, extra = {}) => run(id, { name: "Work Unblock", path: ".github/workflows/work-unblock.yml", conclusion: "failure", ...extra });
const publishJob = (id, steps = []) => ({ id, name: "Publish Lane Level", conclusion: "failure", steps });
const CHANGED = { annotation_level: "failure", message: "lane-variables-changed: created CLAUDE_LANES_DISABLED" };

test("lane variable runs: a red publish-lane-level run is read even past 12 other failed runs", async () => {
  const others = Array.from({ length: 20 }, (_, i) => run(2000 + i, { name: "pr-unblock" }));
  const api = fakeApi([
    [/actions\/runs\?status=failure/, { workflow_runs: others }],
    [/runs\/2\d{3}\/jobs/, { jobs: [] }],
    [/workflows\/work-unblock\.yml\/runs/, { workflow_runs: [unblockRun(80)] }],
    [/runs\/80\/jobs/, { jobs: [{ id: 800, name: "Label Unblocked", conclusion: "success" }, publishJob(801, [{ name: "Check no other repository variable changed", conclusion: "failure" }])] }],
    [/check-runs\/801\/annotations/, [CHANGED]],
    ...routes(),
  ]);
  const data = await collect(input(api));
  assert.equal(data.failedRuns.length, 12, "the general failed-run read stops at its cap");
  assert.ok(!data.failedRuns.some((r) => r.id === 80));
  assert.deepEqual(data.laneVariableRuns, [
    { id: 80, url: "https://github.com/o/r/actions/runs/80", name: "Work Unblock", event: "schedule", annotations: [{ level: "failure", message: CHANGED.message }], failedSteps: ["Check no other repository variable changed: failure"] },
  ]);
  assert.deepEqual(laneVariableFindings(data)[0].facts, ["Work Unblock https://github.com/o/r/actions/runs/80: lane-variables-changed: created CLAUDE_LANES_DISABLED"]);
  assert.ok(api.calls.some((p) => p.startsWith("/repos/o/r/actions/workflows/work-unblock.yml/runs?event=schedule&branch=main&status=failure&created=")));
});

test("lane variable runs: a run from before the job rename names the job publish-lane-level, and is read the same way", async () => {
  const api = fakeApi([
    [/workflows\/work-unblock\.yml\/runs/, { workflow_runs: [unblockRun(80)] }],
    [/runs\/80\/jobs/, { jobs: [{ ...publishJob(801, [{ name: "Check no other repository variable changed", conclusion: "failure" }]), name: "publish-lane-level" }] }],
    [/check-runs\/801\/annotations/, [CHANGED]],
    ...routes(),
  ]);
  const data = await collect(input(api));
  assert.deepEqual(data.laneVariableRuns.map((r) => [r.id, r.failedSteps]), [[80, ["Check no other repository variable changed: failure"]]]);
});

test("lane variable runs: only main's scheduled runs of this repository's head count, and only a failed publish-lane-level job", async () => {
  const api = fakeApi([
    [
      /workflows\/work-unblock\.yml\/runs/,
      {
        workflow_runs: [
          unblockRun(81, { event: "workflow_run" }),
          unblockRun(82, { head_branch: "feature" }),
          unblockRun(83, { head_repository: { full_name: "fork/r" } }),
          unblockRun(84),
        ],
      },
    ],
    [/runs\/84\/jobs/, { jobs: [{ id: 840, name: "Label Unblocked", conclusion: "failure" }, { ...publishJob(841), conclusion: "success" }] }],
    ...routes(),
  ]);
  const data = await collect(input(api));
  assert.deepEqual(data.laneVariableRuns, []);
  assert.ok(!api.calls.some((p) => /runs\/8[123]\/jobs/.test(p)));
});

test("lane variable runs: a run that timed out is read too", async () => {
  const timedOut = unblockRun(85, { conclusion: "timed_out" });
  const api = fakeApi([
    [/workflows\/work-unblock\.yml\/runs\?event=schedule&branch=main&status=timed_out/, { workflow_runs: [timedOut] }],
    [/workflows\/work-unblock\.yml\/runs/, { workflow_runs: [] }],
    [/runs\/85\/jobs/, { jobs: [{ ...publishJob(851, [{ name: "Check no other repository variable changed", conclusion: "cancelled" }]), conclusion: "timed_out" }] }],
    [/check-runs\/851\/annotations/, []],
    ...routes(),
  ]);
  const data = await collect(input(api));
  assert.deepEqual(data.laneVariableRuns.map((r) => [r.id, r.failedSteps]), [[85, ["Check no other repository variable changed: cancelled"]]]);
});

test("lane variable runs: a failed listing or one over the cap is a gap, so signal 14 reads unread", async () => {
  const failed = await collect(input(fakeApi([[/workflows\/work-unblock\.yml\/runs/, new Error("HTTP 502")], ...routes()])));
  assert.deepEqual(failed.gaps, ["lane variable runs: HTTP 502"]);
  assert.ok(unreadSignals(failed.gaps).has("14 lane variables"));
  const many = Array.from({ length: LIMITS.laneVariableRuns + 1 }, (_, i) => unblockRun(900 + i));
  const over = await collect(input(fakeApi([[/workflows\/work-unblock\.yml\/runs/, { workflow_runs: many }], ...routes()])));
  assert.deepEqual(over.gaps, [`lane variable runs: over ${LIMITS.laneVariableRuns} failed scheduled work-unblock runs; the rest were not read`]);
});

// pr-merge run 43092202279 as both APIs answered it on 2026-11-11: GraphQL's
// check runs (newest first, no steps), REST's jobs list (oldest first, steps
// left out), and three of its enable-auto-merge job's 28 annotations.
const RECORDED_RUN = { id: 43092202279, run_attempt: 1 };
const recordedCheckRun = (id, databaseId, name, conclusion) => ({ id, databaseId, name, status: "COMPLETED", conclusion });
const RECORDED_NODE = {
  databaseId: 43092202279,
  runAttempt: 1,
  checkSuite: {
    checkRuns: {
      totalCount: 6,
      nodes: [
        recordedCheckRun("CR_kwDOTCGFQM8AAAAecsxang", 130775014046, "unarmed-status", "SKIPPED"),
        recordedCheckRun("CR_kwDOTCGFQM8AAAAecp1zog", 130771940258, "post-merge-dispatch", "SKIPPED"),
        recordedCheckRun("CR_kwDOTCGFQM8AAAAecpy5Dw", 130771892495, "dispatch-full-run", "SKIPPED"),
        recordedCheckRun("CR_kwDOTCGFQM8AAAAecpy4dg", 130771892342, "gate-check", "SKIPPED"),
        recordedCheckRun("CR_kwDOTCGFQM8AAAAecpy3Fw", 130771891991, "merge", "SKIPPED"),
        recordedCheckRun("CR_kwDOTCGFQM8AAAAecpyvPw", 130771889983, "enable-auto-merge", "SUCCESS"),
      ],
    },
  },
};
const recordedJob = (id, node_id, name, conclusion) => ({ id, node_id, name, status: "completed", conclusion });
const RECORDED_JOBS = [
  recordedJob(130771889983, "CR_kwDOTCGFQM8AAAAecpyvPw", "enable-auto-merge", "success"),
  recordedJob(130771891991, "CR_kwDOTCGFQM8AAAAecpy3Fw", "merge", "skipped"),
  recordedJob(130771892342, "CR_kwDOTCGFQM8AAAAecpy4dg", "gate-check", "skipped"),
  recordedJob(130771892495, "CR_kwDOTCGFQM8AAAAecpy5Dw", "dispatch-full-run", "skipped"),
  recordedJob(130771940258, "CR_kwDOTCGFQM8AAAAecp1zog", "post-merge-dispatch", "skipped"),
  recordedJob(130775014046, "CR_kwDOTCGFQM8AAAAecsxang", "unarmed-status", "skipped"),
];
// That job's 28 annotations as each API answered: REST's annotations read
// (the fields the sources read) and GraphQL's CheckRun node.
const RECORDED = JSON.parse(readFileSync(new URL("./recorded-annotations.json", import.meta.url), "utf8"));
const RECORDED_ANNOTATIONS_NODE = RECORDED.graphql;

test("the GraphQL check-run and annotation readers answer as the REST jobs and annotations reads of the same run", () => {
  assert.deepEqual(restJobs(RECORDED_NODE, RECORDED_RUN), RECORDED_JOBS);
  assert.equal(RECORDED.rest.length, 28);
  assert.deepEqual(restAnnotations(RECORDED_ANNOTATIONS_NODE, { id: RECORDED.checkRun }), RECORDED.rest);
});

test("a GraphQL answer that is cut short, holds a null, is another run's or a re-run's is no answer", () => {
  const checkRuns = RECORDED_NODE.checkSuite.checkRuns;
  const variants = [
    { ...RECORDED_NODE, runAttempt: 2 },
    { ...RECORDED_NODE, databaseId: 1 },
    { ...RECORDED_NODE, checkSuite: { checkRuns: { ...checkRuns, totalCount: 31 } } },
    { ...RECORDED_NODE, checkSuite: { checkRuns: { ...checkRuns, nodes: [...checkRuns.nodes.slice(1), null] } } },
    { ...RECORDED_NODE, checkSuite: { checkRuns: { totalCount: 0, nodes: [] } } },
    { ...RECORDED_NODE, checkSuite: null },
    null,
  ];
  for (const node of variants) assert.equal(restJobs(node, RECORDED_RUN), null, JSON.stringify(node)?.slice(0, 80));
  const annotations = RECORDED_ANNOTATIONS_NODE.annotations;
  for (const node of [
    { ...RECORDED_ANNOTATIONS_NODE, annotations: { ...annotations, totalCount: 101 } },
    { ...RECORDED_ANNOTATIONS_NODE, annotations: null },
    { ...RECORDED_ANNOTATIONS_NODE, databaseId: 1 },
    null,
  ]) {
    assert.equal(restAnnotations(node, { id: 130771889983 }), null, JSON.stringify(node)?.slice(0, 80));
  }
});

// Every source that reads jobs or annotations: pr-merge budget (run 10),
// in-progress (20), failed runs (30), merge groups (50), the hold lanes
// (81, 85, 86, 87) and pr-review-main (7000).
const graphqlScenario = () => [
  [/workflows\/pr-review-main\.yml\/runs/, { workflow_runs: [run(7000, { event: "workflow_run" })] }],
  [/runs\/7000\/jobs/, { jobs: [reviewJob(70000, "trigger", false), reviewJob(70001, "review (claude-review, claude-review)", true)] }],
  [/check-runs\/70000\/annotations/, []],
  [/check-runs\/70001\/annotations/, [notice("pr-review-main", unreadList)]],
  ...queueRoutes().slice(0, 3),
  ...holdRoutes(),
];
const restGets = (api) => api.calls.filter((c) => c !== GRAPHQL);
const nodeQueries = (api) => api.queries.filter((q) => q.query.includes("nodes(ids: $ids)"));
const holdInput = (api) => input(api, { holds: { rule: RULE, carried: CARRIED } });

test("with node ids listed, job lists and annotations are read through GraphQL and every signal reads the same data", async () => {
  const rest = fakeApi(graphqlScenario());
  const before = await collect(holdInput(rest));
  const gql = fakeApi(withNodeIds(graphqlScenario()));
  const after = await collect(holdInput(gql));
  assert.deepEqual(after, before);
  assert.deepEqual(detect(after), detect(before));
  const replaced = ["runs/10/jobs", "runs/20/jobs", "runs/30/jobs", "runs/81/jobs", "runs/85/jobs", "runs/86/jobs", "runs/87/jobs", "runs/7000/jobs"]
    .concat(["check-runs/100/", "check-runs/300/", "check-runs/810/", "check-runs/850/", "check-runs/870/", "check-runs/70001/"]);
  assert.deepEqual(restGets(gql), restGets(rest).filter((c) => !replaced.some((p) => c.includes(p))));
  for (const path of replaced) assert.ok(restGets(rest).some((c) => c.includes(path)), `the REST read makes ${path}`);
  // pr-review-main's trigger job, whose Note the hold was skipped: a REST list
  // shows it, so its annotations go unread; a GraphQL list does not, so they are read in the batch.
  assert.ok(!restGets(rest).some((c) => c.includes("check-runs/70000/")));
  assert.ok(nodeQueries(gql).some((q) => q.variables.ids.includes("CR_70000")));
  // A source that reads steps still lists its run's jobs through REST, and that read is still carried.
  assert.ok(restGets(gql).some((c) => c.includes("runs/50/jobs")));
  assert.deepEqual(after.jobsCarry.map((e) => e.id), [50]);
  // One list and one annotations query for pr-merge budget, failed runs and four hold lanes; a list for in-progress.
  assert.equal(nodeQueries(gql).length, 13);
});

test("a null GraphQL node is read through REST, so a gap stays a gap and never reads as no hold", async () => {
  const gql = fakeApi(withNodeIds(graphqlScenario()));
  const all = await collect(holdInput(gql));
  const api = fakeApi(withNodeIds(graphqlScenario()), { nulls: new Set(["WFR_81", "CR_850"]) });
  const data = await collect(holdInput(api));
  assert.deepEqual(data, all);
  assert.deepEqual(data.laneHolds.filter((h) => [81, 85].includes(h.runId)).map((h) => [h.runId, h.reason]), [
    [85, "fault outcome-unread"],
    [81, "closed-issue listing failed; open listing failed"],
  ]);
  const added = restGets(api).filter((c) => !restGets(gql).includes(c));
  assert.deepEqual(added.sort(), [`/repos/${repo}/actions/runs/81/jobs?filter=latest&per_page=100`, `/repos/${repo}/check-runs/850/annotations?per_page=100`]);
});

test("a failed GraphQL read leaves every job and annotation read on REST, as before", async () => {
  const failing = (routes) => [[GRAPHQL, new Error("HTTP 502")], ...routes];
  const rest = fakeApi(failing(graphqlScenario()));
  const gql = fakeApi(failing(withNodeIds(graphqlScenario())));
  assert.deepEqual(await collect(holdInput(gql)), await collect(holdInput(rest)));
  assert.deepEqual(restGets(gql), restGets(rest));
});

test("a jobs read that fails ends its source at that run, once, keeping the runs read before it", async () => {
  const api = fakeApi([
    [/actions\/runs\?status=failure/, { workflow_runs: [run(30, { name: "pr-unblock" }), run(32, { name: "pr-refine" }), run(33, { name: "work-unblock" })] }],
    [/runs\/32\/jobs/, Object.assign(new Error("HTTP 502"), { status: 502 })],
    ...routes(),
  ]);
  const data = await collect(input(api));
  assert.deepEqual(data.gaps, ["failed runs: HTTP 502"]);
  assert.deepEqual(data.failedRuns.map((r) => r.id), [30]);
  assert.deepEqual(data.failedRuns[0].annotations, [{ level: "failure", message: "lane-token-denied: the broker answered 500 with reason unknown" }]);
  assert.equal(api.calls.filter((c) => c.includes("runs/32/jobs")).length, 1);
  assert.ok(!api.calls.some((c) => c.includes("runs/33/jobs")));
});

// A malformed answer to every nodes query, and which of its ids go to REST.
const MALFORMED = [
  ["a 200 whose error names no node", (a) => ({ ...a, errors: [{ type: "INTERNAL", message: "Something went wrong" }] }), "all"],
  ["data.nodes not an array", () => ({ data: { nodes: {} } }), "all"],
  ["fewer nodes than ids", (a) => ({ data: { nodes: a.data.nodes.slice(0, -1) } }), "last"],
  ["an error on a field inside the first node", (a) => ({ ...a, errors: [{ type: "INTERNAL", message: "field failed", path: ["nodes", 0, "checkSuite"] }] }), "first"],
];
const restPath = (id) => {
  const [, kind, n] = /^(WFR|CR)_(\d+)$/.exec(id);
  return kind === "WFR" ? `runs/${n}/jobs` : `check-runs/${n}/annotations`;
};

test("a malformed GraphQL answer sends the ids it does not answer for to REST, and every signal reads the same data", async () => {
  const rest = fakeApi(graphqlScenario());
  const before = await collect(holdInput(rest));
  for (const [what, shape, toRest] of MALFORMED) {
    const api = fakeApi(withNodeIds(graphqlScenario()));
    const graphql = async (query, variables) => {
      const answer = await api.graphql(query, variables);
      return query.includes("nodes(ids: $ids)") ? shape(answer) : answer;
    };
    const after = await collect({ ...holdInput(api), graphql });
    assert.deepEqual(after, before, what);
    if (toRest === "all") {
      assert.deepEqual(restGets(api), restGets(rest), what);
      continue;
    }
    for (const { variables } of nodeQueries(api)) {
      const id = toRest === "first" ? variables.ids[0] : variables.ids.at(-1);
      assert.ok(restGets(api).some((c) => c.includes(restPath(id))), `${what}: ${id}`);
    }
  }
});

test("a re-run's jobs are not listed through GraphQL", async () => {
  const scenario = withNodeIds(graphqlScenario()).map(([pattern, value]) =>
    String(pattern) === String(/workflows\/work-unblock\.yml\/runs/) ? [pattern, { workflow_runs: value.workflow_runs.map((r) => ({ ...r, run_attempt: 2 })) }] : [pattern, value],
  );
  const api = fakeApi(scenario);
  await collect(holdInput(api));
  assert.ok(restGets(api).some((c) => c.includes("runs/81/jobs")));
  assert.ok(!nodeQueries(api).some((q) => q.variables.ids.includes("WFR_81")));
});

test("the job and step names signal 14 reads are the ones work-unblock.yml uses", () => {
  const text = readFileSync(new URL("../../workflows/work-unblock.yml", import.meta.url), "utf8");
  assert.match(text, new RegExp(`^  ${PUBLISH_LANE_LEVEL_JOB}:$`, "m"));
  for (const name of VARIABLE_STEPS) assert.ok(text.includes(`- name: ${name}\n`), name);
});
