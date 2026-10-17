import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { createGitHubApi, dispatchFeedback, main } from "./feedback-dispatch.mjs";

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
const TITLE_42 = pr_unblockTitle("address-feedback", 42);

const REPOSITORY = "melodic-software/claude-code-plugins";
const HEAD = "1111111111111111111111111111111111111111";
const OLD_HEAD = "2222222222222222222222222222222222222222";
const APP_ID = 337595936; // melodic-automation-lanes[bot]
const ACTIONS_BOT = { login: "github-actions[bot]", id: 41898282 };
const CLAUDE = { databaseId: 209825114 };
const KYLE = { databaseId: 153232337 };
const UPSTREAM_RUN_ID = "38779135732";
const RUN_ID = "38779143370";

const marker = (lane, sha = HEAD, user = ACTIONS_BOT) => ({
  user,
  body: `<!-- claude-lane-reviewed-head lane=${lane} sha=${sha} -->\n${lane} has reviewed this pull request through ${sha}.`,
});
const thread = (authors, isResolved = false) => ({
  isResolved,
  comments: { nodes: authors.map((author) => ({ author })), pageInfo: { hasNextPage: false } },
});

function fakeApi({
  run = {},
  pulls,
  comments = [marker("claude-review"), marker("claude-security-review")],
  threads = [thread([CLAUDE])],
  checkRuns = [],
  annotations = [],
  workflowRuns = [],
  workflowRunId = 38779200001,
} = {}) {
  const calls = { dispatch: [] };
  return {
    calls,
    async getRun(id) {
      return {
        id: Number(id),
        path: ".github/workflows/pr-review-hosted.yml",
        event: "pull_request",
        status: "completed",
        head_sha: HEAD,
        repository: { full_name: REPOSITORY },
        head_repository: { full_name: REPOSITORY },
        ...run,
      };
    },
    async pullsForCommit() {
      return (
        pulls ?? [
          {
            number: 42,
            state: "open",
            draft: false,
            user: { id: APP_ID },
            labels: [{ name: "work-class: mechanical" }],
            head: { sha: HEAD, repo: { full_name: REPOSITORY } },
            base: { ref: "main" },
          },
        ]
      );
    },
    listIssueComments: async () => comments,
    listReviewThreads: async () => threads,
    listCheckRuns: async () => checkRuns,
    listAnnotations: async () => annotations,
    listWorkflowRuns: async () => workflowRuns,
    async dispatchWorkflow(request) {
      calls.dispatch.push(request);
      return { workflowRunId };
    },
  };
}

// What resolveFeedbackSlot returns: resolve-config's ResolvedConfig for the
// pr-unblock lane with address-feedback selected (the lane, every slot with
// its enabled flag, the selected slot), or null when the lane has no
// address-feedback slot (resolve-config's undefined-activity refusal).
const resolvedLane = ({ laneEnabled = true, slots = {}, applies = true, skipReason = null } = {}) => {
  if (Object.hasOwn(slots, "address-feedback") && slots["address-feedback"] === undefined) {
    return null;
  }
  const enabled = { "resolve-conflicts": true, "address-feedback": true, "publish-feedback": true, "report-escalation": true, ...slots };
  const all = Object.entries(enabled)
    .filter(([, on]) => on !== undefined)
    .map(([name, on]) => ({ name, enabled: on, applies: null, "skip-reason": null }));
  const selected = all.find((slot) => slot.name === "address-feedback");
  Object.assign(selected, { applies, "skip-reason": skipReason });
  return { lane: { name: "pr-unblock", enabled: laneEnabled, slots: all }, selected };
};

async function decide(api, resolved = resolvedLane()) {
  const lines = [];
  const asked = [];
  const result = await dispatchFeedback({
    api,
    repository: REPOSITORY,
    runId: RUN_ID,
    upstreamRunId: UPSTREAM_RUN_ID,
    appSenderId: APP_ID,
    resolveSlot: async (request) => {
      asked.push(request);
      return resolved;
    },
    log: (line) => lines.push(line),
  });
  return { result, lines, asked };
}

const pull = (overrides) => [
  {
    number: 42,
    state: "open",
    draft: false,
    user: { id: APP_ID },
    labels: [],
    head: { sha: HEAD, repo: { full_name: REPOSITORY } },
    base: { ref: "main" },
    ...overrides,
  },
];

test("a reviewed lanes App PR with a reviewer-bot thread dispatches address-feedback on main", async () => {
  const api = fakeApi();
  const { result } = await decide(api);
  assert.deepEqual(result, { number: 42, workflowRunId: "38779200001" });
  assert.deepEqual(api.calls.dispatch, [
    {
      workflow: "pr-unblock.yml",
      ref: "refs/heads/main",
      inputs: { "pr-number": "42", activity: "address-feedback", "dispatcher-run-id": RUN_ID },
    },
  ]);
});

test("the address-feedback slot is resolved for the PR and the reviewed head", async () => {
  const { asked } = await decide(fakeApi());
  assert.deepEqual(asked, [{ number: 42, head: HEAD }]);
});

for (const [label, resolved, reason] of [
  ["the address-feedback slot is disabled", resolvedLane({ slots: { "address-feedback": false } }), /no enabled address-feedback and publish-feedback slots/],
  ["the publish-feedback slot is disabled", resolvedLane({ slots: { "publish-feedback": false } }), /no enabled address-feedback and publish-feedback slots/],
  ["the lane has no address-feedback slot", resolvedLane({ slots: { "address-feedback": undefined } }), /no enabled address-feedback and publish-feedback slots/],
  ["the lane has no publish-feedback slot", resolvedLane({ slots: { "publish-feedback": undefined } }), /no enabled address-feedback and publish-feedback slots/],
  ["the lane is disabled", resolvedLane({ laneEnabled: false }), /no enabled address-feedback and publish-feedback slots/],
  ["address-feedback does not apply", resolvedLane({ applies: false, skipReason: "awaiting-human" }), /does not apply \(awaiting-human\)/],
]) {
  test(`no dispatch when ${label}`, async () => {
    const api = fakeApi();
    const { result, lines } = await decide(api, resolved);
    assert.equal(result, null);
    assert.deepEqual(api.calls.dispatch, []);
    assert.match(lines.at(-1), reason);
  });
}

test("a slot that cannot be resolved fails the run", async () => {
  await assert.rejects(
    dispatchFeedback({
      api: fakeApi(),
      repository: REPOSITORY,
      runId: RUN_ID,
      upstreamRunId: UPSTREAM_RUN_ID,
      appSenderId: APP_ID,
      resolveSlot: async () => {
        throw new Error("resolve-config could not resolve");
      },
      log: () => {},
    }),
    /could not resolve/,
  );
});

test("the security review workflow is an upstream too", async () => {
  const api = fakeApi({ run: { path: ".github/workflows/pr-review-security-hosted.yml" } });
  assert.equal((await decide(api)).result.number, 42);
});

for (const [label, options] of [
  ["the upstream is another workflow", { run: { path: ".github/workflows/ci.yml" } }],
  ["the upstream path names a review workflow at another ref", {
    run: { path: ".github/workflows/pr-review-hosted.yml@refs/heads/x" },
  }],
  ["the upstream ran on push", { run: { event: "push" } }],
  ["the upstream ran on pull_request_target", { run: { event: "pull_request_target" } }],
  ["the upstream has not completed", { run: { status: "in_progress" } }],
  ["the upstream ran on a fork's head", { run: { head_repository: { full_name: "stranger/x" } } }],
  ["the upstream is another run than the event named", { run: { id: 1 } }],
  ["the head has moved past the reviewed SHA", { pulls: pull({ head: { sha: OLD_HEAD, repo: { full_name: REPOSITORY } } }) }],
  ["no open PR has the head", { pulls: [] }],
  ["the PR is closed", { pulls: pull({ state: "closed" }) }],
  ["the PR targets another branch", { pulls: pull({ base: { ref: "release" } }) }],
  ["the PR is a draft", { pulls: pull({ draft: true }) }],
  ["a human opened the PR", { pulls: pull({ user: { id: 153232337 } }) }],
  ["the PR is labeled do-not-merge", { pulls: pull({ labels: [{ name: "do-not-merge" }] }) }],
  ["the PR is labeled needs-human", { pulls: pull({ labels: [{ name: "needs-human" }] }) }],
  ["the security lane has not reviewed the head", { comments: [marker("claude-review")] }],
  ["the code lane's marker names an older head", {
    comments: [marker("claude-review", OLD_HEAD), marker("claude-security-review")],
  }],
  ["a marker was written by another account", {
    comments: [marker("claude-review", HEAD, { id: 9999001 }), marker("claude-security-review")],
  }],
  ["every thread is resolved", { threads: [thread([CLAUDE], true)] }],
  ["the only open thread has a human reply", { threads: [thread([CLAUDE, KYLE])] }],
  ["the only open thread is a human's", { threads: [thread([KYLE])] }],
  ["the head already has an address-feedback check run", {
    checkRuns: [{ status: "completed", conclusion: "success", output: { title: "Done" } }],
  }],
]) {
  test(`no dispatch when ${label}`, async () => {
    const api = fakeApi(options);
    const { result, lines } = await decide(api);
    assert.equal(result, null);
    assert.deepEqual(api.calls.dispatch, []);
    assert.equal(lines.length, 1);
    assert.match(lines[0], /^skip: /);
  });
}

test("the newest marker of a lane decides", async () => {
  const api = fakeApi({
    comments: [marker("claude-review"), marker("claude-security-review"), marker("claude-review", OLD_HEAD)],
  });
  assert.equal((await decide(api)).result, null);
});

test("the gate's untrusted-trigger skip on the head does not block a dispatch", async () => {
  const api = fakeApi({
    checkRuns: [
      { status: "completed", conclusion: "neutral", output: { title: "Skipped: untrusted-trigger (bot-actor)" } },
    ],
  });
  assert.equal((await decide(api)).result.number, 42);
});

// FINAL-DESIGN C5: a limit-stopped address-feedback run holds the head only
// until its limit resets; the next review completion then dispatches again.
test("a limit-stopped check on the head blocks a dispatch only until its reset", async () => {
  const stopped = [{ id: 7, status: "completed", conclusion: "failure", completed_at: "2026-10-17T10:00:00Z", output: { title: "x" } }];
  for (const [resets, expected] of [
    ["2026-10-17T11:00:00Z", 42],
    ["2026-10-17T13:00:00Z", undefined],
  ]) {
    const api = fakeApi({ checkRuns: stopped, annotations: [{ message: `class=rate-limit resets=${resets}` }] });
    const result = await dispatchFeedback({
      api,
      repository: REPOSITORY,
      runId: RUN_ID,
      upstreamRunId: UPSTREAM_RUN_ID,
      appSenderId: APP_ID,
      resolveSlot: async () => resolvedLane(),
      log: () => {},
      now: Date.parse("2026-10-17T12:00:00Z"),
    });
    assert.equal(result?.number, expected, resets);
  }
});

test("a failed check on the head that is not a limit stop blocks a dispatch", async () => {
  const api = fakeApi({
    checkRuns: [{ id: 7, status: "completed", conclusion: "failure", completed_at: "2026-10-01T00:00:00Z", output: { title: "x" } }],
    annotations: [{ message: "class=other" }],
  });
  assert.equal((await decide(api)).result, null);
});

test("a dispatch with no usable run id throws", async () => {
  await assert.rejects(decide(fakeApi({ workflowRunId: null })), /no valid workflow_run_id/);
});

test("a malformed upstream run id throws before any read", async () => {
  await assert.rejects(
    dispatchFeedback({ api: {}, repository: REPOSITORY, runId: RUN_ID, upstreamRunId: "1/../2", appSenderId: APP_ID, log: () => {} }),
    /not a run id/,
  );
});

test("main writes run-id and reads the upstream id from UPSTREAM_RUN_ID only", async () => {
  const dir = mkdtempSync(join(tmpdir(), "pr-feedback-dispatch-"));
  try {
    const output = join(dir, "output");
    writeFileSync(output, "");
    const api = fakeApi();
    const code = await main(
      {
        GITHUB_TOKEN: "t",
        GITHUB_REPOSITORY: REPOSITORY,
        GITHUB_RUN_ID: RUN_ID,
        GITHUB_OUTPUT: output,
        UPSTREAM_RUN_ID,
        APP_SENDER_ID: String(APP_ID),
      },
      { api, resolveSlot: async () => resolvedLane(), log: () => {} },
    );
    assert.equal(code, 0);
    assert.equal(readFileSync(output, "utf8"), "run-id=38779200001\n");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a second dispatcher for one head skips while the first one's run is queued or going", async () => {
  for (const status of ["queued", "in_progress", "waiting", "pending"]) {
    const api = fakeApi({ workflowRuns: [{ id: 1, status, display_title: TITLE_42 }] });
    const { result, lines } = await decide(api);
    assert.equal(result, null, status);
    assert.deepEqual(api.calls.dispatch, []);
    assert.match(lines.at(-1), /run 1 for address-feedback is not done yet/);
  }
});

test("a run created before this review started (the round whose push made this head) does not hold the dispatch", async () => {
  const api = fakeApi({
    run: { run_started_at: "2026-10-15T12:10:00Z" },
    workflowRuns: [{ id: 1, status: "in_progress", display_title: TITLE_42, created_at: "2026-10-15T12:00:00Z" }],
  });
  assert.equal((await decide(api)).result.number, 42);
  const held = fakeApi({
    run: { run_started_at: "2026-10-15T12:10:00Z" },
    workflowRuns: [{ id: 2, status: "queued", display_title: TITLE_42, created_at: "2026-10-15T12:11:00Z" }],
  });
  assert.equal((await decide(held)).result, null);
});

test("a finished run, another PR's run or another activity's run does not hold the dispatch", async () => {
  const api = fakeApi({
    workflowRuns: [
      { id: 1, status: "completed", display_title: TITLE_42 },
      { id: 2, status: "in_progress", display_title: pr_unblockTitle("address-feedback", 420) },
      { id: 3, status: "queued", display_title: pr_unblockTitle("resolve-conflicts", 42) },
    ],
  });
  const { result } = await decide(api);
  assert.equal(result.number, 42);
  assert.equal(api.calls.dispatch.length, 1);
});

test("main requires the lanes App id", async () => {
  await assert.rejects(
    main({ GITHUB_TOKEN: "t", GITHUB_REPOSITORY: REPOSITORY, GITHUB_RUN_ID: RUN_ID, GITHUB_OUTPUT: "x", UPSTREAM_RUN_ID }, { api: fakeApi() }),
    /APP_SENDER_ID is not set/,
  );
});

test("the API client reads review threads across pages through GraphQL", async () => {
  const bodies = [];
  const pages = [
    { nodes: [thread([CLAUDE])], pageInfo: { hasNextPage: true, endCursor: "c1" } },
    { nodes: [thread([KYLE])], pageInfo: { hasNextPage: false, endCursor: null } },
  ];
  const fetch = async (url, init) => {
    bodies.push(JSON.parse(init.body));
    const page = pages[bodies.length - 1];
    return new Response(JSON.stringify({ data: { repository: { pullRequest: { reviewThreads: page } } } }));
  };
  const api = createGitHubApi({ token: "t", repository: REPOSITORY, apiUrl: "https://api.example", graphqlUrl: "https://api.example/graphql", fetch });
  const threads = await api.listReviewThreads(42);
  assert.equal(threads.length, 2);
  assert.deepEqual(
    bodies.map((body) => body.variables.after),
    [null, "c1"],
  );
});
