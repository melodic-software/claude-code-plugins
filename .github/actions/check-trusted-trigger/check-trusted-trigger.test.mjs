import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, beforeEach, test } from "node:test";
import { fileURLToPath } from "node:url";

import { readOutputs } from "../check-kill-switch/fixtures/read-outputs.mjs";
import { createGitHub, GitHubError, loadTrustedActors, main } from "./check-trusted-trigger.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES = path.join(HERE, "fixtures");
const SCRIPT = path.join(HERE, "check-trusted-trigger.mjs");
const REPOSITORY = "melodic-software/claude-code-plugins";
const LIST = path.join(FIXTURES, "trusted-actors.json");
const HEAD_SHA = "1111111111111111111111111111111111111111";
const BASE_SHA = "2222222222222222222222222222222222222222";
const STRANGER = { login: "stranger", id: 9999001, type: "User" };

const fixture = (name) => JSON.parse(readFileSync(path.join(FIXTURES, name), "utf8"));

function fakeGitHub(routes) {
  const calls = [];
  const github = async (method, apiPath) => {
    calls.push(`${method} ${apiPath}`);
    const key = `${method} ${apiPath}`;
    if (!(key in routes)) {
      throw new GitHubError(404, key);
    }
    return structuredClone(routes[key]);
  };
  github.calls = calls;
  return github;
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
}) {
  const outputPath = writeJson("output", "");
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
    },
    github,
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
  assert.deepEqual(github.calls, [`GET /repos/${REPOSITORY}/pulls/42`]);
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

test("triggering-actor: a listed re-runner proceeds, matched without case", async () => {
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

test("untrusted-rerunner: an empty re-runner login stops instead of skipping the check", async () => {
  assert.deepEqual(
    await gate({
      eventName: "pull_request",
      event: fixture("event-pull-request.json"),
      triggeringActor: "",
    }),
    STOPPED("untrusted-rerunner"),
  );
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

test("createGitHub raises on a GraphQL response that carries errors", async () => {
  const fetchImpl = async () =>
    new Response(JSON.stringify({ data: null, errors: [{ message: "nope" }] }), { status: 200 });
  const github = createGitHub({ token: "t", apiUrl: "https://api.example", fetchImpl });
  await assert.rejects(github("POST", "/graphql", { query: "{}" }), GitHubError);
});
