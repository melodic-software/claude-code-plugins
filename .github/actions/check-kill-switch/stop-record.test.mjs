import assert from "node:assert/strict";
import { test } from "node:test";

import { deferResets, readStop, STOP_RECORD_TITLE, stopRecordLine } from "./stop-record.mjs";

const COMMAND = /^::notice title=([^:]+)::(.*)$/;
const asAnnotation = (line) => {
  const [, title, message] = COMMAND.exec(line);
  return { annotation_level: "notice", title, message };
};

test("the record is the fixed-prefix JSON notice the owner decision names", () => {
  assert.equal(stopRecordLine({ pool: "core", cause: "defer", reset: 1800000000 }), '::notice title=stop-record::{"pool":"core","cause":"defer","reset":1800000000}');
  assert.equal(stopRecordLine({ cause: "switch" }), '::notice title=stop-record::{"pool":null,"cause":"switch","reset":null}');
  assert.equal(STOP_RECORD_TITLE, "stop-record");
});

test("a written record reads back as the stop it records", () => {
  for (const stop of [
    { pool: "core", cause: "defer", reset: 1800000000 },
    { pool: "core", cause: "budget", reset: 1795642264 },
    { pool: null, cause: "switch", reset: null },
    { pool: "*", cause: "limit", reset: 1800000000 },
  ]) {
    assert.deepEqual(readStop(asAnnotation(stopRecordLine(stop))), stop);
  }
});

test("the older stop text still reads as a defer stop, and only where the old reader matched it", () => {
  const hosted = "a kill switch stops this review (lanes: kill-switch cause=defer reset=1800000000, CLAUDE_REVIEW_DISABLED: unset)";
  const verify = "deferred: the GITHUB_TOKEN window is projected to run short before this judgment ends; nothing is judged, and the lost-run reconciler re-runs this run once after the reset (cause=defer reset=1800000000)";
  for (const message of [hosted, verify]) {
    assert.deepEqual(readStop({ title: null, message }), { pool: null, cause: "defer", reset: 1800000000 }, message);
  }
  assert.deepEqual(readStop({ title: "pr-verify", message: verify }), { pool: null, cause: "defer", reset: 1800000000 }, "another title keeps the text form");
  for (const message of [
    "a kill switch stops this review (lanes: kill-switch cause=budget reset=1800000000, CLAUDE_REVIEW_DISABLED: unset)",
    "a kill switch stops this review (lanes: kill-switch cause=switch reset=none, CLAUDE_REVIEW_DISABLED: unset)",
    "a kill switch stops this review (lanes: kill-switch cause defer, lane: unset); no verdict, so the lane stays unbound",
    "deferred until the GITHUB_TOKEN window resets at 1800000000 (2027-01-15T08:00:00Z): x; cause=defer, so a later run after the reset does this work",
    "cause=defer reset=12345678",
  ]) {
    assert.equal(readStop({ message }), null, message);
  }
});

test("a stop-record annotation outside the record's shape reads as no stop", () => {
  for (const message of [
    "not json",
    "null",
    '{"pool":"core","reset":1800000000}',
    '{"pool":"core","cause":"defer","reset":"1800000000"}',
    '{"pool":"core","cause":"defer","reset":12345678}',
    '{"pool":"Core Pool","cause":"defer","reset":1800000000}',
    '{"pool":"core","cause":"Defer Now","reset":1800000000}',
  ]) {
    assert.equal(readStop({ title: STOP_RECORD_TITLE, message }), null, message);
  }
  assert.equal(readStop({ title: STOP_RECORD_TITLE, message: '{"pool":"core","cause":"defer","reset":1800000000} cause=defer reset=1800000001' }), null, "a record title never falls back to the text form");
});

test("the writer refuses a field outside the record's shape", () => {
  for (const stop of [{}, { cause: "defer", reset: "1800000000" }, { cause: "defer", reset: 1.5e9 + 0.5 }, { cause: "defer", pool: "a b" }, { cause: "x::y" }]) {
    assert.throws(() => stopRecordLine(stop), /a stop record takes/, JSON.stringify(stop));
  }
});

test("a job's defer resets come from records and older text alike, and no other stop", () => {
  const annotations = [
    asAnnotation(stopRecordLine({ pool: "core", cause: "defer", reset: 1800000300 })),
    asAnnotation(stopRecordLine({ cause: "switch" })),
    asAnnotation(stopRecordLine({ pool: "core", cause: "budget", reset: 1800000900 })),
    { title: null, message: "a kill switch stops this review (lanes: kill-switch cause=defer reset=1800000000, CLAUDE_REVIEW_DISABLED: unset)" },
    { title: "api-budget", message: "api calls: 12" },
  ];
  assert.deepEqual(deferResets(annotations), [1800000300, 1800000000]);
  assert.deepEqual(deferResets([]), []);
});
