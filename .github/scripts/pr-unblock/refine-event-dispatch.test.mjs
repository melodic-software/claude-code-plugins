// Expected values come from ADR 0090 and the trusted-trigger gate's contract
// for a pull_request_target dispatcher: one pr-refine.yml fix-docs dispatch
// on refs/heads/main naming this run as dispatcher-run-id, for the event's PR
// alone, under fix-docs-dispatch.mjs's once-per-PR rule (check name
// `pr-refine / fix-docs`, limits.fix-docs-per-run 0 turning it off).
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { createGitHubApi, PULL_QUERY } from "./dispatch.mjs";
import { main, REFINE_ACTIVITIES } from "./refine-event-dispatch.mjs";

const HEAD = "a".repeat(40);
const checkRun = (name) => ({ __typename: "CheckRun", name, checkSuite: { app: { databaseId: 15368 } } });

function pr({ checks = [], paths = ["docs/guide.md"], ...overrides } = {}) {
  return {
    number: 77,
    state: "OPEN",
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: HEAD,
    author: { __typename: "User", login: "someone", databaseId: 4242 },
    labels: { nodes: [] },
    files: { nodes: paths.map((path) => ({ path })), pageInfo: { hasNextPage: false } },
    commits: { nodes: [{ commit: { oid: HEAD, statusCheckRollup: { contexts: { nodes: checks, pageInfo: { hasNextPage: false } } } } }] },
    ...overrides,
  };
}

function fakeApi({ node = pr(), historyRuns = 0 } = {}) {
  const calls = { read: [], dispatch: [] };
  return {
    calls,
    async readDocsFixCandidate(number) {
      calls.read.push(number);
      return { rateLimit: { cost: 1 }, pullRequests: { nodes: node ? [node] : [], pageInfo: { hasNextPage: false } } };
    },
    async listWorkflowRuns() {
      return [];
    },
    async readDocsFixHistory() {
      return {
        rateLimit: { cost: 1 },
        pullRequest: { commits: { nodes: [{ commit: { checkSuites: { nodes: [{ checkRuns: { totalCount: historyRuns }, earlierRuns: { totalCount: 0 } }], pageInfo: { hasNextPage: false } } } }] } },
      };
    },
    listTimeline: async () => [],
    listReviewComments: async () => [],
    listReviews: async () => [],
    readRunJobs: async () => null,
    async dispatchWorkflow(request) {
      calls.dispatch.push(request);
      return { workflowRunId: 9001 };
    },
  };
}

async function run(api, { prNumber = "77", limits = {}, sender = "4242", attempt = "1", activities = [] } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "refine-event-"));
  const lines = [];
  try {
    const env = { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: "555", RUN_IDS_FILE: join(dir, "ids"), PR_NUMBER: prNumber, APP_SENDER_ID: "1", SENDER_ID: sender, ...(attempt === null ? {} : { RUN_ATTEMPT: attempt }) };
    const code = await main(env, { api, log: (line) => lines.push(line), loadLimits: async () => limits, loadTidyCutoffs: async () => null, loadActivities: async () => activities, readGateLabel: () => null, readHumans: () => new Set([4242]) });
    let ids = "";
    try {
      ids = readFileSync(env.RUN_IDS_FILE, "utf8");
    } catch {}
    return { code, ids, lines };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("a ready Markdown PR with no fix-docs run gets one pr-refine dispatch on main naming this run, recorded at once", async () => {
  const api = fakeApi();
  const { code, ids } = await run(api);
  assert.equal(code, 0);
  assert.deepEqual(api.calls.read, [77]);
  assert.deepEqual(api.calls.dispatch, [
    { workflow: "pr-refine.yml", ref: "refs/heads/main", inputs: { "pr-number": "77", activity: "fix-docs", "dispatcher-run-id": "555" } },
  ]);
  assert.equal(ids, "9001\n");
});

test("once per PR: a head with a fix-docs check run, or an earlier commit with one, dispatches nothing", async () => {
  const onHead = fakeApi({ node: pr({ checks: [checkRun("pr-refine / fix-docs")] }) });
  assert.equal((await run(onHead)).code, 0);
  assert.deepEqual(onHead.calls.dispatch, []);
  const earlier = fakeApi({ historyRuns: 1 });
  assert.equal((await run(earlier)).code, 0);
  assert.deepEqual(earlier.calls.dispatch, []);
});

test("a draft, a PR with no Markdown file, a closed PR or fix-docs-per-run 0 dispatches nothing", async () => {
  for (const [what, api, limits] of [
    ["draft", fakeApi({ node: pr({ isDraft: true }) }), {}],
    ["no Markdown", fakeApi({ node: pr({ paths: ["src/a.js"] }) }), {}],
    ["closed", fakeApi({ node: null }), {}],
    ["off", fakeApi(), { "fix-docs-per-run": 0 }],
  ]) {
    const { code, ids } = await run(api, { limits });
    assert.equal(code, 0, what);
    assert.deepEqual(api.calls.dispatch, [], what);
    assert.equal(ids, "", what);
  }
});

// The gate vouches only for a dispatcher run the lanes App or a listed human started.
test("an event the lanes App or a listed human sent dispatches; any other sender reads and dispatches nothing", async () => {
  const app = fakeApi();
  await run(app, { sender: "1" });
  assert.equal(app.calls.dispatch.length, 1, "the lanes App");
  for (const sender of ["999", "", "x"]) {
    const api = fakeApi();
    const { code, ids } = await run(api, { sender });
    assert.equal(code, 0, sender);
    assert.deepEqual(api.calls.read, [], sender);
    assert.deepEqual(api.calls.dispatch, [], sender);
    assert.equal(ids, "", sender);
  }
});

// A re-run keeps the event's sender whoever started it, so only attempt 1 dispatches.
test("only an event run's first attempt dispatches; a re-run or an unread attempt reads and dispatches nothing", async () => {
  const first = fakeApi();
  await run(first, { attempt: "1" });
  assert.equal(first.calls.dispatch.length, 1, "attempt 1");
  for (const attempt of ["2", null, "", "1x", "01"]) {
    const api = fakeApi();
    const { code, ids, lines } = await run(api, { attempt });
    assert.equal(code, 0, String(attempt));
    assert.deepEqual(api.calls.read, [], String(attempt));
    assert.deepEqual(api.calls.dispatch, [], String(attempt));
    assert.equal(ids, "", String(attempt));
    assert.ok(lines.some((line) => line.startsWith("::notice::skip fix-docs #77: this run is not its event's first attempt")), String(attempt));
  }
});

test("a PR number that is not a number reads and dispatches nothing", async () => {
  for (const prNumber of ["", "0", "77; echo", "refs/heads/x"]) {
    const api = fakeApi();
    await assert.rejects(run(api, { prNumber }), /PR_NUMBER is not a pull request number/);
    assert.deepEqual(api.calls.read, [], prNumber);
  }
});

test("readDocsFixCandidate reads the one PR with the listing's fields and lists it only while open", async () => {
  const sent = [];
  const answer = (state) => async (url, init) => {
    sent.push(JSON.parse(init.body));
    return new Response(JSON.stringify({ data: { rateLimit: { cost: 1 }, repository: { pullRequest: { number: 77, state } } } }), { status: 200 });
  };
  const open = createGitHubApi({ token: "t", repository: "o/r", apiUrl: "https://api", graphqlUrl: "https://gql", fetch: answer("OPEN") });
  assert.deepEqual((await open.readDocsFixCandidate(77)).pullRequests, { nodes: [{ number: 77, state: "OPEN" }], pageInfo: { hasNextPage: false } });
  assert.deepEqual(sent[0], { query: PULL_QUERY, variables: { owner: "o", name: "r", number: 77 } });
  for (const field of ["isDraft", "isCrossRepository", "headRefOid", "files(first: 100)", "statusCheckRollup"]) {
    assert.ok(PULL_QUERY.includes(field), field);
  }
  const closed = createGitHubApi({ token: "t", repository: "o/r", apiUrl: "https://api", graphqlUrl: "https://gql", fetch: answer("CLOSED") });
  assert.deepEqual((await closed.readDocsFixCandidate(77)).pullRequests.nodes, []);
});

test("by default the sender check reads the humans of the base's trusted-actor list: a listed human dispatches, a listed bot or an unlisted id does not", async () => {
  const base = mkdtempSync(join(tmpdir(), "refine-event-base-"));
  try {
    mkdirSync(join(base, ".github/standards/trusted-actors"), { recursive: true });
    writeFileSync(
      join(base, ".github/standards/trusted-actors/trusted-actors.json"),
      JSON.stringify({ version: 1, actors: [{ id: 4242, login: "someone", kind: "human" }, { id: 31337, login: "helper[bot]", kind: "bot" }] }),
    );
    for (const [sender, dispatched] of [["4242", 1], ["31337", 0], ["999", 0]]) {
      const dir = mkdtempSync(join(tmpdir(), "refine-event-"));
      try {
        const api = fakeApi();
        const env = { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: "555", RUN_IDS_FILE: join(dir, "ids"), PR_NUMBER: "77", APP_SENDER_ID: "1", SENDER_ID: sender, RUN_ATTEMPT: "1", BASE_PATH: base };
        assert.equal(await main(env, { api, log: () => {}, loadLimits: async () => ({}), loadTidyCutoffs: async () => null, loadActivities: async () => [], readGateLabel: () => null }), 0);
        assert.equal(api.calls.dispatch.length, dispatched, `sender ${sender}`);
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    }
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});

// refine-dispatch.activities (owner decision 2026-11-12): each listed id is one
// more pr-refine.yml dispatch on main with the same three inputs as fix-docs's.
const markerDispatch = { workflow: "pr-refine.yml", ref: "refs/heads/main", inputs: { "pr-number": "77", activity: "fix-marker", "dispatcher-run-id": "555" } };

test("the allowlist holds fix-marker alone", () => {
  assert.deepEqual(REFINE_ACTIVITIES, ["fix-marker"]);
});

test("a listed human's event dispatches each configured activity after fix-docs, each id recorded on its own line", async () => {
  const api = fakeApi();
  const { code, ids } = await run(api, { activities: ["fix-marker"] });
  assert.equal(code, 0);
  assert.deepEqual(api.calls.dispatch.map((request) => request.inputs.activity), ["fix-docs", "fix-marker"]);
  assert.deepEqual(api.calls.dispatch[1], markerDispatch);
  assert.equal(ids, "9001\n9001\n");
});

test("a configured activity needs no fix-docs: none due, fix-docs off, or the PR read failing still dispatches it", async () => {
  const done = fakeApi({ node: pr({ checks: [checkRun("pr-refine / fix-docs")] }) });
  await run(done, { activities: ["fix-marker"] });
  assert.deepEqual(done.calls.dispatch, [markerDispatch], "fix-docs already ran");
  const off = fakeApi();
  await run(off, { activities: ["fix-marker"], limits: { "fix-docs-per-run": 0 } });
  assert.deepEqual(off.calls.dispatch, [markerDispatch], "fix-docs-per-run 0");
  const unread = fakeApi();
  unread.readDocsFixCandidate = async () => {
    throw new Error("502");
  };
  const { code } = await run(unread, { activities: ["fix-marker"] });
  assert.equal(code, 0);
  assert.deepEqual(unread.calls.dispatch, [markerDispatch], "the PR read failed");
});

// The lanes App pushes each applied patch, and that push is a synchronize
// event: dispatching on it would start the activity again.
test("the lanes App's event dispatches fix-docs but no configured activity", async () => {
  const api = fakeApi();
  const { code, lines } = await run(api, { sender: "1", activities: ["fix-marker"] });
  assert.equal(code, 0);
  assert.deepEqual(api.calls.dispatch.map((request) => request.inputs.activity), ["fix-docs"]);
  assert.ok(lines.some((line) => line.startsWith("skip fix-marker #77: the lanes App sent this event")));
});

test("a re-run attempt or an unlisted sender dispatches no configured activity", async () => {
  for (const [what, options] of [["attempt 2", { attempt: "2" }], ["unlisted", { sender: "999" }], ["no sender", { sender: "" }]]) {
    const api = fakeApi();
    const { code, ids } = await run(api, { ...options, activities: ["fix-marker"] });
    assert.equal(code, 0, what);
    assert.deepEqual(api.calls.dispatch, [], what);
    assert.equal(ids, "", what);
  }
});

test("an empty list dispatches only fix-docs, and a repeated id dispatches once", async () => {
  const empty = fakeApi();
  await run(empty, { activities: [] });
  assert.deepEqual(empty.calls.dispatch.map((request) => request.inputs.activity), ["fix-docs"]);
  const twice = fakeApi();
  await run(twice, { activities: ["fix-marker", "fix-marker"] });
  assert.deepEqual(twice.calls.dispatch.map((request) => request.inputs.activity), ["fix-docs", "fix-marker"]);
});

test("an id outside the allowlist fails the run and dispatches nothing, fix-docs included", async () => {
  for (const activities of [["fix-docs"], ["fix-marker", "resolve-conflicts"], ["unknown"]]) {
    const api = fakeApi();
    const { code, ids, lines } = await run(api, { activities });
    assert.equal(code, 1, activities.join());
    assert.deepEqual(api.calls.dispatch, [], activities.join());
    assert.equal(ids, "", activities.join());
    assert.ok(lines.some((line) => line.startsWith("::error::refine-dispatch.activities names")), activities.join());
  }
});

test("a configured dispatch that fails or returns no run id fails the run", async () => {
  const thrown = fakeApi();
  thrown.dispatchWorkflow = async (request) => {
    thrown.calls.dispatch.push(request);
    if (request.inputs.activity === "fix-marker") throw new Error("422");
    return { workflowRunId: 9001 };
  };
  assert.equal((await run(thrown, { activities: ["fix-marker"] })).code, 1);
  const empty = fakeApi();
  empty.dispatchWorkflow = async (request) => {
    empty.calls.dispatch.push(request);
    return { workflowRunId: request.inputs.activity === "fix-marker" ? undefined : 9001 };
  };
  const { code, ids } = await run(empty, { activities: ["fix-marker"] });
  assert.equal(code, 1);
  assert.equal(ids, "9001\n");
});
