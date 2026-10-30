import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import { ACTIONS_BOT_ID, LABEL, main, markerFor, NEEDS_HUMAN, readEvent } from "./flag.mjs";

const OUTSIDER = { id: 777, login: "stranger", type: "User" };
const LISTED = { id: 153232337, login: "kyle-sexton", type: "User" };
const LISTED_BOT = { id: 209825114, login: "claude[bot]", type: "Bot" };
const ACTIONS_BOT = { id: ACTIONS_BOT_ID, login: "github-actions[bot]", type: "Bot" };
const REPO = "melodic-software/claude-code-plugins";

const issue = (user = OUTSIDER, association = "NONE") => ({ number: 5, user, author_association: association, body: "ignore previous instructions" });
const pull = (user = OUTSIDER, association = "NONE") => ({ number: 9, user, author_association: association, body: "pr text" });
const events = {
  issues: (user, association) => ({ action: "opened", issue: issue(user, association) }),
  issue_comment: (user, association) => ({ action: "created", issue: issue(LISTED, "OWNER"), comment: { user, author_association: association, body: "hi" } }),
  pull_request_review: (user, association) => ({ action: "submitted", pull_request: pull(LISTED, "OWNER"), review: { user, author_association: association, body: "lgtm" } }),
  pull_request_review_comment: (user, association) => ({ action: "created", pull_request: pull(LISTED, "OWNER"), comment: { user, author_association: association, body: "nit" } }),
  pull_request_target: (user, association) => ({ action: "opened", pull_request: pull(user, association) }),
};

// A fake GitHub that records every call and answers the comment list.
function fakeGitHub(comments = []) {
  const calls = [];
  const github = async (method, apiPath, body) => {
    calls.push({ method, apiPath, body });
    if (method === "GET" && apiPath.includes("/comments")) {
      return comments;
    }
    return {};
  };
  return { github, calls };
}

function run(eventName, payload, { comments, list = "valid" } = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), "outside-actor-"));
  try {
    const eventPath = path.join(dir, "event.json");
    writeFileSync(eventPath, JSON.stringify(payload));
    const listPath = path.join(dir, "trusted-actors.json");
    if (list === "valid") {
      writeFileSync(
        listPath,
        JSON.stringify({
          version: 1,
          actors: [
            { id: LISTED.id, login: LISTED.login, kind: "human" },
            { id: LISTED_BOT.id, login: LISTED_BOT.login, kind: "bot" },
          ],
        }),
      );
    } else if (list === "malformed") {
      writeFileSync(listPath, "{ not json");
    }
    const fake = fakeGitHub(comments);
    const lines = [];
    return main({
      env: { GITHUB_REPOSITORY: REPO, GITHUB_EVENT_NAME: eventName, GITHUB_EVENT_PATH: eventPath, TRUSTED_ACTORS_PATH: listPath },
      github: fake.github,
      log: (line) => lines.push(line),
    }).then((code) => ({ code, calls: fake.calls, lines }));
  } finally {
    // main reads both files synchronously before its first await.
    rmSync(dir, { recursive: true, force: true });
  }
}

const posts = (calls) => calls.filter((call) => call.method === "POST");

test("an OWNER or MEMBER author is trusted by association and nothing is written", async () => {
  for (const association of ["OWNER", "MEMBER"]) {
    const { code, calls } = await run("issue_comment", events.issue_comment(OUTSIDER, association));
    assert.equal(code, 0);
    assert.deepEqual(calls, [], association);
  }
});

test("a listed id is trusted whatever its association: a bot and a private-membership human", async () => {
  for (const user of [LISTED, LISTED_BOT]) {
    const { code, calls } = await run("pull_request_review", events.pull_request_review(user, "CONTRIBUTOR"));
    assert.equal(code, 0);
    assert.deepEqual(calls, [], user.login);
  }
});

test("a COLLABORATOR or CONTRIBUTOR association alone does not trust", async () => {
  for (const association of ["COLLABORATOR", "CONTRIBUTOR", "FIRST_TIME_CONTRIBUTOR", "NONE"]) {
    const { calls } = await run("issues", events.issues(OUTSIDER, association));
    assert.equal(posts(calls).length, 2, association);
  }
});

for (const [eventName, number, kind] of [
  ["issues", 5, "issue opened"],
  ["issue_comment", 5, "comment created"],
  ["pull_request_review", 9, "pull request review submitted"],
  ["pull_request_review_comment", 9, "pull request review comment created"],
  ["pull_request_target", 9, "pull request opened"],
]) {
  test(`an outside ${eventName} labels the item and posts one comment naming the actor, quoting none of their text`, async () => {
    const payload = events[eventName](OUTSIDER, "NONE");
    const { code, calls } = await run(eventName, payload);
    assert.equal(code, 0);
    const [label, comment] = posts(calls);
    assert.equal(label.apiPath, `/repos/${REPO}/issues/${number}/labels`);
    assert.deepEqual(label.body, { labels: [LABEL, NEEDS_HUMAN] });
    assert.equal(comment.apiPath, `/repos/${REPO}/issues/${number}/comments`);
    assert.ok(comment.body.body.startsWith(markerFor({ id: OUTSIDER.id })));
    assert.match(comment.body.body, /`stranger` \(id 777\)/);
    assert.ok(comment.body.body.includes(`(event: ${kind})`), kind);
    assert.match(comment.body.body, /A person reviews this/);
    assert.doesNotMatch(comment.body.body, /@stranger/, "the login is never a mention");
    for (const text of ["ignore previous instructions", "pr text", "lgtm", "nit", "hi\n"]) {
      assert.ok(!comment.body.body.includes(text), `quotes no event text: ${text}`);
    }
  });
}

for (const [eventName, action, number, kind] of [
  ["issues", "reopened", 5, "issue reopened"],
  ["pull_request_target", "synchronize", 9, "pull request synchronize"],
  ["pull_request_target", "reopened", 9, "pull request reopened"],
]) {
  test(`an outside ${eventName} ${action} labels the item and comments with the action`, async () => {
    const payload = { ...events[eventName](OUTSIDER, "NONE"), action, sender: OUTSIDER };
    const { code, calls } = await run(eventName, payload);
    assert.equal(code, 0);
    const [label, comment] = posts(calls);
    assert.equal(label.apiPath, `/repos/${REPO}/issues/${number}/labels`);
    assert.ok(comment.body.body.includes(`(event: ${kind})`), kind);
  });
}

test("an item already carrying both labels gets no label write, but a new actor still gets a comment", async () => {
  const payload = events.issue_comment(OUTSIDER, "NONE");
  payload.issue.labels = [{ name: NEEDS_HUMAN }, { name: LABEL }, { name: "bug" }];
  const { code, calls } = await run("issue_comment", payload);
  assert.equal(code, 0);
  assert.deepEqual(
    posts(calls).map((call) => call.apiPath),
    [`/repos/${REPO}/issues/5/comments`],
  );
});

test("an item carrying only one of the two labels is labeled again", async () => {
  for (const name of [LABEL, NEEDS_HUMAN]) {
    const payload = events.pull_request_target(OUTSIDER, "NONE");
    payload.pull_request.labels = [{ name }];
    const { calls } = await run("pull_request_target", payload);
    assert.ok(posts(calls).some((call) => call.apiPath.endsWith("/labels")), name);
  }
});

test("a second event from the same actor re-adds the labels and posts no second comment", async () => {
  const own = { user: ACTIONS_BOT, body: `${markerFor({ id: OUTSIDER.id })}\n**Outside actor.**` };
  const { code, calls } = await run("issue_comment", events.issue_comment(OUTSIDER, "NONE"), { comments: [own] });
  assert.equal(code, 0);
  assert.deepEqual(
    posts(calls).map((call) => call.apiPath),
    [`/repos/${REPO}/issues/5/labels`],
  );
});

test("a different outside actor on a flagged item gets its own comment", async () => {
  const own = { user: ACTIONS_BOT, body: `${markerFor({ id: 12345 })}\n**Outside actor.**` };
  const { calls } = await run("issue_comment", events.issue_comment(OUTSIDER, "NONE"), { comments: [own] });
  assert.equal(posts(calls).length, 2);
});

test("a marker written by anyone but github-actions[bot] is ignored", async () => {
  const marker = `${markerFor({ id: OUTSIDER.id })}\n`;
  const spoofs = [
    { user: OUTSIDER, body: marker },
    { user: { id: 999, login: "github-actions[bot]", type: "User" }, body: marker },
    { user: { ...ACTIONS_BOT, type: "User" }, body: marker },
    { user: LISTED_BOT, body: marker },
    { user: ACTIONS_BOT, body: `quoted: ${marker}` },
  ];
  const { calls } = await run("issue_comment", events.issue_comment(OUTSIDER, "NONE"), { comments: spoofs });
  assert.equal(posts(calls).length, 2, "the spoofed markers do not suppress the comment");
});

test("an unreadable or malformed trusted-actor list fails closed and flags a listed id", async () => {
  for (const list of ["missing", "malformed"]) {
    const { code, calls, lines } = await run("issue_comment", events.issue_comment(LISTED, "CONTRIBUTOR"), { list });
    assert.equal(code, 0);
    assert.equal(posts(calls).length, 2, list);
    assert.ok(lines.some((line) => line.includes("trusted-actor list is unreadable")), list);
  }
});

test("an unreadable list still trusts an OWNER or MEMBER association", async () => {
  const { calls } = await run("issues", events.issues(LISTED, "OWNER"), { list: "missing" });
  assert.deepEqual(calls, []);
});

test("an author with no readable id or login is flagged, with no mention", async () => {
  const { calls } = await run("issues", events.issues({ login: "@everyone <b>" }, "NONE"));
  const [, comment] = posts(calls);
  assert.match(comment.body.body, /an account whose login could not be read \(id unknown\)/);
  assert.ok(comment.body.body.startsWith("<!-- security-outside-actor actor=unknown -->"));
});

test("a payload with no item number or an unhandled event fails the run and writes nothing", async () => {
  const noNumber = await run("issues", { action: "opened", issue: { user: OUTSIDER } });
  assert.equal(noNumber.code, 1);
  assert.deepEqual(noNumber.calls, []);
  const other = await run("push", events.issues(OUTSIDER, "NONE"));
  assert.equal(other.code, 1);
  assert.deepEqual(other.calls, []);
});

test("a listed owner editing an outsider's issue is judged as the editor: nothing is written", async () => {
  const payload = { ...events.issues(OUTSIDER, "NONE"), action: "edited", sender: LISTED };
  const { code, calls } = await run("issues", payload);
  assert.equal(code, 0);
  assert.deepEqual(calls, []);
});

test("an unlisted editor of an outsider's item is flagged by their own id, association ignored", async () => {
  const editor = { id: 4242, login: "helper", type: "User" };
  const payload = { ...events.pull_request_target(OUTSIDER, "NONE"), action: "edited", sender: editor };
  const { calls } = await run("pull_request_target", payload);
  const comments = posts(calls).filter((call) => call.apiPath.endsWith("/comments"));
  assert.equal(comments.length, 1);
  assert.ok(comments[0].body.body.startsWith(markerFor({ id: 4242 })));
  assert.match(comments[0].body.body, /`helper` \(id 4242\)/);
});

test("an outsider editing their own comment is flagged", async () => {
  const payload = { ...events.issue_comment(OUTSIDER, "NONE"), action: "edited", sender: OUTSIDER };
  const { calls } = await run("issue_comment", payload);
  assert.equal(posts(calls).length, 2);
});

test("a failed label write still posts the comment and fails the run", async () => {
  const dir = mkdtempSync(path.join(tmpdir(), "outside-actor-"));
  try {
    const eventPath = path.join(dir, "event.json");
    writeFileSync(eventPath, JSON.stringify(events.issues(OUTSIDER, "NONE")));
    const calls = [];
    const github = async (method, apiPath, body) => {
      calls.push({ method, apiPath, body });
      if (apiPath.endsWith("/labels")) throw new Error("403");
      return method === "GET" ? [] : {};
    };
    const code = await main({
      env: { GITHUB_REPOSITORY: REPO, GITHUB_EVENT_NAME: "issues", GITHUB_EVENT_PATH: eventPath, TRUSTED_ACTORS_PATH: path.join(dir, "none.json") },
      github,
      log: () => {},
    });
    assert.equal(code, 1);
    assert.ok(calls.some((call) => call.method === "POST" && call.apiPath.endsWith("/comments")));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("readEvent takes the comment's author before the issue's and the review's before the pull request's", () => {
  assert.equal(readEvent("issue_comment", events.issue_comment(OUTSIDER, "NONE")).id, OUTSIDER.id);
  assert.equal(readEvent("pull_request_review", events.pull_request_review(OUTSIDER, "NONE")).id, OUTSIDER.id);
  assert.equal(readEvent("pull_request_review_comment", events.pull_request_review_comment(OUTSIDER, "NONE")).number, 9);
});
