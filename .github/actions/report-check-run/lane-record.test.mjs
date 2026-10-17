import assert from "node:assert/strict";
import { test } from "node:test";

import { limitResetsAt } from "../../scripts/pr-unblock/limit-stop.mjs";
import { laneRecordAnnotation, laneRecordOutput } from "./lane-record.mjs";

const ENDED = "2026-10-17T12:00:00Z";
const RESETS = "2026-10-17T15:30:00Z";
const run = { conclusion: "failure", completed_at: ENDED };

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

test("the output record is one line of key=value tokens in a fixed order, its JSON form, and a run-scoped external id", () => {
  const record = laneRecordOutput({
    lane: "pr-unblock",
    activity: "resolve-conflicts",
    failureClass: "rate-limit",
    resets: RESETS,
    turns: "12",
    maxTurns: "30",
    runId: "4242",
    runAttempt: "2",
  });
  assert.equal(
    record.line,
    `lane=pr-unblock activity=resolve-conflicts class=rate-limit resets=${RESETS} turns=12 max-turns=30`,
  );
  assert.equal(
    record.text,
    "```json\n" +
      `{"lane":"pr-unblock","activity":"resolve-conflicts","class":"rate-limit","resets":"${RESETS}","turns":12,"max-turns":30}` +
      "\n```",
  );
  assert.equal(record.externalId, "pr-unblock:resolve-conflicts:4242:2");
});

test("absent fields are omitted from the output record, and a success carries no class", () => {
  const record = laneRecordOutput({ lane: "pr-refine", activity: "simplify", turns: "4" });
  assert.equal(record.line, "lane=pr-refine activity=simplify turns=4");
  assert.equal(record.text, '```json\n{"lane":"pr-refine","activity":"simplify","turns":4}\n```');
  assert.equal(record.externalId, null);
});

test("the output record drops what fails its shape: a reset off rate-limit, a forged reset, a malformed run id", () => {
  assert.equal(
    laneRecordOutput({ lane: "pr-unblock", activity: "x", failureClass: "other", resets: RESETS }).line,
    "lane=pr-unblock activity=x class=other",
  );
  assert.equal(
    laneRecordOutput({ lane: "pr-unblock", activity: "x", failureClass: "rate-limit", resets: `${RESETS} turns=1` }).line,
    "lane=pr-unblock activity=x class=rate-limit",
  );
  const forgedRun = { lane: "pr-unblock", activity: "x", failureClass: "other", runAttempt: "1" };
  assert.equal(laneRecordOutput({ ...forgedRun, runId: "1:2" }).externalId, null);
  assert.equal(laneRecordOutput({ ...forgedRun, runId: "7", runAttempt: "0" }).externalId, null);
});

test("no record, an unknown class, or a malformed name add no output record", () => {
  assert.equal(laneRecordOutput({ lane: "pr-unblock", activity: "x" }), null);
  assert.equal(laneRecordOutput({ lane: "pr-unblock", activity: "x", failureClass: "forged class" }), null);
  assert.equal(laneRecordOutput({ lane: "pr-unblock", activity: "x y=1", failureClass: "other" }), null);
});
