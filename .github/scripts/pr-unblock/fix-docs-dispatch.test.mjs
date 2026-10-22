// Expected values come from fix-docs's applies-when in
// docs/conventions/pr-pipeline.yaml (paths **/*.md, labels-absent do-not-merge
// and needs-human, draft false), the check name `pr-unblock / fix-docs` the
// read runner posts as `<lane> / <activity>`, and pr-refine.yml's old trigger:
// once when a PR opened ready or turned ready, never on a bot's event.
import assert from "node:assert/strict";
import { test } from "node:test";

import { emptyRecord, isHandled, markHandled } from "./dispatch-record.mjs";
import { createGitHubApi } from "./dispatch.mjs";
import { dispatchDocsFixes, HISTORY_COMMITS, HISTORY_QUERY, LIST_QUERY } from "./fix-docs-dispatch.mjs";

const ACTIONS = 15368;
const CHECK = "pr-unblock / fix-docs";

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
    author: { __typename: "User", login: "someone" },
    labels: { nodes: [] },
    files: { nodes: paths.map((path) => ({ path })), pageInfo: { hasNextPage: more } },
    commits: { nodes: [{ commit: { oid: head, statusCheckRollup: { contexts: { nodes: checks, pageInfo: { hasNextPage: false } } } } }] },
    ...overrides,
  };
}

// Per PR number, the check-run counts on each of its last commits; absent is none.
const history = (counts = []) => ({
  commits: { nodes: counts.map((count) => ({ commit: { checkSuites: { nodes: [{ checkRuns: { totalCount: count } }], pageInfo: { hasNextPage: false } } } })) },
});

function fakeApi({ pages = [[]], histories = {}, workflowRuns = [], failHistory = new Set() } = {}) {
  const calls = { history: [], dispatch: [] };
  return {
    calls,
    async listDocsFixCandidates({ after }) {
      const index = after === undefined ? 0 : Number(after);
      return {
        rateLimit: { cost: 3, remaining: 4990 },
        pullRequests: { nodes: pages[index], pageInfo: { hasNextPage: index + 1 < pages.length, endCursor: String(index + 1) } },
      };
    },
    async readDocsFixHistory({ number, appId, checkName }) {
      calls.history.push({ number, appId, checkName });
      if (failHistory.has(number)) {
        throw new Error("history read failed");
      }
      return { rateLimit: { cost: 1, remaining: 4989 }, pullRequest: histories[number] ?? history([0]) };
    },
    async listWorkflowRuns() {
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

test("a ready PR a person opened that changes Markdown is dispatched fix-docs on main with the dispatcher's run id", async () => {
  const { api, result, lines } = await run({ pages: [[pr(5)]] });
  assert.deepEqual(api.calls.dispatch, [
    { workflow: "pr-unblock.yml", ref: "refs/heads/main", inputs: { "pr-number": "5", activity: "fix-docs", "dispatcher-run-id": "4242" } },
  ]);
  assert.deepEqual(result, { dispatched: [{ number: 5, workflowRunId: "8005" }], failed: 0 });
  assert.deepEqual(api.calls.history, [{ number: 5, appId: ACTIONS, checkName: CHECK }]);
  assert.ok(lines.includes("fix-docs listing page 1: rateLimit.cost=3 remaining=4990"), "the listing's cost is logged");
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

test("PRs the lanes App, Dependabot or any other bot opened are not dispatched, as pr-refine.yml skipped bot events", async () => {
  const pulls = [
    pr(20, { author: { __typename: "Bot", login: "melodic-automation-lanes" } }),
    pr(21, { author: { __typename: "Bot", login: "dependabot" } }),
    pr(22, { author: null }),
    pr(23),
  ];
  assert.deepEqual(numbers((await run({ pages: [pulls] })).api), ["23"]);
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
      { id: 1, status: "in_progress", display_title: "pr-unblock fix-docs #50" },
      { id: 2, status: "completed", display_title: "pr-unblock fix-docs #51" },
      { id: 3, status: "queued", display_title: "pr-unblock fix-ci #51" },
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
  const read = await api.readDocsFixHistory({ number: 9, appId: ACTIONS, checkName: CHECK });
  assert.deepEqual(bodies[0].variables, { owner: "octo", name: "repo", base: "main", after: null });
  assert.deepEqual(bodies[1].variables, { owner: "octo", name: "repo", number: 9, appId: ACTIONS, checkName: CHECK });
  assert.equal(bodies[1].query, HISTORY_QUERY);
  assert.match(HISTORY_QUERY, new RegExp(`commits\\(last: ${HISTORY_COMMITS}\\)`));
  assert.deepEqual(read.pullRequest, history([0]));
});
