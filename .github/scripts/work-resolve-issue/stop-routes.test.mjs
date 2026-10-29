// Expected values come from the owner's direction of 2026-10-27, restated
// 2026-10-29: a person only for an intent, design, security or cost reason;
// every retry has a hard end.
import assert from "node:assert/strict";
import { test } from "node:test";

import { HOLD_CLASSES, runCode, STOP_ROUTES, stopRetries, stopRoute } from "./stop-routes.mjs";

test("a reason the table does not list holds", () => {
  assert.equal(stopRoute("no-such-reason"), "hold");
});

// stop-routes.mjs's header: a person only for an intent, design, security or
// cost reason, so every hold row names which one.
test("every hold row's class is intent-change, design-change, security-risk or cost-risk", () => {
  const classes = ["intent-change", "design-change", "security-risk", "cost-risk"];
  assert.deepEqual([...HOLD_CLASSES].sort(), [...classes].sort());
  for (const [reason, row] of Object.entries(STOP_ROUTES)) {
    if (row.route === "hold") {
      assert.ok(classes.includes(row.class), `${reason} holds with class ${row.class}`);
    }
  }
});

// These stops name no owner reason, so none goes to a person.
test("a stop with no code, a done or delivered issue, a wait on a pull request and a split go to no person", () => {
  assert.equal(stopRoute("stopped"), "retry");
  assert.equal(stopRetries("stopped", 2), 1);
  assert.equal(stopRetries("outcome-unread", 2), 2);
  assert.equal(stopRoute("already-done"), "close");
  assert.equal(stopRoute("report-delivered"), "close");
  assert.equal(stopRoute("blocked-by-pr"), "wait");
  assert.equal(stopRoute("split-required"), "intake");
  for (const code of ["already-done", "report-delivered", "blocked-by-pr"]) {
    assert.equal(runCode(`${code}: why`), code);
  }
});

test("a spent cap never retries again", () => {
  for (const spent of ["retry-spent", "turn-cap-spent"]) {
    assert.equal(stopRoute(spent), "fail", spent);
  }
});

test("a run's stop reason routes by the code it opens with, and by none otherwise", () => {
  assert.equal(runCode("host-only: needs the native bundle"), "host-only");
  assert.equal(runCode("  `security-risk`: a token leaks"), "security-risk");
  assert.equal(runCode("patch-protected-path: .github/workflows/ci.yml"), "patch-protected-path");
  assert.equal(runCode("manual-external: a DNS record at the registrar"), "manual-external");
  assert.equal(runCode("The tests failed; not host-only."), "stopped");
  assert.equal(runCode("check-failed: a code no run may give"), "stopped");
  assert.equal(runCode(undefined), "stopped");
});

// Owner decision 2026-10-28: a manual external step needs the owner present,
// which is attended, not a decision (needs-human) or a host run (host-run).
test("a manual external step routes to attended, and a host-only stop to host-run", () => {
  assert.equal(stopRoute("manual-external"), "attended");
  assert.equal(stopRoute("host-only"), "host-run");
});
