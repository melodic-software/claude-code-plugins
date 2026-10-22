import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { createGitHubApi } from "./dispatch.mjs";
import { dispatchCiFixes, humanGatedLabel, LIST_QUERY, skipReason } from "./fix-ci-dispatch.mjs";

// The lanes App bot's user id and the GitHub Actions app id
// (.github/standards/trusted-actors/trusted-actors.json; dispatch.mjs).
const APP = 337595936;
const ACTIONS = 15368;

// pr-require-checks run 39710654665's latest jobs (recorded, trimmed): two
// time-limit cancels and a real lint-shell failure. Without lint-shell its
// failures are infra only.
const MIXED_JOBS = JSON.parse(readFileSync(new URL("../maintenance-reconcile-lost-runs/fixtures/jobs-39710654665.json", import.meta.url), "utf8")).jobs;
const INFRA_JOBS = MIXED_JOBS.filter((job) => job.name !== "lint-shell");

// A tested pr-require-checks run that failed, an hour before NOW unless named.
const NOW = Date.parse("2026-10-22T12:00:00Z");
const tested = (attempt, hoursAgo = 1) => ({
  status: "completed",
  conclusion: "failure",
  run_attempt: attempt,
  created_at: new Date(NOW - hoursAgo * 3_600_000).toISOString(),
});

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

function fakeApi({ pages = [[]], cost = 1, workflowRuns = [], failDispatch = new Set(), runIds = new Map(), requiredRuns = new Map() } = {}) {
  const calls = { list: 0, runs: 0, dispatch: [], jobs: [] };
  return {
    calls,
    // The head's tested pr-require-checks run and its latest jobs; a real
    // failure at attempt 1 unless the test names the head.
    async readRequiredRun(sha) {
      calls.jobs.push(sha);
      const required = requiredRuns.get(sha) ?? { run: tested(1), jobs: MIXED_JOBS };
      if (required instanceof Error) {
        throw required;
      }
      return required;
    },
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
    now: NOW,
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
        // More checks than the page holds could hide an earlier fix-ci run.
        pr(6, {
          commits: {
            nodes: [{ commit: { oid: "6".padStart(40, "a"), statusCheckRollup: { contexts: { nodes: [check("ci-status", "FAILURE")], pageInfo: { hasNextPage: true } } } } }],
          },
        }),
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

test("a listing that repeats its cursor stops instead of looping", async () => {
  const api = fakeApi();
  let calls = 0;
  api.listCiFixCandidates = async () => {
    calls += 1;
    return { rateLimit: { cost: 1 }, pullRequests: { nodes: [], pageInfo: { hasNextPage: true, endCursor: "same" } } };
  };
  const lines = [];
  await dispatchCiFixes({ api, runId: "1", log: (line) => lines.push(line), appSenderId: APP, maxDispatch: 2, restarts: 1 });
  assert.equal(calls, 2);
  assert.ok(lines.some((line) => line.includes("listing stopped after page 2")), lines.join("\n"));
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

// Owner decision Q22 (2026-10-22): a non-draft PR by an adoptable owner
// account is a candidate once both it and its head commit are 24 hours idle.
const OWNER = 153232337;
const hoursAgo = (hours) => new Date(NOW - hours * 3_600_000).toISOString();
const ADOPTION = { ownerIds: [OWNER], idleHours: 24 };

function ownerPr(number, { updated = 25, committed = 25, committedDate = hoursAgo(committed), ...overrides } = {}) {
  const node = pr(number, { author: { login: "kyle-sexton", databaseId: OWNER }, updatedAt: hoursAgo(updated), ...overrides });
  node.commits.nodes[0].commit.committedDate = committedDate;
  return node;
}

test("an adoptable owner's PR idle 25 hours whose ci-status failed is dispatched", async () => {
  const { result } = await run({ pages: [[ownerPr(9)]] }, { adoption: ADOPTION, now: NOW });
  assert.deepEqual(result, { dispatched: [{ number: 9, workflowRunId: "7009" }], failed: 0 });
});

test("an owner PR active within the idle window is skipped with a reason", () => {
  const options = { base: "main", appSenderId: APP, actionsAppId: ACTIONS, checkName: "pr-unblock / fix-ci", holdLabels: ["do-not-merge", "needs-human"], restarts: 1, adoption: ADOPTION, now: NOW };
  assert.equal(skipReason(ownerPr(1, { updated: 2, committed: 2 }), options), "owner PR or its head commit active in the last 24 hour(s)");
  // Idle means both: an old PR with a fresh commit, or the reverse, is active.
  assert.equal(skipReason(ownerPr(2, { updated: 25, committed: 2 }), options), "owner PR or its head commit active in the last 24 hour(s)");
  assert.equal(skipReason(ownerPr(3, { updated: 2, committed: 25 }), options), "owner PR or its head commit active in the last 24 hour(s)");
  assert.equal(skipReason(ownerPr(4), options), "");
});

test("owner drafts, holds, unlisted or spoofed users and unreadable dates are left alone, each for its reason", async () => {
  const options = { base: "main", appSenderId: APP, actionsAppId: ACTIONS, checkName: "pr-unblock / fix-ci", holdLabels: ["do-not-merge", "needs-human"], restarts: 1, adoption: ADOPTION, now: NOW };
  const unlisted = "not opened by the lanes App or an adoptable owner";
  const active = "owner PR or its head commit active in the last 24 hour(s)";
  const cases = [
    [ownerPr(1, { isDraft: true }), "not a ready same-repository PR into the base"],
    [ownerPr(2, { labels: { nodes: [{ name: "do-not-merge" }] } }), "held"],
    [ownerPr(3, { labels: { nodes: [{ name: "needs-human" }] } }), "held"],
    [ownerPr(4, { body: "Closes #1\n\nHold: until the demo\n" }), "held by a Hold: line"],
    [ownerPr(5, { author: { login: "octocat", databaseId: 4242 } }), unlisted],
    // The id decides, never the login.
    [ownerPr(6, { author: { login: "kyle-sexton", databaseId: 4242 } }), unlisted],
    [ownerPr(7, { author: null }), unlisted],
    // An unreadable date is not proof of idleness.
    [ownerPr(8, { updatedAt: "not a date" }), active],
    [ownerPr(9, { committedDate: "not a date" }), active],
  ];
  for (const [node, reason] of cases) {
    assert.equal(skipReason(node, options), reason, `#${node.number}`);
  }
  const { result } = await run({ pages: [cases.map(([node]) => node)] }, { adoption: ADOPTION, now: NOW });
  assert.deepEqual(result.dispatched, []);
  const none = await run({ pages: [[ownerPr(10)]] }, { now: NOW });
  assert.deepEqual(none.result.dispatched, [], "with no adoption list no owner PR is adopted");
});

test("a listed owner id is adopted whatever its login", async () => {
  const { result } = await run({ pages: [[ownerPr(11, { author: { login: "someone-else", databaseId: OWNER } })]] }, { adoption: ADOPTION, now: NOW });
  assert.deepEqual(result.dispatched.map((d) => d.number), [11]);
});

test("a Hold: line holds an owner PR in any case, after any whitespace, and after a bare CR", () => {
  const options = { base: "main", appSenderId: APP, actionsAppId: ACTIONS, checkName: "pr-unblock / fix-ci", holdLabels: ["do-not-merge", "needs-human"], restarts: 1, adoption: ADOPTION, now: NOW };
  for (const body of ["  Hold: demo", "hold: demo", "x\rHold: y", " Hold: z", "\u00a0Hold: nbsp", "Closes #1\r\n\tHOLD: tab"]) {
    assert.equal(skipReason(ownerPr(12, { body }), options), "held by a Hold: line", JSON.stringify(body));
  }
  // Not a line start, or a newline before the word on the same "line": no hold.
  for (const body of ["Closes #1. Hold: not at a line start", "Holding: no colon after hold", "x\n\nThe word hold: mid-line"]) {
    assert.equal(skipReason(ownerPr(12, { body }), options), "", JSON.stringify(body));
  }
});

test("the human-gated label comes from the tracker config, else needs-human", () => {
  assert.equal(humanGatedLabel(null), "needs-human");
  assert.equal(humanGatedLabel('{"config":{"lease_ttl_hours":24}}'), "needs-human");
  assert.equal(humanGatedLabel('{"config":{"role_labels":{"human-gated":"  human-gated  "}}}'), "human-gated");
  assert.equal(humanGatedLabel('{"config":{"role_labels":{"human-gated":"   "}}}'), "needs-human");
  assert.equal(humanGatedLabel('{"config":"x"}'), "needs-human");
  assert.throws(() => humanGatedLabel("{not json"));
});

test("lanes App PRs keep their rules: no idle wait, and a Hold: line does not hold them", async () => {
  const fresh = pr(8, { body: "Closes #1\n\nHold: a human merges this\n", updatedAt: hoursAgo(0) });
  const { result } = await run({ pages: [[fresh]] }, { adoption: ADOPTION, now: NOW });
  assert.deepEqual(result.dispatched.map((d) => d.number), [8]);
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
  for (const field of ["rateLimit", "cost", "statusCheckRollup", "commits(last: 1)", "databaseId", "... on User { databaseId }", "updatedAt", "committedDate", "body"]) {
    assert.ok(LIST_QUERY.includes(field), field);
  }
});

test("a head whose ci-status failed on infra only gets no fix-ci run, and takes no place under the cap", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const { api, lines, result } = await run({ pages: [[pr(5), pr(6), pr(7)]], requiredRuns: new Map([[head(5), { run: tested(1), jobs: INFRA_JOBS }]]) });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [6, 7],
  );
  assert.deepEqual(api.calls.jobs, [head(5), head(6), head(7)]);
  assert.ok(lines.includes("skip fix-ci #5: infra failure, re-run job owns it"));
});

test("an adopted owner PR whose ci-status failed on infra only is the reconciler's too", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const requiredRuns = new Map([[head(13), { run: tested(1), jobs: INFRA_JOBS }]]);
  const { lines, result } = await run({ pages: [[ownerPr(13), ownerPr(14)]], requiredRuns }, { adoption: ADOPTION, now: NOW });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [14],
  );
  assert.ok(lines.includes("skip fix-ci #13: infra failure, re-run job owns it"));
});

test("a head whose required run's jobs cannot be read gets no fix-ci run this time", async () => {
  const head = "5".padStart(40, "a");
  const { lines, result } = await run({ pages: [[pr(5)]], requiredRuns: new Map([[head, new Error("GET returned 502")]]) });
  assert.deepEqual(result, { dispatched: [], failed: 0 });
  assert.ok(lines.some((line) => line.startsWith("::warning::#5: could not read its required run's jobs")));
});

test("an infra-only head is the reconciler's for its two re-runs; at attempt 3 fix-ci takes it", async () => {
  // The reconciler re-runs an infra-only run at attempts 1 and 2 only (INFRA_BACKOFF_MINUTES, two entries).
  const head = (number) => String(number).padStart(40, "a");
  const requiredRuns = new Map([
    [head(5), { run: tested(2), jobs: INFRA_JOBS }],
    [head(6), { run: tested(3), jobs: INFRA_JOBS }],
  ]);
  const { lines, result } = await run({ pages: [[pr(5), pr(6)]], requiredRuns });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [6],
  );
  assert.ok(lines.includes("skip fix-ci #5: infra failure, re-run job owns it"));
});

test("an infra-only head past the reconciler's 24-hour lookback is fix-ci's", async () => {
  // The reconciler re-runs only runs created in the last 24 hours (LOOKBACK_HOURS).
  const head = (number) => String(number).padStart(40, "a");
  const requiredRuns = new Map([
    [head(5), { run: tested(1, 25), jobs: INFRA_JOBS }],
    [head(6), { run: tested(1, 23), jobs: INFRA_JOBS }],
  ]);
  const { lines, result } = await run({ pages: [[pr(5), pr(6)]], requiredRuns });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [5],
  );
  assert.ok(lines.includes("skip fix-ci #6: infra failure, re-run job owns it"));
});
