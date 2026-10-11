import assert from "node:assert/strict";
import { test } from "node:test";

import { createGitHubApi, dispatchConflicting } from "./dispatch.mjs";

const CHECK_NAME = "pr-unblock / resolve-conflicts";
const SUCCESS_RUN = { status: "completed", conclusion: "success", output: { title: "Resolved" } };
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
// or a Map from head SHA to the check runs GitHub returns for it.
function fakeApi({
  pages = [[]],
  requeries = [],
  checked = new Set(),
  failDispatch = new Set(),
  failChecks = new Set(),
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
    async dispatchWorkflow({ workflow, ref, inputs }) {
      calls.dispatch.push({ workflow, ref, inputs });
      if (failDispatch.has(inputs["pr-number"])) {
        throw new Error("dispatch failed");
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

// The REST contract (docs.github.com rest/actions/workflows "Create a workflow
// dispatch event": 200 with workflow_run_id; rest/checks/runs "List check runs
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
  assert.deepEqual(requests[2].body, { ref: "refs/heads/main", inputs: { "pr-number": "1" } });
  assert.equal(requests[2].method, "POST");
  assert.equal(requests[2].auth, "Bearer t0ken");
});
