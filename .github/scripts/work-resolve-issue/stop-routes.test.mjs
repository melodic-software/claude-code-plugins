// Expected values come from the owner's direction of 2026-10-27, restated
// 2026-10-29: a person only for an intent, design, security or cost reason;
// every retry has a hard end.
import assert from "node:assert/strict";
import { copyFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";

import { HOLD_CLASSES, runCode, STOP_ROUTES, stopReasonCode, stopRetries, stopRoute } from "./stop-routes.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

test("a reason the table does not list names no owner reason, so it fails, to no person", () => {
  assert.equal(stopRoute("no-such-reason"), "fail");
  assert.equal(stopReasonCode("no-such-reason"), "none");
});

test("a hold row's comment carries its class as the stop-reason code, and no other row carries a person code", () => {
  for (const [reason, row] of Object.entries(STOP_ROUTES)) {
    const code = stopReasonCode(reason);
    assert.equal(code === "none", row.route !== "hold", `${reason}: ${code}`);
  }
  assert.equal(stopReasonCode("pushback"), "intent");
  assert.equal(stopReasonCode("patch-invalid"), "security");
  assert.equal(stopReasonCode("probe-first"), "design");
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

// Security review on #10978: `stopped` retries and then fails, so a security
// code the run misformats must still reach a person.
test("a code opens the reason in any case, past emphasis, backticks and a Reason: label, with a space or hyphen between its words", () => {
  for (const reason of [
    "Security-risk: a token leaks",
    "security risk: a token leaks",
    "**security-risk**: a token leaks",
    "SECURITY-RISK the token leaks",
    "Reason: security-risk",
    "_`Reason:` **Security Risk**_: a token leaks",
  ]) {
    assert.equal(runCode(reason), "security-risk", reason);
  }
  assert.equal(runCode("Host-Only: needs the native bundle"), "host-only");
  assert.equal(runCode("blocked by pr: #5 adds the helper"), "blocked-by-pr");
});

test("a reason with no code that names an owner reason as a word holds for that reason, security first", () => {
  assert.equal(runCode("The change would print the token, a security problem."), "security-risk");
  assert.equal(runCode("It would change what the issue's intent is."), "intent-change");
  assert.equal(runCode("This needs a Design call on the module split."), "design-change");
  assert.equal(runCode("The new job would raise the cost of every run."), "cost-risk");
  assert.equal(runCode("A design question with a security side."), "security-risk");
  for (const reason of ["The change would print the token, a security problem.", "This needs a Design call."]) {
    assert.equal(stopRoute(runCode(reason)), "hold", reason);
  }
});

test("a reason that opens with another code keeps it, and one naming no owner reason stays stopped", () => {
  assert.equal(runCode("already-done: the security fix is on main"), "already-done");
  assert.equal(runCode("blocked-by-pr: #5 settles the design"), "blocked-by-pr");
  assert.equal(runCode("The tests failed twice on a flaky network read."), "stopped");
  assert.equal(runCode("The designer's costs and insecure intents"), "stopped", "only the whole word counts");
  assert.equal(runCode("Reason: the tests failed"), "stopped");
});

// The load check runs on import, so each case imports a copy of the module
// beside its own copy of the real table.
async function loadsWith(table) {
  const dir = tempDir("stop-routes-");
  try {
    copyFileSync(new URL("./stop-routes.mjs", import.meta.url), join(dir, "stop-routes.mjs"));
    writeFileSync(join(dir, "stop-routes.json"), JSON.stringify(table));
    return await import(pathToFileURL(join(dir, "stop-routes.mjs")).href);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("the table does not load when a hold row's class is not an owner reason", async () => {
  assert.ok((await loadsWith(STOP_ROUTES)).STOP_ROUTES, "the real table loads");
  await assert.rejects(loadsWith({ ...STOP_ROUTES, pushback: { ...STOP_ROUTES.pushback, class: "maintenance" } }), /pushback/);
  await assert.rejects(loadsWith({ ...STOP_ROUTES, pushback: { route: "hold", why: "no class" } }), /pushback/);
});

// Owner decision 2026-10-28: a manual external step needs the owner present,
// which is attended, not a decision (needs-human) or a host run (host-run).
test("a manual external step routes to attended, and a host-only stop to host-run", () => {
  assert.equal(stopRoute("manual-external"), "attended");
  assert.equal(stopRoute("host-only"), "host-run");
});
