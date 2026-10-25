import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { BORN_TRIAGED_MARKER, checkBornTriaged, humanIds, run } from "./check-born-triaged.mjs";

const SCRIPT = fileURLToPath(new URL("./check-born-triaged.mjs", import.meta.url));

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

test("triages a marker that is not the body's last line", () => {
  assert.deepEqual(check({ body: `> quoted ${BORN_TRIAGED_MARKER}\n\nmore text` }), { skip: "false", reason: "no-marker" });
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

test("checkBornTriaged does not match an author with no id against a list entry with no id", () => {
  const list = { version: 1, actors: [{ login: "x", kind: "human" }] };
  assert.equal(check({ author: { login: "x" } }, list).reason, "untrusted-author");
});

function runCli(env) {
  const dir = mkdtempSync(path.join(tmpdir(), "born-triaged-"));
  try {
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    const result = spawnSync(process.execPath, [SCRIPT], {
      env: { PATH: process.env.PATH, GITHUB_OUTPUT: outputPath, ...env },
      encoding: "utf8",
    });
    const outputs = Object.fromEntries(
      [...readFileSync(outputPath, "utf8").matchAll(/^([\w-]+)<<(\S+)\n([^\n]*)\n\2$/gm)].map((m) => [m[1], m[3]]),
    );
    return { status: result.status, outputs };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("CLI triages a non-numeric issue number and exits 0", () => {
  const { status, outputs } = runCli({ ISSUE_NUMBER: "7; echo", TRUSTED_ACTORS_PATH: "/nonexistent" });
  assert.equal(status, 0);
  assert.deepEqual(outputs, { skip: "false", reason: "issue-unreadable", "human-ids": "", "rate-limited": "false" });
});

test("CLI triages an unreadable trusted-actor list and exits 0", () => {
  const { status, outputs } = runCli({
    ISSUE_NUMBER: "7",
    TRUSTED_ACTORS_PATH: "/nonexistent",
    GITHUB_API_URL: "http://127.0.0.1:9",
  });
  assert.equal(status, 0);
  assert.deepEqual(outputs, { skip: "false", reason: "list-unreadable", "human-ids": "", "rate-limited": "false" });
});

test("CLI emits the listed human ids even when the issue is unreadable", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "born-triaged-list-"));
  try {
    const listPath = path.join(dir, "trusted-actors.json");
    writeFileSync(listPath, JSON.stringify(LIST));
    const { status, outputs } = runCli({
      ISSUE_NUMBER: "7",
      TRUSTED_ACTORS_PATH: listPath,
      GITHUB_API_URL: "http://127.0.0.1:9",
    });
    assert.equal(status, 0);
    assert.deepEqual(outputs, { skip: "false", reason: "issue-unreadable", "human-ids": "153232337", "rate-limited": "false" });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// A rate-guard stop the job already holds: no request, rate-limited=true for
// the callers to stop their API jobs on, and the step still exits 0.
test("CLI reports rate-limited=true and sends nothing while the job's rate guard holds a stop", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "born-triaged-stop-"));
  try {
    const listPath = path.join(dir, "trusted-actors.json");
    writeFileSync(listPath, JSON.stringify(LIST));
    mkdirSync(path.join(dir, "api-budget"));
    writeFileSync(path.join(dir, "api-budget", "stop"), `core ${Math.floor(Date.now() / 1000) + 3600}\n`);
    const { status, outputs } = runCli({
      ISSUE_NUMBER: "7",
      TRUSTED_ACTORS_PATH: listPath,
      GITHUB_API_URL: "http://127.0.0.1:9",
      RUNNER_TEMP: dir,
    });
    assert.equal(status, 0);
    assert.deepEqual(outputs, { skip: "false", reason: "issue-unreadable", "human-ids": "153232337", "rate-limited": "true" });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("humanIds lists only the human actors' ids", () => {
  const second = { id: 42, login: "other", kind: "human" };
  assert.equal(humanIds({ version: 1, actors: [HUMAN, LISTED_BOT, LANES_APP, second] }), "153232337,42");
  assert.equal(humanIds({ version: 1, actors: [LISTED_BOT] }), "");
  assert.equal(humanIds({ version: 1, actors: [{ id: "153232337", login: "x", kind: "human" }, { id: 0, login: "y", kind: "human" }] }), "");
  assert.equal(humanIds(null), "");
  assert.equal(humanIds({ version: 2, actors: [HUMAN] }), "", "a wrong-version list yields no ids");
});
