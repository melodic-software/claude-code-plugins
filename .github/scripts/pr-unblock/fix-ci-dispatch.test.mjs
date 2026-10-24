import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { createGitHubApi } from "./dispatch.mjs";
import { RERUN_DUE_MINUTES } from "../maintenance-reconcile-lost-runs/infra-failure.mjs";
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
const REQUIRED = ".github/workflows/pr-require-checks.yml";
const ADVISORY = ".github/workflows/pr-test-windows.yml";
const tested = (attempt, hoursAgo = 1) => ({
  id: 40119285048,
  status: "completed",
  conclusion: "failure",
  run_attempt: attempt,
  created_at: new Date(NOW - hoursAgo * 3_600_000).toISOString(),
  updated_at: new Date(NOW - hoursAgo * 3_600_000).toISOString(),
});
// A tested run whose re-run is queued or going: the same run id at its next attempt.
const rerunning = (attempt, status) => ({ ...tested(attempt), status, conclusion: null });

const check = (name, conclusion, extra = {}) => ({
  __typename: "CheckRun",
  name,
  status: conclusion ? "COMPLETED" : "IN_PROGRESS",
  conclusion,
  title: null,
  checkSuite: { app: { databaseId: ACTIONS } },
  ...extra,
});

// The head's ci-lanes commit status as the GraphQL rollup returns it: the
// creator recorded live from a pull request's ci-lanes status, which GraphQL
// reports as login `github-actions`, not REST's `github-actions[bot]`.
const ACTIONS_BOT = Object.freeze({ __typename: "Bot", login: "github-actions", databaseId: 41898282 });
const lanes = (state, creator = ACTIONS_BOT) => ({ __typename: "StatusContext", context: "ci-lanes", state, creator });

// A lanes App PR whose head's lanes failed and has no fix-ci run yet.
function pr(number, { checks = [lanes("FAILURE")], ...overrides } = {}) {
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

function fakeApi({
  pages = [[]],
  cost = 1,
  workflowRuns = [],
  failDispatch = new Set(),
  runIds = new Map(),
  requiredRuns = new Map(),
  baseCommittedAt,
  comments = new Map(),
  labelEvents = new Map(),
} = {}) {
  const calls = { list: 0, runs: 0, dispatch: [], jobs: [], paths: [], timeline: [] };
  return {
    calls,
    // The REST issue timeline: its comments, then its label events.
    async listTimeline(number) {
      calls.timeline.push(number);
      return [...(comments.get(number) ?? []).map((comment) => ({ event: "commented", ...comment })), ...(labelEvents.get(number) ?? [])];
    },
    // The head's tested run of the workflow at path and its latest jobs; a
    // real failure at attempt 2 (its one re-run spent) unless the test names
    // the head, or the head and path.
    async readRequiredRun(sha, path = REQUIRED) {
      calls.jobs.push(sha);
      calls.paths.push(path);
      const required = requiredRuns.get(`${sha} ${path}`) ?? requiredRuns.get(sha) ?? { run: tested(2), jobs: MIXED_JOBS };
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
        baseCommittedAt,
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

test("a head whose ci-lanes passed, is pending, is missing or came from another writer is left alone", async () => {
  const { result } = await run({
    pages: [
      [
        pr(1, { checks: [lanes("SUCCESS")] }),
        pr(2, { checks: [lanes("PENDING")] }),
        pr(3, { checks: [] }),
        pr(4, { checks: [lanes("FAILURE", "someone")] }),
        pr(5, { commits: { nodes: [] } }),
        // More checks than the page holds could hide an earlier fix-ci run.
        pr(6, {
          commits: {
            nodes: [{ commit: { oid: "6".padStart(40, "a"), statusCheckRollup: { contexts: { nodes: [lanes("FAILURE")], pageInfo: { hasNextPage: true } } } } }],
          },
        }),
      ],
    ],
  });
  assert.deepEqual(result.dispatched, []);
});

test("a head that already has a fix-ci run is skipped, unless every run failed within the restart count", async () => {
  const fix = (conclusion, extra) => check("pr-unblock / fix-ci", conclusion, extra);
  const failed = lanes("FAILURE");
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

// A head's fix-ci runs that failed or found nothing to fix count toward
// fix-ci-restarts only on the base they ran against: once the base tip moves
// past them the head is dispatched again, until limit-stops-per-head (3) such
// runs stand on it. A new head carries none of the old head's runs.
test("a new base dispatches a failed or not-applicable head again, within the per-head cap", async () => {
  const BASE_AT = "2026-10-22T11:00:00Z";
  const before = { completedAt: "2026-10-22T10:00:00Z" };
  const after = { completedAt: "2026-10-22T11:30:00Z" };
  const fix = (conclusion, extra) => check("pr-unblock / fix-ci", conclusion, extra);
  const notApplicable = (extra) => fix("NEUTRAL", { title: "Skipped: not-applicable", ...extra });
  const failed = lanes("FAILURE");
  const { api, result } = await run(
    {
      pages: [
        [
          pr(1, { checks: [failed, notApplicable(before)] }),
          pr(2, { checks: [failed, notApplicable(after)] }),
          pr(3, { checks: [failed, fix("FAILURE", before), fix("FAILURE", before)] }),
          pr(4, { checks: [failed, fix("FAILURE", after), fix("FAILURE", after)] }),
          pr(5, { checks: [failed, fix("FAILURE", before), fix("FAILURE", before), notApplicable(before)] }),
          pr(6, { checks: [failed, fix("SUCCESS", before)] }),
          pr(7, { checks: [failed] }),
        ],
      ],
      baseCommittedAt: BASE_AT,
    },
    { maxDispatch: 10 },
  );
  assert.deepEqual(result.dispatched.map((d) => d.number), [1, 3, 7]);
  assert.equal(api.calls.list, 1, "the base tip comes with the listing");
});

test("many base moves on one unchanged head dispatch it at most three times", async () => {
  const fix = (completedAt) => check("pr-unblock / fix-ci", "NEUTRAL", { title: "Skipped: not-applicable", completedAt });
  const runs = [];
  let dispatches = 0;
  for (let hour = 1; hour <= 10; hour += 1) {
    const base = `2026-10-22T${String(hour).padStart(2, "0")}:00:00Z`;
    const { result } = await run({ pages: [[pr(9, { checks: [lanes("FAILURE"), ...runs] })]], baseCommittedAt: base });
    if (result.dispatched.length > 0) {
      dispatches += 1;
      runs.push(fix(`2026-10-22T${String(hour).padStart(2, "0")}:30:00Z`));
    }
  }
  assert.equal(dispatches, 3);
});

const APP_USER = { login: "melodic-automation-lanes[bot]", id: APP, type: "Bot" };
const PERSON = { login: "kyle-sexton", id: 153232337, type: "User" };
const labeledBy = (actor) => [{ event: "labeled", actor, label: { name: "needs-human" }, created_at: "2026-10-22T10:00:00Z" }];
// report-escalation.sh's comment, with the reason it names.
const escalationComment = (reason) => [
  {
    user: APP_USER,
    created_at: "2026-10-22T10:00:05Z",
    body: `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${"b".repeat(40)} -->\nStopped.\n\n- Reason: \`${reason}\``,
  },
];
const humanGated = { labels: { nodes: [{ name: "needs-human" }] } };

test("needs-human from another lane's escalation does not hold fix-ci; fix-ci's own, a person's or do-not-merge does", async () => {
  const { api, lines, result } = await run(
    {
      pages: [
        [
          pr(1, humanGated),
          pr(2, humanGated),
          pr(3, humanGated),
          pr(4, { labels: { nodes: [{ name: "needs-human" }, { name: "do-not-merge" }] } }),
        ],
      ],
      labelEvents: new Map([
        [1, labeledBy(APP_USER)],
        [2, labeledBy(APP_USER)],
        [3, labeledBy(PERSON)],
        [4, labeledBy(APP_USER)],
      ]),
      comments: new Map([
        [1, escalationComment("feedback-disputed")],
        [2, escalationComment("ci-fix-escalated")],
        [4, escalationComment("feedback-disputed")],
      ]),
    },
    { gateLabel: "needs-human", maxDispatch: 10 },
  );
  assert.deepEqual(result.dispatched.map((d) => d.number), [1]);
  assert.ok(lines.includes("skip fix-ci #2: held by needs-human: fix-ci escalated it"), lines.join("\n"));
  assert.deepEqual(api.calls.timeline, [1, 2, 3], "a do-not-merge PR needs no timeline read");
});

test("an awaiting-human skip left while the PR was held does not hold it once the hold is gone, but counts toward the per-head cap", async () => {
  const held = check("pr-unblock / fix-ci", "NEUTRAL", { title: "Skipped: awaiting-human" });
  const { result } = await run({ pages: [[pr(1, { checks: [lanes("FAILURE"), held] }), pr(2, { checks: [lanes("FAILURE"), held, held, held] })]] });
  assert.deepEqual(result.dispatched.map((d) => d.number), [1], "three held skips reach the cap of three");
});

test("a hold that cannot be read counts as a failed dispatch", async () => {
  const api = fakeApi({ pages: [[pr(1, humanGated)]] });
  api.listTimeline = async () => {
    throw new Error("GET timeline returned 502");
  };
  const result = await dispatchCiFixes({ api, runId: "1", log: () => {}, appSenderId: APP, maxDispatch: 2, restarts: 1, gateLabel: "needs-human", now: NOW });
  assert.deepEqual(result, { dispatched: [], failed: 1 });
});

test("a restart count of 0 never dispatches a head again", async () => {
  const { result } = await run(
    { pages: [[pr(4, { checks: [lanes("FAILURE"), check("pr-unblock / fix-ci", "FAILURE")] })]] },
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

// Owner decision 2026-10-22: a trusted App's PR (the release App here) does
// not wait out the idle window; a person's still does.
test("a listed bot's PR is adopted with no idle wait, a listed person's waits", () => {
  const RELEASE = 337859524;
  const options = { base: "main", appSenderId: APP, actionsAppId: ACTIONS, checkName: "pr-unblock / fix-ci", holdLabels: ["do-not-merge", "needs-human"], restarts: 1, adoption: { ownerIds: [OWNER, RELEASE], idleHours: 24 }, now: NOW };
  const bot = { __typename: "Bot", login: "melodic-plugin-release", databaseId: RELEASE };
  assert.equal(skipReason(ownerPr(1, { updated: 0, committed: 0, author: bot }), options), "");
  assert.equal(skipReason(ownerPr(2, { updated: 0, committed: 0, author: { __typename: "User", login: "kyle-sexton", databaseId: OWNER } }), options), "owner PR or its head commit active in the last 24 hour(s)");
  assert.equal(skipReason(ownerPr(3, { updated: 0, committed: 0, author: { ...bot, databaseId: 4242 } }), options), "not opened by the lanes App or an adoptable owner");
});

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

test("adoption.held skips every owner PR with its reason and leaves lanes App PRs alone", () => {
  const held = "base tracker config unreadable, so its human-gated label is unknown";
  const options = { base: "main", appSenderId: APP, actionsAppId: ACTIONS, checkName: "pr-unblock / fix-ci", holdLabels: ["do-not-merge", "needs-human"], restarts: 1, adoption: { ...ADOPTION, held }, now: NOW };
  assert.equal(skipReason(ownerPr(15), options), held);
  assert.equal(skipReason(pr(16), options), "");
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
        JSON.stringify({
          data: {
            rateLimit: { cost: 4, remaining: 9 },
            repository: { ref: { target: { committedDate: "2026-10-22T11:00:00Z" } }, pullRequests: { nodes: [], pageInfo: { hasNextPage: false, endCursor: null } } },
          },
        }),
        { status: 200 },
      );
    },
  });
  const page = await api.listCiFixCandidates({ base: "main" });
  assert.equal(page.rateLimit.cost, 4);
  assert.equal(page.baseCommittedAt, "2026-10-22T11:00:00Z");
  assert.ok(LIST_QUERY.includes("ref(qualifiedName: $base) { target { ... on Commit { committedDate } } }"));
  assert.ok(LIST_QUERY.includes("title completedAt checkSuite"));
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, "https://api.example/graphql");
  assert.equal(requests[0].body.query, LIST_QUERY);
  assert.deepEqual(requests[0].body.variables, { owner: "octo", name: "repo", base: "main", after: null });
  for (const field of ["rateLimit", "cost", "statusCheckRollup", "commits(last: 1)", "databaseId", "... on User { databaseId }", "updatedAt", "committedDate", "body", "... on StatusContext { context state creator { __typename ... on Bot { databaseId } } }"]) {
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
  assert.ok(lines.includes("skip fix-ci #5: infra failure, re-run job re-runs it once"), lines.join("\n"));
});

test("an adopted owner PR whose ci-status failed on infra only is the reconciler's too", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const requiredRuns = new Map([[head(13), { run: tested(1), jobs: INFRA_JOBS }]]);
  const { lines, result } = await run({ pages: [[ownerPr(13), ownerPr(14)]], requiredRuns }, { adoption: ADOPTION, now: NOW });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [14],
  );
  assert.ok(lines.includes("skip fix-ci #13: infra failure, re-run job re-runs it once"), lines.join("\n"));
});

// A gate never hangs on one API field: a required run that cannot be read is
// no reason to wait, so fix-ci takes the head under its usual caps.
test("a head whose required run's jobs cannot be read is dispatched fix-ci, and the log says why", async () => {
  const head = "5".padStart(40, "a");
  const { lines, result } = await run({ pages: [[pr(5)]], requiredRuns: new Map([[head, new Error("GET returned 502")]]) });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [5],
  );
  assert.ok(lines.some((line) => line.startsWith("::warning::#5: could not read its required run's jobs (GET returned 502); dispatching fix-ci")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #5 ") && line.endsWith("(cause: required run unreadable)")), lines.join("\n"));
});

test("an unreadable required run still keeps the per-head cap, the restart count and an in-flight run", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const fix = check("pr-unblock / fix-ci", "FAILURE");
  const failed = lanes("FAILURE");
  const requiredRuns = new Map([1, 2, 3].map((number) => [head(number), new Error("GET returned 502")]));
  const { api, lines, result } = await run(
    {
      pages: [[pr(1, { checks: [failed, fix, fix, fix] }), pr(2, { checks: [failed, fix, fix] }), pr(3)]],
      requiredRuns,
      workflowRuns: [{ id: 99, status: "in_progress", display_title: "pr-unblock fix-ci #3" }],
    },
    { maxDispatch: 5 },
  );
  assert.deepEqual(result.dispatched, []);
  assert.deepEqual(api.calls.dispatch, []);
  assert.ok(lines.some((line) => line.startsWith("skip fix-ci #1:")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("skip fix-ci #2:")), lines.join("\n"));
});

// Rule: fix-ci skips a failed head only while a re-run of its tested run is
// actually queued or going on that head; that re-run's result decides.
test("a head whose tested run is being re-run waits for the re-run's result", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const requiredRuns = new Map([
    [head(5), { run: rerunning(2, "queued"), jobs: null }],
    [head(6), { run: rerunning(2, "in_progress"), jobs: null }],
    [head(7), { run: rerunning(3, "waiting"), jobs: null }],
  ]);
  const { lines, result } = await run({ pages: [[pr(5), pr(6), pr(7)]], requiredRuns }, { maxDispatch: 5 });
  assert.deepEqual(result.dispatched, []);
  assert.ok(lines.includes("skip fix-ci #5: run 40119285048 attempt 2 is queued; its result decides"), lines.join("\n"));
  assert.ok(lines.includes("skip fix-ci #6: run 40119285048 attempt 2 is in_progress; its result decides"), lines.join("\n"));
  assert.ok(lines.includes("skip fix-ci #7: run 40119285048 attempt 3 is waiting; its result decides"), lines.join("\n"));
});

// Once per head: an infra-only failure gets one re-run, then fix-ci.
test("an infra-only head gets one re-run; once it failed again at attempt 2, fix-ci takes it", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const requiredRuns = new Map([
    [head(5), { run: tested(1), jobs: INFRA_JOBS }],
    [head(6), { run: tested(2), jobs: INFRA_JOBS }],
    [head(7), { run: tested(3), jobs: INFRA_JOBS }],
  ]);
  const { lines, result } = await run({ pages: [[pr(5), pr(6), pr(7)]], requiredRuns }, { maxDispatch: 5 });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [6, 7],
  );
  assert.ok(lines.includes("skip fix-ci #5: infra failure, re-run job re-runs it once"), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #6 ") && line.endsWith("(cause: infra failure at attempt 2)")), lines.join("\n"));
});

// The re-run job runs half-hourly and can defer a head; an infra-only first
// failure no re-run picked up within RERUN_DUE_MINUTES is fix-ci's, not a
// silent wait.
test("an infra-only first failure that no re-run picked up in time is fix-ci's", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const minutesAgo = (minutes) => new Date(NOW - minutes * 60_000).toISOString();
  const run1 = (minutes) => ({ ...tested(1), created_at: minutesAgo(minutes), updated_at: minutesAgo(minutes) });
  const requiredRuns = new Map([
    [head(5), { run: run1(RERUN_DUE_MINUTES + 1), jobs: INFRA_JOBS }],
    [head(6), { run: run1(RERUN_DUE_MINUTES - 1), jobs: INFRA_JOBS }],
  ]);
  const { lines, result } = await run({ pages: [[pr(5), pr(6)]], requiredRuns }, { maxDispatch: 5 });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [5],
  );
  assert.ok(lines.includes("skip fix-ci #6: infra failure, re-run job re-runs it once"), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #5 ") && line.endsWith(`(cause: infra failure at attempt 1, no re-run within ${RERUN_DUE_MINUTES} min)`)), lines.join("\n"));
});

test("an infra-only head past the reconciler's 24-hour lookback is fix-ci's", async () => {
  // The reconciler re-runs only runs created in the last 24 hours (LOOKBACK_HOURS).
  const head = (number) => String(number).padStart(40, "a");
  const requiredRuns = new Map([
    [head(5), { run: tested(1, 25), jobs: INFRA_JOBS }],
    [head(6), { run: { ...tested(1, 23), updated_at: new Date(NOW - 60_000).toISOString() }, jobs: INFRA_JOBS }],
  ]);
  const { lines, result } = await run({ pages: [[pr(5), pr(6)]], requiredRuns });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [5],
  );
  assert.ok(lines.includes("skip fix-ci #6: infra failure, re-run job re-runs it once"), lines.join("\n"));
});

// A test assertion, lint or typecheck failure (a failed step that is not an
// install or a stop) goes straight to fix-ci: no re-run is waited for unless
// one is actually queued.
test("a real failure goes straight to fix-ci at attempt 1, and the log names its job and step", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const typos = [
    { name: "lint-repo", conclusion: "failure", steps: [{ name: "Set up job", conclusion: "success" }, { name: "Check spelling", conclusion: "failure" }] },
    { name: "ci-status", conclusion: "failure", steps: [] },
  ];
  const requiredRuns = new Map([
    [head(5), { run: tested(1), jobs: MIXED_JOBS }],
    [head(6), { run: tested(2), jobs: MIXED_JOBS }],
    [head(7), { run: tested(1, 25), jobs: MIXED_JOBS }],
    // Only ci-status failed.
    [head(8), { run: tested(1), jobs: [{ name: "lint-repo", conclusion: "success" }, { name: "ci-status", conclusion: "failure" }] }],
    [head(9), { run: tested(1), jobs: typos }],
  ]);
  const { lines, result } = await run({ pages: [[pr(5), pr(6), pr(7), pr(8), pr(9)]], requiredRuns }, { maxDispatch: 5 });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [5, 6, 7, 8, 9],
  );
  assert.ok(!lines.some((line) => line.includes("first failure")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #9 ") && line.endsWith("(cause: code failure in lint-repo / Check spelling)")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #8 ") && line.endsWith("(cause: no failed lane job)")), lines.join("\n"));
});

// Missing or malformed data fails toward recovery: fix-ci is dispatched and
// the log says what could not be classified.
test("a tested run that is missing or malformed dispatches fix-ci with the reason logged", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const requiredRuns = new Map([
    [head(1), { run: null, jobs: [] }],
    [head(2), { run: tested(1), jobs: null }],
    [head(3), { run: { ...tested(1), status: undefined }, jobs: INFRA_JOBS }],
    [head(4), { run: { ...tested(1), updated_at: "not a date" }, jobs: INFRA_JOBS }],
    [head(5), { run: { ...tested(1), run_attempt: "1" }, jobs: INFRA_JOBS }],
  ]);
  const { lines, result } = await run({ pages: [[pr(1), pr(2), pr(3), pr(4), pr(5)]], requiredRuns }, { maxDispatch: 5 });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [1, 2, 3, 4, 5],
  );
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #1 ") && line.endsWith("(cause: no tested run found)")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #2 ") && line.endsWith("(cause: failed jobs unreadable)")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #3 ") && line.endsWith("(cause: infra failure, run field status unreadable)")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #4 ") && line.endsWith("(cause: infra failure, run field updated_at unreadable)")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("dispatched fix-ci #5 ") && line.endsWith("(cause: infra failure, run field run_attempt unreadable)")), lines.join("\n"));
});

// pr-test-windows is not in ci-status, but the merge gate holds a PR on any
// failing check, such as a macOS test_tunnel flake.
test("a failed advisory pr-test-windows run with ci-status green is fix-ci's unless a re-run of it is going", async () => {
  const head = (number) => String(number).padStart(40, "a");
  const advisory = [lanes("SUCCESS"), check("test-macos-planning-shared", "FAILURE")];
  const requiredRuns = new Map([
    [`${head(5)} ${ADVISORY}`, { run: tested(1), jobs: MIXED_JOBS }],
    [`${head(6)} ${ADVISORY}`, { run: tested(2), jobs: MIXED_JOBS }],
    [`${head(7)} ${ADVISORY}`, { run: { ...tested(2), conclusion: "success" }, jobs: [] }],
    [`${head(8)} ${ADVISORY}`, { run: rerunning(2, "in_progress"), jobs: null }],
  ]);
  const prs = [5, 6, 7, 8].map((number) => pr(number, { checks: advisory }));
  const { api, lines, result } = await run({ pages: [prs], requiredRuns }, { maxDispatch: 4 });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [5, 6],
  );
  assert.deepEqual(api.calls.paths, [ADVISORY, ADVISORY, ADVISORY, ADVISORY]);
  assert.ok(lines.includes("skip fix-ci #7: ci-lanes passed and no pr-test-windows run failed"), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("skip fix-ci #8:")), lines.join("\n"));
});

test("a green ci-status with only a failed fix-ci run, or no failure, is left alone", async () => {
  const { api, result } = await run({
    pages: [[pr(5, { checks: [lanes("SUCCESS"), check("pr-unblock / fix-ci", "FAILURE")] }), pr(6, { checks: [lanes("SUCCESS"), check("lint", "SUCCESS")] })]],
  });
  assert.deepEqual(result.dispatched, []);
  assert.deepEqual(api.calls.paths, []);
});

// ci-status also fails while a review lane is pending, missing or holding the
// PR, with no label on it; none of that is a CI fix. Only ci-lanes counts.
test("a red ci-status over green or absent ci-lanes summons no fix-ci", async () => {
  const red = check("ci-status", "FAILURE");
  const { api, lines, result } = await run({
    pages: [[pr(1, { checks: [red, lanes("SUCCESS")] }), pr(2, { checks: [red] }), pr(3, { checks: [red, lanes("PENDING")] })]],
  });
  assert.deepEqual(result.dispatched, []);
  assert.deepEqual(api.calls.paths, []);
  assert.equal(skipReason(pr(1, { checks: [red, lanes("SUCCESS")] }), { base: "main", appSenderId: APP, actionsAppId: ACTIONS, checkName: "pr-unblock / fix-ci", holdLabels: [], restarts: 1, now: NOW }), "ci-lanes has not failed");
  assert.ok(!lines.some((line) => line.includes("fix-ci #")), lines.join("\n"));
});

test("a ci-lanes failure or error from the GitHub Actions bot is dispatched, whatever ci-status says", async () => {
  const { api, result } = await run({
    pages: [[pr(1, { checks: [check("ci-status", "SUCCESS"), lanes("FAILURE")] }), pr(2, { checks: [lanes("ERROR")] })]],
  }, { maxDispatch: 5 });
  assert.deepEqual(
    result.dispatched.map((d) => d.number),
    [1, 2],
  );
  assert.deepEqual(api.calls.paths, [REQUIRED, REQUIRED]);
});

test("a ci-lanes failure set by any other actor, or with no creator, is not trusted, and its skip is logged", async () => {
  const untrusted = [
    { __typename: "User", login: "octocat", databaseId: 583231 },
    { __typename: "User", login: "github-actions", databaseId: 41898282 },
    { __typename: "Bot", login: "github-actions", databaseId: 1 },
    { __typename: "Bot", login: "github-actions[bot]" },
    null,
  ];
  const { api, lines, result } = await run({
    pages: [[...untrusted.map((creator, index) => pr(index + 1, { checks: [lanes("FAILURE", creator)] })), pr(9, { checks: [{ ...lanes("FAILURE"), creator: undefined }] })]],
  }, { maxDispatch: 9 });
  assert.deepEqual(result.dispatched, []);
  assert.deepEqual(api.calls.paths, []);
  for (const number of [1, 2, 3, 4, 5, 9]) {
    assert.ok(lines.includes(`skip fix-ci #${number}: ci-lanes failed but the GitHub Actions bot did not set it`), lines.join("\n"));
  }
});

test("a listed head with failed lanes that is skipped logs why; a passing or pending one stays quiet", async () => {
  const { lines, result } = await run({
    pages: [[pr(1, { isDraft: true }), pr(2, { checks: [lanes("SUCCESS")] }), pr(3, { checks: [lanes("PENDING")] }), pr(4, { checks: [] }), pr(5, { isDraft: true, checks: [lanes("ERROR")] })]],
  });
  assert.deepEqual(result.dispatched, []);
  assert.deepEqual(
    lines.filter((line) => line.includes("fix-ci #")),
    ["skip fix-ci #1: not a ready same-repository PR into the base", "skip fix-ci #5: not a ready same-repository PR into the base"],
  );
});
