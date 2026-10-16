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

import { checkCloser, main as runMain } from "./label-unblocked.mjs";

// resolve-issue's admission in docs/conventions/pr-pipeline.yaml; the
// resolve-config live-config test checks the script's reader returns it.
const ADMISSION = { classes: ["work-class: read-only", "work-class: mechanical"], ratified: true };
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

const issue = (number, { state = "open", reason = state === "closed" ? "completed" : null, labels = [], repo = REPO } = {}) => ({
  number,
  state,
  state_reason: reason,
  labels: labels.map((name) => ({ name })),
  repository_url: `${API}/repos/${repo}`,
});
const marker = (user = OWNER, body = MARKER) => ({ id: 9, body, user, created_at: STAMP, updated_at: STAMP });

// The closed blocker, number 10, blocks the issues in `blocking`; `issues` is what a
// fresh GET /issues/{n} answers, `blockedBy` and `comments` per issue number.
function world({ blocking, issues = {}, blockedBy = {}, comments = {}, failOn } = {}) {
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
    if (route === `${base}/10/dependencies/blocking`) {
      return listed(blocking);
    }
    if ((match = route.match(/\/issues\/(\d+)\/dependencies\/blocked_by$/))) {
      return listed(blockedBy[match[1]] ?? []);
    }
    if ((match = route.match(/\/issues\/(\d+)\/comments$/))) {
      return listed(comments[match[1]] ?? []);
    }
    if (method === "POST" && (match = route.match(/\/issues\/(\d+)\/labels$/))) {
      return [];
    }
    if ((match = route.match(/\/issues\/(\d+)$/)) && issues[match[1]]) {
      return issues[match[1]];
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

const writes = (calls) => calls.filter((call) => !call.startsWith("GET "));
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

test("a ratified issue with a work class resolve-issue does not admit stays unlabeled, even beside an admitted one", async () => {
  for (const labels of [["work-class: feature"], ["work-class: mechanical", "Work-Class: Feature"]]) {
    const { github, calls } = oneDependent({ labels });
    assert.equal(await main({ env: envFor(), github }), 0);
    assert.deepEqual(writes(calls), [], JSON.stringify(labels));
  }
});

test("a ratified issue with an admitted work class is labeled", async () => {
  const { github, calls } = oneDependent({ labels: ["work-class: mechanical"] });
  assert.equal(await main({ env: envFor(), github }), 0);
  assert.deepEqual(writes(calls), [labeled(20)]);
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
  const { github, calls } = oneDependent();
  assert.equal(await main({ env: envFor({ action: "reopened" }), github }), 1);
  assert.deepEqual(calls, []);
});
