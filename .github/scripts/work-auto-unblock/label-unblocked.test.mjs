// Expected values come from issue #7599: when an issue closes, each issue it
// blocked gets `agent-ready` only when every blocker is closed, it is open,
// it carries no hold label, and the owner ratified it with the admission
// marker (the resolve-issue lane's rule, #7610). Every fact is read from the
// API when the run starts, never from the event payload. The kill switch and
// a close by the lanes App stop the run before any API call.
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { main } from "./label-unblocked.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const TRUSTED = join(HERE, "../../actions/check-trusted-trigger/fixtures/trusted-actors.json");
const API = "https://api.github.com";
const REPO = "melodic-software/claude-code-plugins";
const OWNER = { id: 153232337, login: "kyle-sexton" };
const LANES_APP_ID = 337595936;
const MARKER = "<!-- admission: admitted when unblocked, owner batch ratification 2026-10-16 -->";
const STAMP = "2026-10-16T12:00:00Z";

const issue = (number, { state = "open", labels = [], repo = REPO } = {}) => ({
  number,
  state,
  labels: labels.map((name) => ({ name })),
  repository_url: `${API}/repos/${repo}`,
});
const marker = (user = OWNER, body = MARKER) => ({ id: 9, body, user, created_at: STAMP, updated_at: STAMP });

// The closed issue #10 blocks the issues in `blocking`; `issues` is what a
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
  const dir = mkdtempSync(join(tmpdir(), "auto-unblock-"));
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
    LANES_APP_SENDER_ID: String(LANES_APP_ID),
    TRUSTED_ACTORS_PATH: TRUSTED,
    ...extra,
  };
}

const writes = (calls) => calls.filter((call) => !call.startsWith("GET "));
const labeled = (n) => `POST /repos/${REPO}/issues/${n}/labels {"labels":["agent-ready"]}`;

// #20 is blocked by #10 (now closed) and #11.
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

test("a close by the lanes App stops the run before any API call", async () => {
  const { github, calls } = oneDependent();
  const event = { sender: { id: LANES_APP_ID, login: "melodic-automation-lanes[bot]" } };
  assert.equal(await main({ env: envFor(event), github }), 0);
  assert.deepEqual(calls, []);
});

test("a missing lanes App sender id fails red before any API call", async () => {
  const { github, calls } = oneDependent();
  assert.equal(await main({ env: envFor({}, { LANES_APP_SENDER_ID: "" }), github }), 1);
  assert.deepEqual(calls, []);
});

test("labels are read fresh from the API, never from the blocking list or the payload", async () => {
  // The blocking list (and the payload) show #20 open and unlabeled; the
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

test("an event other than an issue closing changes nothing and fails red", async () => {
  const { github, calls } = oneDependent();
  assert.equal(await main({ env: envFor({ action: "reopened" }), github }), 1);
  assert.deepEqual(calls, []);
});
