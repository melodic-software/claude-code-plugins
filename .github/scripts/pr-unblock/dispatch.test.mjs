import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { createGitHubApi, dispatchConflicting, main } from "./dispatch.mjs";

const CHECK_NAME = "pr-unblock / resolve-conflicts";
const SUCCESS_RUN = { status: "completed", conclusion: "success", output: { title: "Resolved" } };
// The lane record report-lane-outcome (ci-workflows) writes on a limit stop.
const limitRecord = (tokens = "") => ({
  annotation_level: "failure",
  title: "",
  message: `pr-unblock skipped: usage limit reached; re-run after it resets (pr-unblock exited with: failure class=rate-limit${tokens}). Last SDK result: {}`,
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
// included; any other PR gets 9000 plus its number.
function fakeApi({
  pages = [[]],
  requeries = [],
  checked = new Set(),
  failDispatch = new Set(),
  failChecks = new Set(),
  runIds = new Map(),
  annotations = new Map(),
} = {}) {
  const calls = { list: [], get: [], checks: [], dispatch: [] };
  let round = 0;
  return {
    calls,
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
    async listAnnotations(checkRunId) {
      return annotations.get(checkRunId) ?? [];
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

test("an in-progress run or any other completed conclusion counts as handled", async () => {
  const running = pr(14);
  const failed = pr(15);
  const otherNeutral = pr(16);
  const mixed = pr(17);
  const sameTitleFailed = pr(18);
  const sameTitleRunning = pr(19);
  const { api, run } = harness({
    pages: [[running, failed, otherNeutral, mixed, sameTitleFailed, sameTitleRunning]],
    checked: new Map([
      [running.headRefOid, [{ status: "in_progress", conclusion: null, output: { title: null } }]],
      [failed.headRefOid, [{ status: "completed", conclusion: "failure", output: { title: "x" } }]],
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
      [sameTitleFailed.headRefOid, [{ ...UNTRUSTED_SKIP, conclusion: "failure" }]],
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
// ended. Until then, and for any other failure, it still counts.
test("a limit-stopped run counts as handled only until its limit resets", async () => {
  const now = Date.parse("2026-10-17T12:00:00Z");
  const stop = (id, completed) => ({ id, status: "completed", conclusion: "failure", completed_at: completed, output: { title: "x" } });
  const [statedPast, statedFuture, fallbackPast, fallbackFuture] = [pr(21), pr(22), pr(23), pr(24)];
  const { api, run } = harness(
    {
      pages: [[statedPast, statedFuture, fallbackPast, fallbackFuture]],
      checked: new Map([
        [statedPast.headRefOid, [stop(1, "2026-10-17T10:00:00Z")]],
        [statedFuture.headRefOid, [stop(2, "2026-10-17T10:00:00Z")]],
        [fallbackPast.headRefOid, [stop(3, "2026-10-17T06:00:00Z")]],
        [fallbackFuture.headRefOid, [stop(4, "2026-10-17T08:00:00Z")]],
      ]),
      annotations: new Map([
        [1, [{ annotation_level: "failure", message: "Process completed with exit code 1." }, limitRecord(" resets=2026-10-17T11:00:00Z turns=3")]],
        [2, [limitRecord(" resets=2026-10-17T13:00:00Z resets-window=five_hour")]],
        [3, [limitRecord()]],
        [4, [limitRecord(" turns=2")]],
      ]),
    },
    { now, maxDispatch: 10 },
  );
  await run();
  assert.deepEqual(dispatchedNumbers(api), ["21", "23"]);
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
async function runMain(apiOptions) {
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
      },
      { api: fakeApi(apiOptions), sleep: async () => {}, log: () => {} },
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
    author: { login: "dependabot[bot]" },
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
});
