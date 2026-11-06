import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { parseHold } from "../maintenance-monitor-signals/signals.mjs";
import { envPrefix, passOutcome, passRecords } from "./log-pass-records.mjs";

const OK = { "fix-docs-head": "success", "fix-docs": "success", "fix-docs-fallback": "skipped", "apply-docs-patch": "success" };

test("a pass that pushed, found nothing, or lost its head reports that outcome", () => {
  assert.deepEqual(passOutcome({ results: OK, pushedCommit: "a".repeat(40) }), { outcome: "pushed", reason: null });
  assert.deepEqual(passOutcome({ results: { ...OK, "apply-docs-patch": "skipped" } }), { outcome: "none", reason: null });
  assert.deepEqual(passOutcome({ results: OK, skipReason: "superseded-sha" }), { outcome: "superseded", reason: null });
  assert.deepEqual(passOutcome({ results: OK, skipReason: "awaiting-human" }), { outcome: "none", reason: null });
});

test("a failed or cancelled job fails the pass, named by job and result; a pass with no jobs is unwired", () => {
  assert.deepEqual(passOutcome({ results: { ...OK, "fix-docs": "failure" }, pushedCommit: "" }), { outcome: "failed", reason: "fix-docs-failure" });
  assert.deepEqual(passOutcome({ results: { ...OK, "apply-docs-patch": "cancelled" } }), { outcome: "failed", reason: "apply-docs-patch-cancelled" });
  assert.deepEqual(passOutcome({ results: null }), { outcome: "failed", reason: "unwired" });
});

test("each planned pass emits one record, and a failed one also a refine-failed warning", () => {
  const wiring = (pass) => (pass === "fix-docs" ? { results: OK, pushedCommit: "b".repeat(40) } : { results: { "lint-code": "failure" } });
  assert.deepEqual(passRecords({ passes: ["fix-docs", "lint-code"], files: { "fix-docs": 3, "lint-code": 1 }, seconds: 42, wiring }), [
    "::notice title=refine-pass::pass=fix-docs files=3 outcome=pushed seconds=42",
    "::notice title=refine-pass::pass=lint-code files=1 outcome=failed seconds=42",
    "::warning title=refine-failed::pass=lint-code reason=lint-code-failure",
  ]);
  assert.deepEqual(passRecords({ passes: [], files: {}, seconds: 1, wiring }), []);
});

test("a failed plan logs refine-failed for pass=plan, which signal 13 counts", () => {
  const lines = passRecords({ planResult: "failure", passes: [], files: {}, seconds: 0, wiring: () => ({ results: {} }) });
  assert.deepEqual(lines, ["::warning title=refine-failed::pass=plan reason=plan-failure"]);
  const [, title, message] = /^::warning title=([^:]+)::(.*)$/.exec(lines[0]);
  assert.deepEqual(parseHold(title, message, "warning"), { item: null, reason: "plan failed: plan-failure" });
});

// The warning's title and message are what signal 13 parses.
test("the refine-failed warning parses as a pr-refine hold at warning level only", () => {
  const [, warning] = passRecords({ passes: ["fix-docs"], files: {}, seconds: 0, wiring: () => ({ results: { "fix-docs": "failure" } }) });
  const [, title, message] = /^::warning title=([^:]+)::(.*)$/.exec(warning);
  assert.deepEqual(parseHold(title, message, "warning"), { item: null, reason: "fix-docs failed: fix-docs-failure" });
  assert.equal(parseHold(title, message, "notice"), null);
});

test("the script reads each pass's wiring from its env prefix", () => {
  assert.equal(envPrefix("fix-docs"), "FIX_DOCS");
  const run = spawnSync(process.execPath, [fileURLToPath(new URL("./log-pass-records.mjs", import.meta.url))], {
    env: {
      PATH: process.env.PATH,
      PASSES: '["fix-docs","lint-code"]',
      FILES: '{"fix-docs":2}',
      STARTED_AT: String(Math.round(Date.now() / 1000)),
      FIX_DOCS_RESULTS: JSON.stringify(OK),
      FIX_DOCS_PUSHED: "",
      FIX_DOCS_SKIP: "superseded-sha",
    },
    encoding: "utf8",
  });
  assert.equal(run.status, 0, run.stderr);
  assert.match(run.stdout, /^::notice title=refine-pass::pass=fix-docs files=2 outcome=superseded seconds=\d+$/m);
  assert.match(run.stdout, /^::notice title=refine-pass::pass=lint-code files=0 outcome=failed seconds=\d+$/m);
  assert.match(run.stdout, /^::warning title=refine-failed::pass=lint-code reason=unwired$/m);
});
