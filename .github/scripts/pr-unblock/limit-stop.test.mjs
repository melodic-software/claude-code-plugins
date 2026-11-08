import assert from "node:assert/strict";
import { test } from "node:test";

import { anyHandles, cappedAt, HEAD_LAG_STOP, headLagStop, KILL_SWITCH_STOP, killSwitchStop, limitResetsAt, pendingStop, permanentlyHandles, releasedBy, releasesHead, stopRelease } from "./limit-stop.mjs";

const HOUR = 3_600_000;
const ENDED = "2026-10-17T10:00:00Z";
const ended = Date.parse(ENDED);
const run = (id = 1) => ({ id, status: "completed", conclusion: "failure", completed_at: ENDED, output: { title: "x" } });
// The lane-outcome record report-check-run writes into output.text of a posted
// check run named `<lane> / <activity>`, built by hand from
// docs/lane-outcome.md's rate-limit example plus the hub's activity; `fields`
// override it.
const RECORD = {
  v: 1,
  lane: "pr-unblock",
  activity: "resolve-conflicts",
  outcome: "failure",
  credential: { secret: "CLAUDE_CODE_OAUTH_TOKEN", kind: "oauth-token" },
};
const posted = (fields, extra = {}) => ({
  ...run(),
  name: "pr-unblock / resolve-conflicts",
  output: {
    title: "Failed",
    summary: "The activity step failed.",
    text: `lane-outcome ${JSON.stringify({ ...RECORD, ...fields })} trailing free text }`,
  },
  ...extra,
});
const resets = (at) => ({ resets: { at, window: "five_hour" } });
const LIMIT = { class: "rate-limit" };
const LIMIT_LINE = { ...LIMIT, ...resets("2026-10-17T13:00:00Z"), turns: 4, maxTurns: 30 };

test("the record's stated reset is read; with none, it resets five hours after the run ended", () => {
  assert.equal(limitResetsAt(posted(LIMIT_LINE)), Date.parse("2026-10-17T13:00:00Z"));
  assert.equal(limitResetsAt(posted(LIMIT)), ended + 5 * HOUR);
});

test("a stated reset is held between one hour and seven days after the run ended", () => {
  assert.equal(limitResetsAt(posted({ ...LIMIT, ...resets("2026-10-01T00:00:00Z") })), ended + HOUR);
  assert.equal(limitResetsAt(posted({ ...LIMIT, ...resets("2027-01-01T00:00:00Z") })), ended + 7 * 24 * HOUR);
});

// A 401 fails every run on that credential until a person re-sets it, so it
// waits like a usage limit that states no reset, and counts toward the cap.
test("a refused credential (class auth) is a limit stop that resets fallback-reset hours after the run ended", () => {
  const AUTH = { class: "auth", turns: 1 };
  assert.equal(limitResetsAt(posted(AUTH)), ended + 5 * HOUR);
  const stops = [1, 2, 3].map((id) => posted(AUTH, { id }));
  assert.equal(anyHandles(stops.slice(0, 1), { now: ended + 5 * HOUR - 1, failuresRetry: true }), true);
  assert.equal(anyHandles(stops.slice(0, 2), { now: ended + 5 * HOUR, failuresRetry: true }), false);
  assert.equal(anyHandles(stops, { now: ended + 5 * HOUR, failuresRetry: true }), true);
});

test("pendingStop names the unreset stop that resets last, and nothing once all have reset", () => {
  const auth = posted({ class: "auth" }, { id: 1 });
  const limit = posted(LIMIT_LINE, { id: 2 });
  assert.deepEqual(pendingStop([limit, auth], { now: ended }), { failureClass: "auth", resetsAt: ended + 5 * HOUR });
  assert.deepEqual(pendingStop([limit, auth], { now: ended + 4 * HOUR }), { failureClass: "auth", resetsAt: ended + 5 * HOUR });
  assert.equal(pendingStop([limit, auth], { now: ended + 5 * HOUR }), null);
  assert.equal(pendingStop([run()], { now: ended }), null);
});

// A key out of credit does not recover when a usage window resets, so a credit
// stop is no limit stop: its failed run handles the head, and no reset waits.
test("a credit stop is no limit stop: no reset, nothing pending, and the head is handled", () => {
  const credit = posted({ class: "credit-stop", turns: 1 });
  assert.equal(limitResetsAt(credit), null);
  assert.equal(pendingStop([credit], { now: ended }), null);
  assert.equal(anyHandles([credit], { now: ended + 5 * HOUR }), true);
  assert.equal(permanentlyHandles([credit]), true);
});

test("another class, or a failed run with no record, is no limit stop", () => {
  assert.equal(limitResetsAt(posted({ class: "other", turns: 3 })), null);
  assert.equal(limitResetsAt(run()), null);
});

// The `lane=<lane> activity=<activity> class=...` summary line report-check-run
// wrote before ADR 0087 slice 3 is retired.
test("the retired summary line is not read: a run that carries only it is no limit stop", () => {
  const legacy = {
    ...run(),
    name: "pr-unblock / resolve-conflicts",
    output: {
      title: "Failed",
      summary: "lane=pr-unblock activity=resolve-conflicts class=rate-limit resets=2026-10-17T13:00:00Z\n\nThe activity step failed.",
    },
  };
  assert.equal(limitResetsAt(legacy), null);
  assert.equal(anyHandles([legacy], { now: ended + HOUR }), true, "it handles the head like any red run with no record");
});

test("a run that did not fail is no limit stop, whatever its summary says", () => {
  assert.equal(limitResetsAt(posted(LIMIT_LINE, { conclusion: "success" })), null);
  assert.equal(limitResetsAt(posted(LIMIT_LINE, { conclusion: "neutral" })), null);
});

test("reset limit stops stop handling a head until three of them stand on it", () => {
  const now = ended + 6 * HOUR;
  const stops = [1, 2, 3].map((id) => posted(LIMIT, { id }));
  assert.equal(anyHandles(stops.slice(0, 2), { now }), false);
  assert.equal(anyHandles(stops, { now }), true);
});

test("a limit stop handles the head until its reset", () => {
  assert.equal(anyHandles([posted(LIMIT_LINE)], { now: Date.parse("2026-10-17T12:59:59Z") }), true);
  assert.equal(anyHandles([posted(LIMIT_LINE)], { now: Date.parse("2026-10-17T13:00:00Z") }), false);
});

// A resolved `limits` leaf set away from every default (hours and counts).
const SET = {
  "fallback-reset": 2,
  "reset-clamp-min": 3,
  "reset-clamp-max": 24,
  "restarts-per-run": 5,
  "limit-stops-per-head": 1,
  "limit-stops-per-issue": 3,
};

test("the resolved limits set the fallback reset and the clamp", () => {
  assert.equal(limitResetsAt(posted(LIMIT), SET), ended + 3 * HOUR);
  assert.equal(limitResetsAt(posted(LIMIT), { ...SET, "reset-clamp-min": 1 }), ended + 2 * HOUR);
  assert.equal(limitResetsAt(posted({ ...LIMIT, ...resets("2027-01-01T00:00:00Z") }), SET), ended + 24 * HOUR);
});

test("the resolved limits set how many reset limit stops handle a head", () => {
  const now = ended + 30 * HOUR;
  assert.equal(anyHandles([posted(LIMIT, { id: 1 })], { now }), false);
  assert.equal(anyHandles([posted(LIMIT, { id: 1 })], { now, limits: SET }), true);
});

// Without an opt-in, the count of limit stops holds a head (anyHandles) but
// never records it: a head recorded at the default cap of 3 would stay
// recorded under a resolved cap of 5.
test("limit stops alone never handle a head for good, under the default cap or a higher one", () => {
  const three = [1, 2, 3].map((id) => posted(LIMIT, { id }));
  const FIVE = { ...SET, "limit-stops-per-head": 5 };
  assert.equal(permanentlyHandles(three, { limits: FIVE }), false);
  assert.equal(permanentlyHandles(three), false);
  assert.equal(anyHandles(three, { now: ended + 30 * HOUR, limits: FIVE }), false, "3 reset stops of a cap of 5");
});

test("a failed run with no record handles the head, however long ago it ended", () => {
  assert.equal(anyHandles([run()], { now: ended + 30 * 24 * HOUR }), true);
  assert.equal(anyHandles([posted(LIMIT, { id: 1 }), run(2)], { now: ended + 6 * HOUR }), true);
  assert.equal(permanentlyHandles([run()]), true);
});

// resolve-conflicts opts in: a failed run is retried, every failure (limit
// stops included) counting toward limit-stops-per-head (3 by default).
test("with failures retried, failed runs stop handling the head until three of them stand on it", () => {
  const now = ended + HOUR;
  const options = { now, failuresRetry: true };
  assert.equal(anyHandles([run(1)], options), false);
  assert.equal(anyHandles([run(1), run(2)], options), false);
  assert.equal(anyHandles([run(1), posted(LIMIT, { id: 2 }), run(3)], { ...options, now: ended + 6 * HOUR }), true);
  assert.equal(anyHandles([run(1), run(2), run(3)], options), true);
  assert.equal(anyHandles([run(1), run(2)], { ...options, limits: SET }), true, "the resolved cap of 1");
  assert.equal(permanentlyHandles([run(1), run(2)], { failuresRetry: true }), false);
  assert.equal(permanentlyHandles([run(1), run(2), run(3)], { failuresRetry: true }), true);
});

// A class whose run never started the model (ci-workflows lane-outcome.md:
// install-failed, sandbox-unavailable) is a fault: it holds, counts toward no
// cap, and the next tick dispatches the head again. A class that persists or
// that a model turn may have run under (no-credential, max-turns) still counts.
test("a fault stop holds without counting toward the cap; a max-turns failure still counts", () => {
  const now = ended + HOUR;
  const fault = (cls, id) => posted({ class: cls }, { id });
  for (const faults of [
    [1, 2, 3, 4].map((id) => fault("install-failed", id)),
    [1, 2, 3, 4].map((id) => fault("sandbox-unavailable", id)),
  ]) {
    for (const opt of [{}, { failuresRetry: true }, { failuresRetry: true, heldSkipsRelease: true, lagStopsRelease: true }]) {
      assert.equal(anyHandles(faults, { now, ...opt }), false);
      assert.equal(permanentlyHandles(faults, opt), false);
      assert.equal(cappedAt(faults, opt), 0);
    }
  }
  const turns = [1, 2, 3].map((id) => fault("max-turns", id));
  assert.equal(anyHandles(turns, { now, failuresRetry: true }), true);
  assert.equal(cappedAt(turns, { failuresRetry: true }), 3);
  assert.equal(anyHandles([turns[0], fault("install-failed", 9), turns[1]], { now, failuresRetry: true }), false, "two counted failures of three");
  assert.equal(anyHandles([run(1)], { now }), true, "a red run with no record still handles the head");
  const noCred = [1, 2, 3].map((id) => fault("no-credential", id));
  assert.equal(anyHandles(noCred, { now, failuresRetry: true }), true, "a missing credential fails every tick, so it still caps the head");
  assert.equal(cappedAt(noCred, { failuresRetry: true }), 3);
});

test("with failures retried, an unreset limit stop or any run that did not fail still handles the head", () => {
  const options = { now: ended + HOUR, failuresRetry: true };
  assert.equal(anyHandles([posted(LIMIT, { id: 1 })], options), true);
  assert.equal(anyHandles([run(1), { ...run(2), conclusion: "success" }], options), true);
  assert.equal(permanentlyHandles([run(1), { ...run(2), conclusion: "success" }], { failuresRetry: true }), true);
});

// The neutral check report-check-run posts for a skip whose reason is
// awaiting-human (decide.mjs: "Skipped: <reason>"), as a held PR leaves it.
const heldSkip = { id: 9, status: "completed", conclusion: "neutral", completed_at: ENDED, output: { title: "Skipped: awaiting-human" } };

test("with held skips released, an awaiting-human skip does not handle the head", () => {
  const now = ended + HOUR;
  assert.equal(anyHandles([heldSkip], { now }), true, "by default it handles the head");
  assert.equal(permanentlyHandles([heldSkip]), true);
  assert.equal(anyHandles([heldSkip], { now, heldSkipsRelease: true }), false);
  assert.equal(permanentlyHandles([heldSkip], { heldSkipsRelease: true }), false);
  const other = { ...heldSkip, output: { title: "Skipped: not-applicable" } };
  assert.equal(anyHandles([other], { now, heldSkipsRelease: true }), true, "another skip still handles it");
  // A run that reads a hold the dispatcher does not stops at the cap.
  const three = [heldSkip, { ...heldSkip, id: 10 }, { ...heldSkip, id: 11 }];
  assert.equal(anyHandles(three, { now, heldSkipsRelease: true }), true);
  assert.equal(permanentlyHandles(three, { heldSkipsRelease: true }), true);
  assert.equal(anyHandles([heldSkip, run(1), run(2)], { now, heldSkipsRelease: true, failuresRetry: true }), true, "held skips and failures share the cap");
});

test("with lag stops released, a head-lag stop does not handle the head until the cap; by default it does", () => {
  const now = ended + HOUR;
  const lagged = (id) => ({ ...heldSkip, id, output: { title: HEAD_LAG_STOP } });
  assert.equal(HEAD_LAG_STOP, "Skipped: superseded-sha");
  assert.equal(headLagStop(lagged(1)), true);
  assert.equal(headLagStop({ ...lagged(1), conclusion: "failure" }), false);
  assert.equal(anyHandles([lagged(1)], { now }), true, "by default it handles the head");
  assert.equal(anyHandles([lagged(1)], { now, lagStopsRelease: true }), false);
  assert.equal(permanentlyHandles([lagged(1)], { lagStopsRelease: true }), false);
  assert.equal(anyHandles([lagged(1), { ...lagged(2), status: "in_progress", conclusion: null }], { now, lagStopsRelease: true }), true, "a newer run going handles it");
  assert.equal(anyHandles([lagged(1), { ...lagged(2), conclusion: "success", output: { title: "Passed" } }], { now, lagStopsRelease: true }), true, "a newer run that acted handles it");
  const three = [lagged(1), lagged(2), lagged(3)];
  assert.equal(anyHandles(three, { now, lagStopsRelease: true }), true, "the cap ends it");
  assert.equal(cappedAt(three, { lagStopsRelease: true }), 3);
});

// A run the lanes kill switch stopped did no work: its own kill-switch step,
// or a broker refusal of its mint (request-lane-token kill-switch-ok), posts
// neutral kill-switch (decide.mjs: "Skipped: <reason>").
const killed = (id = 20, started = "2026-10-17T09:00:00Z") => ({
  id,
  status: "completed",
  conclusion: "neutral",
  started_at: started,
  completed_at: ENDED,
  output: { title: KILL_SWITCH_STOP },
});

test("a kill-switch stop never handles a head, with or without the opt-ins, until three stops stand on it", () => {
  const now = ended + HOUR;
  assert.equal(KILL_SWITCH_STOP, "Skipped: kill-switch");
  assert.equal(killSwitchStop(killed()), true);
  assert.equal(killSwitchStop({ ...killed(), conclusion: "failure" }), false, "a red kill-switch denial is no such stop");
  assert.equal(killSwitchStop({ ...killed(), output: { title: "Skipped: prerequisite-missing" } }), false);
  for (const options of [{}, { heldSkipsRelease: true, failuresRetry: true }]) {
    assert.equal(anyHandles([killed()], { now, ...options }), false);
    assert.equal(permanentlyHandles([killed()], options), false);
    const three = [killed(20), killed(21), killed(22)];
    assert.equal(anyHandles(three, { now, ...options }), true, "a switch that keeps flipping mid-run ends the head at the cap");
  }
  assert.equal(anyHandles([killed(), run(1), run(2)], { now, failuresRetry: true }), true, "kill-switch stops and failures share the cap");
  assert.equal(anyHandles([killed(), { ...killed(30), conclusion: "success", output: { title: "Passed" } }], { now }), true, "another run still handles the head");
});

test("an emitter check's kill-switch stop releases the head's earlier activity checks, like a lane stop", () => {
  const activity = { ...killed(1, "2026-10-17T08:00:00Z"), conclusion: "success", output: { title: "Passed" } };
  const stop = killed(2, "2026-10-17T08:30:00Z");
  assert.equal(releasesHead(stop), true);
  const { cut, stops } = stopRelease([stop], 3);
  assert.equal(cut, Date.parse("2026-10-17T08:30:00Z"));
  assert.equal(stops, 1);
  assert.deepEqual(releasedBy([activity], cut), []);
  const capped = stopRelease([killed(2), killed(3), killed(4)], 3);
  assert.equal(capped.cut, null, "the dispatcher's per-head cap ends the retries");
  assert.equal(stopRelease([{ ...stop, output: { title: "Passed" } }], 3).cut, null, "a push that acted releases nothing");
});

test("an auth stop waits fallback-reset even when its record states a reset", () => {
  assert.equal(limitResetsAt(posted({ class: "auth", ...resets("2026-10-17T14:00:00Z") })), ended + 5 * HOUR);
});

test("a record's Claude model ids, with the [1m] suffix, are read", () => {
  const models = { ...LIMIT_LINE, models: ["claude-opus-5-5", "claude-haiku-5-5[1m]"] };
  assert.equal(limitResetsAt(posted(models)), Date.parse("2026-10-17T13:00:00Z"));
});

test("an impossible stated reset (month 13) is no stated reset: it resets five hours after the run ended", () => {
  assert.equal(limitResetsAt(posted({ ...LIMIT, ...resets("2026-13-01T00:00:00Z") })), ended + 5 * HOUR);
});

test("a key the reader does not know, top level or nested, is ignored and the record still read", () => {
  const extra = { ...LIMIT_LINE, laterField: { note: "a } in a string" }, resets: { ...LIMIT_LINE.resets, laterNested: 1 } };
  assert.equal(limitResetsAt(posted(extra)), Date.parse("2026-10-17T13:00:00Z"));
});

test("an unreadable record, or a handoff leg's, is no limit stop", () => {
  for (const [label, fields] of [
    ["another v", { v: 2 }],
    ["a malformed known key", { turns: "4" }],
    ["a malformed nested key", { resets: { at: "tomorrow" } }],
    ["a value-shaped secret", { credential: { secret: "sk-ant-abc", kind: "api-key" } }],
    ["a kind that disagrees with the secret", { credential: { secret: "CLAUDE_CODE_OAUTH_TOKEN", kind: "api-key" } }],
    ["a class outside the enum", { class: "rate limited" }],
    ["a failure with no class", { class: undefined }],
    ["a handoff leg", { handoff: true }],
    ["an email as a model", { models: ["kyle.sexton@example.com"] }],
    ["a host:port as a model", { models: ["runner-7.corp.internal:443"] }],
    ["a key prefix as a model", { models: ["sk-ant-api03-abcdef"] }],
  ]) {
    assert.equal(limitResetsAt(posted({ ...LIMIT_LINE, ...fields })), null, label);
  }
});

test("a record naming another check run is no limit stop", () => {
  assert.equal(limitResetsAt(posted({ ...LIMIT_LINE, activity: "address-feedback" })), null);
  assert.equal(limitResetsAt(posted({ ...LIMIT_LINE, lane: "pr-review" })), null);
});

test("a credit stop on an API key is no limit stop", () => {
  const credit = { class: "credit-stop", credential: { secret: "LANES_CLAUDE_API_KEY", kind: "api-key", role: "LANES" } };
  assert.equal(limitResetsAt(posted(credit)), null);
});

// docs/lane-outcome.md, Failure classes: review-unposted is a run that
// succeeded with no review to post, shell-failed an older run with no working
// shell. Neither is a usage limit or a run whose model never started.
test("review-unposted and shell-failed records are read, and are neither a limit nor a fault stop", () => {
  const now = ended + HOUR;
  for (const cls of ["review-unposted", "shell-failed"]) {
    const runs = [1, 2, 3].map((id) => posted({ class: cls }, { id }));
    assert.equal(limitResetsAt(runs[0]), null, cls);
    assert.equal(anyHandles(runs.slice(0, 1), { now }), true, `${cls} handles the head`);
    assert.equal(cappedAt(runs, { failuresRetry: true }), 3, `${cls} counts toward the cap`);
  }
});

test("a record whose class this reader does not know is no limit stop", () => {
  const later = posted({ class: "later-class" });
  assert.equal(limitResetsAt(later), null);
  assert.equal(anyHandles([later], { now: ended + HOUR, failuresRetry: true }), false, "a failure with no stop class retries");
});
