import assert from "node:assert/strict";
import { test } from "node:test";

import { main, overlapReport, peakOverlap, spanOf } from "./overlap.mjs";
import { sinkDir } from "./pull-fixtures.mjs";
import { ensureDir, writeRows } from "./store.mjs";

const row = (lane, start, end) => ({ lane, created_at: end, date: end.slice(0, 10), duration_ms: Date.parse(end) - Date.parse(start) });
const spans = (rows) => rows.map(spanOf);
const weekEnds = [row("pr-verify", "2026-11-01T00:00:00Z", "2026-11-01T00:10:00Z"), row("pr-verify", "2026-11-07T23:00:00Z", "2026-11-07T23:10:00Z")];

function run(argv, env = {}) {
  let out = "";
  let err = "";
  const code = main(argv, env, { out: (s) => (out += s), err: (s) => (err += s) });
  return { code, out, err };
}

function sinkWith(rows) {
  const sink = sinkDir();
  ensureDir(sink);
  writeRows(sink, rows);
  return sink;
}

test("two runs that touch end to start do not overlap", () => {
  const result = peakOverlap(spans([row("pr-verify", "2026-11-03T10:00:00Z", "2026-11-03T11:00:00Z"), row("pr-review", "2026-11-03T11:00:00Z", "2026-11-03T12:00:00Z")]));
  assert.equal(result.peak, 1);
  assert.equal(result.peak_occurrences, 1, "the count never drops below 1 at the handoff, so it reaches the peak once");
});

test("three nested runs count 3, at the hour the innermost starts, broken down by lane", () => {
  const result = peakOverlap(
    spans([
      row("work-resolve-issue", "2026-11-03T10:00:00Z", "2026-11-03T14:00:00Z"),
      row("pr-verify", "2026-11-03T11:00:00Z", "2026-11-03T13:00:00Z"),
      row("pr-verify", "2026-11-03T11:30:00Z", "2026-11-03T12:30:00Z"),
    ]),
  );
  assert.deepEqual(result, {
    peak: 3,
    peak_at: "2026-11-03T11:30:00.000Z",
    peak_hour: "2026-11-03T11:00Z",
    peak_lanes: { "pr-verify": 2, "work-resolve-issue": 1 },
    peak_occurrences: 1,
    peak_hours: ["2026-11-03T11:00Z"],
  });
});

test("a row with no duration is left out of the count and reported as uncounted", () => {
  const report = overlapReport([...weekEnds, { lane: "pr-verify", created_at: "2026-11-04T10:00:00Z", date: "2026-11-04", duration_ms: null }]);
  assert.equal(report.runs, 2);
  assert.equal(report.uncounted_rows, 1);
  assert.equal(report.window.days, 7);
  assert.ok(report.limits.length > 0);
  const uncountedEnd = overlapReport([weekEnds[0], { lane: "pr-verify", created_at: "2026-11-07T10:00:00Z", date: "2026-11-07", duration_ms: null }]);
  assert.deepEqual(uncountedEnd, { refused: true, window: { since: null, until: null, first_date: "2026-11-01", last_date: "2026-11-01", days: 1 } });
});

test("a window with under 7 days of rows is refused, naming how many days it has", () => {
  const sink = sinkWith([...weekEnds, row("pr-verify", "2026-11-02T00:00:00Z", "2026-11-02T00:10:00Z")]);
  const short = run(["--sink", sink, "--since", "2026-11-02"]);
  assert.equal(short.code, 1);
  assert.equal(short.out, "");
  assert.match(short.err, /holds 6 days of rows \(2026-11-02 to 2026-11-07\)/);
  const empty = run(["--sink", sinkWith([])]);
  assert.equal(empty.code, 1);
  assert.match(empty.err, /holds 0 days of rows;/);
});

test("a window of 7 days of rows reports the peak as JSON", () => {
  const result = run(["--sink", sinkWith(weekEnds)]);
  assert.equal(result.code, 0);
  const report = JSON.parse(result.out);
  assert.equal(report.peak, 1);
  assert.deepEqual(report.window, { since: null, until: null, first_date: "2026-11-01", last_date: "2026-11-07", days: 7 });
});

test("an unknown flag or a relative sink is a usage error", () => {
  assert.equal(run(["--lane", "pr-verify"]).code, 2);
  assert.equal(run(["--sink", "relative"]).code, 2);
});
