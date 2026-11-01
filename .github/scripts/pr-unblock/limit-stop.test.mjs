import assert from "node:assert/strict";
import { test } from "node:test";

import { anyHandles, KILL_SWITCH_STOP, killSwitchStop, limitResetsAt, pendingStop, permanentlyHandles, releasedBy, releasesHead, stopRelease } from "./limit-stop.mjs";

const HOUR = 3_600_000;
const ENDED = "2026-10-17T10:00:00Z";
const ended = Date.parse(ENDED);
const run = (id = 1) => ({ id, status: "completed", conclusion: "failure", completed_at: ENDED, output: { title: "x" } });
// The summary record report-check-run writes on the first line of a posted
// check run named `<lane> / <activity>`.
const posted = (line, extra = {}) => ({
  ...run(),
  name: "pr-unblock / resolve-conflicts",
  output: { title: "Failed", summary: `${line}\n\nThe activity step failed.` },
  ...extra,
});
const LIMIT = "lane=pr-unblock activity=resolve-conflicts class=rate-limit";
const LIMIT_LINE = `${LIMIT} resets=2026-10-17T13:00:00Z turns=4 max-turns=30`;

test("the summary record's stated reset is read; with none, it resets five hours after the run ended", () => {
  assert.equal(limitResetsAt(posted(LIMIT_LINE)), Date.parse("2026-10-17T13:00:00Z"));
  assert.equal(limitResetsAt(posted(LIMIT)), ended + 5 * HOUR);
});

test("a record ending in the models and profile tokens is still read", () => {
  const line = `${LIMIT_LINE} models=claude-opus-5-5,claude-haiku-5-5[1m] profile=standard`;
  assert.equal(limitResetsAt(posted(line)), Date.parse("2026-10-17T13:00:00Z"));
  assert.equal(limitResetsAt(posted(`${LIMIT} profile=standard`)), ended + 5 * HOUR);
});

test("a stated reset is held between one hour and seven days after the run ended", () => {
  assert.equal(limitResetsAt(posted(`${LIMIT} resets=2026-10-01T00:00:00Z`)), ended + HOUR);
  assert.equal(limitResetsAt(posted(`${LIMIT} resets=2027-01-01T00:00:00Z`)), ended + 7 * 24 * HOUR);
});

// A 401 fails every run on that credential until a person re-sets it, so it
// waits like a usage limit that states no reset, and counts toward the cap.
test("a refused credential (class auth) is a limit stop that resets fallback-reset hours after the run ended", () => {
  const AUTH = "lane=pr-unblock activity=resolve-conflicts class=auth turns=1";
  assert.equal(limitResetsAt(posted(AUTH)), ended + 5 * HOUR);
  const stops = [1, 2, 3].map((id) => posted(AUTH, { id }));
  assert.equal(anyHandles(stops.slice(0, 1), { now: ended + 5 * HOUR - 1, failuresRetry: true }), true);
  assert.equal(anyHandles(stops.slice(0, 2), { now: ended + 5 * HOUR, failuresRetry: true }), false);
  assert.equal(anyHandles(stops, { now: ended + 5 * HOUR, failuresRetry: true }), true);
});

test("pendingStop names the unreset stop that resets last, and nothing once all have reset", () => {
  const auth = posted("lane=pr-unblock activity=resolve-conflicts class=auth", { id: 1 });
  const limit = posted(LIMIT_LINE, { id: 2 });
  assert.deepEqual(pendingStop([limit, auth], { now: ended }), { failureClass: "auth", resetsAt: ended + 5 * HOUR });
  assert.deepEqual(pendingStop([limit, auth], { now: ended + 4 * HOUR }), { failureClass: "auth", resetsAt: ended + 5 * HOUR });
  assert.equal(pendingStop([limit, auth], { now: ended + 5 * HOUR }), null);
  assert.equal(pendingStop([run()], { now: ended }), null);
});

// A key out of credit does not recover when a usage window resets, so a credit
// stop is no limit stop: its failed run handles the head, and no reset waits.
test("a credit stop is no limit stop: no reset, nothing pending, and the head is handled", () => {
  const credit = posted("lane=pr-unblock activity=resolve-conflicts class=credit-stop turns=1");
  assert.equal(limitResetsAt(credit), null);
  assert.equal(pendingStop([credit], { now: ended }), null);
  assert.equal(anyHandles([credit], { now: ended + 5 * HOUR }), true);
  assert.equal(permanentlyHandles([credit]), true);
});

test("another class, or a failed run with no summary record, is no limit stop", () => {
  assert.equal(limitResetsAt(posted("lane=pr-unblock activity=resolve-conflicts class=other turns=3")), null);
  assert.equal(limitResetsAt(run()), null);
});

test("a summary line that is not the record is not read as one", () => {
  const notRecords = [
    // the record below the first line
    posted(`Failed.\n${LIMIT_LINE}`),
    // embedded in other text, or with a token out of order or unknown
    posted(`Model said: ${LIMIT_LINE}`),
    posted("lane=pr-unblock activity=resolve-conflicts resets=2026-10-17T13:00:00Z class=rate-limit"),
    posted(`${LIMIT_LINE} note=x`),
    posted(`${LIMIT_LINE} profile=standard models=claude-opus-5-5`),
    posted(`${LIMIT_LINE} models=claude opus`),
    posted(`${LIMIT_LINE} models=`),
    // a record naming another check run
    posted(LIMIT_LINE.replace("resolve-conflicts", "address-feedback")),
  ];
  for (const forged of notRecords) {
    assert.equal(limitResetsAt(forged), null, forged.output.summary);
  }
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
  assert.equal(limitResetsAt(posted(`${LIMIT} resets=2027-01-01T00:00:00Z`), SET), ended + 24 * HOUR);
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

test("a failed run with no summary record handles the head, however long ago it ended", () => {
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

// The lane-outcome record report-check-run writes into output.text, built by
// hand from docs/lane-outcome.md's rate-limit example plus the hub's activity.
const RECORD = {
  v: 1,
  lane: "pr-unblock",
  activity: "resolve-conflicts",
  outcome: "failure",
  class: "rate-limit",
  credential: { secret: "CLAUDE_CODE_OAUTH_TOKEN", kind: "oauth-token" },
  resets: { at: "2026-10-17T14:00:00Z", window: "five_hour" },
  turns: 4,
};
const withText = (record, line = "", extra = {}) =>
  posted(line, { output: { title: "Failed", summary: `${line}\n\nThe activity step failed.`, text: `lane-outcome ${JSON.stringify(record)} trailing free text }` }, ...extra });

test("the lane-outcome record in output.text is read before the legacy summary line", () => {
  assert.equal(limitResetsAt(withText(RECORD, LIMIT_LINE)), Date.parse("2026-10-17T14:00:00Z"));
  assert.equal(limitResetsAt(withText({ ...RECORD, class: "auth", resets: undefined })), ended + 5 * HOUR);
});

test("a record's Claude model ids, with the [1m] suffix, are read", () => {
  const models = { ...RECORD, models: ["claude-opus-5-5", "claude-haiku-5-5[1m]"] };
  assert.equal(limitResetsAt(withText(models, LIMIT_LINE)), Date.parse("2026-10-17T14:00:00Z"));
});

test("an impossible stated reset (month 13) is no stated reset: it resets five hours after the run ended", () => {
  assert.equal(limitResetsAt(withText({ ...RECORD, resets: { at: "2026-13-01T00:00:00Z", window: "five_hour" } })), ended + 5 * HOUR);
  assert.equal(limitResetsAt(posted(`${LIMIT} resets=2026-13-01T00:00:00Z`)), ended + 5 * HOUR);
});

test("a key the reader does not know, top level or nested, is ignored and the record still read", () => {
  const extra = { ...RECORD, laterField: { note: "a } in a string" }, resets: { ...RECORD.resets, laterNested: 1 } };
  assert.equal(limitResetsAt(withText(extra, LIMIT_LINE)), Date.parse("2026-10-17T14:00:00Z"));
});

test("with no record, or an unreadable one, the legacy summary line is read", () => {
  assert.equal(limitResetsAt(posted(LIMIT_LINE)), Date.parse("2026-10-17T13:00:00Z"));
  for (const [label, record] of [
    ["another v", { ...RECORD, v: 2 }],
    ["a malformed known key", { ...RECORD, turns: "4" }],
    ["a malformed nested key", { ...RECORD, resets: { at: "tomorrow" } }],
    ["a value-shaped secret", { ...RECORD, credential: { secret: "sk-ant-abc", kind: "api-key" } }],
    ["a kind that disagrees with the secret", { ...RECORD, credential: { secret: "CLAUDE_CODE_OAUTH_TOKEN", kind: "api-key" } }],
    ["a class outside the enum", { ...RECORD, class: "rate limited" }],
    ["a failure with no class", { ...RECORD, class: undefined }],
    ["a handoff leg", { ...RECORD, handoff: true }],
    ["an email as a model", { ...RECORD, models: ["kyle.sexton@example.com"] }],
    ["a host:port as a model", { ...RECORD, models: ["runner-7.corp.internal:443"] }],
    ["a key prefix as a model", { ...RECORD, models: ["sk-ant-api03-abcdef"] }],
  ]) {
    assert.equal(limitResetsAt(withText(record, LIMIT_LINE)), Date.parse("2026-10-17T13:00:00Z"), label);
  }
});

test("a record naming another check run is ignored: the legacy line wins, and with none there is no stop", () => {
  const other = { ...RECORD, activity: "address-feedback" };
  assert.equal(limitResetsAt(withText(other, LIMIT_LINE)), Date.parse("2026-10-17T13:00:00Z"));
  assert.equal(limitResetsAt(withText(other, "The activity step failed.")), null);
  assert.equal(limitResetsAt(withText({ ...RECORD, lane: "pr-review" }, "The activity step failed.")), null);
});

test("a credit stop is no limit stop on the record or the legacy line", () => {
  const credit = { ...RECORD, class: "credit-stop", resets: undefined, credential: { secret: "LANES_CLAUDE_API_KEY", kind: "api-key", role: "LANES" } };
  assert.equal(limitResetsAt(withText(credit)), null);
  assert.equal(limitResetsAt(withText(credit, LIMIT_LINE)), null, "a readable record wins over the legacy line");
  assert.equal(limitResetsAt(posted("lane=pr-unblock activity=resolve-conflicts class=credit-stop")), null);
});
