// The red-main rule (owner decision 2026-10-20, docs/conventions/pr-pipeline/
// README.md "Red main"): expected values are the rule's own words, never the
// functions' output.
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  attribute,
  commitStatus,
  confirm,
  decide,
  failingChecks,
  firstParentRange,
  isRevert,
  plannedRevert,
  resolveRedMain,
} from "./red-main.mjs";

const job = (id, name, conclusion, failedSteps = ["Run tests"]) => ({
  id,
  name,
  conclusion,
  steps: failedSteps.map((step) => ({ name: step, conclusion: "failure" })),
});

test("a value outside the schema's range falls back to the default", () => {
  assert.deepEqual(
    resolveRedMain({ "dry-run": "no", "daily-cap": 11, "max-culprit-age-hours": 0, "confirm-wait-minutes": 46, remedy: "revert" }),
    { "dry-run": true, "daily-cap": 3, "max-culprit-age-hours": 24, "confirm-wait-minutes": 40, remedy: "rollback" },
  );
  assert.deepEqual(
    resolveRedMain({ "dry-run": false, "daily-cap": 0, "max-culprit-age-hours": 6, "confirm-wait-minutes": 0, remedy: "fail-forward" }),
    { "dry-run": false, "daily-cap": 0, "max-culprit-age-hours": 6, "confirm-wait-minutes": 0, remedy: "fail-forward" },
  );
});

test("the remedy defaults to rollback and takes rollback or fail-forward", () => {
  assert.equal(resolveRedMain({}).remedy, "rollback");
  assert.equal(resolveRedMain({ remedy: "rollback" }).remedy, "rollback");
  assert.equal(resolveRedMain({ remedy: "fail-forward" }).remedy, "fail-forward");
  assert.equal(resolveRedMain({ remedy: "Fail-Forward" }).remedy, "rollback");
});

test("a failed job is a check; a cancelled or timed-out job is not", () => {
  assert.deepEqual(
    failingChecks([job(1, "test-node", "failure"), job(2, "test-bash", "cancelled"), job(3, "test-python", "timed_out")]),
    ["test-node"],
  );
});

test("ci-status beside another failed job adds nothing; alone it is the check", () => {
  assert.deepEqual(failingChecks([job(1, "ci-status", "failure"), job(2, "lint-repo", "failure")]), ["lint-repo"]);
  assert.deepEqual(failingChecks([job(1, "ci-status", "failure")]), ["ci-status"]);
});

test("a hygiene gate is its own check, and the all-branches gitleaks gate counts against no merge", () => {
  const aggregatorOnly = job(7, "lint-repo", "failure", ["Aggregate hygiene results"]);
  const titled = (title) => ({ annotation_level: "failure", title });
  assert.deepEqual(failingChecks([aggregatorOnly], { 7: [titled("gitleaks failed")] }), []);
  assert.deepEqual(failingChecks([aggregatorOnly], { 7: [titled("typos failed"), titled("gitleaks failed")] }), [
    "lint-repo: typos failed",
  ]);
});

test("a failed job listing no failed step is a check of its own; the full list keeps the gitleaks excuse", () => {
  // The jobs API can answer a completed job with no steps or a cut list.
  const gitleaks = { 7: [{ annotation_level: "failure", title: "gitleaks failed" }] };
  const withSteps = (steps) => ({ id: 7, name: "lint-repo", conclusion: "failure", steps });
  assert.deepEqual(failingChecks([withSteps([])], gitleaks), ["lint-repo"]);
  assert.deepEqual(failingChecks([{ id: 7, name: "lint-repo", conclusion: "failure" }], gitleaks), ["lint-repo"]);
  assert.deepEqual(failingChecks([withSteps([{ name: "Set up job", conclusion: "success" }])], gitleaks), ["lint-repo"]);
  assert.deepEqual(
    failingChecks([withSteps([{ name: "Set up job", conclusion: "success" }, { name: "Aggregate hygiene results", conclusion: "failure" }])], gitleaks),
    [],
  );
  // A failed step beside the aggregator still charges the job.
  assert.deepEqual(
    failingChecks(
      [
        withSteps([
          { name: "Aggregate hygiene results", conclusion: "failure" },
          { name: "Test hygiene result aggregation", conclusion: "failure" },
        ]),
      ],
      gitleaks,
    ),
    ["lint-repo"],
  );
});

const attempt = (n, conclusion, checks) => ({ attempt: n, conclusion, checks });

test("confirmed red: the run fails and its one re-run fails again in the same job", () => {
  const verdict = confirm(attempt(1, "failure", ["test-node", "lint-repo"]), attempt(2, "failure", ["test-node"]));
  assert.equal(verdict.confirmed, true);
  assert.deepEqual(verdict.checks, ["test-node"]);
});

test("a re-run that passes, or one that never finished, is not a confirmed red", () => {
  assert.equal(confirm(attempt(1, "failure", ["test-node"]), attempt(2, "success", [])).confirmed, false);
  assert.equal(confirm(attempt(1, "failure", ["test-node"]), null).confirmed, false);
});

test("a re-run that fails only in another job is not a confirmed red", () => {
  assert.equal(confirm(attempt(1, "failure", ["test-node"]), attempt(2, "failure", ["test-bash"])).confirmed, false);
});

test("a cancelled run or a cancelled re-run never triggers", () => {
  assert.equal(confirm(attempt(1, "cancelled", ["test-node"]), attempt(2, "failure", ["test-node"])).confirmed, false);
  assert.equal(confirm(attempt(1, "failure", ["test-node"]), attempt(2, "cancelled", ["test-node"])).confirmed, false);
});

const sha = (c) => c.repeat(40);
const [BASE, A, B, H] = ["0", "a", "b", "f"].map(sha);

test("the range is the first-parent chain from the last green run to the failing head", () => {
  const commits = [
    { sha: A, parent: BASE },
    { sha: sha("e"), parent: A }, // a merged branch's commit, not on main's first-parent chain
    { sha: B, parent: A },
    { sha: H, parent: B },
  ];
  assert.deepEqual(firstParentRange(BASE, H, commits), [A, B, H]);
  assert.equal(firstParentRange(BASE, H, [{ sha: H, parent: B }]), null);
});

test("a range of one merge: that merge is the culprit, since its parent is the last green run", () => {
  assert.equal(attribute(BASE, [H], { [H]: "red" }).culprit, H);
});

test("a range of several: the one merge that fails where its parent passes is the culprit", () => {
  assert.equal(attribute(BASE, [A, B, H], { [A]: "red", [B]: "untested", [H]: "red" }).culprit, A);
});

test("a range whose oldest merge has no full run of its own pins no culprit, and names the merges to test", () => {
  const result = attribute(BASE, [A, B, H], { [A]: "untested", [B]: "untested", [H]: "red" });
  assert.equal(result.culprit, null);
  assert.deepEqual(result.untested, [A, B]);
});

test("two green-to-red transitions pin no culprit", () => {
  assert.equal(attribute(BASE, [A, B, H], { [A]: "red", [B]: "green", [H]: "red" }).culprit, null);
});

test("a merge that failed without a confirming re-run is no culprit", () => {
  assert.equal(attribute(BASE, [A, H], { [A]: "red-unconfirmed", [H]: "red" }).culprit, null);
});

test("a merge's own run is red only when confirmed in a check the head also fails", () => {
  const run = (latestChecks) => ({
    conclusion: "failure",
    first: attempt(1, "failure", ["test-node"]),
    latest: attempt(2, "failure", latestChecks),
  });
  assert.equal(commitStatus(run(["test-node"]), ["test-node"]), "red");
  assert.equal(commitStatus(run(["test-node"]), ["test-bash"]), "red-unconfirmed");
  assert.equal(commitStatus({ conclusion: "success" }, ["test-node"]), "green");
  assert.equal(commitStatus(undefined, ["test-node"]), "untested");
});

const NOW = "2026-10-20T12:00:00Z";
const LANES = "melodic-automation-lanes[bot]";
const CONFIG = resolveRedMain({});
const laneMerge = (over = {}) => ({
  sha: A,
  number: 101,
  enqueuer: LANES,
  message: "fix(x): y (#101)",
  labels: [],
  mergedAt: "2026-10-20T10:00:00Z",
  ...over,
});
const decideFor = (culprit, over = {}) =>
  decide({
    culprit,
    agentIdentity: LANES,
    config: CONFIG,
    now: NOW,
    revertsToday: 0,
    culpritDecided: false,
    platformFault: null,
    revertApplies: true,
    ...over,
  });

test("a pinned lane merge under every limit auto-reverts", () => {
  assert.deepEqual(decideFor(laneMerge()), { decision: "auto-revert", reasons: [] });
});

test("an owner merge never auto-reverts", () => {
  assert.equal(decideFor(laneMerge({ enqueuer: "kyle-sexton" })).decision, "human");
  assert.equal(decideFor(laneMerge({ enqueuer: "" })).decision, "human");
});

test("a revert is never reverted", () => {
  assert.equal(decideFor(laneMerge({ message: 'Revert "fix(x): y (#101)" (#102)' })).decision, "human");
  assert.equal(decideFor(laneMerge({ message: "revert: y (#102)\n\nThis reverts commit abcdef1." })).decision, "human");
  assert.equal(decideFor(laneMerge({ labels: ["auto-revert"] })).decision, "human");
  assert.equal(isRevert("feat: reverse the list (#103)"), false);
});

test("only a culprit merged under 24 hours ago auto-reverts", () => {
  assert.equal(decideFor(laneMerge({ mergedAt: "2026-10-19T12:30:00Z" })).decision, "auto-revert");
  assert.equal(decideFor(laneMerge({ mergedAt: "2026-10-19T12:00:00Z" })).decision, "human");
  assert.equal(decideFor(laneMerge({ mergedAt: "" })).decision, "human");
});

test("at most 3 auto-reverts a day", () => {
  assert.equal(decideFor(laneMerge(), { revertsToday: 2 }).decision, "auto-revert");
  assert.equal(decideFor(laneMerge(), { revertsToday: 3 }).decision, "human");
});

test("one auto-revert per culprit", () => {
  assert.equal(decideFor(laneMerge(), { culpritDecided: true }).decision, "human");
});

test("a suspected platform fault or a revert that does not apply goes to a person", () => {
  assert.equal(decideFor(laneMerge(), { platformFault: "canary record #9 is open" }).decision, "human");
  assert.equal(decideFor(laneMerge(), { revertApplies: false }).decision, "human");
  assert.equal(decideFor(laneMerge(), { revertApplies: null }).decision, "human");
});

test("under fail-forward even a lane merge under every limit goes to a person, named by the remedy", () => {
  const verdict = decideFor(laneMerge(), { config: resolveRedMain({ remedy: "fail-forward" }) });
  assert.equal(verdict.decision, "human");
  assert.equal(verdict.reasons.length, 1);
  assert.match(verdict.reasons[0], /fail-forward/);
});

test("a person's revert is a draft labeled needs-human; the bot's goes through the merge queue", () => {
  const human = plannedRevert(laneMerge(), "human", "https://example.test/run");
  assert.equal(human.draft, true);
  assert.deepEqual(human.labels, ["auto-revert", "needs-human"]);
  const bot = plannedRevert(laneMerge(), "auto-revert", "https://example.test/run");
  assert.equal(bot.draft, false);
  assert.equal(bot.command, `git revert --no-edit ${A}`);
  assert.equal(bot.title, "revert: fix(x): y");
  assert.match(bot.merge, /merge queue/);
});
