// Expected values come from fix-docs's applies-when in
// docs/conventions/pr-pipeline.yaml (paths **/*.md, labels-absent do-not-merge
// and needs-human, draft false), the check name `pr-refine / fix-docs` the
// read runner posts as `<lane> / <activity>` (and `pr-unblock / fix-docs`, the
// lane fix-docs ran in before), the owner's call to tidy every PR but
// Dependabot's, the release App's and the standards-sync App's, and once per
// PR, as pr-refine.yml's old trigger ran it when a PR opened or turned ready.
import assert from "node:assert/strict";
import { test } from "node:test";

import { emptyRecord, isHandled, markHandled, parseRecord, serializeRecord } from "./dispatch-record.mjs";
import { createGitHubApi } from "./dispatch.mjs";
import { dispatchDocsFixes, docsRunState, HISTORY_COMMITS, HISTORY_QUERY, LIST_QUERY } from "./fix-docs-dispatch.mjs";

const ACTIONS = 15368;
const CHECK = "pr-refine / fix-docs";
const EARLIER_CHECK = "pr-unblock / fix-docs";
// GET /users/<login> ids, which GraphQL's Bot.databaseId returns too.
const DEPENDABOT = 49699333;
const RELEASE_APP = 337859524;
const STANDARDS_SYNC_APP = 300666570;
const LANES_APP = 337595936;

const checkRun = (name, app = ACTIONS) => ({ __typename: "CheckRun", name, checkSuite: { app: { databaseId: app } } });

// A ready PR a person opened that changes a Markdown file, with no fix-docs run.
function pr(number, { paths = ["docs/guide.md"], more = false, checks = [], ...overrides } = {}) {
  const head = String(number).padStart(40, "d");
  return {
    number,
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: head,
    author: { __typename: "User", login: "someone", databaseId: 4242 },
    labels: { nodes: [] },
    files: { nodes: paths.map((path) => ({ path })), pageInfo: { hasNextPage: more } },
    commits: { nodes: [{ commit: { oid: head, statusCheckRollup: { contexts: { nodes: checks, pageInfo: { hasNextPage: false } } } } }] },
    ...overrides,
  };
}

// Per PR number, the check-run counts on each of its last commits; absent is
// none. `earlier` gives the counts under the earlier check name.
const history = (counts = [], earlier = counts.map(() => 0)) => ({
  commits: {
    nodes: counts.map((count, index) => ({
      commit: {
        checkSuites: { nodes: [{ checkRuns: { totalCount: count }, earlierRuns: { totalCount: earlier[index] } }], pageInfo: { hasNextPage: false } },
      },
    })),
  },
});

function fakeApi({ pages = [[]], histories = {}, workflowRuns = [], failHistory = new Set(), comments = new Map(), labelEvents = new Map(), runJobs = new Map() } = {}) {
  const calls = { history: [], dispatch: [], jobs: [] };
  return {
    calls,
    // Per run id, its status and latest jobs, null when it is gone, or the
    // error the read throws.
    async readRunJobs(runId) {
      calls.jobs.push(runId);
      const read = runJobs.get(runId);
      if (read instanceof Error) {
        throw read;
      }
      return read ?? null;
    },
    // The REST issue timeline: its comments, then its label events.
    async listTimeline(number) {
      return [...(comments.get(number) ?? []).map((comment) => ({ event: "commented", ...comment })), ...(labelEvents.get(number) ?? [])];
    },
    async listDocsFixCandidates({ after }) {
      const index = after === undefined ? 0 : Number(after);
      return {
        rateLimit: { cost: 3, remaining: 4990 },
        pullRequests: { nodes: pages[index], pageInfo: { hasNextPage: index + 1 < pages.length, endCursor: String(index + 1) } },
      };
    },
    async readDocsFixHistory({ number, appId, checkName, earlierCheckName }) {
      calls.history.push({ number, appId, checkName, earlierCheckName });
      if (failHistory.has(number)) {
        throw new Error("history read failed");
      }
      return { rateLimit: { cost: 1, remaining: 4989 }, pullRequest: histories[number] ?? history([0]) };
    },
    async listWorkflowRuns() {
      if (workflowRuns instanceof Error) {
        throw workflowRuns;
      }
      return workflowRuns;
    },
    async dispatchWorkflow({ workflow, ref, inputs }) {
      calls.dispatch.push({ workflow, ref, inputs });
      return { workflowRunId: 8000 + Number(inputs["pr-number"]) };
    },
  };
}

async function run(apiOptions, options = {}) {
  const api = fakeApi(apiOptions);
  const lines = [];
  const record = options.record ?? emptyRecord();
  const result = await dispatchDocsFixes({ api, runId: "4242", log: (line) => lines.push(line), maxDispatch: 2, record, ...options });
  return { api, lines, result, record };
}

const numbers = (api) => api.calls.dispatch.map((call) => call.inputs["pr-number"]);

test("a ready PR a person opened that changes Markdown is dispatched pr-refine.yml fix-docs on main with the dispatcher's run id", async () => {
  const { api, result, lines } = await run({ pages: [[pr(5)]] });
  assert.deepEqual(api.calls.dispatch, [
    { workflow: "pr-refine.yml", ref: "refs/heads/main", inputs: { "pr-number": "5", activity: "fix-docs", "dispatcher-run-id": "4242" } },
  ]);
  assert.deepEqual(result, { dispatched: [{ number: 5, workflowRunId: "8005" }], failed: 0 });
  assert.deepEqual(api.calls.history, [{ number: 5, appId: ACTIONS, checkName: CHECK, earlierCheckName: EARLIER_CHECK }]);
  assert.ok(lines.includes("fix-docs listing page 1: rateLimit.cost=3 remaining=4990"), "the listing's cost is logged");
});

test("a rate-limited run listing defers with a warning; any other listing error fails", async () => {
  const limited = Object.assign(new Error("GET runs returned 403"), { rateLimited: true });
  const deferred = await run({ pages: [[pr(5)]], workflowRuns: limited });
  assert.deepEqual(deferred.result, { dispatched: [], failed: 0 });
  assert.ok(deferred.lines.some((line) => line.startsWith("::warning::") && line.includes("rate limited")));
  const broken = await run({ pages: [[pr(5)]], workflowRuns: new Error("GET runs returned 404") });
  assert.deepEqual(broken.result, { dispatched: [], failed: 1 });
  assert.ok(broken.lines.some((line) => line.startsWith("::error::") && line.includes("404")));
});

test("a PR that changes no Markdown file is not dispatched; a file list cut off at 100 leaves it to the lane", async () => {
  assert.deepEqual(numbers((await run({ pages: [[pr(6, { paths: ["src/a.js", "README.txt", "notes.mdx"] })]] })).api), []);
  assert.deepEqual(numbers((await run({ pages: [[pr(7, { paths: ["src/a.js"], more: true })]] })).api), ["7"]);
  assert.deepEqual(numbers((await run({ pages: [[pr(8, { paths: ["a/b/c.md"] })]] })).api), ["8"]);
});

test("a draft, a fork, a PR into another base, or a held PR is not dispatched", async () => {
  const pulls = [
    pr(10, { isDraft: true }),
    pr(11, { isCrossRepository: true }),
    pr(12, { baseRefName: "release" }),
    pr(13, { labels: { nodes: [{ name: "do-not-merge" }] } }),
    pr(14, { labels: { nodes: [{ name: "needs-human" }] } }),
  ];
  const { api } = await run({ pages: [pulls] });
  assert.deepEqual(numbers(api), []);
  assert.deepEqual(api.calls.history, [], "no history read for a PR the listing drops");
});

// report-escalation.sh's comment and label, by the lanes App, or the label by a person.
const APP_USER = { login: "melodic-automation-lanes[bot]", id: LANES_APP, type: "Bot" };
const labeledBy = (actor) => [{ event: "labeled", actor, label: { name: "needs-human" }, created_at: "2026-10-22T10:00:00Z" }];
const escalation = [
  {
    user: APP_USER,
    created_at: "2026-10-22T10:00:05Z",
    body: `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${"b".repeat(40)} -->\nStopped.\n\n- Reason: \`ci-fix-escalated\``,
  },
];

test("needs-human from a lane escalation does not hold fix-docs, which never escalates; a person's does", async () => {
  const gated = { labels: { nodes: [{ name: "needs-human" }] } };
  const { api, record } = await run(
    {
      pages: [[pr(15, gated), pr(16, gated)]],
      comments: new Map([[15, escalation]]),
      labelEvents: new Map([
        [15, labeledBy(APP_USER)],
        [16, labeledBy({ login: "kyle-sexton", id: 153232337, type: "User" })],
      ]),
    },
    { gateLabel: "needs-human", appSenderId: LANES_APP },
  );
  assert.deepEqual(numbers(api), ["15"]);
  assert.equal(isHandled(record, CHECK, pr(16).headRefOid), false, "a held PR is not done");
});

test("PRs the lanes App or another bot opened are dispatched; Dependabot's, the release App's and the standards-sync App's are not", async () => {
  const pulls = [
    pr(20, { author: { __typename: "Bot", login: "melodic-automation-lanes", databaseId: LANES_APP } }),
    pr(21, { author: { __typename: "Bot", login: "dependabot", databaseId: DEPENDABOT } }),
    pr(22, { author: { __typename: "Bot", login: "melodic-plugin-release", databaseId: RELEASE_APP } }),
    pr(23, { author: { __typename: "Bot", login: "melodic-standards-sync", databaseId: STANDARDS_SYNC_APP } }),
    pr(24, { author: { __typename: "Bot", login: "claude", databaseId: 209825114 } }),
    pr(25),
  ];
  assert.deepEqual(numbers((await run({ pages: [pulls] })).api), ["20", "24"]);
});

test("an excluded account is matched by id, not login, and a PR whose author has no id is not dispatched", async () => {
  const pulls = [
    pr(26, { author: { __typename: "Bot", login: "renamed-dependabot", databaseId: DEPENDABOT } }),
    pr(27, { author: { __typename: "User", login: "dependabot" } }),
    pr(28, { author: null }),
    pr(29, { author: { __typename: "Bot", login: "x", databaseId: "49699333" } }),
  ];
  assert.deepEqual(numbers((await run({ pages: [pulls] })).api), []);
});

test("a head or an earlier commit with a pr-unblock / fix-docs run, from before the lane moved, is not dispatched again", async () => {
  const record = emptyRecord();
  markHandled(record, EARLIER_CHECK, pr(38).headRefOid);
  const { api } = await run({
    pages: [[pr(36, { checks: [checkRun(EARLIER_CHECK)] }), pr(37), pr(38), pr(39)]],
    histories: { 37: history([0, 0], [0, 1]) },
  }, { record });
  assert.deepEqual(numbers(api), ["39"]);
  assert.deepEqual(api.calls.history.map((call) => call.number), [37, 39], "a head recorded under the earlier name skips its read");
  assert.ok(isHandled(record, CHECK, pr(36).headRefOid), "a head handled under the earlier name is recorded under the current one");
  assert.ok(isHandled(record, CHECK, pr(37).headRefOid));
});

test("once per PR: a head with a fix-docs run, or any earlier commit with one, is not dispatched again", async () => {
  const { api, record } = await run({
    pages: [[pr(30, { checks: [checkRun(CHECK)] }), pr(31), pr(32)]],
    histories: { 31: history([0, 1, 0]) },
  });
  assert.deepEqual(numbers(api), ["32"]);
  assert.ok(isHandled(record, CHECK, pr(30).headRefOid), "the head's own run is recorded");
  assert.ok(isHandled(record, CHECK, pr(31).headRefOid), "an earlier commit's run is recorded");
  assert.ok(!isHandled(record, CHECK, pr(32).headRefOid), "a dispatch is not recorded as handled");
});

test("a run another app posted under the name does not count", async () => {
  assert.deepEqual(numbers((await run({ pages: [[pr(33, { checks: [checkRun(CHECK, 999)] })]] })).api), ["33"]);
});

test("a commit whose check suites were not listed whole counts as having a run", async () => {
  const cut = { commits: { nodes: [{ commit: { checkSuites: { nodes: [], pageInfo: { hasNextPage: true } } } }] } };
  assert.deepEqual(numbers((await run({ pages: [[pr(34)]], histories: { 34: cut } })).api), []);
});

test("a recorded head is skipped without a history read", async () => {
  const record = emptyRecord();
  markHandled(record, CHECK, pr(35).headRefOid);
  const { api } = await run({ pages: [[pr(35)]] }, { record });
  assert.deepEqual(numbers(api), []);
  assert.deepEqual(api.calls.history, []);
});

test("at most maxDispatch per run, lowest PR number first; a PR with history does not use a slot", async () => {
  const { api, lines } = await run({ pages: [[pr(44), pr(41), pr(43), pr(42)]], histories: { 41: history([1]) } });
  assert.deepEqual(numbers(api), ["42", "43"]);
  assert.ok(lines.some((line) => line.startsWith("defer fix-docs #44")));
});

test("a fix-docs run still queued or going for the PR holds the dispatch", async () => {
  const { api } = await run({
    pages: [[pr(50), pr(51)]],
    workflowRuns: [
      { id: 1, status: "in_progress", display_title: "pr-refine fix-docs #50" },
      { id: 2, status: "completed", display_title: "pr-refine fix-docs #51" },
      { id: 3, status: "queued", display_title: "pr-unblock fix-docs #51" },
    ],
  });
  assert.deepEqual(numbers(api), ["51"]);
});

test("a failed history read counts as a failure and dispatches nothing for that PR", async () => {
  const { api, result } = await run({ pages: [[pr(60), pr(61)]], failHistory: new Set([60]) });
  assert.deepEqual(numbers(api), ["61"]);
  assert.equal(result.failed, 1);
});

test("every listing page is read", async () => {
  assert.deepEqual(numbers((await run({ pages: [[pr(70)], [pr(71)]] })).api), ["70", "71"]);
});

// A fix-docs run's status and latest jobs as the REST listings name them:
// pr-refine.yml's fix-docs call's jobs are `fix-docs / <job>`
// (pr-run-activity-read.yml's broker-check, broker-allowed, run and report).
const job = (name, conclusion, status = "completed") => ({ name, status, conclusion });
const ended = (...jobs) => ({ status: "completed", jobs });
// The broker allowed it and its run job emitted an empty head: no check posted.
const EMPTY_HEAD = ended(
  job("fix-docs-head", "success"),
  job("fix-docs / broker-check", "success"),
  job("fix-docs / broker-allowed", "success"),
  job("fix-docs / run", "success"),
  job("fix-docs / report", "success"),
  job("fix-docs-handoff", "success"),
);
// The broker refused it: broker-allowed and the run job skipped.
const REFUSED = ended(
  job("fix-docs-head", "success"),
  job("fix-docs / broker-check", "failure"),
  job("fix-docs / broker-allowed", "skipped"),
  job("fix-docs / run", "skipped"),
  job("fix-docs / report", "success"),
  job("fix-docs-handoff", "success"),
);
// fix-docs-head found a person's hold: the call never started.
const HELD = ended(job("fix-docs-head", "success"), job("fix-docs", "skipped"));
const GOING = { status: "in_progress", jobs: [job("fix-docs-head", "success"), job("fix-docs / broker-check", null, "in_progress")] };

test("docsRunState: only a succeeded broker-allowed job counts; a run that ended without one, or is gone, is done; any other is going", () => {
  assert.equal(docsRunState(EMPTY_HEAD), "allowed");
  assert.equal(docsRunState(REFUSED), "done");
  assert.equal(docsRunState(HELD), "done");
  assert.equal(docsRunState(GOING), "going");
  assert.equal(docsRunState({ status: "queued", jobs: [] }), "going", "a run with no job listed yet");
  assert.equal(docsRunState(ended()), "done", "a run that ended with no job, as a startup failure does");
  assert.equal(docsRunState(null), "done", "a run that is gone");
  assert.equal(docsRunState(ended(job("fix-docs / run", "success"))), "done", "a run job's success is not the broker's allow");
});

// Run ids the dispatch record keeps for a head.
const kept = (record, number, ids) => record.docsRuns.set(pr(number).headRefOid, ids);

test("a head whose fix-docs runs reach the per-head cap with no check run is not dispatched, recorded, and warned about once; a head below it is dispatched", async () => {
  const record = emptyRecord();
  kept(record, 80, ["101", "102", "103"]);
  kept(record, 81, ["111", "112"]);
  const runJobs = new Map(["101", "102", "103"].map((id) => [id, EMPTY_HEAD]));
  const { api, lines, result } = await run({ pages: [[pr(80), pr(81)]], runJobs }, { record });
  assert.deepEqual(numbers(api), ["81"]);
  assert.deepEqual(result, { dispatched: [{ number: 81, workflowRunId: "8081" }], failed: 0 });
  assert.deepEqual(lines.filter((line) => line.startsWith("::warning::")), [
    `::warning::#80: head ${pr(80).headRefOid}'s fix-docs ran 3 time(s) with no ${CHECK} check run, the most one head gets; no fix-docs until a new push`,
  ]);
  assert.ok(isHandled(record, CHECK, pr(80).headRefOid), "the capped head goes into the dispatch record");
  assert.equal(record.docsRuns.has(pr(80).headRefOid), false);
  assert.deepEqual(api.calls.jobs, ["101", "102", "103"], "a head below the cap reads no runs");
  assert.deepEqual(record.docsRuns.get(pr(81).headRefOid), ["111", "112", "8081"], "the dispatch joins its head's runs");

  const next = await run({ pages: [[pr(80)]], runJobs }, { record: parseRecord(serializeRecord(record)) });
  assert.deepEqual(numbers(next.api), []);
  assert.deepEqual([next.api.calls.history, next.api.calls.jobs], [[], []], "the recorded head is skipped before any read");
  assert.deepEqual(next.lines.filter((line) => line.startsWith("::warning::")), []);
});

test("broker-refused, held and gone runs do not count toward the cap and leave the list; a run still going stays", async () => {
  const record = emptyRecord();
  kept(record, 82, ["201", "202", "203", "204", "205"]);
  const runJobs = new Map([["201", EMPTY_HEAD], ["202", REFUSED], ["203", HELD], ["204", GOING], ["205", null]]);
  const { api } = await run({ pages: [[pr(82)]], runJobs }, { record });
  assert.deepEqual(numbers(api), ["82"]);
  assert.deepEqual(record.docsRuns.get(pr(82).headRefOid), ["201", "204", "8082"]);
  assert.equal(isHandled(record, CHECK, pr(82).headRefOid), false);
});

test("maxRunsPerHead sets the cap", async () => {
  const record = emptyRecord();
  kept(record, 83, ["301"]);
  const { api } = await run({ pages: [[pr(83)]], runJobs: new Map([["301", EMPTY_HEAD]]) }, { record, maxRunsPerHead: 1 });
  assert.deepEqual(numbers(api), []);
  assert.ok(isHandled(record, CHECK, pr(83).headRefOid));
});

test("a head whose runs cannot be read is not dispatched: a rate limit or a server error warns, any other error fails", async () => {
  const cases = [
    [Object.assign(new Error("GET jobs returned 403"), { rateLimited: true }), 0],
    [Object.assign(new Error("GET jobs returned 502"), { status: 502 }), 0],
    [Object.assign(new Error("GET jobs returned 401"), { status: 401 }), 1],
  ];
  for (const [error, failed] of cases) {
    const record = emptyRecord();
    kept(record, 84, ["401", "402", "403"]);
    const runJobs = new Map([["401", EMPTY_HEAD], ["402", error], ["403", EMPTY_HEAD]]);
    const { api, result } = await run({ pages: [[pr(84)]], runJobs }, { record });
    assert.deepEqual(numbers(api), [], error.message);
    assert.equal(result.failed, failed, error.message);
    assert.equal(isHandled(record, CHECK, pr(84).headRefOid), false, error.message);
    assert.deepEqual(record.docsRuns.get(pr(84).headRefOid), ["401", "402", "403"], error.message);
  }
});

test("the GitHub API reads a run's status and its latest jobs as one complete page; a gone run reads null", async () => {
  const urls = [];
  const responses = [
    { ok: true, status: 200, body: { id: 38779200001, status: "completed" } },
    { ok: true, status: 200, body: { total_count: 1, jobs: [job("fix-docs / broker-allowed", "success")] } },
    { ok: false, status: 404, body: {} },
    { ok: true, status: 200, body: { id: 38779200003, status: "completed" } },
    { ok: true, status: 200, body: { total_count: 101, jobs: [] } },
  ];
  const api = createGitHubApi({
    token: "t",
    repository: "octo/repo",
    apiUrl: "https://api.example",
    graphqlUrl: "https://api.example/graphql",
    fetch: async (url) => {
      urls.push(url);
      const { ok, status, body } = responses.shift();
      return { ok, status, json: async () => body };
    },
  });
  assert.deepEqual(await api.readRunJobs("38779200001"), { status: "completed", jobs: [job("fix-docs / broker-allowed", "success")] });
  assert.deepEqual(urls, [
    "https://api.example/repos/octo/repo/actions/runs/38779200001",
    "https://api.example/repos/octo/repo/actions/runs/38779200001/jobs?filter=latest&per_page=100",
  ]);
  assert.equal(await api.readRunJobs("38779200002"), null);
  await assert.rejects(api.readRunJobs("38779200003"), /not one complete page/);
  await assert.rejects(api.readRunJobs("../1"), /not a run id/);
});

test("the GitHub API sends the listing and history queries with their variables", async () => {
  const bodies = [];
  const fetch = async (url, init) => {
    const body = JSON.parse(init.body);
    bodies.push(body);
    const data = body.query === LIST_QUERY
      ? { rateLimit: { cost: 1, remaining: 1 }, repository: { pullRequests: { nodes: [], pageInfo: { hasNextPage: false, endCursor: null } } } }
      : { rateLimit: { cost: 1, remaining: 1 }, repository: { pullRequest: history([0]) } };
    return { ok: true, status: 200, json: async () => ({ data }) };
  };
  const api = createGitHubApi({ token: "t", repository: "octo/repo", apiUrl: "https://api.example", graphqlUrl: "https://api.example/graphql", fetch });
  await api.listDocsFixCandidates({ base: "main" });
  const read = await api.readDocsFixHistory({ number: 9, appId: ACTIONS, checkName: CHECK, earlierCheckName: EARLIER_CHECK });
  assert.deepEqual(bodies[0].variables, { owner: "octo", name: "repo", base: "main", after: null });
  assert.deepEqual(bodies[1].variables, { owner: "octo", name: "repo", number: 9, appId: ACTIONS, checkName: CHECK, earlierCheckName: EARLIER_CHECK });
  assert.match(LIST_QUERY, /\.\.\. on Bot \{ databaseId \}/);
  assert.match(LIST_QUERY, /\.\.\. on User \{ databaseId \}/);
  assert.equal(bodies[1].query, HISTORY_QUERY);
  assert.match(HISTORY_QUERY, new RegExp(`commits\\(last: ${HISTORY_COMMITS}\\)`));
  assert.deepEqual(read.pullRequest, history([0]));
});
