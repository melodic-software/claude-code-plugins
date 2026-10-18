import assert from "node:assert/strict";
import { test } from "node:test";

import { anyHandles, limitResetsAt } from "./limit-stop.mjs";

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

test("a failed run with no summary record handles the head, however long ago it ended", () => {
  assert.equal(anyHandles([run()], { now: ended + 30 * 24 * HOUR }), true);
  assert.equal(anyHandles([posted(LIMIT, { id: 1 }), run(2)], { now: ended + 6 * HOUR }), true);
});
