// clear-escalations.mjs and enable-auto-merge.mjs read a review lane's hold
// from the issue timeline: a hold comment counts only when its lane's run
// recorded it (lib/lane-binding.mjs), a legacy one while the cutoff is unset.
import assert from "node:assert/strict";
import { test } from "node:test";

import { bound, fakeActions, HEAD, recordEntry, RUN } from "../lib/lane-binding.fixtures.mjs";
import { laneChecker } from "../lib/lane-binding.mjs";
import { holdsSince, laneTimeline, restLaneChecker } from "./clear-escalations.mjs";
import { liftBlocked } from "./enable-auto-merge.mjs";

const PR = 7;
const CODE = ".github/workflows/pr-review-hosted.yml";
const ACTIONS = { login: "github-actions[bot]", id: 41898282, type: "Bot" };
const HOLD = `<!-- claude-lane-hold lane=claude-review sha=${HEAD} criteria=real-charge -->`;
const GENUINE = bound(HOLD);
const FORGED = bound(`${HOLD}\nforged`);
const LEGACY = `${HOLD}\n\nclaude-lane: claude-review`;
const AT = "2026-11-11T10:00:00Z";
const comment = (id, body) => ({ event: "commented", id, user: ACTIONS, body, created_at: AT, updated_at: AT });
const runs = () => ({ [RUN]: { path: CODE, artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [recordEntry(GENUINE, { kind: "issue_comment", id: 21 })] }] } });
// A check-trusted-trigger client serving one timeline page.
const github = (timeline) => async (_method, path) => {
  if (path.includes("/timeline")) {
    return timeline;
  }
  throw new Error(`unexpected read ${path}`);
};

test("clear-escalations reads only a bound or legacy hold comment as a review-lane hold", async () => {
  const labeled = { event: "labeled", actor: ACTIONS, label: { name: "needs-human" }, created_at: AT };
  const actions = fakeActions(runs());
  const check = restLaneChecker({ read: async () => assert.fail("no REST read: laneReads serves them"), repo: "o/r", pr: PR, laneReads: actions });
  const timeline = await laneTimeline(github([labeled, comment(21, GENUINE), comment(22, FORGED), comment(23, LEGACY)]), "o/r", PR, check);
  assert.deepEqual(timeline[0], labeled);
  assert.deepEqual(holdsSince(timeline, -Infinity).shas, [HEAD, HEAD]);
  assert.equal(timeline[1].body, LEGACY);
});

test("clear-escalations fails the read when a hold's run does not read", async () => {
  const check = restLaneChecker({ read: async () => [], repo: "o/r", pr: PR, laneReads: fakeActions({}) });
  await assert.rejects(laneTimeline(github([comment(21, GENUINE)]), "o/r", PR, check), /Not Found/);
});

test("enable-auto-merge keeps the label for a bound hold on the head, and not for a forged one", async () => {
  const options = { label: "needs-human", login: "melodic-automation-lanes[bot]", humans: new Set(), head: HEAD };
  const check = () => laneChecker({ pr: PR, ...fakeActions(runs()) });
  assert.match(await liftBlocked(github([comment(21, GENUINE)]), "o/r", PR, options, check()), /a review lane holds head/);
  assert.doesNotMatch(String(await liftBlocked(github([comment(22, FORGED)]), "o/r", PR, options, check())), /a review lane holds head/);
});
