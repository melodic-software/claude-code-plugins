// Expected values: the external_id format docs/conventions/pr-pipeline/pr-run-activity.md
// specifies (`<lane>:<activity>:<run id>:<run attempt>`), and check run
// 122864732692 as the API returned it on #10583 (details_url
// https://github.com/melodic-software/claude-code-plugins/runs/122864732692,
// external_id "", posted by run 40700900804).
import assert from "node:assert/strict";
import { test } from "node:test";

import { externalIdOf, postingRunId } from "./posting-run.mjs";

const REPO = "https://github.com/melodic-software/claude-code-plugins";

test("the external id names the lane, activity, run and attempt", () => {
  assert.equal(
    externalIdOf({ lane: "pr-unblock", activity: "resolve-conflicts", runId: "4242", runAttempt: "2" }),
    "pr-unblock:resolve-conflicts:4242:2",
  );
});

test("a malformed lane, activity, run id or attempt makes no external id", () => {
  const good = { lane: "pr-unblock", activity: "x", runId: "7", runAttempt: "1" };
  for (const bad of [{ runId: "1:2" }, { runAttempt: "0" }, { runId: "" }, { runAttempt: undefined }, { lane: "Pr:x" }, { activity: "" }]) {
    assert.equal(externalIdOf({ ...good, ...bad }), null, JSON.stringify(bad));
  }
});

test("the posting run is the one external_id names, round-tripping externalIdOf", () => {
  const external_id = externalIdOf({ lane: "pr-unblock", activity: "apply-feedback-patch", runId: "40700900804", runAttempt: "1" });
  assert.equal(postingRunId({ details_url: `${REPO}/runs/122864732692`, external_id }), "40700900804");
});

test("a check with no run-scoped external_id is read from a details_url naming the run's page, never the check run's own", () => {
  assert.equal(postingRunId({ details_url: `${REPO}/actions/runs/40700900804`, external_id: "" }), "40700900804");
  assert.equal(postingRunId({ details_url: `${REPO}/runs/122864732692`, external_id: "" }), null);
  assert.equal(postingRunId({ details_url: `${REPO}/runs/1`, external_id: "pr-merge-gate" }), null);
  assert.equal(postingRunId({ external_id: "pr-unblock:x:7:1 " }), null);
  assert.equal(postingRunId({}), null);
});
