// Expected values come from the owner's direction of 2026-10-27: a person
// only for an intent, design, security or cost reason; every retry has a
// hard end.
import assert from "node:assert/strict";
import { test } from "node:test";

import { runCode, STOP_ROUTES, stopRoute } from "./stop-routes.mjs";

test("a reason the table does not list holds", () => {
  assert.equal(stopRoute("no-such-reason"), "hold");
});

test("only intent, design, security and cost reasons, and reasons the lane cannot tell from them, hold", () => {
  const holds = Object.keys(STOP_ROUTES).filter((reason) => STOP_ROUTES[reason].route === "hold").sort();
  assert.deepEqual(holds, [
    "collect-refused",
    "cost-risk",
    "design-change",
    "intent-change",
    "issue-edited",
    "patch-invalid",
    "probe-first",
    "pushback",
    "research-first",
    "scan-refused-output",
    "security-risk",
    "split-required",
    "stopped",
  ]);
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
