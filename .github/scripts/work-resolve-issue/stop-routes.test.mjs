// Expected values come from the owner's direction of 2026-10-27, restated
// 2026-10-29: a person only for an intent, design, security or cost reason;
// every retry has a hard end.
import assert from "node:assert/strict";
import { copyFileSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";

import { causeName, HOLD_CLASSES, runCode, securityWord, STOP_ROUTES, stopFault, stopReasonCode, stopRetries, stopRoute } from "./stop-routes.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const KNOWN_NAMES = JSON.parse(readFileSync(new URL("./known-names.json", import.meta.url), "utf8"));

// A fault says nothing about the issue: a runner, job or crash, not what the
// run wrote or decided, which a retry can repeat for a reason in the issue.
test("a stop is a fault only when the lane's machinery failed, never for what the run wrote", () => {
  for (const reason of ["outcome-unread", "issue-file", "scan-refused-fault", "patch-apply-failed"]) {
    assert.equal(stopFault(reason), true, reason);
    assert.equal(stopRoute(reason), "retry", reason);
  }
  for (const reason of ["outcome-invalid", "patch-invalid", "stopped", "done-no-commit", "check-failed", "security-risk", "no-such-reason"]) {
    assert.equal(stopFault(reason), false, reason);
  }
});

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
  assert.equal(stopReasonCode("patch-credential"), "security");
  assert.equal(stopReasonCode("patch-invalid"), "none");
  assert.equal(stopReasonCode("probe-first"), "none");
});

// Owner decision on #11021: an issue its Uncertainty skips parks at
// status: confirmed with no person, as admission parks the same refusal, and
// one its Size skips goes to intake's size split (owner Q93). A patch carrying
// a credential shape holds for the owner as a token-leak path (section 10); any
// other invalid patch retries like patch-apply-failed.
test("the dimension skips reach no person, and only a credential-shaped patch holds", () => {
  assert.equal(stopRoute("research-first"), "park");
  assert.equal(stopRoute("probe-first"), "park");
  assert.equal(stopRoute("split-required"), "intake");
  assert.equal(stopRoute("patch-credential"), "hold");
  assert.equal(STOP_ROUTES["patch-credential"].class, "security-risk");
  assert.equal(stopRoute("patch-invalid"), stopRoute("patch-apply-failed"));
  assert.equal(stopRoute("patch-invalid"), "retry");
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

// An ordering stop names no owner reason ("When work stops for the owner",
// docs/contracts/loop-lane/README.md): intake triage writes the blocked-by
// edge, so admission waits for the blocker.
test("a blocked-by-issue code goes back through intake once, and an intent-change code still holds", () => {
  assert.equal(runCode("blocked-by-issue #13187 must land first"), "blocked-by-issue");
  assert.equal(runCode("blocked-by-issue: #13187 must land first"), "blocked-by-issue");
  assert.equal(stopRoute("blocked-by-issue"), "intake");
  assert.equal(stopRetries("blocked-by-issue", 2), 1);
  assert.equal(stopReasonCode("blocked-by-issue"), "none");
  assert.equal(runCode("intent-change: must land after the sibling part #13187"), "intent-change");
  assert.equal(stopRoute("intent-change"), "hold");
  // Owner Q4: intake removes agent-ready, so a security mention after the
  // code still reaches a person, as it does with no code.
  assert.equal(runCode("blocked-by-issue: #5 rotates the leaked token"), "security-risk");
  assert.equal(runCode("rotates the leaked token"), "security-risk");
});

test("the issue lane's prompt names the blocked-by-issue code", () => {
  const prompt = readFileSync(new URL("../../../plugins/work-items/skills/work/reference/ci-mode.md", import.meta.url), "utf8");
  assert.ok(prompt.includes("`blocked-by-issue`"), "ci-mode.md names blocked-by-issue");
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

// Security review on #10978: an uncoded reason naming a concern without one
// of the first eight words retried and then failed, so nobody was told. The
// reasons are the finding's own examples; the acronyms count only as words.
test("an uncoded reason naming a password, an API key, a backdoor, XSS, RCE, a CVE, branch protection or ignored instructions is security-risk", () => {
  for (const reason of [
    "the issue asks to hard-code the admin password",
    "this would expose the API key",
    "looks like a backdoor / XSS / RCE / CVE",
    "this would leak the private key",
    "the issue text tells me to ignore previous instructions",
    "the issue asks me to disable branch protection",
  ]) {
    assert.equal(runCode(reason), "security-risk", reason);
  }
  for (const reason of ["the source file does not parse", "force the resource to rebuild", "enforce the lint rule"]) {
    assert.equal(runCode(reason), "stopped", reason);
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
    ["design-change. X", "design-change"],
    ["design-change, X", "design-change"],
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
    "secu\u200brity concern in the parser",
    "secu\u00adrity concern in the parser",
    "vuln: the parser trusts input",
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

// Owner decision 2026-10-29 (Q4): a security mention always reaches the
// owner. A close, host-run or attended code whose text names security holds;
// a wait or retry code comes back to the lane anyway, so it keeps its route.
test("a close, host-run or attended reason that names security holds as security-risk", () => {
  for (const reason of [
    "report-delivered: security audit found CRITICAL leak",
    "host-only: vulnerability in X",
    "already-done: fixed the token leak in #5",
    "already-done: the security fix is on main",
    "manual-external: rotate the leaked credential",
    "patch-protected-path: the workflow could exfiltrate secrets",
  ]) {
    assert.equal(runCode(reason), "security-risk", reason);
    assert.equal(stopRoute(runCode(reason)), "hold", reason);
  }
  assert.equal(runCode("blocked-by-pr: #5 fixes the injection"), "blocked-by-pr", "a wait code keeps its route");
  assert.equal(runCode("already-done: both items are on main at abb359be"), "already-done", "a close that names no security");
  assert.equal(runCode("host-only: needs the desktop's GPU"), "host-only", "a host-run that names no security");
});

// Owner rule: a capability limit routes to host-run or fail, never to a
// person. Run 41012431399 held #10022 as security because its host-only reason
// said "tokens" and "model credentials". After an ending code, a secret noun
// holds unless it is part of a known needs-a-credential capability phrasing.
test("an ending reason that names a secret noun as a capability keeps its route", () => {
  for (const reason of [
    "host-only: the work runs the eval suites against prepaid credit and records pass rate, tokens, advisor call rate and wall time. That needs `claude` eval runs on a host with model credentials; this lane cannot invoke `claude` or spend credit.",
    "host-only: needs an API key the lane does not hold",
    "host-only: tokens per completed task need a live run",
    "host-only: needs a host with model credentials to run the evals",
    "host-only: printer driver needs a host with credentials",
    "host-only: the lane lacks the deploy token; run on the desktop",
  ]) {
    assert.equal(runCode(reason), "host-only", reason);
    assert.equal(stopRoute(runCode(reason)), "host-run", reason);
  }
  for (const reason of [
    "host-only: the eval would print the API key",
    "host-only: a token leaks to the run output",
    "manual-external: rotate the compromised password",
    "host-only: the secret is exposed in the fixture",
    "host-only: needs credentials, and the run found a backdoor",
  ]) {
    assert.equal(runCode(reason), "security-risk", reason);
    assert.equal(stopRoute(runCode(reason)), "hold", reason);
  }
});

// A technical sense of a secret noun names no secret, so an ending reason
// keeps its route. Each reason below held as security-risk on a real stop.
test("an ending reason that names a token or credential only in a technical sense keeps its route", () => {
  for (const reason of [
    "host-only: the eval needs paid model calls on the role's subscription token",
    "host-only: shipped the bytes-per-token re-pin; the rest needs a desktop run",
    "host-only: This CI lane has no Azure credentials",
    "host-only: it needs a dequeue step with a pull-requests: write token",
    "host-only: it requires the token-spending admission and dispatch workflows",
    "host-only: the `merge` job, whose token has no `statuses: read`, cannot read it",
    "host-only: the token's permissions do not cover the workflow write",
  ]) {
    assert.equal(runCode(reason), "host-only", reason);
    assert.equal(securityWord(reason), "", reason);
  }
  // A secret value, an exposure or a credential path still holds beside a technical sense.
  for (const reason of [
    "host-only: the subscription token was pasted into the log",
    "host-only: a write token leaked in the fixture",
    "host-only: the per-token pricing note sits beside an exposed API key",
    "host-only: has no credentials, and the secret is in ~/.aws/credentials",
    "host-only: the token is ghp_ in the commit",
    "host-only: the OAuth token is in the public run log",
    "host-only: the session token sits in the issue body",
    "host-only: a write token was sent to an external URL",
    "host-only: the token has no expiry and sits in the public issue",
    "host-only: the subscription token is stored in plaintext",
    "host-only: a pull-requests: write token, now in the public log",
    "host-only: the token's permissions appear in the output with its value",
    "host-only: the write token the lane uses is in the public run log",
    "host-only: the subscription token; it is in the public run log",
    "host-only: (a write token) sits in the public issue body",
    "host-only: a write token, so anyone can read it in the public log",
    "host-only: the model token cannot expire and sits in the issue body",
    "host-only: the subscription token to use is in the issue body",
    "host-only: the write token cannot read it, and it is in the public log",
    "host-only: the public run log now holds the write token.",
    "host-only: the issue body contains the subscription token",
    "host-only: anyone reading the public issue can see the model token",
    "host-only: the public log includes the read token",
    "host-only: the output token is in the public run log",
    "host-only: the checkout input token sits in the issue body",
    "host-only: the step's output token appears in the public job log",
  ]) {
    assert.equal(runCode(reason), "security-risk", reason);
  }
});

// A large token count is a measure, not a credential: run 41380225807 held a
// host-only reason as security on the "tokens" in its count.
test("an ending reason that names a large token count keeps its route", () => {
  for (const reason of [
    "host-only: Attributing the startup gap (76,888 tokens headless vs 45,141 interactive) by source means re-running headless `claude -p` ...",
    "host-only: the startup payload is 120k tokens",
    "host-only: the startup payload is 1.5M tokens",
    "host-only: the run spent 1500000 tokens",
    "host-only: the run spent 1500000 tokens.",
    "host-only: the startup payload is 120k tokens. ",
    "manual-external: 76,888 tokens headless vs 45,141 interactive",
    "host-only: the startup footprint is 76,888 tokens headless",
  ]) {
    assert.equal(runCode(reason), reason.split(":")[0], reason);
    assert.equal(securityWord(reason), "", reason);
  }
  for (const reason of [
    "host-only: 3 tokens leaked in the log",
    "host-only: 2 tokens in the run output",
    "host-only: rotate the 1,200 tokens",
    "host-only: 76,888 tokens and the deploy key was posted",
    "host-only: 120k tokens, and the secret is in the log",
    "host-only: 1500000 tokens were uploaded to a gist",
    "host-only: 76,888 tokens; an attacker read the output",
    "host-only: needs the token to be rotated",
    "host-only: 1,500 tokens were sent to a third-party endpoint",
    "host-only: 2,048 tokens are in the public run log",
    "host-only: 2,048 tokens, now in the public run log",
    "host-only: 1,500 tokens. They were sent to a third-party endpoint",
    "host-only: 1,500 tokens.. sent to a third-party endpoint",
  ]) {
    assert.equal(runCode(reason), "security-risk", reason);
  }
});

// Security review of the capability carve-out: a reason that says where a
// secret ended up names no risk word, and must still reach a person.
test("an ending reason that names an exposed secret without a risk word holds", () => {
  const exposures = [
    "needs the API key, which a stranger now has",
    "lacks the token for good: an outsider took it",
    "requires a password for the account an attacker took over",
    "an attacker took over the maintainer account",
    "the API key is in the run log",
    "found a token committed in config.json",
    "credentials written to the artifact",
    "the secret appears in output",
    "the token was checked into the repo",
    "the api key is visible in the workflow log",
    "the secret was pushed to a public branch",
    "the token was logged by the runner",
    "the password is shown in the job summary",
    "the credentials end up in the cache",
    "the token was dumped into the debug output",
    "the api key is revealed in the URL",
    "needs a host with credentials; also the token is in the run log",
    "the run log holds the API key in plain text",
    "the job summary holds credentials",
    "Holds the TOKEN, visible to forks",
    "the fork PR job holds a token with write scope",
    "needs the token that leaked into the log",
    "requires the secret that is committed in config.json",
    "committed without the secret redacted",
    "a host with the token printed in its env",
    "the log holds tokens; needs a host",
    "tokens used in the public log are real",
    "needs the token rotated after it showed up in a screenshot",
    "requires the old password changed since a contractor saw it",
    "needs the token revoked",
    "the deploy key sits in the repo history",
    "needs the token to be rotated",
    "requires the password to be revoked",
    "needs the API key, which was shared in Slack",
    "needs the credentials for the account a contractor still has",
    "needs an API key, which was emailed to an external contractor",
    "needs the password to be changed since a contractor saw it",
    "needs the token to be revoked after the contractor left",
    "needs the reused token.",
    "needs an API key. It was emailed to a contractor.",
    "needs an API key. The run then copies it, with the rest of the state, into the job summary",
    "tokens per task, from a key shared with a contractor",
  ];
  for (const code of ["host-only", "manual-external", "already-done"]) {
    for (const exposure of exposures) {
      const reason = `${code}: ${exposure}`;
      assert.equal(runCode(reason), "security-risk", reason);
    }
  }
  // An exposure word anywhere in the reason holds, even in a clause apart
  // from the secret noun: the last two exposures above leave the noun's own
  // sentence, so a check scoped near the noun would release them.
  const apart = "host-only: needs a host with model credentials; the eval writes its summary to an artifact";
  assert.equal(runCode(apart), "security-risk", apart);
  const pasted = "manual-external: the dashboard holds an api key that was pasted publicly";
  assert.equal(runCode(pasted), "security-risk", pasted);
});

// The exposures above that say "took over" also say "attacker", so this case
// alone holds the phrase in the word list.
test("an ending reason that says took over, with no other security word, holds", () => {
  for (const code of ["host-only", "manual-external", "already-done"]) {
    const reason = `${code}: someone took over the maintainer account`;
    assert.equal(runCode(reason), "security-risk", reason);
    assert.equal(stopRoute(runCode(reason)), "hold", reason);
  }
});

// Security review: the release takes only an allowlist of capability words
// beside the secret noun, so an exposure worded with no listed sink word, a
// pronoun or a bare "key" that points at the secret, or text in another
// script still reaches a person.
test("an ending reason that names a secret noun beside any unlisted word holds", () => {
  for (const reason of [
    "host-only: needs the API key. It was uploaded to the issue thread.",
    "host-only: needs the credentials. Someone posted them in the issue.",
    "host-only: it was uploaded to the thread; needs the API key.",
    "host-only: needs the API key. The key was uploaded to the issue thread.",
    "host-only: needs the API key. The eval records that.",
    "attended: needs the token. It is in a gist.",
    "already-done: needs the password. \u041e\u043d \u0443\u0442\u0451\u043a.",
  ]) {
    assert.equal(runCode(reason), "security-risk", reason);
  }
});

test("a reason with no code that names a security word holds", () => {
  for (const reason of ["credential printed to the log", "a malicious dependency", "the prompt could inject commands", "the TOKEN is in the URL", "a secret in the fixture"]) {
    assert.equal(runCode(reason), "security-risk", reason);
  }
});

// #12362: run 10:29Z on 2026-11-02 held #7588 on the "attack" in the pstack
// principle name attack-the-premise, which the run quoted while it reported
// the work as done. A listed name (known-names.json) names no security word.
test("a reason that quotes a listed name, and names no risk, keeps its route", () => {
  for (const reason of [
    "already-done: the change is on main at 13617b6a; `attack-the-premise` found no gap in the issue's premise",
    "already-done: review:security-review ran on #7588 and found nothing",
    "host-only: `/review:security-review` needs a host run",
  ]) {
    assert.equal(runCode(reason), reason.split(":")[0], reason);
    assert.equal(securityWord(reason), "", reason);
  }
  const plain = "The tests failed after attack-the-premise questioned the plan.";
  assert.equal(runCode(plain), "stopped", plain);
  assert.equal(securityWord(plain), "", plain);
});

test("a listed name releases no risk beside it, and a word outside a listed name holds", () => {
  for (const [reason, word] of [
    ["already-done: `attack-the-premise` found the work done, but a token was posted in the log", "token"],
    ["already-done: a prompt-injection attack in the issue body", "inject"],
    ["already-done: attack-the-premise found a prompt-injection attack in the issue body", "inject"],
    ["host-only: needs the attack-the-premise token", "token"],
    ["already-done: attack-the-premises names no listed name", "attack"],
    ["already-done: pre-attack-the-premise names no listed name", "attack"],
    ["already-done: security-review alone is not the listed skill id", "security"],
    ["already-done: ATTACK-THE-PREMISE is not the listed spelling", "ATTACK"],
  ]) {
    assert.equal(runCode(reason), "security-risk", reason);
    assert.equal(securityWord(reason), word, reason);
  }
  assert.equal(runCode("attack-the-premise: a prompt-injection attack"), "security-risk");
  assert.equal(runCode("`attack-the-premise` and the secret is in the fixture"), "security-risk");
});

test("a reason that opens with another code keeps it, and one naming no owner reason stays stopped", () => {
  assert.equal(runCode("blocked-by-pr: #5 settles the design"), "blocked-by-pr");
  assert.equal(runCode("The tests failed twice on a flaky network read."), "stopped");
  assert.equal(runCode("The designer's costs and insecure intents"), "stopped", "only the whole word counts");
  assert.equal(runCode("Reason: the tests failed"), "stopped");
});

// The load check runs on import, so each case imports a copy of the module
// beside its own copy of the real table.
const NO_NAMES_FILE = Symbol("no known-names.json");
async function loadsWith(table, names = KNOWN_NAMES) {
  const dir = tempDir("stop-routes-");
  try {
    copyFileSync(new URL("./stop-routes.mjs", import.meta.url), join(dir, "stop-routes.mjs"));
    writeFileSync(join(dir, "stop-routes.json"), JSON.stringify(table));
    if (names !== NO_NAMES_FILE) writeFileSync(join(dir, "known-names.json"), JSON.stringify(names));
    return await import(pathToFileURL(join(dir, "stop-routes.mjs")).href);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("the known names do not load with a bare word, a secret noun, a capital or no why", async () => {
  assert.ok((await loadsWith(STOP_ROUTES, {})).STOP_ROUTES, "an empty list loads");
  for (const name of ["attack", "deploy-token-check", "api-key:audit", "Attack-The-Premise", "attack the premise", "attack-", "a.*-b"]) {
    await assert.rejects(loadsWith(STOP_ROUTES, { ...KNOWN_NAMES, [name]: "why" }), /known-names\.json/, name);
  }
  await assert.rejects(loadsWith(STOP_ROUTES, { "attack-the-premise": "" }), /known-names\.json/);
  for (const names of [null, ["attack-the-premise"], "attack-the-premise"]) {
    await assert.rejects(loadsWith(STOP_ROUTES, names), /known-names\.json/, JSON.stringify(names));
  }
});

// pr-require-checks' sparse checkout of the base lists this module and its
// table alone: with no names file, no name is exempt.
test("with no known-names.json every name holds", async () => {
  const { runCode: bare } = await loadsWith(STOP_ROUTES, NO_NAMES_FILE);
  assert.equal(bare("already-done: `attack-the-premise` found the work done"), "security-risk");
});

// Security review: a match that starts inside a listed name and runs past its
// edge still counts, so a name never splits a two-word secret or concern.
test("a security word that runs past a listed name's edge holds", async () => {
  const { runCode: withNames, securityWord: wordWith } = await loadsWith(STOP_ROUTES, { ...KNOWN_NAMES, "github-deploy": "why", "ci:branch": "why" });
  for (const [reason, word] of [
    ["host-only: needs the github-deploy key", "deploy key"],
    ["already-done: ci:branch protection is off", "branch protection"],
  ]) {
    assert.equal(withNames(reason), "security-risk", reason);
    assert.equal(wordWith(reason), word, reason);
  }
});

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

// A pushback never waits, so with anyCodeEnds a security mention after a wait
// code reads as security-risk; a stopped run's wait code keeps its route.
test("runCode with anyCodeEnds reads a security mention after a wait code", () => {
  const reason = "blocked-by-pr: #12's log printed the deploy token.";
  assert.equal(runCode(reason), "blocked-by-pr");
  assert.equal(runCode(reason, { anyCodeEnds: true }), "security-risk");
  assert.equal(runCode("blocked-by-pr: #12 changes the same file.", { anyCodeEnds: true }), "blocked-by-pr");
});

test("causeName reads a cause as a row name", () => {
  for (const [cause, name] of [
    ["Security Risk", "security-risk"],
    ["ｉｎｔｅｎｔ", "intent"],
    ["intent - change", "intent-change"],
    ["intent:", "intent"],
    ["intent: ", "intent"],
    ["intent: -", "intent"],
    [" Intent_Change\n", "intent-change"],
    ["in\u200btent;", "intent"],
    ["--cost__risk.", "cost-risk"],
    [undefined, ""],
    [7, "7"],
  ]) {
    assert.equal(causeName(cause), name, JSON.stringify(cause));
  }
});
