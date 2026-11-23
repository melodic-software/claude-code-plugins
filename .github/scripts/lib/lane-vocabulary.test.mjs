import assert from "node:assert/strict";
import { test } from "node:test";

import * as vocabulary from "./lane-vocabulary.mjs";

test("each name keeps the value GitHub and the lane config already use", () => {
  assert.deepEqual(
    {
      ACTIONS_BOT_ID: vocabulary.ACTIONS_BOT_ID,
      LANES_APP_LOGIN: vocabulary.LANES_APP_LOGIN,
      AGENT_READY: vocabulary.AGENT_READY,
      READY: vocabulary.READY,
      NEEDS_DECISION: vocabulary.NEEDS_DECISION,
      ATTENDED: vocabulary.ATTENDED,
      HOST_RUN: vocabulary.HOST_RUN,
      DO_NOT_MERGE: vocabulary.DO_NOT_MERGE,
      NEEDS_HUMAN: vocabulary.NEEDS_HUMAN,
      REFINE_MARKER: vocabulary.REFINE_MARKER,
    },
    {
      ACTIONS_BOT_ID: 41898282,
      LANES_APP_LOGIN: "melodic-automation-lanes[bot]",
      AGENT_READY: "agent-ready",
      READY: "status: ready",
      NEEDS_DECISION: "needs-owner-decision",
      ATTENDED: "attended",
      HOST_RUN: "host-run",
      DO_NOT_MERGE: "do-not-merge",
      NEEDS_HUMAN: "needs-human",
      REFINE_MARKER: "<!-- intake-triage refinement -->",
    },
  );
});

test("each caller keeps its own hold set", () => {
  assert.deepEqual(vocabulary.DISPATCH_HOLDS, ["do-not-merge", "needs-human"]);
  assert.deepEqual(vocabulary.FEEDBACK_HOLDS, ["do-not-merge"]);
  assert.deepEqual(vocabulary.SHARED_COPY_HOLDS, ["do-not-merge"]);
  assert.deepEqual(vocabulary.ARM_HOLDS, ["do-not-merge", "pr-verify-failed", "security: outside-actor"]);
  assert.deepEqual([...vocabulary.WIP_CAP_HOLDS], ["needs-human", "do-not-merge"]);
});

test("a caller cannot change a shared hold list for the others", () => {
  for (const name of ["DISPATCH_HOLDS", "FEEDBACK_HOLDS", "SHARED_COPY_HOLDS", "ARM_HOLDS"]) {
    assert.throws(() => vocabulary[name].push("x"), TypeError, name);
  }
});
