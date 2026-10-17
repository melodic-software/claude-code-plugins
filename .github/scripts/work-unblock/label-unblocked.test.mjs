// Expected values come from the work-unblock lane's rules: when an issue
// closes, each issue it blocked gets `agent-ready` only when every blocker is
// closed as completed, it is open, it carries no hold label, the owner
// ratified it with the admission marker, and it carries no work class
// resolve-issue refuses (the resolve-issue lane's admission). Every fact is
// read from the API when the run starts, never from the event payload. The kill switch and
// a close by any bot sender stop the run before any API call.
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { checkCloser, escalationComment, main as runMain } from "./label-unblocked.mjs";

// resolve-issue's admission in docs/conventions/pr-pipeline.yaml; the
// resolve-config live-config test checks the script's reader returns it.
const ADMISSION = { ratified: true };
const main = (args) => runMain({ admission: ADMISSION, ...args });

const HERE = dirname(fileURLToPath(import.meta.url));
const TRUSTED = join(HERE, "fixtures/trusted-actors.json");
const API = "https://api.github.com";
const REPO = "melodic-software/claude-code-plugins";
const OWNER = { id: 153232337, login: "kyle-sexton" };
const SECOND = { id: 2001, login: "second-maintainer" };
const LANES_APP_ID = 337595936;
const MARKER = "<!-- admission: admitted when unblocked, owner batch ratification 2026-10-16 -->";
const STAMP = "2026-10-16T12:00:00Z";

const CLOSED = "2026-10-16T11:30:00Z";
const issue = (
  number,
  {
    state = "open",
    reason = state === "closed" ? "completed" : null,
    labels = [],
    repo = REPO,
    closer = state === "closed" ? OWNER : null,
    at = state === "closed" ? CLOSED : null,
    graphCloser = null,
  } = {},
) => ({
  number,
  state,
  state_reason: reason,
  labels: labels.map((name) => ({ name })),
  repository_url: `${API}/repos/${repo}`,
  closed_by: closer,
  closed_at: at,
  graphCloser,
});
// A fixture's `graphCloser` is the `closer` of the issue's last ClosedEvent
// as GraphQL answers it. For an issue closed when an App merged a pull
// request, it is that pull request: { __typename: "PullRequest", merged:
// true, repository: { nameWithOwner: "melodic-software/claude-code-plugins" } }.
// A plain close has none.
const mergedPr = ({ repo = REPO, number = 900, merged = true } = {}) => ({
  __typename: "PullRequest",
  number,
  merged,
  repository: { nameWithOwner: repo },
});
const commitClose = ({ repo = REPO } = {}) => ({ __typename: "Commit", oid: "a".repeat(40), repository: { nameWithOwner: repo } });
const marker = (user = OWNER, body = MARKER) => ({ id: 9, body, user, created_at: STAMP, updated_at: STAMP });

// The closed blocker, number 10, blocks the issues in `blocking`; `issues` is what a
// fresh GET /issues/{n} answers, `blockedBy` and `comments` per issue number.
// `closedList` is what the sweep's closed-issue listing answers; `blockingOf`
// gives the blocking list of closed issues other than number 10.
// `openReady` is what the sweep's open agent-ready listing answers.
function world({ blocking, blockingOf = {}, closedList = [], openReady = [], issues = {}, blockedBy = {}, comments = {}, events = {}, failOn } = {}) {
  const calls = [];
  const base = `/repos/${REPO}/issues`;
  const github = async (method, path, body) => {
    calls.push(body === undefined ? `${method} ${path}` : `${method} ${path} ${JSON.stringify(body)}`);
    if (failOn && path.startsWith(failOn)) {
      throw new Error(`${method} ${path} failed with status 500`);
    }
    const route = path.replace(/\?.*$/, "");
    const page = Number(new URL(path, "https://x").searchParams.get("page") ?? "1");
    const listed = (items) => (page === 1 ? items : []);
    let match;
    if (route === base && method === "GET") {
      return listed(new URL(path, "https://x").searchParams.get("state") === "open" ? openReady : closedList);
    }
    if (route === `${base}/10/dependencies/blocking`) {
      return listed(blocking);
    }
    if ((match = route.match(/\/issues\/(\d+)\/dependencies\/blocking$/))) {
      return listed(blockingOf[match[1]] ?? []);
    }
    if ((match = route.match(/\/issues\/(\d+)\/dependencies\/blocked_by$/))) {
      return listed(blockedBy[match[1]] ?? []);
    }
    if ((match = route.match(/\/issues\/(\d+)\/comments$/))) {
      return listed(comments[match[1]] ?? []);
    }
    if ((match = route.match(/\/issues\/(\d+)\/events$/))) {
      return listed(events[match[1]] ?? []);
    }
    if (method === "POST" && (match = route.match(/\/issues\/(\d+)\/labels$/))) {
      return [];
    }
    if (method === "DELETE" && route.match(/\/issues\/(\d+)\/labels\/agent-ready$/)) {
      return [];
    }
    const lookup = (number) =>
      issues[number] ??
      closedList.find((item) => String(item.number) === number) ??
      Object.values(blockedBy)
        .flat()
        .find((item) => String(item.number) === number && item.repository_url === `${API}/repos/${REPO}`);
    // The closer read: the last ClosedEvent of one issue in this repository.
    if (method === "POST" && route === "/graphql") {
      const { owner, name, number } = body.variables;
      assert.equal(`${owner}/${name}`, REPO);
      const found = lookup(String(number));
      const nodes = found?.state === "closed" ? [{ closer: found.graphCloser }] : [];
      return { data: { repository: { issue: { timelineItems: { nodes } } } } };
    }
    if ((match = route.match(/\/issues\/(\d+)$/)) && lookup(match[1])) {
      return lookup(match[1]);
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { github, calls };
}

function envFor(event = {}, extra = {}) {
  const dir = mkdtempSync(join(tmpdir(), "work-unblock-"));
  const eventPath = join(dir, "event.json");
  writeFileSync(
    eventPath,
    JSON.stringify({ action: "closed", issue: issue(10, { state: "closed" }), sender: OWNER, ...event }),
  );
  return {
    GITHUB_REPOSITORY: REPO,
    GITHUB_EVENT_NAME: "issues",
    GITHUB_EVENT_PATH: eventPath,
    KILL_SWITCH: "proceed",
    TRUSTED_ACTORS_PATH: TRUSTED,
    ACTOR_ID: String(OWNER.id),
    TRIGGERING_ACTOR: OWNER.login,
    ...extra,
  };
}

// The GraphQL closer read is a POST but writes nothing.
const writes = (calls) => calls.filter((call) => !call.startsWith("GET ") && !call.startsWith("POST /graphql "));
const closerReads = (calls, number) =>
  calls.filter((call) => call.startsWith("POST /graphql ") && call.includes(`"number":${number}`)).length;
const labeled = (n) => `POST /repos/${REPO}/issues/${n}/labels {"labels":["agent-ready"]}`;

// Number 20 is blocked by number 10 (now closed) and number 11.
function oneDependent({ sibling = "closed", labels = [], comments = [marker()], state = "open" } = {}) {
  return world({
    blocking: [issue(20, { state, labels })],
    issues: { 20: issue(20, { state, labels }) },
    blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: sibling })] },
    comments: { 20: comments },
  });
}

test("a closed blocker with one open sibling blocker adds nothing", async () => {
  const { github, calls } = oneDependent({ sibling: "open" });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("the last blocker closing adds agent-ready", async () => {
  const { github, calls } = oneDependent();
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
});

test("an issue held by needs-owner-decision, status: needs-decision or needs-human stays unlabeled", async () => {
  for (const hold of ["needs-owner-decision", "status: needs-decision", "needs-human"]) {
    const { github, calls } = oneDependent({ labels: [hold] });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [], hold);
  }
});

test("a hold or agent-ready label in another casing still counts", async () => {
  for (const label of ["Needs-Human", "Agent-Ready"]) {
    const { github, calls } = oneDependent({ labels: [label] });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [], label);
  }
});

test("a blocker closed as not planned or duplicate still blocks", async () => {
  for (const reason of ["not_planned", "duplicate"]) {
    const { github, calls } = world({
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed", reason })] },
      comments: { 20: [marker()] },
    });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [], reason);
  }
});

test("a pull request blocker counts once merged, and not when closed unmerged", async () => {
  const pull = (merged_at) => ({
    ...issue(15, { state: "closed", reason: null }),
    pull_request: { url: `${API}/repos/${REPO}/pulls/15`, merged_at },
  });
  for (const [mergedAt, expected] of [["2026-10-16T12:00:00Z", [labeled(20)]], [null, []]]) {
    const { github, calls } = world({
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed" }), pull(mergedAt)] },
      comments: { 20: [marker()] },
    });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), expected, String(mergedAt));
  }
});

// The live admission reads no work-class label: the marker alone admits.
test("a ratified issue is labeled whatever its work-class label", async () => {
  for (const labels of [["work-class: mechanical"], ["work-class: scoped"], ["Work-Class: Structural"]]) {
    const { github, calls } = oneDependent({ labels });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [labeled(20)], JSON.stringify(labels));
  }
});

test("under an admission with classes, a ratified issue with another class stays unlabeled", async () => {
  const admission = { classes: ["work-class: read-only", "work-class: mechanical"], ratified: true };
  for (const labels of [["work-class: feature"], ["work-class: mechanical", "Work-Class: Feature"]]) {
    const { github, calls } = oneDependent({ labels });
    assert.equal(await runMain({ admission, env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(labels));
  }
});

test("an admitted work class without the marker stays unlabeled", async () => {
  const { github, calls } = oneDependent({ labels: ["work-class: read-only"], comments: [] });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("an issue with no admission marker stays unlabeled", async () => {
  const { github, calls } = oneDependent({ comments: [] });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("a marker that does not ratify (another author, the lanes App, an App post, an edit) adds nothing", async () => {
  const lanesApp = { id: LANES_APP_ID, login: "melodic-automation-lanes[bot]" };
  for (const comment of [
    marker({ id: 1234, login: "someone-else" }),
    marker(lanesApp),
    { ...marker(), performed_via_github_app: { id: 1 } },
    { ...marker(), updated_at: "2026-10-16T12:05:00Z" },
    marker(OWNER, `> ${MARKER}`),
  ]) {
    const { github, calls } = oneDependent({ comments: [comment] });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(comment));
  }
});

test("an issue already agent-ready, or closed, is left alone", async () => {
  for (const options of [{ labels: ["agent-ready"] }, { state: "closed" }]) {
    const { github, calls } = oneDependent(options);
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(options));
  }
});

test("the kill switch set stops the run before any API call", async () => {
  for (const value of ["", "false", "stop"]) {
    const { github, calls } = oneDependent();
    assert.equal(await main({ env: envFor({}, { KILL_SWITCH: value }), github }), 0);
    assert.deepEqual(calls, [], value);
  }
});

test("a close by any bot (the lanes App, a PR merge by a bot) is a clean skip before any API call", async () => {
  for (const sender of [
    { id: LANES_APP_ID, login: "melodic-automation-lanes[bot]", type: "Bot" },
    { id: 41898282, login: "github-actions[bot]", type: "Bot" },
  ]) {
    const { github, calls } = oneDependent();
    assert.equal(await main({ env: envFor({ sender }), github }), 0);
    assert.deepEqual(calls, [], sender.login);
  }
});

test("a close by a human sender proceeds", async () => {
  const { github, calls } = oneDependent();
  assert.equal(await main({ env: envFor({ sender: { ...OWNER, type: "User" } }), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
});

test("labels are read fresh from the API, never from the blocking list or the payload", async () => {
  // The blocking list (and the payload) show number 20 open and unlabeled; the
  // issue read at run time shows a hold added since.
  const { github, calls } = world({
    blocking: [issue(20)],
    issues: { 20: issue(20, { labels: ["needs-human"] }) },
    blockedBy: { 20: [issue(10, { state: "closed" })] },
    comments: { 20: [marker()] },
  });
  const event = { issue: { ...issue(10, { state: "closed" }), labels: [], blocking: [issue(20)] } };
  assert.equal(await main({ env: envFor(event), github }), 0);
  assert.deepEqual(writes(calls), []);
  assert.ok(calls.includes(`GET /repos/${REPO}/issues/20`));
});

test("blockers are read fresh: a payload that says closed does not outweigh a reopened blocker", async () => {
  const { github, calls } = world({
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "open" })] },
    comments: { 20: [marker()] },
  });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("only the issues every blocker of which is closed are labeled, and other repositories are skipped", async () => {
  const { github, calls } = world({
    blocking: [issue(20), issue(21), issue(22, { repo: "melodic-software/other" })],
    issues: { 20: issue(20), 21: issue(21) },
    blockedBy: {
      20: [issue(10, { state: "closed" })],
      21: [issue(10, { state: "closed" }), issue(5, { state: "open", repo: "melodic-software/other" })],
    },
    comments: { 20: [marker()], 21: [marker()] },
  });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
  assert.ok(!calls.some((call) => call.includes("/issues/22")));
});

test("a failed read on one issue still lets the others through, and fails the run", async () => {
  const { github, calls } = world({
    blocking: [issue(20), issue(21)],
    issues: { 20: issue(20), 21: issue(21) },
    blockedBy: { 21: [issue(10, { state: "closed" })] },
    comments: { 21: [marker()] },
    failOn: `/repos/${REPO}/issues/20/dependencies/blocked_by`,
  });
  assert.equal(await main({ env: envFor(), github }), 1);
  assert.deepEqual(writes(calls), [labeled(21)]);
});

// The broker mints only when the closer and any re-runner are each a listed
// human, so anyone else stops the run quietly, before any API call (and, in
// the workflow, before the token request, through --check-closer).
test("a closer or re-runner who is not a listed human stops the run before any API call", async () => {
  for (const [id, login] of [
    // An unlisted closer, re-run by nobody else.
    ["1234", "someone-else"],
    // An unlisted closer, re-run by a listed human.
    ["1234", OWNER.login],
    // A listed bot is not a listed human, as closer or as re-runner.
    [String(LANES_APP_ID), "melodic-automation-lanes[bot]"],
    [String(OWNER.id), "melodic-automation-lanes[bot]"],
    // An unlisted re-runner.
    [String(OWNER.id), "someone-else"],
    ["", ""],
    [String(OWNER.id), ""],
  ]) {
    const { github, calls } = oneDependent();
    assert.equal(await main({ env: envFor({}, { ACTOR_ID: id, TRIGGERING_ACTOR: login }), github }), 0);
    assert.deepEqual(calls, [], `${id} ${login}`);
  }
});

test("a re-run by a different listed human labels the unblocked issues", async () => {
  const { github, calls } = oneDependent();
  assert.equal(await main({ env: envFor({}, { ACTOR_ID: String(OWNER.id), TRIGGERING_ACTOR: SECOND.login }), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
});

test("the closer check answers proceed only when the closer and the re-runner are each a listed human", () => {
  const check = (id, login) => checkCloser({ ACTOR_ID: id, TRIGGERING_ACTOR: login, TRUSTED_ACTORS_PATH: TRUSTED });
  assert.equal(check(String(OWNER.id), OWNER.login), true);
  assert.equal(check(String(OWNER.id), "Kyle-Sexton"), true);
  assert.equal(check(String(OWNER.id), SECOND.login), true);
  assert.equal(check(String(SECOND.id), "Kyle-Sexton"), true);
  assert.equal(check("1234", "someone-else"), false);
  assert.equal(check("1234", OWNER.login), false);
  assert.equal(check(String(LANES_APP_ID), "melodic-automation-lanes[bot]"), false);
  assert.equal(check(String(OWNER.id), "claude[bot]"), false);
  assert.equal(check(String(OWNER.id), "someone-else"), false);
  assert.equal(check(String(OWNER.id), ""), false);
  assert.equal(check("x", OWNER.login), false);
});

test("a pull request in the blocking list is skipped", async () => {
  const pull = { ...issue(30), pull_request: { url: `${API}/repos/${REPO}/pulls/30` } };
  const { github, calls } = world({
    blocking: [pull],
    issues: { 30: pull },
    blockedBy: { 30: [issue(10, { state: "closed" })] },
    comments: { 30: [marker()] },
  });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), []);
  assert.ok(!calls.some((call) => call.includes("/issues/30")));
});

test("an event other than an issue closing changes nothing and fails red", async () => {
  for (const [event, name] of [[{ action: "reopened" }, "issues"], [{}, "workflow_dispatch"]]) {
    const { github, calls } = oneDependent();
    assert.equal(await main({ env: envFor(event, { GITHUB_EVENT_NAME: name }), github }), 1, name);
    assert.deepEqual(calls, [], name);
  }
});

// The hourly sweep: an issue a bot closed (a PR merge) starts no close run, so
// a scheduled run lists the issues closed in the last LOOKBACK_HOURS (3) and
// runs the close path's rules on each one. A scheduled run has no closer: its
// actor is whoever last changed the schedule, often a bot, so it is not checked.
const NOW = Date.parse("2026-10-16T12:00:00Z");
const SINCE = "2026-10-16T09:00:00.000Z";
const LANES_BOT = { id: LANES_APP_ID, login: "melodic-automation-lanes[bot]", type: "Bot" };
// A swept close; by default the lanes App merged a pull request that closed it.
const closedAt = (number, at, closer = LANES_BOT, graphCloser = mergedPr({ number: 900 + number })) =>
  issue(number, { state: "closed", at, closer, graphCloser });
const sweep = (args, extra = {}) =>
  main({
    now: NOW,
    env: envFor({ schedule: "47 * * * *" }, {
      GITHUB_EVENT_NAME: "schedule",
      ACTOR_ID: String(LANES_APP_ID),
      TRIGGERING_ACTOR: LANES_BOT.login,
      ...extra,
    }),
    ...args,
  });

function sweptDependent({ sibling = "closed" } = {}) {
  return world({
    closedList: [closedAt(10, "2026-10-16T11:30:00Z")],
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: sibling })] },
    comments: { 20: [marker()] },
  });
}

test("the sweep labels an issue whose last blocker a bot closed", async () => {
  const { github, calls } = sweptDependent();
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
  assert.ok(
    calls.includes(
      `GET /repos/${REPO}/issues?state=closed&since=${encodeURIComponent(SINCE)}&sort=updated&direction=desc&per_page=100&page=1`,
    ),
  );
});

test("the sweep skips an issue with an open sibling blocker", async () => {
  const { github, calls } = sweptDependent({ sibling: "open" });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("the kill switch stops the sweep before any API call", async () => {
  for (const value of ["", "false", "stop"]) {
    const { github, calls } = sweptDependent();
    assert.equal(await sweep({ github }, { KILL_SWITCH: value }), 0);
    assert.deepEqual(calls, [], value);
  }
});

test("the sweep does not read a closed issue outside the window, or a pull request", async () => {
  const pull = { ...closedAt(13, "2026-10-16T11:00:00Z"), pull_request: { url: `${API}/repos/${REPO}/pulls/13` } };
  const { github, calls } = world({
    // The second close was updated in the window but closed four hours ago.
    closedList: [closedAt(10, "2026-10-16T11:30:00Z"), closedAt(12, "2026-10-16T08:00:00Z"), pull],
    blocking: [issue(20)],
    blockingOf: { 12: [issue(21)], 13: [issue(21)] },
    issues: { 20: issue(20), 21: issue(21) },
    blockedBy: { 20: [issue(10, { state: "closed" })], 21: [issue(12, { state: "closed" })] },
    comments: { 20: [marker()], 21: [marker()] },
  });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
  assert.ok(!calls.some((call) => /\/issues\/(12|13|21)\b/.test(call)));
});

test("the sweep reads an issue blocked by two swept closes once", async () => {
  const { github, calls } = world({
    closedList: [closedAt(10, "2026-10-16T11:30:00Z"), closedAt(11, "2026-10-16T10:00:00Z")],
    blocking: [issue(20)],
    blockingOf: { 11: [issue(20)] },
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: "closed" })] },
    comments: { 20: [marker()] },
  });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
  assert.equal(calls.filter((call) => call === `GET /repos/${REPO}/issues/20`).length, 1);
  // Each close is judged once per run, as a swept source and as a blocker.
  for (const closed of [10, 11]) {
    assert.equal(closerReads(calls, closed), 1, closed);
  }
});

// The close path acts only on a close by a listed human; the sweep keeps that
// and adds closes by a merged pull request. An outside author who closes their
// own blocking issue starts nothing.
test("the sweep acts on a close by a listed human or a merged pull request, never by anyone else", async () => {
  for (const [closer, graphCloser, expected] of [
    [{ ...OWNER, type: "User" }, null, [labeled(20)]],
    [LANES_BOT, mergedPr({ number: 910 }), [labeled(20)]],
    [{ id: 1234, login: "someone-else", type: "User" }, null, []],
    [null, null, []],
  ]) {
    const { github, calls } = world({
      closedList: [closedAt(10, CLOSED, closer, graphCloser)],
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed" })] },
      comments: { 20: [marker()] },
    });
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), expected, JSON.stringify(closer));
    // An untrusted close is dropped before its dependents are even listed.
    const listedDependents = calls.some((call) => call.startsWith(`GET /repos/${REPO}/issues/10/dependencies/blocking`));
    assert.equal(listedDependents, expected.length > 0, JSON.stringify(closer));
  }
});

// Removing agent-ready by hand stops the lane: no later run, close or sweep,
// puts it back. A person adds it again to restart.
test("an issue whose agent-ready label was removed is not labeled again", async () => {
  const removed = [{ event: "unlabeled", label: { name: "Agent-Ready" }, actor: OWNER }];
  for (const run of [(github) => main({ env: envFor(), github }), (github) => sweep({ github })]) {
    const { github, calls } = world({
      closedList: [closedAt(10, "2026-10-16T11:30:00Z")],
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed" })] },
      comments: { 20: [marker()] },
      events: { 20: removed },
    });
    assert.equal(await run(github), 0);
    assert.deepEqual(writes(calls), []);
  }
});

test("a removed label of another name does not stop the label", async () => {
  const { github, calls } = world({
    closedList: [closedAt(10, "2026-10-16T11:30:00Z")],
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" })] },
    comments: { 20: [marker()] },
    events: { 20: [{ event: "unlabeled", label: { name: "needs-human" } }, { event: "labeled", label: { name: "agent-ready" } }] },
  });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
});

test("a failed read of one swept close still lets the others through, and fails the run", async () => {
  const { github, calls } = world({
    closedList: [closedAt(10, "2026-10-16T11:30:00Z"), closedAt(11, "2026-10-16T10:00:00Z")],
    blocking: [issue(20)],
    blockingOf: { 11: [issue(21)] },
    issues: { 20: issue(20), 21: issue(21) },
    blockedBy: { 21: [issue(11, { state: "closed" })] },
    comments: { 21: [marker()] },
    failOn: `/repos/${REPO}/issues/10/dependencies/blocking`,
  });
  assert.equal(await sweep({ github }), 1);
  assert.deepEqual(writes(calls), [labeled(21)]);
});

// One rule for every blocker, on both paths: a blocking issue counts as done
// only when it was closed as completed by a listed human or a merge, read fresh
// per blocker. An outside author closing their own blocking issue never counts.
test("a sibling blocker closed by an unlisted user keeps the issue unlabeled, on both paths", async () => {
  for (const [name, run] of [
    ["close", (github) => main({ env: envFor(), github })],
    ["sweep", (github) => sweep({ github })],
  ]) {
    for (const closer of [{ id: 1234, login: "someone-else", type: "User" }, null]) {
      const { github, calls } = world({
        closedList: [closedAt(10, "2026-10-16T11:30:00Z")],
        blocking: [issue(20)],
        issues: { 20: issue(20) },
        blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: "closed", closer })] },
        comments: { 20: [marker()] },
      });
      assert.equal(await run(github), 0);
      assert.deepEqual(writes(calls), [], `${name} ${JSON.stringify(closer)}`);
      assert.ok(calls.includes(`GET /repos/${REPO}/issues/11`), name);
    }
  }
});

test("a sibling blocker closed by a listed human counts", async () => {
  const { github, calls } = world({
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: "closed", closer: { ...SECOND, type: "User" } })] },
    comments: { 20: [marker()] },
  });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
});

// A bot close counts only when GraphQL names a merged pull request or a commit
// in this repository as the closer; a GITHUB_TOKEN close from any workflow
// (github-actions[bot]) or an App close with no merge does not.
const siblingClosed = (closer, graphCloser) =>
  world({
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: "closed", closer, graphCloser })] },
    comments: { 20: [marker()] },
  });
const ACTIONS_BOT = { id: 41898282, login: "github-actions[bot]", type: "Bot" };
const MAINTAINER = { id: 3003, login: "unlisted-maintainer", type: "User" };

test("a bot close with no merged-PR evidence does not count, as a sibling or as a swept close", async () => {
  for (const closer of [LANES_BOT, ACTIONS_BOT]) {
    const sibling = siblingClosed(closer, null);
    assert.equal(await main({ env: envFor(), github: sibling.github }), 0);
    assert.deepEqual(writes(sibling.calls), [], `sibling ${closer.login}`);
    const swept = world({
      closedList: [closedAt(10, CLOSED, closer, null)],
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed" })] },
      comments: { 20: [marker()] },
    });
    assert.equal(await sweep({ github: swept.github }), 0);
    assert.deepEqual(writes(swept.calls), [], `swept ${closer.login}`);
  }
});

test("a close by a merged pull request or a commit counts, whoever merged it", async () => {
  for (const [closer, graphCloser] of [
    [LANES_BOT, mergedPr()],
    [{ id: 206951365, login: "cursor[bot]", type: "Bot" }, mergedPr({ number: 6191 })],
    [MAINTAINER, mergedPr()],
    [{ id: 49699333, login: "dependabot[bot]", type: "Bot" }, mergedPr({ repo: REPO.toUpperCase() })],
    [MAINTAINER, commitClose()],
  ]) {
    const { github, calls } = siblingClosed(closer, graphCloser);
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [labeled(20)], `${closer.login} ${JSON.stringify(graphCloser)}`);
  }
});

test("a closer that is an unmerged PR, or a PR or commit in another repository, does not count", async () => {
  for (const graphCloser of [
    mergedPr({ merged: false }),
    mergedPr({ repo: "melodic-software/other" }),
    commitClose({ repo: "melodic-software/other" }),
    { __typename: "PullRequest", number: 900 },
    { __typename: "Issue", number: 900 },
  ]) {
    const { github, calls } = siblingClosed(LANES_BOT, graphCloser);
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(graphCloser));
  }
});

test("the closer is read fresh: a blocked-by entry naming a listed closer does not outweigh the issue itself", async () => {
  const { github, calls } = world({
    blocking: [issue(20)],
    issues: { 20: issue(20), 11: issue(11, { state: "closed", closer: { id: 1234, login: "someone-else", type: "User" } }) },
    blockedBy: { 20: [issue(10, { state: "closed" }), issue(11, { state: "closed" })] },
    comments: { 20: [marker()] },
  });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("a blocker in another repository, closed, does not count", async () => {
  const { github, calls } = world({
    blocking: [issue(20)],
    issues: { 20: issue(20) },
    blockedBy: { 20: [issue(10, { state: "closed" }), issue(5, { state: "closed", repo: "melodic-software/other" })] },
    comments: { 20: [marker()] },
  });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), []);
});

// Restarts after a limit stop (FINAL-DESIGN C4): the sweep restarts an open
// agent-ready issue whose newest lanes-App marker is outcome=limited once its
// reset has passed (a marker with no reset: five hours after it was posted),
// when no agent-ready label was added since the stop, no hold label is on it,
// and it is ratified and admitted. The restart is the App removing and adding
// agent-ready, at most five issues per run, the longest-waiting first.
const limitedNote = (resets, at, user = LANES_BOT) => ({
  id: 30,
  body: `<!-- work-resolve-issue outcome=limited${resets ? ` resets=${resets}` : ""} run=7 -->\nStopped on the usage limit.`,
  user,
  created_at: at,
});
const ready = (n, labels = []) => issue(n, { labels: ["agent-ready", "work-class: read-only", ...labels] });
const added = (at, actor = LANES_BOT) => ({ event: "labeled", label: { name: "agent-ready" }, actor, created_at: at });
const restarted = (n) => [`DELETE /repos/${REPO}/issues/${n}/labels/agent-ready`, labeled(n)];
function stopped({ resets = "2026-10-16T11:00:00Z", at = "2026-10-16T06:00:00Z", labels = [], comments, events } = {}) {
  return world({
    openReady: [ready(30, labels)],
    comments: { 30: comments ?? [marker(), limitedNote(resets, at)] },
    events: { 30: events ?? [added("2026-10-16T05:00:00Z")] },
  });
}

test("a limit-stopped issue past its reset is restarted by removing and adding agent-ready", async () => {
  const { github, calls } = stopped();
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), restarted(30));
});

test("a limit-stopped issue before its reset waits", async () => {
  const { github, calls } = stopped({ resets: "2026-10-16T13:00:00Z" });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("a limit stop with no reset waits five hours from its marker", async () => {
  const early = stopped({ resets: "", at: "2026-10-16T06:00:00Z" });
  assert.equal(await sweep({ github: early.github }), 0);
  assert.deepEqual(writes(early.calls), restarted(30));
  const late = stopped({ resets: "", at: "2026-10-16T08:00:00Z" });
  assert.equal(await sweep({ github: late.github }), 0);
  assert.deepEqual(writes(late.calls), []);
});

test("agent-ready added after the stop means a run started since, so no restart", async () => {
  const { github, calls } = stopped({ events: [added("2026-10-16T05:00:00Z"), added("2026-10-16T11:30:00Z", OWNER)] });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("only the newest lanes-App marker counts, and only the App's", async () => {
  const later = { ...limitedNote("", "2026-10-16T07:00:00Z"), body: "<!-- work-resolve-issue outcome=stopped -->" };
  for (const comments of [
    [marker(), limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z"), later],
    [marker(), limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z", OWNER)],
  ]) {
    const { github, calls } = stopped({ comments });
    assert.equal(await sweep({ github }), 0);
    assert.deepEqual(writes(calls), []);
  }
});

// Hand-back markers name their run, so a reuse check can match a branch to
// its report; the run id must not change how the restart reads them.
test("a hand-back marker naming its run, newer than the limit stop, still stops the restart", async () => {
  const later = { ...limitedNote("", "2026-10-16T07:00:00Z"), body: "<!-- work-resolve-issue outcome=stopped run=9 -->" };
  const { github, calls } = stopped({ comments: [marker(), limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z"), later] });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), []);
});

// A run that skipped the model for earlier work posts no marker; the App's own
// agent-ready after the stop still means a run started since.
test("agent-ready the App added after the stop, by a run that left no marker, means no second restart", async () => {
  const { github, calls } = stopped({ events: [added("2026-10-16T05:00:00Z"), added("2026-10-16T11:30:00Z")] });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), []);
});

test("a held or unratified limit-stopped issue is not restarted", async () => {
  for (const world of [stopped({ labels: ["needs-human"] }), stopped({ comments: [limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z")] })]) {
    assert.equal(await sweep({ github: world.github }), 0);
    assert.deepEqual(writes(world.calls), []);
  }
});

test("a run restarts at most five issues, the longest-waiting first", async () => {
  const numbers = [31, 32, 33, 34, 35, 36];
  const { github, calls } = world({
    openReady: numbers.map((n) => ready(n)),
    // Number 31's limit reset last, so it is the one left for the next run.
    comments: Object.fromEntries(
      numbers.map((n) => [n, [marker(), limitedNote(`2026-10-16T${n === 31 ? "11" : String(n - 30).padStart(2, "0")}:00:00Z`, "2026-10-16T00:30:00Z")]]),
    ),
    events: Object.fromEntries(numbers.map((n) => [n, [added("2026-10-16T00:00:00Z")]])),
  });
  assert.equal(await sweep({ github }), 0);
  assert.deepEqual(writes(calls), [32, 33, 34, 35, 36].flatMap(restarted));
});

// A removal of agent-ready is a restart only when the App made it, the App's
// newest marker before it is `limited`, and the next agent-ready event is the
// App adding it back. A person's removal, a removal before the stop, one never
// added back, or one after a later pushback stops the lane for good.
test("only the App's remove-and-re-add right after a limit stop is a restart; any other removal stops unblocking", async () => {
  const unlabeled = (actor, at) => ({ event: "unlabeled", label: { name: "agent-ready" }, actor, created_at: at });
  const limited = limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z");
  const pushback = { id: 31, body: "<!-- work-resolve-issue outcome=pushback run=8 -->\nUnclear.", user: LANES_BOT, created_at: "2026-10-16T08:00:00Z" };
  for (const [name, notes, events, expected] of [
    ["restart", [limited], [unlabeled(LANES_BOT, "2026-10-16T07:00:00Z"), added("2026-10-16T07:00:01Z")], [labeled(20)]],
    ["never added back", [limited], [unlabeled(LANES_BOT, "2026-10-16T07:00:00Z")], []],
    ["added back by a person", [limited], [unlabeled(LANES_BOT, "2026-10-16T07:00:00Z"), added("2026-10-16T07:00:01Z", OWNER)], []],
    ["before the stop", [limited], [unlabeled(LANES_BOT, "2026-10-16T05:00:00Z"), added("2026-10-16T05:00:01Z")], []],
    ["by a person", [limited], [unlabeled(OWNER, "2026-10-16T07:00:00Z"), added("2026-10-16T07:00:01Z")], []],
    [
      "pushback after a restart",
      [limited, pushback],
      [unlabeled(LANES_BOT, "2026-10-16T07:00:00Z"), added("2026-10-16T07:00:01Z"), unlabeled(LANES_BOT, "2026-10-16T08:00:05Z")],
      [],
    ],
  ]) {
    const { github, calls } = world({
      blocking: [issue(20)],
      issues: { 20: issue(20) },
      blockedBy: { 20: [issue(10, { state: "closed" })] },
      comments: { 20: [marker(), ...notes] },
      events: { 20: events },
    });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), expected, name);
  }
});

test("a stated reset in the past still waits an hour from the stop", async () => {
  const early = stopped({ resets: "2026-10-16T09:00:00Z", at: "2026-10-16T11:30:00Z" });
  assert.equal(await sweep({ github: early.github }), 0);
  assert.deepEqual(writes(early.calls), []);
  const late = stopped({ resets: "2026-10-16T09:00:00Z", at: "2026-10-16T10:30:00Z" });
  assert.equal(await sweep({ github: late.github }), 0);
  assert.deepEqual(writes(late.calls), restarted(30));
});

// Three limit stops since a person last added agent-ready hand the issue to a
// person: needs-human and a comment, no restart.
test("a third limit stop since a person added agent-ready adds needs-human with a comment instead of restarting", async () => {
  const stops = [
    limitedNote("2026-10-16T01:00:00Z", "2026-10-16T00:30:00Z"),
    limitedNote("2026-10-16T03:00:00Z", "2026-10-16T02:30:00Z"),
    limitedNote("2026-10-16T11:00:00Z", "2026-10-16T06:00:00Z"),
  ];
  const third = stopped({ comments: [marker(), ...stops] });
  assert.equal(await sweep({ github: third.github }), 0);
  const written = writes(third.calls);
  assert.equal(written.length, 2);
  assert.ok(written[0].startsWith(`POST /repos/${REPO}/issues/30/comments `), written[0]);
  assert.ok(written[0].includes("<!-- work-unblock escalated -->"), written[0]);
  assert.deepEqual(written.slice(1), [`POST /repos/${REPO}/issues/30/labels {"labels":["needs-human"]}`]);
  // The comment went out but the label did not: the next sweep adds only the
  // label. The App's explanation from before a person's re-add does not count.
  const explanation = (at) => ({ id: 40, body: escalationComment(3), user: LANES_BOT, created_at: at });
  const retry = stopped({ comments: [marker(), ...stops, explanation("2026-10-16T06:30:00Z")] });
  assert.equal(await sweep({ github: retry.github }), 0);
  assert.deepEqual(writes(retry.calls), [`POST /repos/${REPO}/issues/30/labels {"labels":["needs-human"]}`]);
  const stale = stopped({
    comments: [marker(), explanation("2026-10-15T23:00:00Z"), ...stops],
    events: [added("2026-10-15T22:00:00Z", OWNER), added("2026-10-15T23:30:00Z", OWNER)],
  });
  assert.equal(await sweep({ github: stale.github }), 0);
  assert.equal(writes(stale.calls).length, 2);
  // A person adding agent-ready after the first stop starts the count again.
  const reset = stopped({ comments: [marker(), ...stops], events: [added("2026-10-16T00:00:00Z"), added("2026-10-16T01:00:00Z", OWNER)] });
  assert.equal(await sweep({ github: reset.github }), 0);
  assert.deepEqual(writes(reset.calls), restarted(30));
});

// After the DELETE, a failed re-add is tried once more; a second failure is an
// ::error naming the issue and fails the run.
test("a failed re-add after the removal is retried once, then reported", async (t) => {
  for (const [failures, code] of [[1, 0], [2, 1]]) {
    const { github: base, calls } = stopped();
    let left = failures;
    const github = async (method, path, body) => {
      if (method === "POST" && path.endsWith("/issues/30/labels") && left > 0) {
        left -= 1;
        calls.push(`${method} ${path} ${JSON.stringify(body)}`);
        throw new Error("POST failed with status 502");
      }
      return base(method, path, body);
    };
    const log = t.mock.method(console, "log", () => {});
    assert.equal(await sweep({ github }), code, `${failures} failures`);
    assert.deepEqual(writes(calls), [...restarted(30), labeled(30)], `${failures} failures`);
    const errors = log.mock.calls.map((call) => String(call.arguments[0])).filter((line) => line.startsWith("::error"));
    assert.equal(errors.length, code, `${failures} failures`);
    if (code) {
      assert.match(errors[0], /#30: agent-ready was removed for a restart but not added back/);
    }
    log.mock.restore();
  }
});

test("a failed listing of closed issues writes nothing and fails the run", async () => {
  const { github, calls } = world({ closedList: [closedAt(10, "2026-10-16T11:30:00Z")], failOn: `/repos/${REPO}/issues?` });
  assert.equal(await sweep({ github }), 1);
  assert.deepEqual(writes(calls), []);
});
