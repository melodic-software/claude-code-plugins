import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { LIMIT_DEFAULTS } from "../work-resolve-issue/limits.mjs";
import { emptyRecord, parseRecord, serializeRecord } from "./dispatch-record.mjs";
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
const ACTIONS_BOT_NODE = { databaseId: 41898282 };
const CLAUDE = { databaseId: 209825114 };
const KYLE = { databaseId: 153232337 };
const UPSTREAM_RUN_ID = "38779135732";
const RUN_ID = "38779143370";

const marker = (lane, sha = HEAD, user = ACTIONS_BOT) => ({
  user,
  body: `<!-- claude-lane-reviewed-head lane=${lane} sha=${sha} -->\n${lane} has reviewed this pull request through ${sha}.`,
});
// A failed address-feedback run; `line` is the lane record report-check-run
// writes on the first line of its summary, or null for none.
const failedRun = (line, completed = "2026-10-17T10:00:00Z") => ({
  id: 7,
  name: "pr-unblock / address-feedback",
  status: "completed",
  conclusion: "failure",
  completed_at: completed,
  output: { title: "Failed", summary: line === null ? "The activity step failed." : `${line}\n\nThe activity step failed.` },
});
const thread = (authors, isResolved = false) => ({
  isResolved,
  comments: { nodes: authors.map((author) => ({ author })), pageInfo: { hasNextPage: false } },
});
// The #7794 shape: the reviewer bot's finding, the lanes App's UNCERTAIN reply
// (publish-feedback.mjs renderReply), then `reply`, each a minute apart.
const LANE = { databaseId: APP_ID };
const STRANGER = { databaseId: 4242 };
const decidedThread = (reply = { author: KYLE }) => ({
  isResolved: false,
  comments: {
    nodes: [
      { author: CLAUDE, body: "finding" },
      { author: LANE, body: "**pr-unblock / address-feedback: UNCERTAIN, left open for a person**\n\nnote" },
      { body: "Owner decision: drop the reference.", ...reply },
    ].map((node, i) => ({ createdAt: `2026-10-17T20:0${i}:00Z`, lastEditedAt: null, editor: null, ...node })),
    pageInfo: { hasNextPage: false },
  },
});

// A workflow_run event's run object, in the REST workflow run schema
// (https://docs.github.com/en/rest/actions/workflow-runs#get-a-workflow-run).
const upstreamRun = (overrides = {}) => ({
  id: Number(UPSTREAM_RUN_ID),
  path: ".github/workflows/pr-review-hosted.yml",
  event: "pull_request",
  status: "completed",
  head_sha: HEAD,
  repository: { full_name: REPOSITORY },
  head_repository: { full_name: REPOSITORY },
  ...overrides,
});

function fakeApi({
  run = {},
  pulls,
  comments = [marker("claude-review"), marker("claude-security-review")],
  threads = [thread([CLAUDE])],
  checkRuns = [],
  workflowRuns = [],
  workflowRunId = 38779200001,
  permissions = { "kyle-sexton": "admin" },
  labelEvents = [],
} = {}) {
  const calls = { dispatch: [], permission: [], labelEvents: 0 };
  return {
    calls,
    // The event's workflow_run, which the script takes in place of a read.
    upstream: upstreamRun(run),
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
    async listLabelEvents() {
      calls.labelEvents += 1;
      return labelEvents;
    },
    async getPermission(login) {
      calls.permission.push(login);
      return permissions[login] ?? "none";
    },
    // A run that names no check is the address-feedback one.
    listCheckRuns: async ({ checkName }) => checkRuns.filter((run) => (run.name ?? "pr-unblock / address-feedback") === checkName),
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
    upstream: api.upstream,
    appSenderId: APP_ID,
    trustedHumans: new Set([KYLE.databaseId]),
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
      upstream: upstreamRun(),
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

// A pr-review-cli finding: github-actions[bot]'s, its body ending in the lane
// footer (ci-workflows publish-review publish.cjs commentBody at v0.63.0).
const laneThread = (body) => ({
  isResolved: false,
  comments: { nodes: [{ author: ACTIONS_BOT_NODE, body }], pageInfo: { hasNextPage: false } },
});

test("a github-actions[bot] thread ending in the lane footer dispatches like the reviewer bot's", async () => {
  const api = fakeApi({ threads: [laneThread("severity: IMPORTANT\nUnquoted input.\n\nclaude-lane: claude-security-review")] });
  assert.equal((await decide(api)).result.number, 42);
});

test("the code lane's github-actions[bot] thread dispatches like the reviewer bot's", async () => {
  const api = fakeApi({ threads: [laneThread("The loop skips the last item.\n\nclaude-lane: claude-review")] });
  assert.equal((await decide(api)).result.number, 42);
});

test("a github-actions[bot] thread without a review lane's footer last dispatches nothing", async () => {
  for (const body of ["Unquoted input.", "claude-lane: claude-security-review\nUnquoted input."]) {
    const api = fakeApi({ threads: [laneThread(body)] });
    assert.equal((await decide(api)).result, null, body);
    assert.deepEqual(api.calls.dispatch, []);
  }
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
  ["the upstream ran in another repository", { run: { repository: { full_name: "stranger/x" } } }],
  ["the upstream names no head SHA", { run: { head_sha: "main" } }],
  ["the head has moved past the reviewed SHA", { pulls: pull({ head: { sha: OLD_HEAD, repo: { full_name: REPOSITORY } } }) }],
  ["no open PR has the head", { pulls: [] }],
  ["the PR is closed", { pulls: pull({ state: "closed" }) }],
  ["the PR targets another branch", { pulls: pull({ base: { ref: "release" } }) }],
  ["the PR is a draft", { pulls: pull({ draft: true }) }],
  ["a human opened the PR", { pulls: pull({ user: { id: 153232337 } }) }],
  ["the PR is labeled do-not-merge", { pulls: pull({ labels: [{ name: "do-not-merge" }] }) }],
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
  ["the reply after the lane's escalation is a stranger's", { threads: [decidedThread({ author: STRANGER })] }],
  ["the trusted reply was last edited by a stranger", {
    threads: [decidedThread({ author: KYLE, lastEditedAt: "2026-10-17T20:30:00Z", editor: STRANGER })],
  }],
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
  for (const [resets, expected] of [
    ["2026-10-17T11:00:00Z", 42],
    ["2026-10-17T13:00:00Z", undefined],
  ]) {
    const stopped = failedRun(`lane=pr-unblock activity=address-feedback class=rate-limit resets=${resets}`);
    const api = fakeApi({ checkRuns: [stopped] });
    const result = await dispatchFeedback({
      api,
      repository: REPOSITORY,
      runId: RUN_ID,
      upstream: api.upstream,
      appSenderId: APP_ID,
      resolveSlot: async () => resolvedLane(),
      log: () => {},
      now: Date.parse("2026-10-17T12:00:00Z"),
    });
    assert.equal(result?.number, expected, resets);
  }
});

// The restart keys on the current threads and head, never on an earlier run's
// branch: once the reviewer-bot threads are resolved there is nothing to redo,
// and a head that moved past the stopped run's review is not dispatched for it.
test("a reset limit stop does not dispatch once no reviewer-bot thread is open, or once the head moved", async () => {
  const stopped = failedRun("lane=pr-unblock activity=address-feedback class=rate-limit resets=2026-10-17T11:00:00Z");
  for (const [label, options] of [
    ["threads resolved", { threads: [thread([CLAUDE], true)] }],
    ["head moved", { pulls: pull({ head: { sha: OLD_HEAD, repo: { full_name: REPOSITORY } } }) }],
  ]) {
    const api = fakeApi({ checkRuns: [stopped], ...options });
    const result = await dispatchFeedback({
      api,
      repository: REPOSITORY,
      runId: RUN_ID,
      upstream: api.upstream,
      appSenderId: APP_ID,
      resolveSlot: async () => resolvedLane(),
      log: () => {},
      now: Date.parse("2026-10-17T12:00:00Z"),
    });
    assert.equal(result, null, label);
    assert.deepEqual(api.calls.dispatch, [], label);
  }
});

test("a failed check on the head that is not a limit stop blocks a dispatch", async () => {
  for (const line of ["lane=pr-unblock activity=address-feedback class=other", null]) {
    const api = fakeApi({ checkRuns: [failedRun(line, "2026-10-01T00:00:00Z")] });
    assert.equal((await decide(api)).result, null, String(line));
  }
});

// A round whose reply job found no model turn (#9218): its publish-feedback
// check skipped no-model-turn, so the address-feedback check runs before it
// handled nothing, and the next trigger dispatches the head again. Every such
// round posts its round marker, so the select job's round cap still ends it.
const roundRun = (name, conclusion, title, started) => ({
  name: `pr-unblock / ${name}`,
  status: "completed",
  conclusion,
  started_at: started,
  completed_at: started,
  output: { title, summary: "" },
});
const noModelTurn = (started = "2026-10-17T10:05:00Z") => roundRun("publish-feedback", "neutral", "Skipped: no-model-turn", started);

test("a head whose last round had no model turn dispatches again, and is not recorded as handled", async () => {
  for (const [label, check] of [
    ["the activity step failed", roundRun("address-feedback", "failure", "Failed", "2026-10-17T10:00:00Z")],
    ["the broker refused the run", roundRun("address-feedback", "neutral", "Skipped: not-assessed", "2026-10-17T10:00:00Z")],
  ]) {
    const record = emptyRecord();
    const api = fakeApi({ checkRuns: [check, noModelTurn()] });
    const { result } = await decideWith(api, record);
    assert.deepEqual(result, { number: 42, workflowRunId: "38779200001" }, label);
    assert.equal(record.handled.size, 0, label);
  }
});

// A no-model-turn reply never releases a limit stop: it still holds the head
// until its reset and counts toward limits.limit-stops-per-head.
test("a no-model-turn reply after a limit stop leaves the stop's reset hold and cap in place", async () => {
  const stop = (resets, started) => ({
    ...failedRun(`lane=pr-unblock activity=address-feedback class=rate-limit resets=${resets}`, started),
    started_at: started,
  });
  const at = async (runs, now) => {
    const api = fakeApi({ checkRuns: runs });
    const result = await dispatchFeedback({
      api,
      repository: REPOSITORY,
      runId: RUN_ID,
      upstream: api.upstream,
      appSenderId: APP_ID,
      resolveSlot: async () => resolvedLane(),
      log: () => {},
      now: Date.parse(now),
    });
    return result?.number;
  };
  const reply = noModelTurn("2026-10-17T10:05:00Z");
  assert.equal(await at([stop("2026-10-17T13:00:00Z", "2026-10-17T10:00:00Z"), reply], "2026-10-17T12:00:00Z"), undefined, "before its reset");
  assert.equal(await at([stop("2026-10-17T11:00:00Z", "2026-10-17T10:00:00Z"), reply], "2026-10-17T12:00:00Z"), 42, "after its reset");
  const three = ["07", "08", "09"].map((h) => stop(`2026-10-17T${h}:30:00Z`, `2026-10-17T${h}:00:00Z`));
  assert.equal(await at([...three, reply], "2026-10-17T12:00:00Z"), undefined, "three stops reach the per-head cap");
});

test("a round that answered, or a newer address-feedback check, still handles the head", async () => {
  for (const [label, runs] of [
    ["the last round escalated", [roundRun("address-feedback", "success", "Passed", "2026-10-17T10:00:00Z"), roundRun("publish-feedback", "neutral", "Skipped: awaiting-human", "2026-10-17T10:05:00Z")]],
    ["a no-model-turn round before a round that answered", [
      roundRun("address-feedback", "failure", "Failed", "2026-10-17T10:00:00Z"),
      noModelTurn(),
      roundRun("address-feedback", "success", "Passed", "2026-10-17T11:00:00Z"),
      roundRun("publish-feedback", "success", "Passed", "2026-10-17T11:05:00Z"),
    ]],
    // The select job's round cap posts the address-feedback skip after the round.
    ["the round cap was reached after it", [
      roundRun("address-feedback", "failure", "Failed", "2026-10-17T10:00:00Z"),
      noModelTurn(),
      roundRun("address-feedback", "neutral", "Skipped: awaiting-human", "2026-10-17T11:00:00Z"),
    ]],
    ["no reply job ran", [roundRun("address-feedback", "failure", "Failed", "2026-10-17T10:00:00Z")]],
  ]) {
    const api = fakeApi({ checkRuns: runs });
    const { result, lines } = await decide(api);
    assert.equal(result, null, label);
    assert.deepEqual(api.calls.dispatch, [], label);
    assert.match(lines.at(-1), /already has a pr-unblock \/ address-feedback check run/, label);
  }
});

test("a dispatch with no usable run id throws", async () => {
  await assert.rejects(decide(fakeApi({ workflowRunId: null })), /no valid workflow_run_id/);
});

test("a malformed upstream run id throws before any read", async () => {
  await assert.rejects(
    dispatchFeedback({ api: {}, repository: REPOSITORY, runId: RUN_ID, upstream: upstreamRun({ id: "1/../2" }), appSenderId: APP_ID, log: () => {} }),
    /not a run id/,
  );
});

// What the runner writes at GITHUB_EVENT_PATH for a workflow_run event.
const eventFile = (dir, run = upstreamRun()) => {
  const path = join(dir, "event.json");
  writeFileSync(path, JSON.stringify({ action: "completed", workflow_run: run }));
  return path;
};
const noActors = (dir) => {
  const path = join(dir, "actors.json");
  writeFileSync(path, JSON.stringify({ actors: [] }));
  return path;
};

test("main writes run-id and takes the upstream run from the event file", async () => {
  const dir = mkdtempSync(join(tmpdir(), "pr-feedback-dispatch-"));
  try {
    const output = join(dir, "output");
    writeFileSync(output, "");
    const actors = join(dir, "actors.json");
    writeFileSync(actors, JSON.stringify({ actors: [] }));
    const api = fakeApi();
    const code = await main(
      {
        GITHUB_TOKEN: "t",
        GITHUB_REPOSITORY: REPOSITORY,
        GITHUB_RUN_ID: RUN_ID,
        GITHUB_OUTPUT: output,
        GITHUB_EVENT_PATH: eventFile(dir),
        APP_SENDER_ID: String(APP_ID),
        TRUSTED_ACTORS: actors,
      },
      { api, resolveSlot: async () => resolvedLane(), log: () => {} },
    );
    assert.equal(code, 0);
    assert.equal(readFileSync(output, "utf8"), `run-id=38779200001\nupstream-run-id=${UPSTREAM_RUN_ID}\n`);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// A pr-verify run ran on main: its head is main's, so main takes the head its
// post-verify-notes job posted notes on, and the newest completed review run
// there stands in as the upstream the record names.
const VERIFY_RUN = upstreamRun({ id: 99, path: ".github/workflows/pr-verify.yml", event: "workflow_run", head_sha: OLD_HEAD });

// The pr-verify run, read back for its creation time, and one completed review
// run at the head.
const VERIFY_CREATED = "2026-10-17T12:00:00Z";
function verifyApi(options = {}) {
  const note = { isResolved: false, comments: { nodes: [{ author: ACTIONS_BOT_NODE, body: "<!-- pr-verify:fail-note -->\nnotes" }], pageInfo: { hasNextPage: false } } };
  const api = fakeApi({ threads: [note], ...options });
  api.getWorkflowRun = async (id) => (id === VERIFY_RUN.id ? { ...VERIFY_RUN, created_at: VERIFY_CREATED } : null);
  api.listCompletedRuns = async () => [upstreamRun({ id: 13, created_at: "2026-10-17T10:30:00Z" })];
  return api;
}

async function verifyMain(dir, api, head = HEAD, record = null) {
  const output = join(dir, "output");
  writeFileSync(output, "");
  const lines = [];
  await main(
    {
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: REPOSITORY,
      GITHUB_RUN_ID: RUN_ID,
      GITHUB_OUTPUT: output,
      GITHUB_EVENT_PATH: eventFile(dir, VERIFY_RUN),
      APP_SENDER_ID: String(APP_ID),
      TRUSTED_ACTORS: noActors(dir),
      VERIFY_HEAD_SHA: head,
      ...(record ? { DISPATCH_RECORD: record } : {}),
    },
    { api, resolveSlot: async () => resolvedLane(), log: (line) => lines.push(line) },
  );
  return { output: readFileSync(output, "utf8"), lines };
}

test("a pr-verify run dispatches through the newest review run at the posted head", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-feedback-dispatch-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const api = verifyApi();
  const asked = [];
  api.listCompletedRuns = async (path, head) => {
    asked.push([path, head]);
    return path.endsWith("pr-review-hosted.yml")
      ? [upstreamRun({ id: 11, created_at: "2026-10-17T10:00:00Z" }), upstreamRun({ id: 12, conclusion: "cancelled", created_at: "2026-10-17T11:00:00Z" })]
      : [upstreamRun({ id: 13, path, created_at: "2026-10-17T10:30:00Z" })];
  };
  const { output } = await verifyMain(dir, api);
  assert.deepEqual(asked, [
    [".github/workflows/pr-review-hosted.yml", HEAD],
    [".github/workflows/pr-review-security-hosted.yml", HEAD],
  ]);
  assert.equal(api.calls.dispatch.length, 1);
  assert.equal(output, "run-id=38779200001\nupstream-run-id=13\n");
});

// An earlier round at the head (a no-model-turn skip, or one that answered
// without pushing) handled the reviewer's threads, not the notes posted since.
test("a pr-verify run dispatches past a check run and a handled record from before its notes", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-feedback-dispatch-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const before = { name: "pr-unblock / address-feedback", status: "completed", conclusion: "neutral", started_at: "2026-10-17T11:00:00Z", output: { title: "Skipped: no-model-turn" } };
  const record = join(dir, "record.json");
  writeFileSync(record, JSON.stringify({ version: 3, handled: { "pr-unblock / address-feedback": [HEAD] }, dispatched: {} }));
  const api = verifyApi({ checkRuns: [before] });
  const { output } = await verifyMain(dir, api, HEAD, record);
  assert.equal(api.calls.dispatch.length, 1);
  // The dispatch is recorded beside the head's handled entry.
  assert.equal(output, "run-id=38779200001\nupstream-run-id=13\nrecord-changed=true\n");
});

test("a pr-verify run does not dispatch twice: a check run started after it handles its notes", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-feedback-dispatch-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const after = { name: "pr-unblock / address-feedback", status: "completed", conclusion: "success", started_at: "2026-10-17T12:05:00Z" };
  const api = verifyApi({ checkRuns: [after] });
  const { lines } = await verifyMain(dir, api);
  assert.deepEqual(api.calls.dispatch, []);
  assert.match(lines.at(-1), /already has a pr-unblock \/ address-feedback check run/);
});

test("a pr-verify run with no completed review run at the head dispatches nothing", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-feedback-dispatch-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const api = verifyApi();
  api.listCompletedRuns = async () => [upstreamRun({ conclusion: "skipped" })];
  const { output, lines } = await verifyMain(dir, api);
  assert.equal(output, "");
  assert.deepEqual(api.calls.dispatch, []);
  assert.match(lines.at(-1), /no completed review run yet/);
  await assert.rejects(verifyMain(dir, verifyApi(), ""), /VERIFY_HEAD_SHA/);
  const unread = verifyApi();
  unread.getWorkflowRun = async () => ({});
  await assert.rejects(verifyMain(dir, unread), /no readable creation time/);
});

test("an event file that holds no workflow run fails the run", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-feedback-dispatch-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, "event.json");
  writeFileSync(path, JSON.stringify({ action: "completed" }));
  await assert.rejects(
    main(
      { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: REPOSITORY, GITHUB_RUN_ID: RUN_ID, GITHUB_OUTPUT: "x", GITHUB_EVENT_PATH: path, APP_SENDER_ID: String(APP_ID), TRUSTED_ACTORS: noActors(dir) },
      { api: fakeApi(), resolveSlot: async () => resolvedLane(), log: () => {} },
    ),
    /not a run id/,
  );
});

// The repository's GITHUB_TOKEN budget: a review of a PR the lanes App did not
// open is the common case, and it needs only the PR list for the head.
test("a review of a PR the lanes App did not open costs one API request", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "pr-feedback-dispatch-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const urls = [];
  const fetch = async (url) => {
    urls.push(url);
    return new Response(JSON.stringify(pull({ user: { id: KYLE.databaseId } })));
  };
  const api = createGitHubApi({ token: "t", repository: REPOSITORY, apiUrl: "https://api.example", graphqlUrl: "https://api.example/graphql", fetch });
  const lines = [];
  await main(
    {
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: REPOSITORY,
      GITHUB_RUN_ID: RUN_ID,
      GITHUB_OUTPUT: join(dir, "out"),
      GITHUB_EVENT_PATH: eventFile(dir),
      APP_SENDER_ID: String(APP_ID),
      TRUSTED_ACTORS: noActors(dir),
    },
    { api, resolveSlot: async () => resolvedLane(), log: (line) => lines.push(line) },
  );
  assert.deepEqual(urls, [`https://api.example/repos/${REPOSITORY}/commits/${HEAD}/pulls`]);
  assert.match(lines.at(-1), /not opened by the lanes App/);
});

// GitHub Support's probe on 2026-10-22: GET /commits/{sha}/pulls answered 200
// with an empty body while GraphQL's associatedPullRequests read the PR.
test("pullsForCommit reads the commit's PRs from GraphQL when the REST answer is empty", async () => {
  const sent = [];
  const fetch = async (url, init) => {
    sent.push(`${init.method} ${url}`);
    if (url.endsWith("/graphql")) {
      const { variables } = JSON.parse(init.body);
      assert.deepEqual(variables, { owner: "melodic-software", name: "claude-code-plugins", oid: HEAD });
      const node = {
        number: 42,
        state: "OPEN",
        isDraft: false,
        headRefName: "feat/x",
        headRefOid: HEAD,
        baseRefName: "main",
        baseRefOid: OLD_HEAD,
        headRepository: { nameWithOwner: REPOSITORY },
        author: { __typename: "Bot", login: "melodic-automation-lanes", databaseId: APP_ID },
        labels: { nodes: [{ name: "needs-human" }], pageInfo: { hasNextPage: false } },
      };
      return Response.json({ data: { repository: { object: { associatedPullRequests: { nodes: [node], pageInfo: { hasNextPage: false } } } } } });
    }
    return new Response("", { status: 200 });
  };
  const api = createGitHubApi({ token: "t", repository: REPOSITORY, apiUrl: "https://api.example", graphqlUrl: "https://api.example/graphql", fetch });
  assert.deepEqual(await api.pullsForCommit(HEAD), [
    {
      number: 42,
      state: "open",
      draft: false,
      user: { id: APP_ID, login: "melodic-automation-lanes[bot]", type: "Bot" },
      labels: [{ name: "needs-human" }],
      head: { sha: HEAD, ref: "feat/x", repo: { full_name: REPOSITORY } },
      base: { ref: "main", sha: OLD_HEAD },
    },
  ]);
  assert.deepEqual(sent, [`GET https://api.example/repos/${REPOSITORY}/commits/${HEAD}/pulls`, "POST https://api.example/graphql"]);
});

// The GraphQL fallback is a read: it is aborted at the attempt timeout (5 ms
// here) instead of hanging the step. Without it the test times out.
test("pullsForCommit aborts a hung GraphQL fallback at the attempt timeout", { timeout: 5000 }, async () => {
  const fetch = async (url, init) => {
    if (!url.endsWith("/graphql")) {
      return new Response("{}", { status: 500 });
    }
    return new Promise((_, reject) => init.signal?.addEventListener("abort", () => reject(init.signal.reason)));
  };
  const api = createGitHubApi({
    token: "t",
    repository: REPOSITORY,
    apiUrl: "https://api.example",
    graphqlUrl: "https://api.example/graphql",
    fetch,
    attemptTimeoutMs: 5,
  });
  await assert.rejects(api.pullsForCommit(HEAD), (error) => error.name === "TimeoutError");
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

test("a trusted person's reply on a thread the lane escalated dispatches address-feedback", async () => {
  const api = fakeApi({ threads: [decidedThread()] });
  const { result } = await decide(api);
  assert.equal(result.number, 42);
  assert.equal(api.calls.dispatch.length, 1);
});

// On a needs-human PR only a write-access trusted person's fix request
// (address-feedback.mjs isFixRequest) dispatches.
const REQUEST = "*Owner reply.*\n\nPR-fix lane: please fix this finding. Drop the reference.";
const KYLE_LOGIN = { ...KYLE, login: "kyle-sexton" };
const STRANGER_LOGIN = { ...STRANGER, login: "stranger" };
const humanGated = (labels = []) => pull({ labels: [{ name: "needs-human" }, ...labels.map((name) => ({ name }))] });

test("a needs-human PR dispatches when a write-access trusted person asked the lane to fix a thread", async () => {
  const api = fakeApi({ pulls: humanGated(), threads: [decidedThread({ author: KYLE_LOGIN, body: REQUEST })] });
  const { result } = await decide(api);
  assert.equal(result.number, 42);
  assert.equal(api.calls.dispatch.length, 1);
  assert.deepEqual(api.calls.permission, ["kyle-sexton"]);
});

for (const [label, options] of [
  ["a trusted reply that asks no fix", { threads: [decidedThread({ author: KYLE_LOGIN })] }],
  ["a bot-only thread", { threads: [thread([CLAUDE])] }],
  ["a quoted fix request", { threads: [decidedThread({ author: KYLE_LOGIN, body: "> PR-fix lane: please fix this finding." })] }],
  ["a fix request inside a code block", {
    threads: [decidedThread({ author: KYLE_LOGIN, body: "```\nPR-fix lane: please fix this finding.\n```" })],
  }],
  ["an untrusted person's fix request", { threads: [decidedThread({ author: STRANGER_LOGIN, body: REQUEST })], permissions: { stranger: "admin" } }],
  ["a trusted person without write access", {
    threads: [decidedThread({ author: KYLE_LOGIN, body: REQUEST })],
    permissions: { "kyle-sexton": "read" },
  }],
  ["do-not-merge beside a write-access fix request", {
    pulls: humanGated(["do-not-merge"]),
    threads: [decidedThread({ author: KYLE_LOGIN, body: REQUEST })],
  }],
]) {
  test(`a needs-human PR dispatches nothing for ${label}`, async () => {
    const api = fakeApi({ pulls: humanGated(), ...options });
    assert.equal((await decide(api)).result, null);
    assert.deepEqual(api.calls.dispatch, []);
  });
}

// Where needs-human came from (gate-source.mjs). A lane escalation:
// report-escalation.sh's label, then its marked comment, by the lanes App. A
// review-lane hold: the review lane's label and hold comment.
const APP_USER = { login: "melodic-automation-lanes[bot]", id: APP_ID, type: "Bot" };
const ACTIONS_USER = { ...ACTIONS_BOT, type: "Bot" };
const RESUME = `<!-- pr-unblock resume-key=${OLD_HEAD} -->`;
const escalationComment = ({ body = `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n${RESUME}\nThe pr-unblock lane stopped.\n\n- Reason: \`ci-fix-round-cap\``, user = APP_USER, at = "2026-10-18T10:00:05Z" } = {}) => ({
  user,
  body,
  created_at: at,
  updated_at: at,
});
const holdComment = ({ sha = HEAD, at = "2026-10-18T09:00:00Z" } = {}) => ({
  user: ACTIONS_USER,
  body: `<!-- claude-lane-hold lane=claude-security-review sha=${sha} criteria=trust-gate -->\nChanges a trust gate.\n\n\`claude-lane: claude-security-review\``,
  created_at: at,
  updated_at: at,
});
const labelEvent = (event, actor, at) => ({ event, actor, label: { name: "needs-human" }, created_at: at });
const appLabeled = labelEvent("labeled", APP_USER, "2026-10-18T10:00:00Z");
const reviewed = [marker("claude-review"), marker("claude-security-review")];

test("a needs-human PR a lane escalation gated dispatches for a reviewer-bot thread", async () => {
  const api = fakeApi({ pulls: humanGated(), comments: [...reviewed, escalationComment()], labelEvents: [appLabeled] });
  const { result, lines } = await decide(api);
  assert.equal(result?.number, 42, lines.join("\n"));
  assert.equal(api.calls.dispatch.length, 1);
});

for (const [label, source, options] of [
  ["a review-lane hold on the current head", "review-hold", {
    comments: [...reviewed, holdComment()],
    labelEvents: [labelEvent("labeled", ACTIONS_USER, "2026-10-18T09:00:00Z")],
  }],
  ["a lane escalation beside a review-lane hold on the current head", "review-hold", {
    comments: [...reviewed, holdComment({ at: "2026-10-18T10:30:00Z" }), escalationComment()],
    labelEvents: [appLabeled],
  }],
  ["a lane escalation beside an open review-lane hold on an older head", "review-hold", {
    comments: [...reviewed, holdComment({ sha: OLD_HEAD }), escalationComment()],
    labelEvents: [appLabeled],
  }],
  ["an escalation marker with no resume-key line", "unknown", {
    comments: [...reviewed, escalationComment({ body: "<!-- work-items:escalation lane=pr-unblock kind=escalated -->\nThe pr-unblock lane stopped." })],
    labelEvents: [appLabeled],
  }],
  ["a lane escalation beside an escalation marker out of place", "unknown", {
    comments: [...reviewed, escalationComment(), escalationComment({ body: `Note.\n<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n${RESUME}`, at: "2026-10-18T10:05:00Z" })],
    labelEvents: [appLabeled],
  }],
  ["a lane escalation beside a hold marker whose head does not parse", "unknown", {
    comments: [...reviewed, holdComment({ sha: "bbbb" }), escalationComment()],
    labelEvents: [appLabeled],
  }],
  ["an escalation marker someone other than the lanes App wrote", "unknown", {
    comments: [...reviewed, escalationComment({ user: { login: "kyle-sexton", id: KYLE.databaseId, type: "User" } })],
    labelEvents: [appLabeled],
  }],
  ["a lane escalation under a label a person added", "unknown", {
    comments: [...reviewed, escalationComment()],
    labelEvents: [labelEvent("labeled", { login: "kyle-sexton", id: KYLE.databaseId, type: "User" }, "2026-10-18T10:00:00Z")],
  }],
  ["a lane escalation older than the last label add", "unknown", {
    comments: [...reviewed, escalationComment({ at: "2026-10-18T09:00:00Z" })],
    labelEvents: [appLabeled],
  }],
]) {
  test(`a needs-human PR dispatches nothing for a reviewer-bot thread under ${label} (${source})`, async () => {
    const api = fakeApi({ pulls: humanGated(), ...options });
    const { result, lines } = await decide(api);
    assert.equal(result, null, lines.join("\n"));
    assert.deepEqual(api.calls.dispatch, []);
    // The skip names why the label does not admit the PR.
    assert.ok(lines.at(-1).includes(`is labeled needs-human (${source}: `), lines.at(-1));
  });
}

test("a PR without needs-human reads no label events", async () => {
  const api = fakeApi();
  assert.equal((await decide(api)).result.number, 42);
  assert.equal(api.calls.labelEvents, 0);
});

test("without needs-human a trusted reply dispatches with no permission read", async () => {
  const api = fakeApi({ threads: [decidedThread({ author: KYLE_LOGIN })] });
  assert.equal((await decide(api)).result.number, 42);
  assert.deepEqual(api.calls.permission, []);
});

// The #8031 shape: the reviewer bot's finding, then `reply`, with no reply
// from the lanes App.
const askedThread = (reply) => ({
  isResolved: false,
  comments: {
    nodes: [{ author: CLAUDE, body: "finding" }, reply].map((node, i) => ({
      createdAt: `2026-10-17T20:0${i}:00Z`,
      lastEditedAt: null,
      editor: null,
      ...node,
    })),
    pageInfo: { hasNextPage: false },
  },
});

test("a write-access trusted person's fix request on a thread the lane never answered dispatches", async () => {
  const api = fakeApi({ threads: [askedThread({ author: KYLE_LOGIN, body: REQUEST })] });
  assert.equal((await decide(api)).result.number, 42);
  assert.equal(api.calls.dispatch.length, 1);
  assert.deepEqual(api.calls.permission, ["kyle-sexton"]);
});

for (const [label, options] of [
  ["an untrusted person's fix request", { threads: [askedThread({ author: STRANGER_LOGIN, body: REQUEST })], permissions: { stranger: "admin" } }],
  ["a trusted person's fix request without write access", {
    threads: [askedThread({ author: KYLE_LOGIN, body: REQUEST })],
    permissions: { "kyle-sexton": "read" },
  }],
  ["a trusted reply that asks no fix", { threads: [askedThread({ author: KYLE_LOGIN, body: "Owner decision: drop it." })] }],
]) {
  test(`a thread the lane never answered dispatches nothing for ${label}`, async () => {
    const api = fakeApi(options);
    assert.equal((await decide(api)).result, null);
    assert.deepEqual(api.calls.dispatch, []);
  });
}

test("main reads the trusted people from the base's trusted-actor list", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "feedback-dispatch-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const actors = join(dir, "actors.json");
  writeFileSync(actors, JSON.stringify({ actors: [{ id: KYLE.databaseId, login: "kyle-sexton", kind: "human" }] }));
  const env = {
    GITHUB_TOKEN: "t",
    GITHUB_REPOSITORY: REPOSITORY,
    GITHUB_RUN_ID: RUN_ID,
    GITHUB_OUTPUT: join(dir, "out"),
    GITHUB_EVENT_PATH: eventFile(dir),
    APP_SENDER_ID: String(APP_ID),
    TRUSTED_ACTORS: actors,
  };
  const api = fakeApi({ threads: [decidedThread()] });
  await main(env, { api, resolveSlot: async () => resolvedLane(), log: () => {} });
  assert.equal(api.calls.dispatch.length, 1);
});

test("main requires the lanes App id", async () => {
  await assert.rejects(
    main({ GITHUB_TOKEN: "t", GITHUB_REPOSITORY: REPOSITORY, GITHUB_RUN_ID: RUN_ID, GITHUB_OUTPUT: "x", GITHUB_EVENT_PATH: "x" }, { api: fakeApi() }),
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

// The record one run leaves for the next at the same head. `counting` wraps
// a fake so every API call is counted by method.
function counting(api) {
  const counts = {};
  const wrapped = { calls: api.calls, upstream: api.upstream };
  for (const [name, value] of Object.entries(api)) {
    if (typeof value === "function") {
      wrapped[name] = (...args) => {
        counts[name] = (counts[name] ?? 0) + 1;
        return value(...args);
      };
    }
  }
  return { api: wrapped, counts };
}

async function decideWith(api, record, resolved = resolvedLane()) {
  const lines = [];
  const result = await dispatchFeedback({
    api,
    repository: REPOSITORY,
    runId: RUN_ID,
    upstream: api.upstream,
    appSenderId: APP_ID,
    trustedHumans: new Set([KYLE.databaseId]),
    resolveSlot: async () => resolved,
    log: (line) => lines.push(line),
    record,
  });
  return { result, lines };
}

test("a head a finished run handled is recorded, and a later run at that head reads nothing", async () => {
  const handled = { id: 7, name: "pr-unblock / address-feedback", status: "completed", conclusion: "success", started_at: "2026-10-17T10:00:00Z", output: { title: "Done" } };
  // The round's reply job posted after it, so no no-model-turn skip can still release the head.
  const reply = roundRun("publish-feedback", "success", "Passed", "2026-10-17T10:05:00Z");
  const record = emptyRecord();
  const first = counting(fakeApi({ checkRuns: [handled, reply] }));
  assert.equal((await decideWith(first.api, record)).result, null);
  // Without a record: the PR, comments, threads, run listing and both checks' runs.
  assert.deepEqual(first.counts, { pullsForCommit: 1, listIssueComments: 1, listReviewThreads: 1, listWorkflowRuns: 1, listCheckRuns: 2 });
  const later = counting(fakeApi({ checkRuns: [handled, reply] }));
  const { result, lines } = await decideWith(later.api, parseRecord(serializeRecord(record)));
  assert.equal(result, null);
  assert.deepEqual(later.counts, {});
  assert.deepEqual(lines, [`skip: head ${HEAD} already has a pr-unblock / address-feedback check run (recorded)`]);
});

// #9362 part 2: between the round's address-feedback check and its reply
// job's check, a dispatcher run must not record the head, or the reply's
// no-model-turn skip could never release it.
test("a head whose newest address-feedback check has no later reply check is not recorded, and is released once the reply skips no-model-turn", async () => {
  const record = emptyRecord();
  const check = roundRun("address-feedback", "failure", "Failed", "2026-10-17T10:00:00Z");
  const early = await decideWith(fakeApi({ checkRuns: [check] }), record);
  assert.equal(early.result, null, "the head is handled for now");
  assert.equal(record.handled.size, 0, "but not recorded");
  // An older reply check, from an earlier round, does not count.
  await decideWith(fakeApi({ checkRuns: [noModelTurn("2026-10-17T09:05:00Z"), check] }), record);
  assert.equal(record.handled.size, 0);
  const later = await decideWith(fakeApi({ checkRuns: [check, noModelTurn()] }), parseRecord(serializeRecord(record)));
  assert.deepEqual(later.result, { number: 42, workflowRunId: "38779200001" });
});

// A record the dispatcher wrote before a no-model-turn reply released the
// head holds it as handled; that record's version is read as empty.
test("a version 1 record that holds a no-model-turn head is ignored, and the head dispatches again", async () => {
  const old = parseRecord(JSON.stringify({ version: 1, handled: { "pr-unblock / address-feedback": [HEAD] }, dispatched: {} }));
  const check = roundRun("address-feedback", "failure", "Failed", "2026-10-17T10:00:00Z");
  const { result } = await decideWith(fakeApi({ checkRuns: [check, noModelTurn()] }), old);
  assert.deepEqual(result, { number: 42, workflowRunId: "38779200001" });
});

test("a limit-stopped run is not recorded", async () => {
  const record = emptyRecord();
  const stopped = failedRun("lane=pr-unblock activity=address-feedback class=rate-limit resets=2026-10-17T12:00:00Z");
  await decideWith(fakeApi({ checkRuns: [stopped] }), record);
  assert.equal(record.handled.size, 0);
});

// Three limit stops under a resolved limit-stops-per-head of 5: the newest one
// holds the head until its reset, and the head is not recorded, so after the
// reset it dispatches again.
test("three limit stops under a cap of 5 leave the head unrecorded and dispatched after the last reset", async () => {
  const stop = (resets, started) => ({
    ...failedRun(`lane=pr-unblock activity=address-feedback class=rate-limit resets=${resets}`, started),
    started_at: started,
  });
  const runs = [
    stop("2026-10-17T07:30:00Z", "2026-10-17T07:00:00Z"),
    stop("2026-10-17T08:30:00Z", "2026-10-17T08:00:00Z"),
    stop("2026-10-17T13:00:00Z", "2026-10-17T09:00:00Z"),
    noModelTurn("2026-10-17T09:05:00Z"),
  ];
  const resolved = { ...resolvedLane(), limits: { ...LIMIT_DEFAULTS, "limit-stops-per-head": 5 } };
  const at = (record, now) =>
    dispatchFeedback({
      api: fakeApi({ checkRuns: runs }),
      repository: REPOSITORY,
      runId: RUN_ID,
      upstream: upstreamRun(),
      appSenderId: APP_ID,
      resolveSlot: async () => resolved,
      log: () => {},
      record,
      now: Date.parse(now),
    });
  const record = emptyRecord();
  assert.equal(await at(record, "2026-10-17T12:00:00Z"), null, "held before the newest stop's reset");
  assert.equal(record.handled.size, 0, "a limit stop is not recorded");
  assert.equal((await at(parseRecord(serializeRecord(record)), "2026-10-17T14:00:00Z"))?.number, 42, "3 stops of a cap of 5");
});

test("a later run at a head whose dispatched run is still going skips after one read of that run", async () => {
  const record = emptyRecord();
  const first = await decideWith(fakeApi(), record);
  assert.deepEqual(first.result, { number: 42, workflowRunId: "38779200001" });
  assert.deepEqual(record.dispatched.get(HEAD), { number: 42, runId: "38779200001" });

  const going = { id: 38779200001, status: "in_progress", display_title: TITLE_42, created_at: "2026-10-17T10:05:00Z" };
  const run = { run_started_at: "2026-10-17T10:00:00Z" };
  // Without the record the same run is found in the run listing: the same skip.
  const full = counting(fakeApi({ run, workflowRuns: [going] }));
  assert.equal((await decideWith(full.api, emptyRecord())).result, null);
  assert.deepEqual(full.counts, { pullsForCommit: 1, listIssueComments: 1, listReviewThreads: 1, listWorkflowRuns: 1 });

  const later = counting({ ...fakeApi({ run, workflowRuns: [going] }), getWorkflowRun: async () => going });
  const { result, lines } = await decideWith(later.api, record);
  assert.equal(result, null);
  assert.deepEqual(later.counts, { pullsForCommit: 1, getWorkflowRun: 1 });
  assert.ok(lines.at(-1).endsWith("is not done yet (recorded)"));
});

test("a recorded run that finished, started before this review, or cannot be read takes the full path", async () => {
  const record = emptyRecord();
  record.dispatched.set(HEAD, { number: 42, runId: "38779200001" });
  const run = { run_started_at: "2026-10-17T10:00:00Z" };
  for (const getWorkflowRun of [
    async () => ({ id: 1, status: "completed", display_title: TITLE_42, created_at: "2026-10-17T10:05:00Z" }),
    async () => ({ id: 1, status: "queued", display_title: TITLE_42, created_at: "2026-10-17T09:55:00Z" }),
    async () => {
      throw new Error("GET returned 404");
    },
  ]) {
    const { result } = await decideWith({ ...fakeApi({ run }), getWorkflowRun }, record);
    assert.deepEqual(result, { number: 42, workflowRunId: "38779200001" });
  }
});

// The sweep: a completed scheduled pr-unblock-dispatch.yml run on main, and
// the open PRs into main with their heads' check runs.
const TICK = { id: 500, path: ".github/workflows/pr-unblock-dispatch.yml", event: "schedule", status: "completed", head_sha: "3".repeat(40), repository: { full_name: REPOSITORY } };
const SECOND_HEAD = "4".repeat(40);
const failedRound = roundRun("address-feedback", "failure", "Failed", "2026-10-17T10:00:00Z");
function sweepApi({ openPulls = pull(), checksAt = { [HEAD]: [failedRound, noModelTurn()] }, reviewRuns = { [HEAD]: [upstreamRun({ id: 13 })] } } = {}) {
  const api = fakeApi();
  api.listOpenPulls = async () => openPulls;
  api.pullsForCommit = async (sha) => openPulls.filter((p) => p.head.sha === sha);
  // Both review lanes marked each PR's head reviewed.
  const headOf = (number) => openPulls.find((p) => p.number === number).head.sha;
  api.listIssueComments = async (number) => [marker("claude-review", headOf(number)), marker("claude-security-review", headOf(number))];
  api.listCheckRuns = async ({ sha, checkName }) => (checksAt[sha] ?? []).filter((run) => (run.name ?? "pr-unblock / address-feedback") === checkName);
  api.listCompletedRuns = async (path, head) => (path.endsWith("pr-review-hosted.yml") ? (reviewRuns[head] ?? []) : []);
  return api;
}

async function sweepMain(t, api, tick = TICK) {
  const dir = mkdtempSync(join(tmpdir(), "pr-feedback-dispatch-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const output = join(dir, "output");
  writeFileSync(output, "");
  const lines = [];
  await main(
    {
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: REPOSITORY,
      GITHUB_RUN_ID: RUN_ID,
      GITHUB_OUTPUT: output,
      GITHUB_EVENT_PATH: eventFile(dir, tick),
      APP_SENDER_ID: String(APP_ID),
      TRUSTED_ACTORS: noActors(dir),
      DISPATCH_RECORD: join(dir, "record.json"),
    },
    { api, resolveSlot: async () => resolvedLane(), log: (line) => lines.push(line) },
  );
  return { output: readFileSync(output, "utf8"), lines };
}

test("a scheduled tick re-dispatches a head whose last round had no model turn, through its newest review run", async (t) => {
  const api = sweepApi();
  const { output } = await sweepMain(t, api);
  assert.deepEqual(api.calls.dispatch, [
    { workflow: "pr-unblock.yml", ref: "refs/heads/main", inputs: { "pr-number": "42", activity: "address-feedback", "dispatcher-run-id": RUN_ID } },
  ]);
  // The record names the review run, and the sweep keeps no dispatch record.
  assert.equal(output, "run-id=38779200001\nupstream-run-id=13\n");
});

test("the sweep leaves a head whose last round answered, one at its no-model-turn cap, one with no review run, and another author's PR", async (t) => {
  for (const [label, options] of [
    ["the last round answered", { checksAt: { [HEAD]: [noModelTurn(), roundRun("publish-feedback", "success", "Passed", "2026-10-17T11:05:00Z")] } }],
    ["no reply job ran", { checksAt: { [HEAD]: [failedRound] } }],
    ["three no-model-turn rounds", { checksAt: { [HEAD]: [failedRound, noModelTurn("2026-10-17T10:05:00Z"), noModelTurn("2026-10-17T11:05:00Z"), noModelTurn("2026-10-17T12:05:00Z")] } }],
    ["no completed review run", { reviewRuns: {} }],
    ["a person opened it", { openPulls: pull({ user: { id: KYLE.databaseId } }) }],
    ["a draft", { openPulls: pull({ draft: true }) }],
  ]) {
    const api = sweepApi(options);
    const { output } = await sweepMain(t, api);
    assert.deepEqual(api.calls.dispatch, [], label);
    assert.equal(output, "", label);
  }
  // Two no-model-turn rounds are under the cap.
  const two = sweepApi({ checksAt: { [HEAD]: [failedRound, noModelTurn("2026-10-17T10:05:00Z"), noModelTurn("2026-10-17T11:05:00Z")] } });
  await sweepMain(t, two);
  assert.equal(two.calls.dispatch.length, 1);
});

test("a tick dispatches at most one head, and moves past one dispatchFeedback skips", async (t) => {
  const second = pull({ number: 43, head: { sha: SECOND_HEAD, repo: { full_name: REPOSITORY } } })[0];
  const third = pull({ number: 44, head: { sha: "5".repeat(40), repo: { full_name: REPOSITORY } } })[0];
  const api = sweepApi({
    // PR 42 is labeled do-not-merge, so dispatchFeedback skips it.
    openPulls: [...pull({ labels: [{ name: "do-not-merge" }] }), second, third],
    checksAt: { [HEAD]: [failedRound, noModelTurn()], [SECOND_HEAD]: [failedRound, noModelTurn()], ["5".repeat(40)]: [failedRound, noModelTurn()] },
    reviewRuns: { [HEAD]: [upstreamRun({ id: 13 })], [SECOND_HEAD]: [upstreamRun({ id: 14, head_sha: SECOND_HEAD })], ["5".repeat(40)]: [upstreamRun({ id: 15, head_sha: "5".repeat(40) })] },
  });
  const { output } = await sweepMain(t, api);
  assert.deepEqual(api.calls.dispatch.map((request) => request.inputs["pr-number"]), ["43"]);
  assert.equal(output, "run-id=38779200001\nupstream-run-id=14\n");
});

test("a pr-unblock-dispatch.yml run its schedule did not start sweeps nothing", async (t) => {
  const api = sweepApi();
  api.listOpenPulls = async () => assert.fail("a push tick reads no PR");
  const { output, lines } = await sweepMain(t, api, { ...TICK, event: "push" });
  assert.equal(output, "");
  assert.match(lines.join("\n"), /not a scheduled tick/);
});

test("a PR the sweep cannot read is logged and the next PR is still swept", async (t) => {
  const second = pull({ number: 43, head: { sha: SECOND_HEAD, repo: { full_name: REPOSITORY } } })[0];
  const api = sweepApi({
    openPulls: [...pull(), second],
    checksAt: { [SECOND_HEAD]: [failedRound, noModelTurn()] },
    reviewRuns: { [SECOND_HEAD]: [upstreamRun({ id: 14, head_sha: SECOND_HEAD })] },
  });
  const read = api.listCheckRuns;
  api.listCheckRuns = async (request) => (request.sha === HEAD ? Promise.reject(new Error("GET check-runs returned 502")) : read(request));
  const { output, lines } = await sweepMain(t, api);
  assert.deepEqual(api.calls.dispatch.map((request) => request.inputs["pr-number"]), ["43"]);
  assert.equal(output, "run-id=38779200001\nupstream-run-id=14\n");
  assert.ok(lines.some((line) => line.startsWith("::warning::#42:") && line.includes("502")), lines.join("\n"));
});
