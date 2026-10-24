// Expected values come from fix-docs's applies-when in
// docs/conventions/pr-pipeline.yaml (paths **/*.md, labels-absent do-not-merge
// and needs-human, draft false), the check name `pr-refine / fix-docs` the
// read runner posts as `<lane> / <activity>` (and `pr-unblock / fix-docs`, the
// lane fix-docs ran in before), the owner's call to tidy every PR but
// Dependabot's, the release App's and the standards-sync App's, and once per
// PR, as pr-refine.yml's old trigger ran it when a PR opened or turned ready.
import assert from "node:assert/strict";
import { test } from "node:test";

import { emptyRecord, isHandled, markHandled } from "./dispatch-record.mjs";
import { createGitHubApi } from "./dispatch.mjs";
import { dispatchDocsFixes, HISTORY_COMMITS, HISTORY_QUERY, LIST_QUERY } from "./fix-docs-dispatch.mjs";

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

function fakeApi({ pages = [[]], histories = {}, workflowRuns = [], failHistory = new Set(), comments = new Map(), labelEvents = new Map() } = {}) {
  const calls = { history: [], dispatch: [] };
  return {
    calls,
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
