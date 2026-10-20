// Expected values come from the owner's decision for this check: one neutral
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
const checkRun = (databaseId, title, conclusion = "NEUTRAL", name = "pr-merge / gate", externalId = "pr-merge-gate") => ({ databaseId, name, title, conclusion, externalId });
const listed = (...suites) => ({ checkSuites: { totalCount: suites.length, nodes: suites } });

// `checks` maps a head to its commit node in the GraphQL answer.
function world(rows, checks = {}, { readFails = false } = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), "gate-check-"));
  const summary = path.join(dir, "pr-merge-summary.json");
  writeFileSync(summary, JSON.stringify(rows));
  const calls = [];
  const logs = [];
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
    logs,
    writes: () => calls.filter((call) => call.path !== "/graphql"),
    run: async () => {
      const original = console.log;
      console.log = (line) => logs.push(String(line));
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

test("a head whose listing may be cut is left as it is, so no sweep adds a duplicate", async () => {
  const w = world([row(7, sha("a"), { reason: "risk:MED" })], {
    [sha("a")]: { checkSuites: { totalCount: 51, nodes: [suite(checkRun(5, "risk:HIGH"))] } },
  });
  assert.equal(await w.run(), 0);
  assert.deepEqual(w.writes(), []);
  assert.ok(w.logs.includes("gate-check: sweep: 0 written, 0 unchanged, 0 skipped, 1 unread, 0 failed"));
});

test("a failed read writes nothing and fails the step", async () => {
  const w = world([row(7, sha("a"), { reason: "risk:MED" })], {}, { readFails: true });
  assert.equal(await w.run(), 1);
  assert.deepEqual(w.writes(), []);
});

// Markdown outside a code span or fence, where a link or image would render.
const rendered = (summary) => summary.replaceAll(/```text\n[\s\S]*?\n```/g, "").replaceAll(/`[^`\n]*`/g, "");

test("refusal text cannot render as a link or image in the summary", async () => {
  const reason = "see [x](http://e) ![i](http://e)";
  const w = world([row(7, sha("a"), { reason, blockers: [reason] })]);
  await w.run();
  const { summary } = w.writes()[0].body.output;
  assert.ok(summary.includes("[x](http://e)"));
  assert.doesNotMatch(rendered(summary), /\]\(/);
});

test("a same-named check run this script did not create is never rewritten", async () => {
  const w = world([row(7, sha("a"), { reason: "risk:MED" })], {
    [sha("a")]: listed(suite(checkRun(9, "risk:HIGH", "NEUTRAL", "pr-merge / gate", null))),
  });
  await w.run();
  const [write] = w.writes();
  assert.equal(write.method, "POST");
  assert.equal(write.body.external_id, "pr-merge-gate");
  assert.match(w.calls[0].body.query, /externalId/);
});

test("each sweep logs one line with its written and unchanged counts", async () => {
  const w = world([row(1, sha("a"), { reason: "x" }), row(2, sha("b"), { reason: "risk:MED" })], {
    [sha("b")]: listed(suite(checkRun(5, "risk:MED"))),
  });
  await w.run();
  assert.equal(w.logs.filter((line) => line.startsWith("gate-check: sweep")).length, 1);
  assert.ok(w.logs.includes("gate-check: sweep: 1 written, 1 unchanged, 0 skipped, 0 unread, 0 failed"));
});

test("candidates past one read's chunk are read again and matched to their own heads", async () => {
  const heads = Array.from({ length: 51 }, (_, i) => i.toString(16).padStart(40, "0"));
  const last = heads[50];
  const w = world(
    heads.map((head, i) => row(i + 1, head, { reason: "risk:MED" })),
    Object.fromEntries(heads.map((head) => [head, listed(suite(checkRun(5, "risk:MED")))]).concat([[last, listed(suite(checkRun(77, "verify:fail")))]])),
  );
  await w.run();
  assert.equal(w.calls.filter((call) => call.path === "/graphql").length, 2);
  assert.deepEqual(w.writes().map((call) => [call.method, call.path]), [["PATCH", `/repos/${REPO}/check-runs/77`]]);
});

test("the same title with another conclusion is rewritten", async () => {
  const w = world([row(7, sha("a"), { reason: "risk:MED" })], { [sha("a")]: listed(suite(checkRun(5, "risk:MED", "SUCCESS"))) });
  await w.run();
  assert.equal(w.writes()[0].method, "PATCH");
  assert.equal(w.writes()[0].body.conclusion, "neutral");
});

test("a ready candidate not enqueued is titled with the gate's reason when it gives one", async () => {
  const w = world([row(7, sha("a"), { ready: true, reason: "merge-queue entry armed, not yet queued" }), row(8, sha("b"), { ready: true })]);
  await w.run();
  assert.deepEqual(w.writes().map((call) => call.body.output.title), ["merge-queue entry armed, not yet queued", "ready, not enqueued this run"]);
});
