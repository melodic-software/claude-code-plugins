import assert from "node:assert/strict";
import { test } from "node:test";

import { limitResetsAt } from "../../scripts/pr-unblock/limit-stop.mjs";
import { laneRecordAnnotation } from "./lane-record.mjs";

const ENDED = "2026-10-17T12:00:00Z";
const RESETS = "2026-10-17T15:30:00Z";
const run = { completed_at: ENDED };

test("a rate-limit record is the limit stop limit-stop.mjs reads, with its reset", () => {
  const annotation = laneRecordAnnotation({
    lane: "pr-unblock",
    failureClass: "rate-limit",
    resets: RESETS,
    turns: "12",
    maxTurns: "30",
  });
  assert.equal(annotation.annotation_level, "failure");
  assert.equal(annotation.title, undefined);
  assert.equal(
    annotation.message,
    "pr-unblock skipped: usage limit reached; re-run after it resets (pr-unblock exited with: failure " +
      `class=rate-limit resets=${RESETS} turns=12 max-turns=30). Last SDK result: in the run log.`,
  );
  assert.equal(limitResetsAt(run, [annotation]), Date.parse(RESETS));
});

test("a rate-limit record with no reset reads as a limit stop on the fallback reset", () => {
  const annotation = laneRecordAnnotation({ lane: "pr-unblock", failureClass: "rate-limit" });
  assert.equal(limitResetsAt(run, [annotation]), Date.parse(ENDED) + 5 * 3_600_000);
});

test("a review lane's limit stop opens with AI review, as limit-stop.mjs expects", () => {
  const annotation = laneRecordAnnotation({ lane: "pr-review", failureClass: "rate-limit", resets: RESETS });
  assert.match(annotation.message, /^AI review skipped: /);
  assert.equal(limitResetsAt(run, [annotation]), Date.parse(RESETS));
});

test("a malformed reset is dropped, never passed into the message", () => {
  const annotation = laneRecordAnnotation({
    lane: "pr-unblock",
    failureClass: "rate-limit",
    resets: "2099-01-01T00:00:00Z) x=(",
  });
  assert.doesNotMatch(annotation.message, /resets=/);
});

test("another class is a failure record that limit-stop.mjs does not read as a limit stop", () => {
  const annotation = laneRecordAnnotation({ lane: "pr-unblock", failureClass: "max-turns", turns: "31", maxTurns: "30" });
  assert.equal(annotation.annotation_level, "failure");
  assert.equal(annotation.message, "pr-unblock exited with: failure class=max-turns turns=31 max-turns=30.");
  assert.equal(limitResetsAt(run, [annotation]), null);
});

test("a success records turn headroom as a notice", () => {
  const annotation = laneRecordAnnotation({ lane: "pr-unblock", turns: "4", maxTurns: "30" });
  assert.equal(annotation.annotation_level, "notice");
  assert.equal(annotation.message, "pr-unblock completed: turns=4 max-turns=30.");
});

test("a validation skip is a warning that names its success outcome", () => {
  const annotation = laneRecordAnnotation({ lane: "pr-unblock", failureClass: "skipped-validation" });
  assert.equal(annotation.annotation_level, "warning");
  assert.match(annotation.message, /concluded: success class=skipped-validation/);
});

test("no record, an unknown class, or non-numeric turns add nothing", () => {
  assert.equal(laneRecordAnnotation({ lane: "pr-unblock" }), null);
  assert.equal(laneRecordAnnotation({ lane: "pr-unblock", failureClass: "forged class" }), null);
  assert.equal(laneRecordAnnotation({ lane: "pr-unblock", turns: "4 x=1", maxTurns: "" }), null);
});
