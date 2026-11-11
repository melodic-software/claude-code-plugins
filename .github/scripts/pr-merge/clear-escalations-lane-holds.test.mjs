// filterLaneHolds, which ci-status's human-gated and hold-lift steps run on
// the pull request's issue comments: a github-actions[bot] hold comment ending
// in a lane footer keeps the footer only when the run its binding names
// recorded it (lib/lane-binding.mjs); a legacy one keeps it while the cutoff
// is unset.
import assert from "node:assert/strict";
import { test } from "node:test";

import { bound, fakeActions, HEAD, laneRun, recordEntry, RUN } from "../lib/lane-binding.fixtures.mjs";
import { filterLaneHolds } from "./clear-escalations.mjs";

const ENV = { GITHUB_REPOSITORY: "o/r", PR_NUMBER: "7", GH_TOKEN: "t" };
const ACTIONS = { login: "github-actions[bot]", type: "Bot" };
const holdText = `<!-- claude-lane-hold lane=claude-security-review sha=${HEAD} criteria=critical-security -->\nHeld.\nseverity: CRITICAL`;
const BOUND = bound(holdText, { lane: "claude-security-review" });
const LEGACY = `${holdText}\n\nclaude-lane: claude-security-review`;
const comment = (body, id = 11, user = ACTIONS) => ({ id, user, body, created_at: "2026-11-01T10:00:00Z", updated_at: "2026-11-01T10:00:00Z" });
const entry = (overrides = {}) => recordEntry(BOUND, { lane: "claude-security-review", kind: "issue_comment", ...overrides });

const filter = async (comments, runs) => {
  let out = "";
  const actions = fakeActions(runs);
  const code = await filterLaneHolds({ env: ENV, input: JSON.stringify(comments), write: (text) => (out += text), laneReads: actions });
  return { code, out: code === 0 ? JSON.parse(out) : out, calls: actions.calls };
};

test("a bound hold its run recorded keeps its footer and loses its binding", async () => {
  const { code, out } = await filter([comment(BOUND)], { [RUN]: laneRun([entry()], { lane: "claude-security-review" }) });
  assert.equal(code, 0);
  assert.equal(out[0].body, LEGACY);
  assert.match(out[0].body.split("\n").at(-3), /^severity: CRITICAL$/);
});

test("a re-run attempt's record counts", async () => {
  const { out } = await filter([comment(BOUND)], { [RUN]: laneRun([entry()], { lane: "claude-security-review", attempt: 3 }) });
  assert.equal(out[0].body, LEGACY);
});

test("a bound hold no record lists, or whose run is another workflow, reads as a hold with no footer", async () => {
  for (const run of [laneRun([entry({ id: 12 })], { lane: "claude-security-review" }), { ...laneRun([entry()], { lane: "claude-security-review" }), path: ".github/workflows/x.yml" }]) {
    const { code, out } = await filter([comment(BOUND)], { [RUN]: run });
    assert.equal(code, 0);
    assert.equal(out[0].body, holdText);
  }
});

test("a legacy hold, a claude[bot] hold and a comment with no hold pass unchanged with no read", async () => {
  const comments = [comment(LEGACY), comment(BOUND, 12, { login: "claude[bot]", type: "Bot" }), comment(`Note.\n\nclaude-lane: claude-review`, 13)];
  const { out, calls } = await filter(comments, {});
  assert.deepEqual(out, comments);
  assert.deepEqual(calls, []);
});

test("a run that does not read fails closed and prints nothing", async () => {
  const { code, out } = await filter([comment(BOUND)], {});
  assert.equal(code, 1);
  assert.equal(out, "");
});

test("each run is read once for many comments", async () => {
  const second = bound(`${holdText}\nagain`, { lane: "claude-security-review" });
  const { calls } = await filter([comment(BOUND), comment(second, 12)], { [RUN]: laneRun([entry(), recordEntry(second, { lane: "claude-security-review", kind: "issue_comment", id: 12 })], { lane: "claude-security-review" }) });
  assert.equal(calls.filter(([kind]) => kind === "run").length, 1);
});
