import assert from "node:assert/strict";
import { test } from "node:test";

import { createGitHubApi } from "./dispatch.mjs";
import { dispatchCiFixes, LIST_QUERY } from "./fix-ci-dispatch.mjs";

// The lanes App bot's user id and the GitHub Actions app id
// (.github/standards/trusted-actors/trusted-actors.json; dispatch.mjs).
const APP = 337595936;
const ACTIONS = 15368;

const check = (name, conclusion, extra = {}) => ({
  __typename: "CheckRun",
  name,
  status: conclusion ? "COMPLETED" : "IN_PROGRESS",
  conclusion,
  title: null,
  checkSuite: { app: { databaseId: ACTIONS } },
  ...extra,
});

// A lanes App PR whose head's ci-status failed and has no fix-ci run yet.
function pr(number, { checks = [check("ci-status", "FAILURE")], ...overrides } = {}) {
  const head = String(number).padStart(40, "a");
  return {
    number,
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: head,
    author: { login: "melodic-automation-lanes", databaseId: APP },
    labels: { nodes: [] },
    commits: { nodes: [{ commit: { oid: head, statusCheckRollup: { contexts: { nodes: checks } } } }] },
    ...overrides,
  };
}

function fakeApi({ pages = [[]], cost = 1, workflowRuns = [], failDispatch = new Set(), runIds = new Map() } = {}) {
  const calls = { list: 0, runs: 0, dispatch: [] };
  return {
    calls,
    async listCiFixCandidates({ after }) {
      calls.list += 1;
      const index = after === undefined ? 0 : Number(after);
      return {
        rateLimit: { cost, remaining: 4990 },
        pullRequests: { nodes: pages[index], pageInfo: { hasNextPage: index + 1 < pages.length, endCursor: String(index + 1) } },
      };
    },
    async listWorkflowRuns() {
      calls.runs += 1;
      return workflowRuns;
    },
    async dispatchWorkflow({ workflow, ref, inputs }) {
      calls.dispatch.push({ workflow, ref, inputs });
      if (failDispatch.has(inputs["pr-number"])) {
        throw new Error("dispatch failed");
      }
      return { workflowRunId: runIds.has(inputs["pr-number"]) ? runIds.get(inputs["pr-number"]) : 7000 + Number(inputs["pr-number"]) };
    },
  };
}

async function run(apiOptions, options = {}) {
  const api = fakeApi(apiOptions);
  const lines = [];
  const result = await dispatchCiFixes({
    api,
    runId: "4242",
    log: (line) => lines.push(line),
    appSenderId: APP,
    maxDispatch: 2,
    restarts: 1,
    ...options,
  });
  return { api, lines, result };
}

test("a lanes App PR whose ci-status failed is dispatched fix-ci with the dispatcher's run id", async () => {
  const { api, result } = await run({ pages: [[pr(5)]] });
  assert.deepEqual(result, { dispatched: [{ number: 5, workflowRunId: "7005" }], failed: 0 });
  assert.deepEqual(api.calls.dispatch, [
    {
      workflow: "pr-unblock.yml",
      ref: "refs/heads/main",
      inputs: { "pr-number": "5", activity: "fix-ci", "dispatcher-run-id": "4242" },
    },
  ]);
});

test("other authors, drafts, forks, other bases and held PRs are left alone", async () => {
  const { result } = await run({
    pages: [
      [
        pr(1, { author: { login: "octocat", databaseId: 4242 } }),
        pr(2, { isDraft: true }),
        pr(3, { isCrossRepository: true }),
        pr(4, { baseRefName: "release" }),
        pr(6, { labels: { nodes: [{ name: "needs-human" }] } }),
        pr(7, { labels: { nodes: [{ name: "do-not-merge" }] } }),
        pr(8, { author: { login: "melodic-automation-lanes" } }),
      ],
    ],
  });
  assert.deepEqual(result.dispatched, []);
});

test("a head whose ci-status passed, is pending, is missing or came from another app is left alone", async () => {
  const { result } = await run({
    pages: [
      [
        pr(1, { checks: [check("ci-status", "SUCCESS")] }),
        pr(2, { checks: [check("ci-status", null)] }),
        pr(3, { checks: [] }),
        pr(4, { checks: [check("ci-status", "FAILURE", { checkSuite: { app: { databaseId: 999 } } })] }),
        pr(5, { commits: { nodes: [] } }),
      ],
    ],
  });
  assert.deepEqual(result.dispatched, []);
});

test("a head that already has a fix-ci run is skipped, unless every run failed within the restart count", async () => {
  const fix = (conclusion, extra) => check("pr-unblock / fix-ci", conclusion, extra);
  const failed = check("ci-status", "FAILURE");
  const { result } = await run({
    pages: [
      [
        pr(1, { checks: [failed, fix("SUCCESS")] }),
        pr(2, { checks: [failed, fix("NEUTRAL")] }),
        pr(3, { checks: [failed, fix(null)] }),
        pr(4, { checks: [failed, fix("FAILURE")] }),
        pr(5, { checks: [failed, fix("FAILURE"), fix("FAILURE")] }),
        // An untrusted-trigger skip did not run the lane.
        pr(6, { checks: [failed, fix("NEUTRAL", { title: "Skipped: untrusted-trigger" })] }),
        // Another app's run under the lane's name counts for nothing.
        pr(7, { checks: [failed, fix("SUCCESS", { checkSuite: { app: { databaseId: 999 } } })] }),
      ],
    ],
  }, { maxDispatch: 10 });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [4, 6, 7],
  );
});

test("a restart count of 0 never dispatches a head again", async () => {
  const { result } = await run(
    { pages: [[pr(4, { checks: [check("ci-status", "FAILURE"), check("pr-unblock / fix-ci", "FAILURE")] })]] },
    { restarts: 0 },
  );
  assert.deepEqual(result.dispatched, []);
});

test("at most maxDispatch PRs are dispatched, lowest number first; the rest wait for a later run", async () => {
  const { lines, result } = await run({ pages: [[pr(30), pr(10)], [pr(20)]] });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [10, 20],
  );
  assert.ok(lines.some((line) => line.startsWith("defer fix-ci #30")), lines.join("\n"));
});

test("each listing page is one GraphQL query, and its rate-limit cost is logged", async () => {
  const { api, lines } = await run({ pages: [[pr(1)], [pr(2)]], cost: 3 });
  assert.equal(api.calls.list, 2);
  assert.deepEqual(
    lines.filter((line) => line.startsWith("fix-ci listing")),
    ["fix-ci listing page 1: rateLimit.cost=3 remaining=4990", "fix-ci listing page 2: rateLimit.cost=3 remaining=4990"],
  );
});

test("a fix-ci run for the PR that is not done yet holds the dispatch", async () => {
  const { api, result } = await run({
    pages: [[pr(5), pr(6)]],
    workflowRuns: [
      { id: 1, status: "in_progress", display_title: "pr-unblock fix-ci #5" },
      { id: 2, status: "completed", display_title: "pr-unblock fix-ci #6" },
    ],
  });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [6],
  );
  assert.equal(api.calls.runs, 1);
});

test("no candidate reads no workflow runs", async () => {
  const { api } = await run({ pages: [[pr(1, { isDraft: true })]] });
  assert.equal(api.calls.runs, 0);
});

test("a failed dispatch, or one with no usable run id, counts as failed and still uses the cap", async () => {
  const { result } = await run({ pages: [[pr(1), pr(2), pr(3)]], failDispatch: new Set(["1"]), runIds: new Map([["2", undefined]]) });
  assert.deepEqual(result, { dispatched: [], failed: 2 });
});

test("the adapter sends one query naming the PR, its last commit's check rollup and rateLimit cost", async () => {
  const requests = [];
  const api = createGitHubApi({
    token: "t",
    repository: "octo/repo",
    apiUrl: "https://api.example",
    graphqlUrl: "https://api.example/graphql",
    fetch: async (url, init) => {
      requests.push({ url, body: JSON.parse(init.body) });
      return new Response(
        JSON.stringify({ data: { rateLimit: { cost: 4, remaining: 9 }, repository: { pullRequests: { nodes: [], pageInfo: { hasNextPage: false, endCursor: null } } } } }),
        { status: 200 },
      );
    },
  });
  const page = await api.listCiFixCandidates({ base: "main" });
  assert.equal(page.rateLimit.cost, 4);
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, "https://api.example/graphql");
  assert.equal(requests[0].body.query, LIST_QUERY);
  assert.deepEqual(requests[0].body.variables, { owner: "octo", name: "repo", base: "main", after: null });
  for (const field of ["rateLimit", "cost", "statusCheckRollup", "commits(last: 1)", "databaseId"]) {
    assert.ok(LIST_QUERY.includes(field), field);
  }
});
