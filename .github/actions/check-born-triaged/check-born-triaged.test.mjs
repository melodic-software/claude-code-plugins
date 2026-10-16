import assert from "node:assert/strict";
import { test } from "node:test";

import { BORN_TRIAGED_MARKER, checkBornTriaged, run } from "./check-born-triaged.mjs";

const HUMAN = { id: 153232337, login: "kyle-sexton", kind: "human" };
const LISTED_BOT = { id: 49699333, login: "dependabot[bot]", kind: "bot" };
const LANES_APP = { id: 337595936, login: "melodic-automation-lanes[bot]", kind: "bot" };
const LIST = { version: 1, actors: [HUMAN, LISTED_BOT, LANES_APP] };
const LANES_APP_ID = "337595936";

function issue({ author = HUMAN, body = `## Outcome\n\nx\n\n${BORN_TRIAGED_MARKER}\n`, type = "Feature", labels = ["needs-human"] } = {}) {
  return {
    number: 7,
    user: { id: author.id, login: author.login },
    body,
    type: type ? { name: type } : null,
    labels: labels.map((name) => ({ name })),
  };
}

const check = (overrides, list = LIST, appId = LANES_APP_ID) =>
  checkBornTriaged({ issue: issue(overrides), list, lanesAppId: appId });

test("skips a trusted human's issue that carries the marker, an Issue Type and a status label", () => {
  assert.deepEqual(check({}), { skip: "true", reason: "born-triaged" });
});

test("skips the same issue filed by the lanes App", () => {
  assert.deepEqual(check({ author: LANES_APP }), { skip: "true", reason: "born-triaged" });
});

test("accepts agent-ready and any status: label as the status label", () => {
  assert.equal(check({ labels: ["agent-ready"] }).skip, "true");
  assert.equal(check({ labels: ["area: x", "status: ready"] }).skip, "true");
});

test("triages the marker from an author not on the list", () => {
  assert.deepEqual(check({ author: { id: 1, login: "stranger" } }), { skip: "false", reason: "untrusted-author" });
});

test("triages the marker from a listed bot that is not the lanes App", () => {
  assert.deepEqual(check({ author: LISTED_BOT }), { skip: "false", reason: "untrusted-author" });
});

test("triages a stranger who copies a listed human's login", () => {
  assert.equal(check({ author: { id: 2, login: "kyle-sexton" } }).reason, "untrusted-author");
});

test("does not trust the lanes App when its id is not configured", () => {
  for (const appId of ["", null, "abc", "0"]) {
    assert.equal(check({ author: LANES_APP }, LIST, appId).reason, "untrusted-author");
  }
});

test("triages a hand-opened issue with no marker", () => {
  assert.deepEqual(check({ body: "I found a bug" }), { skip: "false", reason: "no-marker" });
  assert.deepEqual(check({ body: null }), { skip: "false", reason: "no-marker" });
});

test("triages a marked trusted issue with no Issue Type", () => {
  assert.deepEqual(check({ type: null }), { skip: "false", reason: "no-type" });
});

test("triages a marked trusted issue with no status label", () => {
  assert.deepEqual(check({ labels: ["area: x", "priority: high"] }), { skip: "false", reason: "no-status" });
});

test("triages when the trusted-actor list is unreadable or the wrong version", () => {
  assert.equal(check({}, null).reason, "list-unreadable");
  assert.equal(check({}, { version: 2, actors: [HUMAN] }).reason, "list-unreadable");
  assert.equal(check({}, { version: 1 }).reason, "list-unreadable");
});

const noSleep = async () => {};

test("run re-reads the issue while only the type or status is still missing", async () => {
  const reads = [issue({ type: null }), issue({ labels: [] }), issue({})];
  let calls = 0;
  const result = await run({
    fetchIssue: async () => reads[calls++],
    list: LIST,
    lanesAppId: LANES_APP_ID,
    sleep: noSleep,
    attempts: 5,
  });
  assert.deepEqual(result, { skip: "true", reason: "born-triaged" });
  assert.equal(calls, 3);
});

test("run gives up after its attempts and triages", async () => {
  let calls = 0;
  const result = await run({
    fetchIssue: async () => {
      calls += 1;
      return issue({ type: null });
    },
    list: LIST,
    lanesAppId: LANES_APP_ID,
    sleep: noSleep,
    attempts: 3,
  });
  assert.deepEqual(result, { skip: "false", reason: "no-type" });
  assert.equal(calls, 3);
});

test("run reads once when the marker or the author already rules a skip out", async () => {
  for (const overrides of [{ body: "x" }, { author: { id: 1, login: "stranger" } }]) {
    let calls = 0;
    await run({
      fetchIssue: async () => {
        calls += 1;
        return issue({ ...overrides, type: null });
      },
      list: LIST,
      lanesAppId: LANES_APP_ID,
      sleep: noSleep,
      attempts: 5,
    });
    assert.equal(calls, 1);
  }
});

test("run triages when the issue cannot be read", async () => {
  const result = await run({
    fetchIssue: async () => {
      throw new Error("HTTP 500");
    },
    list: LIST,
    lanesAppId: LANES_APP_ID,
    sleep: noSleep,
    attempts: 3,
  });
  assert.deepEqual(result, { skip: "false", reason: "issue-unreadable" });
});
