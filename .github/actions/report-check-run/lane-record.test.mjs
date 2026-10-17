import assert from "node:assert/strict";
import { test } from "node:test";

import { laneRecordOutput } from "./lane-record.mjs";

const RESETS = "2026-10-17T15:30:00Z";

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
