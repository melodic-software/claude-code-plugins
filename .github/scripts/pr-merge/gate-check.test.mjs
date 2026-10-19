// Expected values come from the owner decision on #8451: one neutral
// `pr-merge / gate` check run per candidate head, titled with the top
// refusal, rewritten only when the refusal or head changes, so an unchanged
// sweep writes nothing; read from one listing, never one call per candidate.
// The main ruleset requires only `ci-status`, so no write may carry that name.
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import { main } from "./gate-check.mjs";

const REPO = "melodic-software/claude-code-plugins";
const sha = (c) => c.repeat(40);
const NOW = new Date("2026-10-19T12:00:00Z");

const row = (pr, head, fields = {}) => ({ pr, head, exit: 10, ready: false, enqueued: false, merged: false, reportOnly: false, reason: null, blockers: [], ...fields });
const suite = (...runs) => ({ checkRuns: { nodes: runs } });
const checkRun = (databaseId, title, conclusion = "NEUTRAL", name = "pr-merge / gate") => ({ databaseId, name, title, conclusion });
const listed = (...suites) => ({ checkSuites: { totalCount: suites.length, nodes: suites } });

// `checks` maps a head to its commit node in the GraphQL answer.
function world(rows, checks = {}, { readFails = false } = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), "gate-check-"));
  const summary = path.join(dir, "pr-merge-summary.json");
  writeFileSync(summary, JSON.stringify(rows));
  const calls = [];
  const github = async (method, apiPath, body) => {
    calls.push({ method, path: apiPath, body });
    if (method === "POST" && apiPath === "/graphql") {
      if (readFails) throw new Error("POST /graphql failed: 502");
      const heads = [...body.query.matchAll(/h(\d+):object\(oid:"([0-9a-f]{40})"\)/g)];
      return { data: { repository: Object.fromEntries(heads.map(([, i, head]) => [`h${i}`, checks[head] ?? listed()])) } };
    }
    return {};
  };
  const env = { GITHUB_REPOSITORY: REPO, SUMMARY_PATH: summary, GITHUB_RUN_ID: "42" };
  return {
    calls,
    writes: () => calls.filter((call) => call.path !== "/graphql"),
    run: async () => {
      const original = console.log;
      console.log = () => {};
      try {
        return await main({ env, github, now: () => NOW });
      } finally {
        console.log = original;
      }
    },
  };
}

test("a refused candidate with no check at its head gets one neutral check titled with the refusal", async () => {
  const w = world([row(7, sha("a"), { reason: "verify:fail", blockers: ["unattended merge refused: verify:fail"] })]);
  assert.equal(await w.run(), 0);
  const [write] = w.writes();
  assert.equal(w.writes().length, 1);
  assert.equal(write.method, "POST");
  assert.equal(write.path, `/repos/${REPO}/check-runs`);
  assert.equal(write.body.name, "pr-merge / gate");
  assert.equal(write.body.head_sha, sha("a"));
  assert.equal(write.body.status, "completed");
  assert.equal(write.body.conclusion, "neutral");
  assert.equal(write.body.output.title, "verify:fail");
  assert.match(write.body.output.summary, /\nunattended merge refused: verify:fail\n/);
  assert.equal(write.body.details_url, `https://github.com/${REPO}/actions/runs/42`);
});

test("an unchanged refusal writes nothing", async () => {
  const w = world([row(7, sha("a"), { reason: "risk:MED" })], { [sha("a")]: listed(suite(checkRun(5, "risk:MED"))) });
  assert.equal(await w.run(), 0);
  assert.deepEqual(w.writes(), []);
});

test("a changed refusal rewrites the head's check in place", async () => {
  const w = world([row(7, sha("a"), { reason: "verify:earlier-fail" })], {
    [sha("a")]: listed(suite(checkRun(5, "verify:fail")), suite(checkRun(9, "risk:MED"))),
  });
  await w.run();
  const [write] = w.writes();
  assert.equal(w.writes().length, 1);
  assert.equal(write.method, "PATCH");
  assert.equal(write.path, `/repos/${REPO}/check-runs/9`);
  assert.equal(write.body.output.title, "verify:earlier-fail");
  assert.equal(write.body.name, "pr-merge / gate");
});

test("every candidate is read in one listing", async () => {
  const w = world([row(1, sha("a"), { reason: "x" }), row(2, sha("b"), { reason: "y" }), row(3, sha("c"), { reason: "z" })]);
  await w.run();
  assert.equal(w.calls.filter((call) => call.path === "/graphql").length, 1);
  assert.equal(w.writes().length, 3);
});

test("with no reason the title is the first blocker, on one line with no backticks", async () => {
  const w = world([row(7, sha("a"), { blockers: ["failing checks: `test`\nlint", "pending checks: x"] })]);
  await w.run();
  assert.equal(w.writes()[0].body.output.title, "failing checks:  test  lint");
});

test("an enqueued candidate turns a refusal on show into success, and adds no check where none is", async () => {
  const shown = world([row(7, sha("a"), { ready: true, enqueued: true })], { [sha("a")]: listed(suite(checkRun(5, "risk:MED"))) });
  await shown.run();
  const [write] = shown.writes();
  assert.equal(write.method, "PATCH");
  assert.equal(write.body.conclusion, "success");
  const none = world([row(7, sha("a"), { ready: true, merged: true })]);
  await none.run();
  assert.deepEqual(none.writes(), []);
});

test("a row the gate did not judge in this run is left as it is", async () => {
  const w = world([{ ...row(7, sha("a"), { reason: "risk:MED" }), carried: true }]);
  await w.run();
  assert.deepEqual(w.calls, []);
});

test("a check run by another name is never rewritten", async () => {
  const w = world([row(7, sha("a"), { reason: "risk:MED" })], { [sha("a")]: listed(suite(checkRun(5, "All good", "SUCCESS", "ci-status"))) });
  await w.run();
  const [write] = w.writes();
  assert.equal(write.method, "POST");
  assert.equal(write.body.name, "pr-merge / gate");
});

test("a head whose listing may be cut gets a new check, not a guessed one", async () => {
  const w = world([row(7, sha("a"), { reason: "risk:MED" })], {
    [sha("a")]: { checkSuites: { totalCount: 11, nodes: [suite(checkRun(5, "risk:HIGH"))] } },
  });
  await w.run();
  assert.equal(w.writes()[0].method, "POST");
});

test("a failed read writes nothing and fails the step", async () => {
  const w = world([row(7, sha("a"), { reason: "risk:MED" })], {}, { readFails: true });
  assert.equal(await w.run(), 1);
  assert.deepEqual(w.writes(), []);
});
