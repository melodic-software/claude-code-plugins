import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { createRateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { LIMIT_DEFAULTS } from "../work-resolve-issue/limits.mjs";
import { emptyRecord, markHandled, parseRecord, serializeRecord } from "./dispatch-record.mjs";
import { createGitHubApi, dispatchConflicting, main } from "./dispatch.mjs";
import { budgetedFetch } from "./request-budget.mjs";

const CHECK_NAME = "pr-unblock / resolve-conflicts";
// The lanes App bot's user id (.github/standards/trusted-actors/trusted-actors.json).
const LANES_APP = 337595936;
// The title GitHub gives a pr-unblock.yml run, read from the workflow file:
// its top-level run-name scalar as YAML reads it (a double-quoted string, or a
// plain one cut at " #", which starts a comment), with the inputs filled in.
function pr_unblockTitle(activity, number) {
  const workflow = readFileSync(new URL("../../workflows/pr-unblock.yml", import.meta.url), "utf8");
  const raw = /^run-name:[ \t]*(.*)$/m.exec(workflow)?.[1] ?? "";
  const value = raw.startsWith('"') ? JSON.parse(raw.slice(0, raw.lastIndexOf('"') + 1)) : raw.split(/[ \t]#/)[0].trim();
  return value
    .replaceAll("${{ inputs.activity }}", activity)
    .replaceAll("${{ inputs.pr-number }}", String(number));
}
const SUCCESS_RUN = { status: "completed", conclusion: "success", output: { title: "Resolved" } };
// A failed run whose summary opens with the lane record report-check-run
// writes; `tokens` follow class=rate-limit, and null leaves no record.
const failedRun = (completed, tokens = "") => ({
  name: CHECK_NAME,
  status: "completed",
  conclusion: "failure",
  completed_at: completed,
  output: {
    title: "Failed",
    summary:
      tokens === null
        ? "The activity step failed."
        : `lane=pr-unblock activity=resolve-conflicts class=rate-limit${tokens}\n\nThe activity step failed.`,
  },
});
const UNTRUSTED_SKIP = {
  status: "completed",
  conclusion: "neutral",
  output: { title: "Skipped: untrusted-trigger" },
};

function pr(number, overrides = {}) {
  return {
    number,
    isDraft: false,
    isCrossRepository: false,
    mergeable: "CONFLICTING",
    baseRefName: "main",
    headRefOid: String(number).padStart(40, "a"),
    ...overrides,
  };
}

// A fake of the four GitHub calls. `pages` is the open-PR listing, one array
// per page; `requeries` is, per re-query round, the PR nodes GitHub returns;
// `checked` is the set of head SHAs that already carry a successful check run,
// or a Map from head SHA to the check runs GitHub returns for it. `runIds`
// maps a PR number to the workflow_run_id its dispatch returns, undefined
// included; any other PR gets 9000 plus its number. `workflowRuns` is the
// pr-unblock.yml run listing.
function fakeApi({
  pages = [[]],
  requeries = [],
  checked = new Set(),
  failDispatch = new Set(),
  failChecks = new Set(),
  runIds = new Map(),
  workflowRuns = [],
  ciFixPulls = [],
  docsPulls = [],
  comments = new Map(),
  labelEvents = new Map(),
} = {}) {
  const calls = { list: [], get: [], checks: [], dispatch: [], runs: [], timeline: [] };
  let round = 0;
  return {
    calls,
    async listCiFixCandidates() {
      return { rateLimit: { cost: 1, remaining: 4999 }, pullRequests: { nodes: ciFixPulls, pageInfo: { hasNextPage: false, endCursor: null } } };
    },
    async listDocsFixCandidates() {
      return { rateLimit: { cost: 1, remaining: 4999 }, pullRequests: { nodes: docsPulls, pageInfo: { hasNextPage: false, endCursor: null } } };
    },
    async readDocsFixHistory() {
      return { rateLimit: { cost: 1, remaining: 4999 }, pullRequest: { commits: { nodes: [] } } };
    },
    async listOpenPulls({ base, after }) {
      calls.list.push({ base, after });
      const index = after === undefined ? 0 : Number(after);
      return {
        nodes: pages[index],
        pageInfo: { hasNextPage: index + 1 < pages.length, endCursor: String(index + 1) },
      };
    },
    async listPullCommits() {
      return [];
    },
    async getCommit(sha) {
      return { sha, files: [] };
    },
    async listPullFiles() {
      return [];
    },
    async getPulls(numbers) {
      calls.get.push([...numbers]);
      const answer = requeries[Math.min(round, requeries.length - 1)] ?? [];
      round += 1;
      return answer.filter((node) => numbers.includes(node.number));
    },
    async listCheckRuns({ sha, checkName, appId }) {
      calls.checks.push({ sha, checkName, appId });
      if (failChecks.has(sha)) {
        throw new Error("check-runs read failed");
      }
      if (checked instanceof Map) {
        return checked.get(sha) ?? [];
      }
      return checked.has(sha) ? [SUCCESS_RUN] : [];
    },
    async readRequiredRun() {
      return { run: null, jobs: [] };
    },
    // The REST issue timeline: its comments, then its label events.
    async listTimeline(number) {
      calls.timeline.push(number);
      return [...(comments.get(number) ?? []).map((comment) => ({ event: "commented", ...comment })), ...(labelEvents.get(number) ?? [])];
    },
    async listWorkflowRuns(workflow) {
      calls.runs.push(workflow);
      if (workflowRuns instanceof Error) {
        throw workflowRuns;
      }
      return workflowRuns;
    },
    async dispatchWorkflow({ workflow, ref, inputs }) {
      calls.dispatch.push({ workflow, ref, inputs });
      if (failDispatch.has(inputs["pr-number"])) {
        throw new Error("dispatch failed");
      }
      if (runIds.has(inputs["pr-number"])) {
        return { workflowRunId: runIds.get(inputs["pr-number"]) };
      }
      return { workflowRunId: 9000 + Number(inputs["pr-number"]) };
    },
  };
}

function harness(apiOptions, options = {}) {
  const api = fakeApi(apiOptions);
  const sleeps = [];
  const lines = [];
  const run = () =>
    dispatchConflicting({
      api,
      runId: "4242",
      sleep: async (ms) => {
        sleeps.push(ms);
      },
      log: (line) => lines.push(line),
      ...options,
    });
  return { api, sleeps, lines, run };
}

const dispatchedNumbers = (api) => api.calls.dispatch.map((call) => call.inputs["pr-number"]);

test("dispatches only open, non-draft, same-repo CONFLICTING PRs into main", async () => {
  const { api, run } = harness({
    pages: [
      [
        pr(1),
        pr(2, { isDraft: true }),
        pr(3, { isCrossRepository: true }),
        pr(4, { mergeable: "MERGEABLE" }),
        pr(5, { baseRefName: "release" }),
      ],
    ],
  });
  await run();
  assert.deepEqual(dispatchedNumbers(api), ["1"]);
  assert.deepEqual(api.calls.list, [{ base: "main", after: undefined }]);
});

test("never dispatches resolve-conflicts on a Dependabot head", async () => {
  // Dependabot's user id (dependency-classify.mjs DEPENDABOT_ID).
  const dependabot = { login: "dependabot", databaseId: 49699333 };
  const { api, run } = harness({
    pages: [
      [
        pr(1, { headRefName: "dependabot/npm_and_yarn/x-1.2.3", author: dependabot }),
        pr(2, { headRefName: "dependabot/npm_and_yarn/x-1.2.3", author: { login: "octocat", databaseId: 583231 } }),
        pr(3, { headRefName: "feature/x", author: dependabot }),
        pr(4, { headRefName: "dependabot/pip/y-2.0.0", author: dependabot, mergeable: "UNKNOWN" }),
      ],
    ],
  });
  await run();
  assert.deepEqual(dispatchedNumbers(api), ["2", "3"]);
  assert.deepEqual(api.calls.get, []);
});

test("follows the listing past the first 100 PRs", async () => {
  const first = Array.from({ length: 100 }, (_, i) => pr(i + 1, { mergeable: "MERGEABLE" }));
  const second = Array.from({ length: 50 }, (_, i) =>
    pr(i + 101, { mergeable: i + 101 === 140 ? "CONFLICTING" : "MERGEABLE" }),
  );
  const { api, run } = harness({ pages: [first, second] });
  await run();
  assert.deepEqual(api.calls.list, [
    { base: "main", after: undefined },
    { base: "main", after: "1" },
  ]);
  assert.deepEqual(dispatchedNumbers(api), ["140"]);
});

test("re-queries an UNKNOWN PR 10 s apart and dispatches it once it reads CONFLICTING", async () => {
  const { api, sleeps, run } = harness({
    pages: [[pr(7, { mergeable: "UNKNOWN" })]],
    requeries: [[pr(7, { mergeable: "UNKNOWN" })], [pr(7)]],
  });
  await run();
  assert.deepEqual(sleeps, [10_000, 10_000]);
  assert.deepEqual(api.calls.get, [[7], [7]]);
  assert.deepEqual(dispatchedNumbers(api), ["7"]);
});

test("gives up on a PR still UNKNOWN after 5 re-queries, logging the skip", async () => {
  const { api, sleeps, lines, run } = harness({
    pages: [[pr(8, { mergeable: "UNKNOWN" })]],
    requeries: [[pr(8, { mergeable: "UNKNOWN" })]],
  });
  await run();
  assert.deepEqual(sleeps, [10_000, 10_000, 10_000, 10_000, 10_000]);
  assert.equal(api.calls.get.length, 5);
  assert.deepEqual(api.calls.dispatch, []);
  assert.ok(lines.some((line) => line.includes("#8") && /unknown/i.test(line)));
});

test("drops an UNKNOWN PR that resolves MERGEABLE or becomes a draft", async () => {
  const { api, run } = harness({
    pages: [[pr(9, { mergeable: "UNKNOWN" }), pr(10, { mergeable: "UNKNOWN" })]],
    requeries: [[pr(9, { mergeable: "MERGEABLE" }), pr(10, { isDraft: true })]],
  });
  await run();
  assert.equal(api.calls.get.length, 1);
  assert.deepEqual(api.calls.dispatch, []);
});

test("skips a PR whose current head already has a pr-unblock / resolve-conflicts check run", async () => {
  const done = pr(11);
  const { api, lines, run } = harness({
    pages: [[done, pr(12)]],
    checked: new Set([done.headRefOid]),
  });
  await run();
  assert.deepEqual(api.calls.checks[0], {
    sha: done.headRefOid,
    checkName: CHECK_NAME,
    appId: 15368,
  });
  assert.deepEqual(dispatchedNumbers(api), ["12"]);
  assert.ok(lines.some((line) => line.includes("#11")));
});

test("an untrusted-trigger neutral skip does not count as handled", async () => {
  const skipped = pr(13);
  const { api, run } = harness({
    pages: [[skipped]],
    checked: new Map([[skipped.headRefOid, [UNTRUSTED_SKIP]]]),
  });
  await run();
  assert.deepEqual(dispatchedNumbers(api), ["13"]);
});

test("an in-progress run or any other completed conclusion but a failure counts as handled", async () => {
  const running = pr(14);
  const otherNeutral = pr(16);
  const mixed = pr(17);
  const sameTitleRunning = pr(19);
  const { api, run } = harness({
    pages: [[running, otherNeutral, mixed, sameTitleRunning]],
    checked: new Map([
      [running.headRefOid, [{ status: "in_progress", conclusion: null, output: { title: null } }]],
      [
        otherNeutral.headRefOid,
        [
          {
            status: "completed",
            conclusion: "neutral",
            output: { title: "Skipped: not-conflicting" },
          },
        ],
      ],
      [mixed.headRefOid, [UNTRUSTED_SKIP, SUCCESS_RUN]],
      [
        sameTitleRunning.headRefOid,
        [{ ...UNTRUSTED_SKIP, status: "in_progress", conclusion: null }],
      ],
    ]),
  });
  await run();
  assert.deepEqual(api.calls.dispatch, []);
});

// A run the usage limit stopped (FINAL-DESIGN C5) stops counting as handled
// once its limit resets: at its `resets=` time, else five hours after it
// ended. Until then it still counts; a failure with no lane record is retried.
test("a limit-stopped run counts as handled only until its limit resets", async () => {
  const now = Date.parse("2026-10-17T12:00:00Z");
  const [statedPast, statedFuture, fallbackPast, fallbackFuture, noRecord] = [pr(21), pr(22), pr(23), pr(24), pr(25)];
  const { api, run } = harness(
    {
      pages: [[statedPast, statedFuture, fallbackPast, fallbackFuture, noRecord]],
      checked: new Map([
        [statedPast.headRefOid, [failedRun("2026-10-17T10:00:00Z", " resets=2026-10-17T11:00:00Z turns=3")]],
        [statedFuture.headRefOid, [failedRun("2026-10-17T10:00:00Z", " resets=2026-10-17T13:00:00Z")]],
        [fallbackPast.headRefOid, [failedRun("2026-10-17T06:00:00Z")]],
        [fallbackFuture.headRefOid, [failedRun("2026-10-17T08:00:00Z", " turns=2")]],
        [noRecord.headRefOid, [failedRun("2026-10-01T00:00:00Z", null)]],
      ]),
    },
    { now, maxDispatch: 10 },
  );
  await run();
  assert.deepEqual(dispatchedNumbers(api), ["21", "23", "25"]);
});

test("the resolved limits set how many reset limit stops hold a head", async () => {
  const now = Date.parse("2026-10-17T12:00:00Z");
  const stopped = pr(28);
  const apiOptions = { pages: [[stopped]], checked: new Map([[stopped.headRefOid, [failedRun("2026-10-17T06:00:00Z")]]]) };
  const defaults = harness(apiOptions, { now });
  await defaults.run();
  assert.deepEqual(dispatchedNumbers(defaults.api), ["28"]);
  const one = harness(apiOptions, { now, limits: { ...LIMIT_DEFAULTS, "limit-stops-per-head": 1 } });
  await one.run();
  assert.deepEqual(dispatchedNumbers(one.api), []);
});

// A failed resolve-conflicts run is retried on the same head until
// limits.limit-stops-per-head (3 by default) failures stand on it.
test("a failed run is retried until three failures stand on the head", async () => {
  const once = pr(31);
  const twice = pr(32);
  const thrice = pr(33);
  const failed = failedRun("2026-10-17T10:00:00Z", null);
  const record = emptyRecord();
  const { api, run } = harness(
    {
      pages: [[once, twice, thrice]],
      checked: new Map([
        [once.headRefOid, [failed]],
        [twice.headRefOid, [failed, failed]],
        [thrice.headRefOid, [failed, failed, failed]],
      ]),
    },
    { record, maxDispatch: 9 },
  );
  await run();
  assert.deepEqual(dispatchedNumbers(api), ["31", "32"]);
  assert.deepEqual([...(record.handled.get(CHECK_NAME) ?? [])], [thrice.headRefOid]);
});

// The neutral check a select job posts when it skipped a held PR.
const HELD_SKIP = { status: "completed", conclusion: "neutral", output: { title: "Skipped: awaiting-human" } };
const LABELS = (...names) => ({ labels: { nodes: names.map((name) => ({ name })) } });
const OWNER = { login: "kyle-sexton", id: 153232337, type: "User" };
const APP_USER = { login: "melodic-automation-lanes[bot]", id: LANES_APP, type: "Bot" };
const labeledBy = (actor) => [{ event: "labeled", actor, label: { name: "needs-human" }, created_at: "2026-10-18T10:00:00Z" }];
// report-escalation.sh's comment, with the reason it names.
const escalationComment = (reason) => [
  {
    user: APP_USER,
    created_at: "2026-10-18T10:00:05Z",
    body: `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${"b".repeat(40)} -->\nStopped.\n\n- Reason: \`${reason}\``,
  },
];

test("a head skipped while held is dispatched once no hold label is on, and not recorded while held", async () => {
  const released = pr(41);
  const personHeld = pr(42, LABELS("needs-human"));
  const doNotMerge = pr(43, LABELS("do-not-merge"));
  const record = emptyRecord();
  const { api, run } = harness(
    {
      pages: [[released, personHeld, doNotMerge]],
      checked: new Map([
        [released.headRefOid, [HELD_SKIP]],
        [personHeld.headRefOid, [HELD_SKIP]],
        [doNotMerge.headRefOid, [HELD_SKIP]],
      ]),
      labelEvents: new Map([[42, labeledBy(OWNER)]]),
    },
    { record, appSenderId: LANES_APP, maxDispatch: 9 },
  );
  await run();
  assert.deepEqual(dispatchedNumbers(api), ["41"]);
  assert.deepEqual(api.calls.checks.map((call) => call.sha), [released.headRefOid], "a held PR's check runs are not read");
  assert.deepEqual([...(record.handled.get(CHECK_NAME) ?? [])], []);
});

test("another lane's escalation does not hold resolve-conflicts; its own does", async () => {
  const disputed = pr(51, LABELS("needs-human"));
  const unresolved = pr(52, LABELS("needs-human"));
  const { api, run } = harness(
    {
      pages: [[disputed, unresolved]],
      labelEvents: new Map([
        [51, labeledBy(APP_USER)],
        [52, labeledBy(APP_USER)],
      ]),
      comments: new Map([
        [51, escalationComment("feedback-disputed")],
        [52, escalationComment("unresolved-conflict")],
      ]),
    },
    { appSenderId: LANES_APP, maxDispatch: 9 },
  );
  await run();
  assert.deepEqual(dispatchedNumbers(api), ["51"]);
  const noApp = harness({ pages: [[disputed]], labelEvents: new Map([[51, labeledBy(APP_USER)]]), comments: new Map([[51, escalationComment("feedback-disputed")]]) });
  await noApp.run();
  assert.deepEqual(dispatchedNumbers(noApp.api), [], "with no lanes App id the label holds");
});

test("main reads a held PR's timeline once, however many dispatchers ask", async () => {
  const held = pr(61, LABELS("needs-human"));
  const ci = { ...ciFixPull(61), labels: { nodes: [{ name: "needs-human" }] } };
  const docs = { ...docsPull(61), labels: { nodes: [{ name: "needs-human" }] } };
  const api = fakeApi({ pages: [[held]], ciFixPulls: [ci], docsPulls: [docs], labelEvents: new Map([[61, labeledBy(OWNER)]]) });
  const dir = mkdtempSync(join(tmpdir(), "pr-unblock-dispatch-"));
  try {
    await main(
      { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: "1", GITHUB_OUTPUT: join(dir, "out"), APP_SENDER_ID: String(LANES_APP), BASE_PATH: dir },
      { api, sleep: async () => {}, log: () => {}, loadLimits: async () => LIMIT_DEFAULTS, loadAdoption: async () => ({}) },
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
  assert.deepEqual(api.calls.dispatch, [], "a person's label holds all three");
  assert.deepEqual(api.calls.timeline, [61]);
});

test("skips a PR while a resolve-conflicts run for it is queued or going", async () => {
  for (const status of ["queued", "in_progress", "waiting", "pending"]) {
    const { api, lines, run } = harness({
      pages: [[pr(26), pr(27)]],
      workflowRuns: [{ id: 1, status, display_title: pr_unblockTitle("resolve-conflicts", 26) }],
    });
    await run();
    assert.deepEqual(api.calls.runs, ["pr-unblock.yml"], status);
    assert.deepEqual(dispatchedNumbers(api), ["27"], status);
    assert.ok(lines.some((line) => line.includes("#26") && line.includes("run 1")), status);
  }
});

test("a finished run, another PR's run or another activity's run does not hold the dispatch", async () => {
  const { api, run } = harness({
    pages: [[pr(28)]],
    workflowRuns: [
      { id: 1, status: "completed", display_title: pr_unblockTitle("resolve-conflicts", 28) },
      { id: 2, status: "in_progress", display_title: pr_unblockTitle("resolve-conflicts", 280) },
      { id: 3, status: "queued", display_title: pr_unblockTitle("address-feedback", 28) },
    ],
  });
  await run();
  assert.deepEqual(dispatchedNumbers(api), ["28"]);
});

test("an unreadable run listing dispatches nothing and counts as a failure", async () => {
  const { api, lines, run } = harness({
    pages: [[pr(29)]],
    workflowRuns: new Error("runs read failed"),
  });
  const result = await run();
  assert.deepEqual(api.calls.dispatch, []);
  assert.equal(result.failed, 1);
  assert.ok(lines.some((line) => line.startsWith("::error::") && line.includes("runs read failed")));
});

// The error the adapter throws when budgetedFetch gave up on a rate limit.
const rateLimitedListing = () =>
  Object.assign(new Error("GET https://api.example/repos/o/r/actions/workflows/pr-unblock.yml/runs returned 403"), { rateLimited: true });

test("a rate-limited run listing defers: nothing dispatched, a warning, and no failure", async () => {
  const { api, lines, run } = harness({ pages: [[pr(29)]], workflowRuns: rateLimitedListing() });
  const result = await run();
  assert.deepEqual(api.calls.dispatch, []);
  assert.deepEqual(result, { dispatched: [], failed: 0 });
  assert.ok(lines.some((line) => line.startsWith("::warning::") && line.includes("rate limited") && line.includes("returned 403")));
  assert.ok(!lines.some((line) => line.startsWith("::error::")));
});

test("maxDispatch defaults to 3, in ascending PR number, logging the PRs left for a later run", async () => {
  const { api, lines, run } = harness({ pages: [[pr(25), pr(23), pr(21), pr(24), pr(22)]] });
  await run();
  assert.deepEqual(dispatchedNumbers(api), ["21", "22", "23"]);
  for (const left of ["#24", "#25"]) {
    assert.ok(
      lines.some((line) => line.includes(left) && /later run/.test(line)),
      left,
    );
  }
  assert.equal(api.calls.checks.length, 3);
});

test("maxDispatch can be overridden", async () => {
  const { api, run } = harness({ pages: [[pr(32), pr(31), pr(33)]] }, { maxDispatch: 1 });
  await run();
  assert.deepEqual(dispatchedNumbers(api), ["31"]);
});

test("a skipped PR does not use one of the maxDispatch slots", async () => {
  const done = pr(41);
  const { api, run } = harness({
    pages: [[done, pr(42), pr(43), pr(44), pr(45)]],
    checked: new Set([done.headRefOid]),
  });
  await run();
  assert.deepEqual(dispatchedNumbers(api), ["42", "43", "44"]);
});

test("dispatches pr-unblock.yml on main with pr-number and dispatcher-run-id, logging workflow_run_id", async () => {
  const { api, lines, run } = harness({ pages: [[pr(51)]] });
  const result = await run();
  assert.deepEqual(api.calls.dispatch, [
    {
      workflow: "pr-unblock.yml",
      ref: "refs/heads/main",
      inputs: { "pr-number": "51", "dispatcher-run-id": "4242" },
    },
  ]);
  assert.ok(lines.some((line) => line.includes("#51") && line.includes("workflow_run_id=9051")));
  assert.equal(result.failed, 0);
});

test("a failed dispatch or check-run read is reported and the other PRs still go", async () => {
  const unreadable = pr(61);
  const { api, run } = harness({
    pages: [[unreadable, pr(62), pr(63)]],
    failChecks: new Set([unreadable.headRefOid]),
    failDispatch: new Set(["62"]),
  });
  const result = await run();
  assert.deepEqual(dispatchedNumbers(api), ["62", "63"]);
  assert.equal(result.failed, 2);
});

test("a 200 dispatch with no workflow_run_id counts as failed and is not reported dispatched", async () => {
  const { api, lines, run } = harness({
    pages: [[pr(71), pr(72)]],
    runIds: new Map([["71", undefined]]),
  });
  const result = await run();
  assert.deepEqual(dispatchedNumbers(api), ["71", "72"]);
  assert.deepEqual(result.dispatched, [{ number: 72, workflowRunId: "9072" }]);
  assert.equal(result.failed, 1);
  assert.ok(lines.some((line) => line.startsWith("::error::") && line.includes("#71")));
  assert.ok(!lines.some((line) => line.startsWith("dispatched #71")));
});

test("a dispatch with an unusable workflow_run_id still uses one of the maxDispatch slots", async () => {
  const { api, lines, run } = harness({
    pages: [[pr(131), pr(132), pr(133), pr(134)]],
    runIds: new Map([["131", undefined]]),
  });
  const result = await run();
  assert.deepEqual(dispatchedNumbers(api), ["131", "132", "133"]);
  assert.deepEqual(result.dispatched, [
    { number: 132, workflowRunId: "9132" },
    { number: 133, workflowRunId: "9133" },
  ]);
  assert.equal(result.failed, 1);
  assert.ok(lines.some((line) => line.includes("#134") && /later run/.test(line)));
});

test("a dispatch call that throws still uses one of the maxDispatch slots", async () => {
  const { api, lines, run } = harness({
    pages: [[pr(141), pr(142), pr(143), pr(144)]],
    failDispatch: new Set(["141"]),
  });
  const result = await run();
  assert.deepEqual(dispatchedNumbers(api), ["141", "142", "143"]);
  assert.equal(result.failed, 1);
  assert.ok(lines.some((line) => line.includes("#144") && /later run/.test(line)));
});

test("a workflow_run_id that is not 1 to 15 digits without a leading zero counts as failed", async () => {
  const bad = [
    ["81", "0123"],
    ["82", 0],
    ["83", "12a"],
    ["84", 1.5],
    ["85", "1234567890123456"],
    ["86", ""],
    ["87", null],
    ["88", -5],
  ];
  const { lines, run } = harness(
    { pages: [bad.map(([number]) => pr(Number(number)))], runIds: new Map(bad) },
    { maxDispatch: 10 },
  );
  const result = await run();
  assert.deepEqual(result.dispatched, []);
  assert.equal(result.failed, bad.length);
  for (const [number] of bad) {
    assert.ok(
      lines.some((line) => line.startsWith("::error::") && line.includes(`#${number}`)),
      number,
    );
  }
});

test("a 15-digit workflow_run_id is accepted", async () => {
  const { run } = harness({
    pages: [[pr(91)]],
    runIds: new Map([["91", 123456789012345]]),
  });
  const result = await run();
  assert.deepEqual(result.dispatched, [{ number: 91, workflowRunId: "123456789012345" }]);
  assert.equal(result.failed, 0);
});

// main against a fake API, with GITHUB_OUTPUT a real file it appends to.
async function runMain(apiOptions, limits = LIMIT_DEFAULTS, now = undefined) {
  const dir = mkdtempSync(join(tmpdir(), "pr-unblock-dispatch-"));
  const output = join(dir, "output");
  writeFileSync(output, "");
  try {
    const code = await main(
      {
        GITHUB_TOKEN: "t0ken",
        GITHUB_REPOSITORY: "octo/repo",
        GITHUB_RUN_ID: "4242",
        GITHUB_OUTPUT: output,
        APP_SENDER_ID: String(LANES_APP),
      },
      { api: fakeApi(apiOptions), sleep: async () => {}, log: () => {}, loadLimits: async () => limits, loadAdoption: async () => ({}), now },
    );
    return { code, output: readFileSync(output, "utf8") };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("main writes run-ids to GITHUB_OUTPUT in ascending PR order", async () => {
  const { code, output } = await runMain({
    pages: [[pr(103), pr(101), pr(102)]],
    runIds: new Map([
      ["101", 38255833396],
      ["102", 38255833401],
      ["103", 38255833399],
    ]),
  });
  assert.equal(code, 0);
  assert.equal(output, "run-ids=38255833396 38255833401 38255833399\n");
});

test("main writes the recorded ids and exits 1 when another dispatch failed", async () => {
  const { code, output } = await runMain({
    pages: [[pr(111), pr(112), pr(113)]],
    failDispatch: new Set(["112"]),
    runIds: new Map([
      ["111", 500],
      ["113", undefined],
    ]),
  });
  assert.equal(code, 1);
  assert.equal(output, "run-ids=500\n");
});

test("main records a review-dependency dispatch beside the conflict dispatches", async () => {
  const dependabot = pr(131, {
    mergeable: "MERGEABLE",
    author: { login: "dependabot", databaseId: 49699333 },
    headRefName: "dependabot/npm_and_yarn/x-2.0.0",
    title: "build(deps): bump x from 1.0.0 to 2.0.0",
    body: "",
    labels: { nodes: [] },
    changedFiles: 0,
  });
  const { code, output } = await runMain({ pages: [[pr(130), dependabot]] });
  assert.equal(code, 0);
  assert.equal(output, "run-ids=9130 9131\n");
});

// review-dependency holds a limit-stopped head by the base's resolved limits and
// main's clock, as resolve-conflicts does.
test("main holds a limit-stopped review-dependency head until its reset, by the resolved limits", async () => {
  const dependabot = pr(135, {
    mergeable: "MERGEABLE",
    author: { login: "dependabot", databaseId: 49699333 },
    headRefName: "dependabot/npm_and_yarn/x-2.0.0",
    title: "build(deps): bump x from 1.0.0 to 2.0.0",
    body: "",
    labels: { nodes: [] },
    changedFiles: 0,
  });
  const stop = {
    name: "pr-unblock / review-dependency",
    status: "completed",
    conclusion: "failure",
    started_at: "2026-10-17T10:00:00Z",
    completed_at: "2026-10-17T10:00:00Z",
    output: { title: "Failed", summary: "lane=pr-unblock activity=review-dependency class=rate-limit resets=2026-10-17T11:00:00Z" },
  };
  const options = { pages: [[dependabot]], checked: new Map([[dependabot.headRefOid, [stop]]]) };
  const before = await runMain(options, LIMIT_DEFAULTS, Date.parse("2026-10-17T10:30:00Z"));
  assert.deepEqual(before, { code: 0, output: "" }, "held before the reset");
  const after = await runMain(options, LIMIT_DEFAULTS, Date.parse("2026-10-17T12:00:00Z"));
  assert.deepEqual(after, { code: 0, output: "run-ids=9135\n" }, "dispatched after the reset");
  const capped = await runMain(options, { ...LIMIT_DEFAULTS, "limit-stops-per-head": 1 }, Date.parse("2026-10-17T12:00:00Z"));
  assert.deepEqual(capped, { code: 0, output: "" }, "one stop reaches a cap of 1");
});

// A lanes App PR whose head's lanes failed, as fix-ci-dispatch.mjs lists it.
const ciFixPull = (number) => {
  const head = String(number).padStart(40, "c");
  return {
    number,
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: head,
    author: { login: "melodic-automation-lanes", databaseId: LANES_APP },
    labels: { nodes: [] },
    commits: {
      nodes: [
        {
          commit: {
            oid: head,
            statusCheckRollup: {
              contexts: {
                nodes: [
                  { __typename: "CheckRun", name: "ci-status", status: "COMPLETED", conclusion: "FAILURE", checkSuite: { app: { databaseId: 15368 } } },
                  { __typename: "StatusContext", context: "ci-lanes", state: "FAILURE", creator: { __typename: "Bot", login: "github-actions", databaseId: 41898282 } },
                ],
              },
            },
          },
        },
      ],
    },
  };
};

test("main records fix-ci dispatches beside the others, capped by limits.fix-ci-per-run", async () => {
  const pulls = [ciFixPull(141), ciFixPull(142), ciFixPull(143)];
  const capped = await runMain({ pages: [[pr(140)]], ciFixPulls: pulls }, { ...LIMIT_DEFAULTS, "fix-ci-per-run": 1, "fix-ci-restarts": 1 });
  assert.deepEqual(capped, { code: 0, output: "run-ids=9140 9141\n" });
  const fallback = await runMain({ pages: [[]], ciFixPulls: pulls });
  assert.deepEqual(fallback, { code: 0, output: "run-ids=9141 9142\n" }, "with no fix-ci limit the default of 2 holds");
});

// A ready PR a person opened that changes Markdown, as fix-docs-dispatch.mjs lists it.
const docsPull = (number) => {
  const head = String(number).padStart(40, "d");
  return {
    number,
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: head,
    author: { __typename: "User", login: "someone", databaseId: 4242 },
    labels: { nodes: [] },
    files: { nodes: [{ path: "README.md" }], pageInfo: { hasNextPage: false } },
    commits: { nodes: [{ commit: { oid: head, statusCheckRollup: { contexts: { nodes: [] } } } }] },
  };
};

test("main records fix-docs dispatches beside the others, capped by limits.fix-docs-per-run", async () => {
  const docsPulls = [docsPull(171), docsPull(172), docsPull(173)];
  const capped = await runMain({ pages: [[pr(170)]], docsPulls }, { ...LIMIT_DEFAULTS, "fix-docs-per-run": 1 });
  assert.deepEqual(capped, { code: 0, output: "run-ids=9170 9171\n" });
  const fallback = await runMain({ pages: [[]], docsPulls });
  assert.deepEqual(fallback, { code: 0, output: "run-ids=9171 9172\n" }, "with no fix-docs limit the default of 2 holds");
});

// main against a fake API whose run listing fails with `error`, holding one
// candidate for resolve-conflicts, fix-ci and fix-docs each.
async function mainWithFailedListing(error) {
  const api = fakeApi({ pages: [[pr(181)]], ciFixPulls: [ciFixPull(182)], docsPulls: [docsPull(183)], workflowRuns: error });
  const lines = [];
  const dir = mkdtempSync(join(tmpdir(), "pr-unblock-dispatch-"));
  try {
    const code = await main(
      { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: "1", GITHUB_OUTPUT: join(dir, "out"), APP_SENDER_ID: String(LANES_APP), BASE_PATH: dir },
      { api, sleep: async () => {}, log: (line) => lines.push(line), loadLimits: async () => LIMIT_DEFAULTS, loadAdoption: async () => ({}) },
    );
    return { api, code, lines };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("main lists each workflow's runs once, and a rate-limited listing ends the run green with nothing dispatched", async () => {
  const { api, code, lines } = await mainWithFailedListing(rateLimitedListing());
  assert.equal(code, 0);
  assert.deepEqual(api.calls.dispatch, []);
  assert.deepEqual(api.calls.runs, ["pr-unblock.yml", "pr-refine.yml"], "resolve-conflicts and fix-ci share one pr-unblock.yml listing");
  assert.ok(lines.includes("dispatched 0 run(s), 0 failure(s)"));
});

test("main still exits 1 on a run listing that fails for any other reason", async () => {
  const { api, code } = await mainWithFailedListing(new Error("GET runs returned 404"));
  assert.equal(code, 1);
  assert.deepEqual(api.calls.dispatch, []);
});

test("the adapter marks a run listing budgetedFetch gave up on as rate limited, and a refusal as not", async () => {
  const reset = Math.floor(Date.now() / 1000) + 19 * 60;
  // Each listing gets its own latch: a limit refuses its latch's later calls.
  const apiFor = (answer) => {
    const latch = createRateLimitLatch({ log: () => {}, fail: () => {}, limits: () => ({}), stopFile: null });
    const budget = budgetedFetch({ fetch: async () => answer, log: () => {}, sleep: async () => assert.fail("no wait fits"), latch });
    return createGitHubApi({ token: "t", repository: "o/r", apiUrl: "https://api.example", graphqlUrl: "https://api.example/graphql", fetch: budget.fetch });
  };
  const limited = apiFor(
    new Response('{"message":"API rate limit exceeded for installation."}', {
      status: 403,
      headers: { "x-ratelimit-remaining": "0", "x-ratelimit-reset": String(reset) },
    }),
  );
  await assert.rejects(limited.listWorkflowRuns("pr-unblock.yml"), (error) => error.rateLimited === true && /returned 403/.test(error.message));
  await assert.rejects(limited.listWorkflowRuns("pr-refine.yml"), (error) => error.rateLimited === true, "a refused later listing is rate limited too");
  const refused = apiFor(new Response('{"message":"Resource not accessible by integration"}', { status: 403, headers: { "x-ratelimit-remaining": "4000" } }));
  await assert.rejects(refused.listWorkflowRuns("pr-refine.yml"), (error) => error.rateLimited !== true && /returned 403/.test(error.message));
});

test("without the lanes App sender id main still dispatches conflicts, dispatches no fix-ci, and exits 1", async () => {
  const dir = mkdtempSync(join(tmpdir(), "pr-unblock-dispatch-"));
  try {
    const output = join(dir, "output");
    writeFileSync(output, "");
    const code = await main(
      { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: "1", GITHUB_OUTPUT: output },
      { api: fakeApi({ pages: [[pr(150)]], ciFixPulls: [ciFixPull(151)] }), log: () => {}, loadLimits: async () => LIMIT_DEFAULTS, loadAdoption: async () => ({}) },
    );
    assert.equal(code, 1);
    assert.equal(readFileSync(output, "utf8"), "run-ids=9150\n");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("main appends each run id to RUN_IDS_FILE as soon as its dispatch returns", async () => {
  const dir = mkdtempSync(join(tmpdir(), "pr-unblock-dispatch-"));
  try {
    const file = join(dir, "ids");
    const api = fakeApi({ pages: [[pr(160), pr(161)]], runIds: new Map([["161", undefined]]) });
    const seen = [];
    const dispatch = api.dispatchWorkflow;
    api.dispatchWorkflow = async (request) => {
      seen.push(readFileSync(file, { encoding: "utf8", flag: "a+" }));
      return dispatch(request);
    };
    await main(
      { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: "1", GITHUB_OUTPUT: join(dir, "out"), APP_SENDER_ID: String(LANES_APP), RUN_IDS_FILE: file },
      { api, log: () => {}, loadLimits: async () => LIMIT_DEFAULTS, loadAdoption: async () => ({}) },
    );
    assert.deepEqual(seen, ["", "9160\n"], "the first id is on disk before the second dispatch");
    assert.equal(readFileSync(file, "utf8"), "9160\n", "an id that is not a run id is not recorded");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("main writes nothing to GITHUB_OUTPUT when no run was dispatched", async () => {
  const noPulls = await runMain({ pages: [[pr(121, { mergeable: "MERGEABLE" })]] });
  assert.deepEqual(noPulls, { code: 0, output: "" });
  const noRunId = await runMain({
    pages: [[pr(122)]],
    runIds: new Map([["122", undefined]]),
  });
  assert.deepEqual(noRunId, { code: 1, output: "" });
});

// The REST contract (docs.github.com rest/actions/workflows "Create a workflow
// dispatch event", API version 2022-11-28: 200 with workflow_run_id only when
// return_run_details is true, else 204; rest/checks/runs "List check runs
// for a Git reference" with check_name) and the GraphQL listing.
test("the GitHub adapter calls the documented endpoints", async () => {
  const requests = [];
  const responses = [
    {
      data: {
        repository: {
          pullRequests: { nodes: [pr(1)], pageInfo: { hasNextPage: false, endCursor: null } },
        },
      },
    },
    { total_count: 1, check_runs: [SUCCESS_RUN] },
    { workflow_run_id: 77, run_url: "u", html_url: "h" },
    { total_count: 1, workflow_runs: [{ id: 5, status: "queued" }] },
  ];
  const fetchStub = async (url, init) => {
    requests.push({
      url,
      method: init.method,
      body: init.body && JSON.parse(init.body),
      auth: init.headers.Authorization,
    });
    const body = init.body && JSON.parse(init.body);
    if (url.endsWith("/dispatches") && body.return_run_details !== true) {
      responses.shift();
      return { ok: true, status: 204, json: async () => assert.fail("204 has no body") };
    }
    return { ok: true, status: 200, json: async () => responses.shift() };
  };
  const api = createGitHubApi({
    token: "t0ken",
    repository: "octo/repo",
    apiUrl: "https://api.example",
    graphqlUrl: "https://api.example/graphql",
    fetch: fetchStub,
  });
  const page = await api.listOpenPulls({ base: "main" });
  assert.equal(page.nodes[0].number, 1);
  assert.equal(requests[0].url, "https://api.example/graphql");
  assert.deepEqual(
    {
      owner: requests[0].body.variables.owner,
      name: requests[0].body.variables.name,
      base: requests[0].body.variables.base,
    },
    { owner: "octo", name: "repo", base: "main" },
  );
  assert.deepEqual(await api.listCheckRuns({ sha: "abc", checkName: CHECK_NAME, appId: 15368 }), [
    SUCCESS_RUN,
  ]);
  assert.equal(
    requests[1].url,
    "https://api.example/repos/octo/repo/commits/abc/check-runs?check_name=pr-unblock+%2F+resolve-conflicts&app_id=15368&filter=all&per_page=100",
  );
  const sent = await api.dispatchWorkflow({
    workflow: "pr-unblock.yml",
    ref: "refs/heads/main",
    inputs: { "pr-number": "1" },
  });
  assert.deepEqual(sent, { workflowRunId: 77 });
  assert.equal(
    requests[2].url,
    "https://api.example/repos/octo/repo/actions/workflows/pr-unblock.yml/dispatches",
  );
  assert.deepEqual(requests[2].body, {
    ref: "refs/heads/main",
    inputs: { "pr-number": "1" },
    return_run_details: true,
  });
  assert.equal(requests[2].method, "POST");
  assert.equal(requests[2].auth, "Bearer t0ken");
  assert.deepEqual(await api.listWorkflowRuns("pr-unblock.yml"), [{ id: 5, status: "queued" }]);
  assert.equal(
    requests[3].url,
    "https://api.example/repos/octo/repo/actions/workflows/pr-unblock.yml/runs?event=workflow_dispatch&per_page=100",
  );
});

test("the required-run read takes the newest pr-require-checks run that tested the head", async () => {
  const head = "c".repeat(40);
  const urls = [];
  const failed = (id, path, created) => ({ id, path, created_at: created, status: "completed", conclusion: "failure" });
  // Run 14 is a contract-only run (only ci-status ran), stepped past.
  const contractOnly = [
    { name: "ci-status", conclusion: "failure" },
    { name: "lint-repo", conclusion: "skipped" },
  ];
  const responses = [
    {
      total_count: 4,
      workflow_runs: [
        failed(11, ".github/workflows/pr-require-checks.yml", "2026-10-22T02:00:00Z"),
        failed(12, ".github/workflows/pr-require-checks.yml", "2026-10-22T03:00:00Z"),
        failed(13, ".github/workflows/pr-test-windows.yml", "2026-10-22T04:00:00Z"),
        failed(14, ".github/workflows/pr-require-checks.yml", "2026-10-22T03:00:14Z"),
      ],
    },
    { total_count: 2, jobs: contractOnly },
    { total_count: 1, jobs: [{ name: "test-node", conclusion: "cancelled" }] },
    { total_count: 0, workflow_runs: [] },
    { total_count: 1, workflow_runs: [failed(11, ".github/workflows/pr-require-checks.yml", "2026-10-22T02:00:00Z"), failed(13, ".github/workflows/pr-test-windows.yml", "2026-10-22T04:00:00Z")] },
    { total_count: 1, jobs: [{ name: "test-macos-planning-shared", conclusion: "failure" }] },
  ];
  const api = createGitHubApi({
    token: "t0ken",
    repository: "octo/repo",
    apiUrl: "https://api.example",
    graphqlUrl: "https://api.example/graphql",
    fetch: async (url) => {
      urls.push(url);
      return { ok: true, status: 200, json: async () => responses.shift() };
    },
  });
  assert.deepEqual(await api.readRequiredRun(head), {
    run: failed(12, ".github/workflows/pr-require-checks.yml", "2026-10-22T03:00:00Z"),
    jobs: [{ name: "test-node", conclusion: "cancelled" }],
  });
  assert.deepEqual(urls, [
    `https://api.example/repos/octo/repo/actions/runs?head_sha=${head}&event=pull_request&per_page=100`,
    "https://api.example/repos/octo/repo/actions/runs/14/jobs?filter=latest&per_page=100",
    "https://api.example/repos/octo/repo/actions/runs/12/jobs?filter=latest&per_page=100",
  ]);
  assert.deepEqual(await api.readRequiredRun(head), { run: null, jobs: [] });
  // A named workflow reads that workflow's runs instead.
  assert.deepEqual(await api.readRequiredRun(head, ".github/workflows/pr-test-windows.yml"), {
    run: failed(13, ".github/workflows/pr-test-windows.yml", "2026-10-22T04:00:00Z"),
    jobs: [{ name: "test-macos-planning-shared", conclusion: "failure" }],
  });
  assert.equal(urls.at(-1), "https://api.example/repos/octo/repo/actions/runs/13/jobs?filter=latest&per_page=100");
  await assert.rejects(api.readRequiredRun("main"), /not a commit SHA/);
});

// The record a run leaves: the next run, against the same GitHub state,
// dispatches the same PRs and skips the reads the record makes redundant.
// #1 conflicts at a head a successful run handled; #2 conflicts and is new;
// #3 reads UNKNOWN, then CONFLICTING at a head a successful run handled.
const recordState = () => ({
  pages: [[pr(1), pr(2), pr(3, { mergeable: "UNKNOWN" })]],
  requeries: [[pr(3)]],
  checked: new Set([pr(1).headRefOid, pr(3).headRefOid]),
});

test("a run records heads a finished run handled, and the next run skips their reads and re-queries", async () => {
  const record = emptyRecord();
  const first = harness(recordState(), { record });
  await first.run();
  // Without a record: a check-run read per conflicting head (#1, #2, #3) and
  // one re-query round after one 10 s wait.
  assert.deepEqual(dispatchedNumbers(first.api), ["2"]);
  assert.equal(first.api.calls.checks.length, 3);
  assert.equal(first.api.calls.get.length, 1);
  assert.deepEqual(first.sleeps, [10_000]);
  assert.deepEqual([...record.handled.get(CHECK_NAME)].sort(), [pr(1).headRefOid, pr(3).headRefOid]);

  const second = harness(recordState(), { record: parseRecord(serializeRecord(record)) });
  await second.run();
  assert.deepEqual(dispatchedNumbers(second.api), ["2"]);
  assert.deepEqual(second.api.calls.checks.map((call) => call.sha), [pr(2).headRefOid]);
  assert.equal(second.api.calls.get.length, 0);
  assert.deepEqual(second.sleeps, []);
  assert.ok(second.lines.includes(`skip #1: head ${pr(1).headRefOid} already has a ${CHECK_NAME} check run (recorded)`));
});

test("a run whose every candidate is recorded lists no workflow runs", async () => {
  const record = emptyRecord();
  markHandled(record, CHECK_NAME, pr(1).headRefOid);
  const { api, run } = harness({ pages: [[pr(1)]] }, { record });
  await run();
  assert.deepEqual(api.calls.runs, []);
  assert.deepEqual(api.calls.checks, []);
});

test("only a finished run that handles the head for good is recorded", async () => {
  const runs = new Map([
    [pr(1).headRefOid, [UNTRUSTED_SKIP]],
    [pr(2).headRefOid, [{ status: "in_progress", conclusion: null }]],
    [pr(3).headRefOid, [failedRun("2026-10-17T10:00:00Z", " resets=2026-10-17T12:00:00Z")]],
    [pr(4).headRefOid, [failedRun("2026-10-17T10:00:00Z", null)]],
    [pr(5).headRefOid, [SUCCESS_RUN]],
  ]);
  const record = emptyRecord();
  const { run } = harness({ pages: [[pr(1), pr(2), pr(3), pr(4), pr(5)]], checked: runs }, { record, maxDispatch: 9 });
  await run();
  // #4 failed once, so it is retried; #5 finished: handled for good.
  assert.deepEqual([...(record.handled.get(CHECK_NAME) ?? [])], [pr(5).headRefOid]);
});

test("main carries the record in DISPATCH_RECORD and writes it only when it changed", async () => {
  const dir = mkdtempSync(join(tmpdir(), "pr-unblock-record-"));
  const output = join(dir, "output");
  const path = join(dir, "record.json");
  const env = {
    GITHUB_TOKEN: "t0ken",
    GITHUB_REPOSITORY: "octo/repo",
    GITHUB_RUN_ID: "4242",
    GITHUB_OUTPUT: output,
    APP_SENDER_ID: String(LANES_APP),
    DISPATCH_RECORD: path,
  };
  // A recorded head no open PR carries any more is dropped.
  writeFileSync(path, JSON.stringify({ version: 4, handled: { [CHECK_NAME]: ["f".repeat(40)] }, dispatched: {} }));
  const options = () => ({ api: fakeApi({ pages: [[pr(1)]], checked: new Set([pr(1).headRefOid]) }), sleep: async () => {}, log: () => {}, loadLimits: async () => LIMIT_DEFAULTS, loadAdoption: async () => ({}) });
  try {
    writeFileSync(output, "");
    assert.equal(await main(env, options()), 0);
    assert.equal(readFileSync(output, "utf8"), "record-changed=true\n");
    assert.deepEqual(JSON.parse(readFileSync(path, "utf8")), { version: 4, handled: { [CHECK_NAME]: [pr(1).headRefOid] }, dispatched: {} });
    writeFileSync(output, "");
    assert.equal(await main(env, options()), 0);
    assert.equal(readFileSync(output, "utf8"), "");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// The per-head cap is the loop's hard end, so it is shown: one warning on the
// run that records the head, and none from the runs that skip it on the record.
test("a head at the resolve-conflicts cap is warned about once, as it is recorded; a head done for another reason is not", async () => {
  const capped = pr(61);
  const done = pr(62);
  const failed = failedRun("2026-10-17T10:00:00Z", null);
  const state = () => ({
    pages: [[capped, done]],
    checked: new Map([
      [capped.headRefOid, [failed, HELD_SKIP, failed]],
      [done.headRefOid, [SUCCESS_RUN]],
    ]),
  });
  const warning = `::warning::#61: head ${capped.headRefOid}'s ${CHECK_NAME} failed or was skipped while held 3 time(s), the most one head gets; no resolve-conflicts until a new push`;
  const record = emptyRecord();
  const first = harness(state(), { record });
  await first.run();
  assert.deepEqual(first.lines.filter((line) => line.startsWith("::warning::")), [warning]);
  assert.deepEqual([...record.handled.get(CHECK_NAME)].sort(), [capped.headRefOid, done.headRefOid]);

  const second = harness(state(), { record: parseRecord(serializeRecord(record)) });
  await second.run();
  assert.deepEqual(second.lines.filter((line) => line.startsWith("::warning::")), []);
  assert.deepEqual([second.api.calls.checks, second.api.calls.timeline, second.api.calls.runs], [[], [], []]);
});

test("main records a fix-ci head at the per-head cap in DISPATCH_RECORD, warns once, and reads nothing for it on the next run", async () => {
  const dir = mkdtempSync(join(tmpdir(), "pr-unblock-record-"));
  const output = join(dir, "output");
  const path = join(dir, "record.json");
  const env = {
    GITHUB_TOKEN: "t0ken",
    GITHUB_REPOSITORY: "octo/repo",
    GITHUB_RUN_ID: "4242",
    GITHUB_OUTPUT: output,
    APP_SENDER_ID: String(LANES_APP),
    DISPATCH_RECORD: path,
  };
  const fixCi = ciFixPull(151);
  const notApplicable = { name: "pr-unblock / fix-ci", status: "completed", conclusion: "neutral", output: { title: "Skipped: not-applicable" }, completed_at: "2026-10-17T10:00:00Z" };
  const once = () => {
    const api = fakeApi({
      pages: [[{ ...fixCi, mergeable: "MERGEABLE" }]],
      ciFixPulls: [fixCi],
      checked: new Map([[fixCi.headRefOid, [notApplicable, notApplicable, notApplicable]]]),
    });
    const lines = [];
    return { api, lines, options: { api, sleep: async () => {}, log: (line) => lines.push(line), loadLimits: async () => LIMIT_DEFAULTS, loadAdoption: async () => ({}) } };
  };
  const warning = `::warning::#151: head ${fixCi.headRefOid}'s pr-unblock / fix-ci ran 3 time(s), the most one head gets; no fix-ci until a new push`;
  try {
    writeFileSync(output, "");
    const first = once();
    assert.equal(await main(env, first.options), 0);
    assert.deepEqual(first.api.calls.dispatch, []);
    assert.deepEqual(first.lines.filter((line) => line.startsWith("::warning::#151")), [warning]);
    assert.deepEqual(JSON.parse(readFileSync(path, "utf8")).handled, { "pr-unblock / fix-ci": [fixCi.headRefOid] });

    const second = once();
    assert.equal(await main(env, second.options), 0);
    assert.deepEqual(second.lines.filter((line) => line.startsWith("::warning::#151")), []);
    assert.deepEqual([second.api.calls.checks, second.api.calls.timeline, second.api.calls.runs], [[], [], []]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
