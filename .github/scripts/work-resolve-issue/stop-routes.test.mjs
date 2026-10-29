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
test("the security code opens the reason in any case and width, past emphasis, backticks and a Reason: label, with any separator or none", () => {
  for (const reason of [
    "Security-risk: a token leaks",
    "security risk: a token leaks",
    "**security-risk**: a token leaks",
    "SECURITY-RISK the token leaks",
    "Reason: security-risk",
    "_`Reason:` **Security Risk**_: a token leaks",
    "SECURITY_RISK: a token leaks",
    "SecurityRisk: a token leaks",
    "\uff33ecurity-risk: a token leaks",
  ]) {
    assert.equal(runCode(reason), "security-risk", reason);
  }
});

// Re-review on #10978: a space for the hyphen made "Design change in X" a
// hold, so every other code needs its hyphenated form, then a colon, a
// backtick, closing emphasis, a space or the end.
test("every other code opens the reason in any case only in its hyphenated form", () => {
  for (const [reason, code] of [
    ["design-change: X", "design-change"],
    ["Design-Change: X", "design-change"],
    ["**design-change**: X", "design-change"],
    ["Reason: `design-change` X", "design-change"],
    ["design-change", "design-change"],
    ["Host-Only: needs the native bundle", "host-only"],
    ["Design change in X needs a call", "stopped"],
    ["design_change: X", "stopped"],
    ["design-changes are listed", "stopped"],
    ["cost risk: retrying twice", "stopped"],
    ["blocked by pr: #5 adds the helper", "stopped"],
  ]) {
    assert.equal(runCode(reason), code, reason);
  }
  assert.equal(stopRoute(runCode("design-change: X")), "hold");
});

test("a reason with no code that names security or a vulnerability, even inside a word, holds as security", () => {
  for (const reason of [
    "possible security issue in X",
    "The change would print the token, a Security problem.",
    "It opens a vulnerability in the parser.",
    "Two vulnerable reads.",
    "A non-security-reviewed path.",
    "Seen by the SecurityScanner.",
    "\uff53ecurity concern in the parser",
  ]) {
    assert.equal(runCode(reason), "security-risk", reason);
    assert.equal(stopRoute(runCode(reason)), "hold", reason);
  }
});

// Owner rule: only a real owner reason reaches a person, and plain reasons
// name intent, design and cost all the time, so only their code holds.
test("a reason with no code that names intent, design or cost stays stopped", () => {
  for (const reason of ["the test design needs X", "the cost of retrying", "The intent of the check is unclear.", "insecure-looking but fine"]) {
    assert.equal(runCode(reason), "stopped", reason);
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

// Re-review on #10978: runCode's security backstop names the security-risk
// row, and a class on a row that does not hold would read as an owner reason.
test("the table does not load without a security-risk hold row, or with a class on a row that does not hold", async () => {
  const { "security-risk": _, ...noSecurity } = STOP_ROUTES;
  await assert.rejects(loadsWith(noSecurity), /security-risk/);
  await assert.rejects(loadsWith({ ...STOP_ROUTES, "security-risk": { ...STOP_ROUTES["security-risk"], class: "design-change" } }), /security-risk/);
  await assert.rejects(loadsWith({ ...STOP_ROUTES, "security-risk": { route: "retry", why: "w", code: true } }), /security-risk/);
  await assert.rejects(loadsWith({ ...STOP_ROUTES, stopped: { ...STOP_ROUTES.stopped, class: "security-risk" } }), /stopped/);
});

// Owner decision 2026-10-28: a manual external step needs the owner present,
// which is attended, not a decision (needs-human) or a host run (host-run).
test("a manual external step routes to attended, and a host-only stop to host-run", () => {
  assert.equal(stopRoute("manual-external"), "attended");
  assert.equal(stopRoute("host-only"), "host-run");
});
