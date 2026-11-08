// The job if: gates that keep a pipeline workflow from starting a runner that
// could only skip or fail: pr-feedback-dispatch.yml on a review run GitHub
// skipped (a draft) or cancelled (a newer push superseded it). And the gates
// of pr-unblock.yml's address-feedback and review-dependency jobs, which a
// skipped subscription call or a forged model-call output must not turn.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { isVerdictName } from "../pr-verify/write-verdict.mjs";
import { laneBranchIssue } from "../work-resolve-issue/report-outcome.mjs";
import { MAX_THREADS } from "./adjudicate-feedback.mjs";
import { DEFERRED_RECORD } from "./feedback-dispatch.mjs";

// A job's folded `if: >-` scalar, joined the way YAML folds it.
function jobIf(file, job) {
  const text = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
  const block = new RegExp(`\\n  ${job}:\\n(?: {4}#.*\\n)*    if: >-\\n((?: {6}.*\\n)+)`).exec(text);
  assert.ok(block, `${file}: job ${job} has a folded if:`);
  return block[1]
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .join(" ");
}

// A job's block of the workflow text: from `  <job>:` to the next job.
function jobBlock(file, job) {
  const lines = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8").split("\n");
  const start = lines.indexOf(`  ${job}:`);
  assert.notEqual(start, -1, `${file}: job ${job}`);
  const end = lines.findIndex((line, i) => i > start && /^ {2}[a-z][\w-]*:$/.test(line));
  return lines.slice(start + 1, end === -1 ? undefined : end);
}

// The if: at lines[at], indented by `indent` spaces, single-line or folded.
function ifAt(lines, at, indent) {
  const gate = lines[at].slice(indent + "if: ".length);
  if (gate !== ">-") {
    return gate;
  }
  const folded = [];
  for (const line of lines.slice(at + 1)) {
    if (!line.startsWith(" ".repeat(indent + 2))) break;
    folded.push(line.trim());
  }
  return folded.join(" ");
}

// A job's if:, single-line or folded, and its needs, as written.
function jobGate(file, job) {
  const block = jobBlock(file, job);
  const at = block.findIndex((line) => /^ {4}if: /.test(line));
  assert.notEqual(at, -1, `${file}: job ${job} has an if:`);
  const gate = ifAt(block, at, 4);
  const needsLine = block.find((line) => /^ {4}needs: /.test(line)) ?? "    needs: []";
  const needs = needsLine.slice("    needs: ".length).replace(/^\[|\]$/g, "").split(",").map((name) => name.trim()).filter(Boolean);
  return { gate, needs };
}

// Evaluates the expression with each context reference replaced by its value.
// Covers only the operators and functions these gates use (&&, ||, ==, !=, !,
// format('{0}', x), startsWith(x, 'y')); GitHub compares strings
// case-insensitively, and every value here is already in the case the gate
// names.
function evaluate(expression, context) {
  let body = expression.replace(/^\$\{\{([\s\S]*)\}\}$/, "$1").replaceAll("!cancelled()", "true");
  for (const name of Object.keys(context).sort((a, b) => b.length - a.length)) {
    body = body.replaceAll(name, JSON.stringify(context[name]));
  }
  body = body.replace(/format\('\{0\}', ([^)]*)\)/g, "String($1)");
  body = body.replace(/startsWith\(([^,]*), ('[^']*')\)/g, "String($1).startsWith($2)");
  // String literals, a workflow path among them, hold no reference.
  assert.doesNotMatch(body.replace(/'[^']*'|"[^"]*"/g, "''"), /[A-Za-z_][\w-]*\.[\w.-]+/, `an unresolved context reference in ${body}`);
  return Function(`return (${body});`)();
}

const LANE_BRANCH = "work-resolve-issue/issue-12-345-1";
// The review-comment relay clause's one term no other case sets, so a review,
// verify, sweep or pr-merge case below also shows the relay clause admits none.
const RELAY_ON = { "github.event.workflow_run.actor.type": "User" };

test("pr-feedback-dispatch.yml starts no runner for a skipped or cancelled review run", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "dispatch");
  const runs = (conclusion, event = "pull_request", posted = "", branch = LANE_BRANCH, passed = "", rerun = {}) =>
    evaluate(gate, {
      "github.ref": "refs/heads/main",
      "github.repository": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.path": ".github/workflows/pr-review-hosted.yml",
      "github.event.workflow_run.event": event,
      "github.event.workflow_run.repository.full_name": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.head_repository.full_name": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.head_branch": branch,
      "github.event.workflow_run.conclusion": conclusion,
      "needs.post-verify-notes.outputs.head-sha": posted,
      "needs.post-verify-notes.outputs.pass-head-sha": passed,
      "github.run_attempt": "1",
      "github.triggering_actor": "a-person",
      ...RELAY_ON,
      ...rerun,
    });
  assert.equal(runs("skipped"), false);
  assert.equal(runs("cancelled"), false);
  for (const conclusion of ["success", "failure"]) {
    assert.equal(runs(conclusion), true, conclusion);
  }
  // A pr-verify run dispatches only once its notes are on the PR.
  assert.equal(runs("success", "workflow_run"), false);
  assert.equal(runs("success", "workflow_run", "a".repeat(40)), true);
  // A pr-verify run's branch is main, and its notes still dispatch.
  assert.equal(runs("success", "workflow_run", "a".repeat(40), "main"), true);
  // A pass dispatches only once its job found a stale fail-note thread.
  assert.equal(runs("success", "workflow_run", "", "main"), false);
  assert.equal(runs("success", "workflow_run", "", "main", "a".repeat(40)), true);
  // The reconciler's re-run of a verdict the kill switch stopped posts the
  // notes but dispatches nothing: the gate trusts that dispatcher only at
  // attempt 1 or re-run by a listed human.
  const bot = { "github.run_attempt": "2", "github.triggering_actor": "github-actions[bot]" };
  assert.equal(runs("success", "workflow_run", "a".repeat(40), "main", "", bot), false);
  assert.equal(runs("success", "workflow_run", "", "main", "a".repeat(40), bot), false);
  assert.equal(runs("success", "workflow_run", "a".repeat(40), "main", "", { "github.run_attempt": "2" }), true);
});

test("pr-feedback-dispatch.yml starts no runner for a review run off a lane branch", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "dispatch");
  const prefix = /startsWith\(github\.event\.workflow_run\.head_branch, '([^']+)'\)/.exec(gate)?.[1];
  assert.ok(prefix, "the dispatch gate checks the head branch");
  const runs = (branch) =>
    evaluate(gate, {
      "github.ref": "refs/heads/main",
      "github.repository": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.path": ".github/workflows/pr-review-hosted.yml",
      "github.event.workflow_run.event": "pull_request",
      "github.event.workflow_run.repository.full_name": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.head_repository.full_name": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.head_branch": branch,
      "github.event.workflow_run.conclusion": "success",
      "needs.post-verify-notes.outputs.head-sha": "",
      "needs.post-verify-notes.outputs.pass-head-sha": "",
      "github.run_attempt": "1",
      "github.triggering_actor": "a-person",
      ...RELAY_ON,
    });
  // Every branch the issue lane opens a PR from passes; a rename of the lane
  // branch fails here instead of silently stopping dispatches.
  assert.equal(laneBranchIssue(LANE_BRANCH), 12);
  assert.ok(LANE_BRANCH.startsWith(prefix), `${LANE_BRANCH} starts with ${prefix}`);
  assert.equal(laneBranchIssue(`x${LANE_BRANCH}`), null);
  assert.equal(runs(LANE_BRANCH), true);
  for (const branch of ["feat/x", "release/plugins", "dependabot/npm/x", "work-resolve-issue"]) {
    assert.equal(laneBranchIssue(branch), null, branch);
    assert.equal(runs(branch), false, branch);
  }
});

test("pr-feedback-dispatch.yml sweeps only after a scheduled pr-unblock-dispatch.yml run on main of this repository", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "dispatch");
  const repo = "melodic-software/claude-code-plugins";
  const runs = (overrides = {}) =>
    evaluate(gate, {
      "github.ref": "refs/heads/main",
      "github.repository": repo,
      "github.event.workflow_run.path": ".github/workflows/pr-unblock-dispatch.yml",
      "github.event.workflow_run.event": "schedule",
      "github.event.workflow_run.repository.full_name": repo,
      "github.event.workflow_run.head_repository.full_name": repo,
      "github.event.workflow_run.head_branch": "main",
      "github.event.workflow_run.conclusion": "success",
      "needs.post-verify-notes.outputs.head-sha": "",
      "needs.post-verify-notes.outputs.pass-head-sha": "",
      "github.run_attempt": "1",
      "github.triggering_actor": "a-person",
      ...RELAY_ON,
      ...overrides,
    });
  assert.equal(runs(), true);
  assert.equal(runs({ "github.event.workflow_run.conclusion": "failure" }), true, "a failed tick still sweeps");
  for (const [label, overrides] of [
    ["a push to main", { "github.event.workflow_run.event": "push" }],
    ["a hand-started tick", { "github.event.workflow_run.event": "workflow_dispatch" }],
    ["a pull request's refine run", { "github.event.workflow_run.event": "pull_request_target", "github.event.workflow_run.head_branch": "feat/x" }],
    ["another branch", { "github.event.workflow_run.head_branch": "feat/x" }],
    ["another repository", { "github.event.workflow_run.repository.full_name": "fork/claude-code-plugins" }],
    ["another workflow's schedule", { "github.event.workflow_run.path": ".github/workflows/maintenance-reconcile-lost-runs.yml" }],
  ]) {
    assert.equal(runs(overrides), false, label);
  }
});

test("pr-feedback-dispatch.yml dispatches for a relayed review comment only from a person on a lane branch of this repository", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "dispatch");
  const repo = "melodic-software/claude-code-plugins";
  const runs = (overrides = {}) =>
    evaluate(gate, {
      "github.ref": "refs/heads/main",
      "github.repository": repo,
      "github.event.workflow_run.path": ".github/workflows/pr-review-comment-relay.yml",
      "github.event.workflow_run.event": "pull_request_review_comment",
      "github.event.workflow_run.repository.full_name": repo,
      "github.event.workflow_run.head_repository.full_name": repo,
      "github.event.workflow_run.head_branch": LANE_BRANCH,
      "github.event.workflow_run.conclusion": "success",
      "needs.post-verify-notes.outputs.head-sha": "",
      "needs.post-verify-notes.outputs.pass-head-sha": "",
      "github.run_attempt": "1",
      "github.triggering_actor": "a-person",
      ...RELAY_ON,
      ...overrides,
    });
  assert.equal(runs(), true);
  for (const [label, overrides] of [
    ["a relay run its own condition skipped", { "github.event.workflow_run.conclusion": "skipped" }],
    ["a relay run that failed", { "github.event.workflow_run.conclusion": "failure" }],
    // A pull_request event is the review clause's, which the script checks by path.
    ["a relay run on another event", { "github.event.workflow_run.event": "pull_request_target" }],
    ["a review-comment run of another workflow", { "github.event.workflow_run.path": ".github/workflows/copy.yml" }],
    ["a fork's PR", { "github.event.workflow_run.head_repository.full_name": "fork/claude-code-plugins" }],
    ["another repository", { "github.event.workflow_run.repository.full_name": "fork/claude-code-plugins" }],
    ["a branch the lanes App opens no PR from", { "github.event.workflow_run.head_branch": "feat/x" }],
    ["a bot's comment", { "github.event.workflow_run.actor.type": "Bot" }],
    ["a run off main", { "github.ref": "refs/heads/feat/x" }],
  ]) {
    assert.equal(runs(overrides), false, label);
  }
});

// The relay is listed by the name its file gives, and holds nothing a
// PR-controlled copy could use: no permission, no checkout, no secret, and no
// event field in a step (only the job's condition reads the event).
test("pr-review-comment-relay.yml is a workflow_run upstream and reaches no token, secret or event text in a step", () => {
  const relay = readFileSync(new URL("../../workflows/pr-review-comment-relay.yml", import.meta.url), "utf8");
  const dispatcher = readFileSync(new URL("../../workflows/pr-feedback-dispatch.yml", import.meta.url), "utf8");
  assert.equal(/^name: (.+)$/m.exec(relay)?.[1], "PR Review Comment Relay");
  const upstreams = dispatcher.match(/\n    workflows: \[([^\]]*)\]\n/)[1].split(",").map((name) => name.trim());
  assert.ok(upstreams.includes("PR Review Comment Relay"));
  assert.match(relay, /\non:\n  pull_request_review_comment:\n    types: \[created\]\n\npermissions: \{\}\n/);
  const steps = relay.slice(relay.indexOf("    steps:"));
  assert.doesNotMatch(relay, /secrets\.|actions\/checkout|permissions: (?!\{\})/);
  assert.doesNotMatch(steps, /github\.event|\$\{\{/);
});

test("pr-review-comment-relay.yml starts a runner only for a person's comment on a lane branch of this repository", () => {
  const gate = jobIf("pr-review-comment-relay.yml", "relay");
  const repo = "melodic-software/claude-code-plugins";
  const runs = (o = {}) =>
    evaluate(gate, {
      "github.repository": repo,
      "github.event.comment.user.type": "User",
      "github.event.pull_request.head.repo.full_name": repo,
      "github.event.pull_request.head.ref": LANE_BRANCH,
      ...o,
    });
  assert.equal(runs(), true);
  // The lanes App's own replies (publish-feedback, report-escalation) and any
  // review bot's comments are Bot accounts: no relay, so no dispatcher loop.
  assert.equal(runs({ "github.event.comment.user.type": "Bot" }), false);
  assert.equal(runs({ "github.event.pull_request.head.repo.full_name": "fork/repo" }), false);
  assert.equal(runs({ "github.event.pull_request.head.ref": "feat/x" }), false);
});

// The relay's round passes the dispatch job's kill switch and upstream status
// checks like every other upstream: the dispatch step runs behind both.
test("pr-feedback-dispatch.yml dispatches only behind the kill switch, for a relayed round too", () => {
  const block = jobBlock("pr-feedback-dispatch.yml", "dispatch");
  const at = block.findIndex((line) => line.trim() === "- name: Dispatch address-feedback");
  assert.notEqual(at, -1);
  const gate = ifAt(block, block.findIndex((line, i) => i > at && /^ {8}if: /.test(line)), 8);
  assert.match(gate, /steps\.kill\.outputs\.proceed == 'true'/);
});

// A needs-human unlabel reaches pr-feedback-dispatch.yml only through this
// run's completion, so dropping the type strands a head the human gate skipped.
test("pr-merge.yml wakes on a pull request's unlabeled event", () => {
  const text = readFileSync(new URL("../../workflows/pr-merge.yml", import.meta.url), "utf8");
  assert.match(text, /\n {2}pull_request_target:.*\n {4}types: \[unlabeled\]\n/);
});

test("pr-feedback-dispatch.yml decides a lane branch's head again after a pull_request_target run of pr-merge.yml, whatever its conclusion", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "dispatch");
  const repo = "melodic-software/claude-code-plugins";
  const runs = (overrides = {}) =>
    evaluate(gate, {
      "github.ref": "refs/heads/main",
      "github.repository": repo,
      "github.event.workflow_run.path": ".github/workflows/pr-merge.yml",
      "github.event.workflow_run.event": "pull_request_target",
      "github.event.workflow_run.repository.full_name": repo,
      "github.event.workflow_run.head_repository.full_name": repo,
      "github.event.workflow_run.head_branch": LANE_BRANCH,
      "github.event.workflow_run.conclusion": "skipped",
      "needs.post-verify-notes.outputs.head-sha": "",
      "needs.post-verify-notes.outputs.pass-head-sha": "",
      "github.run_attempt": "1",
      "github.triggering_actor": "a-person",
      ...RELAY_ON,
      ...overrides,
    });
  assert.equal(runs(), true, "the lanes App's own unlabel skips pr-merge's job and still counts");
  assert.equal(runs({ "github.event.workflow_run.conclusion": "success" }), true);
  for (const [label, overrides] of [
    ["pr-merge's schedule", { "github.event.workflow_run.event": "schedule", "github.event.workflow_run.head_branch": "main" }],
    ["a hand-started pr-merge run", { "github.event.workflow_run.event": "workflow_dispatch" }],
    ["a branch the lanes App opens no PR from", { "github.event.workflow_run.head_branch": "feat/x" }],
    ["a fork's PR", { "github.event.workflow_run.head_repository.full_name": "fork/claude-code-plugins" }],
    ["another workflow's pull_request_target run", { "github.event.workflow_run.path": ".github/workflows/intake-reenter.yml" }],
  ]) {
    assert.equal(runs(overrides), false, label);
  }
  const text = readFileSync(new URL("../../workflows/pr-feedback-dispatch.yml", import.meta.url), "utf8");
  assert.match(text, /\n    workflows: \[[^\]]*\bPR Merge\b[^\]]*\]\n/, "PR Merge is a workflow_run upstream");
});

test("pr-feedback-dispatch.yml posts verifier notes only for a pr-verify run of main", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "post-verify-notes");
  const repo = "melodic-software/claude-code-plugins";
  const runs = (overrides = {}) =>
    evaluate(gate, {
      "github.ref": "refs/heads/main",
      "github.repository": repo,
      "github.event.workflow_run.path": ".github/workflows/pr-verify.yml",
      "github.event.workflow_run.event": "workflow_run",
      "github.event.workflow_run.head_branch": "main",
      "github.event.workflow_run.conclusion": "success",
      "github.event.workflow_run.repository.full_name": repo,
      "github.event.workflow_run.head_repository.full_name": repo,
      ...overrides,
    });
  assert.equal(runs(), true);
  assert.equal(runs({ "github.event.workflow_run.path": ".github/workflows/pr-review-hosted.yml" }), false);
  assert.equal(runs({ "github.event.workflow_run.event": "pull_request" }), false);
  assert.equal(runs({ "github.event.workflow_run.head_branch": "feat/x" }), false);
  assert.equal(runs({ "github.event.workflow_run.head_repository.full_name": "fork/repo" }), false);
  // A skipped pr-verify run judged nothing and uploaded no verdict.
  assert.equal(runs({ "github.event.workflow_run.conclusion": "skipped" }), false);
  for (const conclusion of ["success", "failure", "cancelled"]) {
    assert.equal(runs({ "github.event.workflow_run.conclusion": conclusion }), true, conclusion);
  }
});

// Every same-repository PR's completed review re-runs its head's ci-status,
// whatever the branch: ci-status needs both review lanes on the head.
test("pr-feedback-dispatch.yml re-runs ci-status for a completed review run of a same-repository PR only", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "rerun-ci-status");
  const repo = "melodic-software/claude-code-plugins";
  const runs = (overrides = {}) =>
    evaluate(gate, {
      "github.ref": "refs/heads/main",
      "github.repository": repo,
      "github.event.workflow_run.path": ".github/workflows/pr-review-hosted.yml",
      "github.event.workflow_run.event": "pull_request",
      "github.event.workflow_run.conclusion": "success",
      "github.event.workflow_run.repository.full_name": repo,
      "github.event.workflow_run.head_repository.full_name": repo,
      // Not gated on a lanes App branch: a person's PR needs its ci-status re-run too.
      "github.event.workflow_run.head_branch": "feat/x",
      ...overrides,
    });
  assert.equal(runs(), true);
  assert.equal(runs({ "github.event.workflow_run.path": ".github/workflows/pr-review-security-hosted.yml" }), true);
  for (const conclusion of ["failure", "cancelled", "timed_out"]) {
    assert.equal(runs({ "github.event.workflow_run.conclusion": conclusion }), true, conclusion);
  }
  // A draft's review run is skipped: it reviewed nothing.
  assert.equal(runs({ "github.event.workflow_run.conclusion": "skipped" }), false);
  assert.equal(runs({ "github.event.workflow_run.path": ".github/workflows/pr-verify.yml" }), false);
  assert.equal(runs({ "github.event.workflow_run.event": "workflow_dispatch" }), false);
  assert.equal(runs({ "github.event.workflow_run.event": "push" }), false);
  assert.equal(runs({ "github.event.workflow_run.head_repository.full_name": "fork/repo" }), false);
  assert.equal(runs({ "github.ref": "refs/heads/feat/x" }), false);
});

// A relayed approval changes what ci-status reads, so it re-runs it too. A
// pr-unblock run does not: ci-status reads no pr-unblock/* status.
test("pr-feedback-dispatch.yml re-runs ci-status after a relayed review, not a pr-unblock dispatch on main", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "rerun-ci-status");
  const repo = "melodic-software/claude-code-plugins";
  const base = {
    "github.ref": "refs/heads/main",
    "github.repository": repo,
    "github.event.workflow_run.conclusion": "success",
    "github.event.workflow_run.repository.full_name": repo,
    "github.event.workflow_run.head_repository.full_name": repo,
  };
  assert.equal(
    evaluate(gate, {
      ...base,
      "github.event.workflow_run.path": ".github/workflows/pr-unblock.yml",
      "github.event.workflow_run.event": "workflow_dispatch",
      "github.event.workflow_run.head_branch": "main",
    }),
    false,
  );
  const review = (o = {}) =>
    evaluate(gate, {
      ...base,
      "github.event.workflow_run.path": ".github/workflows/pr-review-approved.yml",
      "github.event.workflow_run.event": "pull_request_review",
      "github.event.workflow_run.head_branch": "feat/x",
      ...o,
    });
  assert.equal(review(), true);
  // A review that is not an approval skips the relay's job, so its run is skipped.
  assert.equal(review({ "github.event.workflow_run.conclusion": "skipped" }), false);
  assert.equal(review({ "github.event.workflow_run.event": "pull_request" }), false);
  assert.equal(review({ "github.event.workflow_run.head_repository.full_name": "fork/repo" }), false);
  assert.equal(review({ "github.ref": "refs/heads/feat/x" }), false);
  const text = readFileSync(new URL("../../workflows/pr-feedback-dispatch.yml", import.meta.url), "utf8");
  const upstreams = text.match(/\n    workflows: \[([^\]]*)\]\n/)[1].split(",").map((name) => name.trim());
  assert.ok(upstreams.includes("PR Review Approved"), "PR Review Approved is a workflow_run upstream");
  assert.ok(!upstreams.includes("PR Unblock"), "PR Unblock is no workflow_run upstream");
});

// The relay starts a runner only for an approval of a same-repository PR.
test("pr-review-approved.yml relays only an approval of a same-repository PR, with no permission", () => {
  const gate = jobIf("pr-review-approved.yml", "relay");
  const repo = "melodic-software/claude-code-plugins";
  const runs = (o = {}) =>
    evaluate(gate, {
      "github.repository": repo,
      "github.event.review.state": "approved",
      "github.event.pull_request.head.repo.full_name": repo,
      ...o,
    });
  assert.equal(runs(), true);
  for (const state of ["commented", "changes_requested", "dismissed"]) {
    assert.equal(runs({ "github.event.review.state": state }), false, state);
  }
  assert.equal(runs({ "github.event.pull_request.head.repo.full_name": "fork/repo" }), false);
  const text = readFileSync(new URL("../../workflows/pr-review-approved.yml", import.meta.url), "utf8");
  assert.match(text, /\non:\n  pull_request_review:\n    types: \[submitted\]\n\npermissions: \{\}\n/);
});

const UNBLOCK = "pr-unblock.yml";
const JOBS = [
  "address-feedback-select",
  "address-feedback-not-run",
  "address-feedback",
  "address-feedback-handoff",
  "address-feedback-subscription",
  "address-feedback-subscription-handoff",
  "address-feedback-fallback",
  "apply-feedback-patch",
  "adjudicate-key-credit",
  "adjudicate-feedback",
  "publish-feedback",
];

// Run 39783964241's shape: an API-key run skips the subscription call, and a
// job that needs a skipped job and lacks !cancelled() (or always()) is skipped
// too, so the push and the reply would never run.
test("pr-unblock.yml: every address-feedback job after a model call starts its if: with !cancelled()", () => {
  const after = JOBS.filter((job) => jobGate(UNBLOCK, job).needs.some((need) => need === "address-feedback" || need === "address-feedback-subscription" || need === "address-feedback-fallback"));
  assert.deepEqual(after, ["address-feedback-handoff", "address-feedback-subscription", "address-feedback-subscription-handoff", "address-feedback-fallback", "apply-feedback-patch", "adjudicate-key-credit", "adjudicate-feedback", "publish-feedback"]);
  for (const job of [...after, "address-feedback", "address-feedback-not-run"]) {
    assert.match(jobGate(UNBLOCK, job).gate, /^\$\{\{ !cancelled\(\) && /, job);
  }
});

// The reply job decides on the select job's proceed alone: a hostile model
// job can forge a handoff, a neutral check or any output of its own, and the
// round still posts its marker, so the round cap holds.
test("pr-unblock.yml: publish-feedback runs exactly when the select job proceeded or listed stale fail notes, whatever a model call reports", () => {
  const { gate, needs } = jobGate(UNBLOCK, "publish-feedback");
  assert.deepEqual(needs, ["address-feedback-select", "address-feedback", "address-feedback-subscription", "address-feedback-fallback", "apply-feedback-patch", "adjudicate-feedback"]);
  // The evaluator refuses any reference left unset: the gate reads nothing else.
  for (const [proceed, resolveOnly, runs] of [
    ["true", "", true],
    ["", "true", true],
    ["false", "", false],
    ["", "", false],
  ]) {
    assert.equal(
      evaluate(gate, { "needs.address-feedback-select.outputs.proceed": proceed, "needs.address-feedback-select.outputs.resolve-only": resolveOnly }),
      runs,
      JSON.stringify([proceed, resolveOnly]),
    );
  }
});

// resolve-threads.mjs serves only a PR a listed person opened, and leaves
// open every thread a person wrote in, so a lanes App PR's round and a
// relayed person's reply start no resolve job and ask the broker for no token
// (#13580). A person's PR on a review-completion round runs as before.
test("pr-unblock.yml: resolve-feedback-threads starts no job on a PR no listed person opened or a relayed reply", () => {
  const { gate } = jobGate(UNBLOCK, "resolve-feedback-threads");
  const runs = (overrides = {}) =>
    evaluate(gate, {
      "needs.publish-feedback.result": "success",
      "needs.publish-feedback.outputs.skip-reason": "",
      "needs.address-feedback-select.outputs.person-opened": "true",
      "inputs.upstream-relay": "",
      ...overrides,
    });
  assert.equal(runs(), true, "a person's PR on a review-completion round");
  assert.equal(runs({ "needs.publish-feedback.outputs.skip-reason": "lane-stopped" }), true, "and on the reply script's own stop");
  assert.equal(runs({ "needs.address-feedback-select.outputs.person-opened": "false" }), false, "a lanes App PR");
  assert.equal(runs({ "needs.address-feedback-select.outputs.person-opened": "" }), false, "an unread author");
  assert.equal(runs({ "inputs.upstream-relay": "true" }), false, "a relayed person's reply");
  assert.equal(runs({ "needs.address-feedback-select.outputs.person-opened": "false", "inputs.upstream-relay": "true" }), false, "a relay on a lanes App PR");
  // The input feedback-dispatch.mjs sends on a relay round is declared, or
  // GitHub refuses the dispatch.
  assert.match(readFileSync(new URL(`../../workflows/${UNBLOCK}`, import.meta.url), "utf8"), /\n      upstream-relay:\n        description: .+\n        required: false\n        type: string\n        default: ""\n/);
});

// A pass-only round lists only stale fail-note threads: its select job's
// proceed stays empty, so no model job and no neutral check runs, and only
// resolve-only turns on the reply job.
test("pr-unblock.yml: a pass-only select uploads its context but never proceeds to a model", () => {
  const block = jobBlock(UNBLOCK, "address-feedback-select");
  const output = (key) => {
    const at = block.findIndex((line) => line.startsWith(`      ${key}: `));
    const first = block[at].slice(`      ${key}: `.length);
    if (first !== ">-") return first;
    const folded = [];
    for (const line of block.slice(at + 1)) {
      if (!line.startsWith("        ")) break;
      folded.push(line.trim());
    }
    return folded.join(" ");
  };
  const outputs = (upload, select) =>
    Object.fromEntries(
      ["proceed", "resolve-only"].map((key) => [
        key,
        evaluate(output(key), {
          "steps.upload.outcome": upload,
          "steps.slot.outputs.applies": "true",
          "steps.select.outputs.proceed": select.proceed ?? "",
          "steps.select.outputs.resolve-only": select.resolveOnly ?? "",
        }),
      ]),
    );
  assert.deepEqual(outputs("success", { proceed: "true" }), { proceed: "true", "resolve-only": "" });
  assert.deepEqual(outputs("success", { resolveOnly: "true" }), { proceed: "", "resolve-only": "true" });
  assert.deepEqual(outputs("skipped", {}), { proceed: "", "resolve-only": "" });
  // The context is scanned on the same condition and uploads only on the scan's clean output.
  const scan = block.findIndex((line) => line === "        id: scan-upload");
  assert.equal(ifAt(block, scan + 1, 8), "steps.select.outputs.proceed == 'true' || steps.select.outputs.resolve-only == 'true'");
  const upload = block.findIndex((line) => line === "        id: upload");
  assert.ok(scan > 0 && scan < upload);
  assert.equal(
    ifAt(block, upload + 1, 8),
    "(steps.select.outputs.proceed == 'true' || steps.select.outputs.resolve-only == 'true') && steps.scan-upload.outputs.clean == 'true'",
  );
});

// The post-hoc review of #9565: the job checked out, set up and staged on
// every round, though only an INCORRECT reply gives it work. Skipping it is
// fail-closed: an INCORRECT reply with no verdict escalates
// feedback-unadjudicated (adjudicate-feedback.mjs settleDisputes).
test("pr-unblock.yml: adjudicate-feedback runs on an INCORRECT reply from the leg that answered, whatever its patch", () => {
  const { gate } = jobGate(UNBLOCK, "adjudicate-feedback");
  // The answering leg: the fallback call when it ran, else the subscription
  // call when it ran, else the key call. Every other leg reports `other`.
  const runs = (proceed, subResult, replies, disputed = "true", other = "", fbResult = "skipped") => {
    const leg = fbResult !== "skipped" ? "fb" : subResult !== "skipped" ? "sub" : "key";
    return evaluate(gate, {
      "needs.address-feedback-select.outputs.proceed": proceed,
      "needs.address-feedback-fallback.result": fbResult,
      "needs.address-feedback-subscription.result": subResult,
      "needs.address-feedback-fallback.outputs.feedback-attempt": leg === "fb" ? replies : "",
      "needs.address-feedback-subscription.outputs.feedback-attempt": leg === "sub" ? replies : "",
      "needs.address-feedback.outputs.feedback-attempt": leg === "key" ? replies : "",
      "needs.address-feedback-fallback.outputs.feedback-disputed": leg === "fb" ? disputed : other,
      "needs.address-feedback-subscription.outputs.feedback-disputed": leg === "sub" ? disputed : other,
      "needs.address-feedback.outputs.feedback-disputed": leg === "key" ? disputed : other,
    });
  };
  assert.equal(runs("true", "skipped", "1"), true, "the key call's INCORRECT reply");
  assert.equal(runs("true", "success", "1"), true, "the subscription call's INCORRECT reply after a handoff");
  assert.equal(runs("true", "success", "1", "true", "", "success"), true, "the fallback call's INCORRECT reply after a second handoff");
  assert.equal(runs("true", "success", "1", "", "true", "success"), false, "an earlier leg's INCORRECT reply never counts once the fallback call ran");
  assert.equal(runs("true", "skipped", "1", ""), false, "replies with no INCORRECT one");
  assert.equal(runs("true", "success", "1", "", "true"), false, "the other leg's INCORRECT reply never counts");
  assert.equal(runs("true", "skipped", ""), false, "no replies");
  assert.equal(runs("false", "skipped", "1"), false, "a select job that did not proceed");
});

// prepare's contents reads go through request-budget.mjs, which records each
// reading under API_BUDGET_TOKEN; the job ends by logging them.
test("pr-unblock.yml: adjudicate-feedback logs the API budget its prepare step spends", () => {
  const block = jobBlock(UNBLOCK, "adjudicate-feedback").join("\n");
  assert.match(block, /\n {6}- name: Stage the disputed threads\n(?: {8}.*\n)*? {10}API_BUDGET_TOKEN: github-token\n/);
  assert.match(block, /\n {6}- name: Log the API budget at the end\n {8}if: always\(\)\n {8}continue-on-error: true\n(?: {8}.*\n)*? {8}uses: \.\/\.base\/\.github\/actions\/log-api-budget.*\n {8}with:\n {10}tokens: github-token\n/);
});

// adjudicate-feedback.mjs stages up to MAX_THREADS slots, and the job has one
// stage step, three judge legs (key, subscription, fallback) and one keep
// step per slot; a slot with no steps would read as unadjudicated with no
// error.
test("pr-unblock.yml: adjudicate-feedback judges every slot prepare stages, each with the same grants", () => {
  const steps = [];
  for (const line of jobBlock(UNBLOCK, "adjudicate-feedback")) {
    if (line.startsWith("      - ")) steps.push([]);
    steps.at(-1)?.push(line);
  }
  const field = (step, key) => step.find((line) => line.startsWith(`        ${key}: `))?.slice(`        ${key}: `.length);
  const nameOf = (step) => step[0].slice("      - name: ".length);
  const gateOf = (step) => ifAt(step, step.findIndex((line) => line.startsWith("        if: ")), 8);
  const slotOf = (step) => /\/adjudicate\/(\d+)$/.exec(step.find((line) => line.includes("SLOT_DIR:")) ?? "")?.[1];
  const judges = steps.filter((step) => /run-claude-cli@/.test(field(step, "uses") ?? ""));
  const slots = Array.from({ length: MAX_THREADS }, (_, n) => n);
  const legIds = (n) => [`judge-${n}`, `judge-${n}-subscription`, `judge-${n}-fallback`];
  assert.deepEqual(judges.map((step) => field(step, "id")), slots.flatMap(legIds));
  for (const n of slots) {
    const stage = steps.find((step) => nameOf(step) === `Stage disputed thread ${n}`);
    const [key, sub, fb] = legIds(n).map((id) => judges.find((step) => field(step, "id") === id));
    const keep = steps.find((step) => nameOf(step) === `Keep disputed thread ${n}'s verdict`);
    const counted = `fromJSON(steps.prepare.outputs.count || '0') > ${n}`;
    const any = "(steps.key.outputs.present == 'true' || steps.sub.outputs.present == 'true' || steps.fb.outputs.present == 'true')";
    assert.equal(gateOf(stage), `${any} && ${counted}`, `stage ${n}`);
    // Each leg runs on its credential call's present and the leg the slot's
    // next-leg call names; credential-legs.test.mjs drives these through
    // select-model-credential against the conditions before it.
    assert.equal(gateOf(key), `steps.key.outputs.present == 'true' && ${counted}`, `key leg ${n}`);
    assert.equal(gateOf(sub), `steps.sub.outputs.present == 'true' && ${counted} && steps.next-${n}.outputs.next-leg == 'subscription'`, `subscription leg ${n}`);
    assert.equal(gateOf(fb), `steps.fb.outputs.present == 'true' && ${counted} && steps.next-${n}-subscription.outputs.next-leg == 'fallback'`, `fallback leg ${n}`);
    assert.match(gateOf(keep), new RegExp(`^always\\(\\) && \\(steps\\.judge-${n}\\.outputs\\.structured-output-file != ''`), `keep ${n}`);
    assert.equal(slotOf(stage), String(n), `stage ${n} copies its own slot`);
    assert.equal(slotOf(keep), String(n), `keep ${n} writes its own slot`);
    // Each leg passes exactly one credential, the fallback-ready only on the subscription leg.
    const credentials = (step) => step.filter((line) => /^ {10}(?:api-key|subscription-token|fallback-token|fallback-ready): /.test(line)).map((line) => line.trim());
    assert.deepEqual(credentials(key), ["api-key: ${{ secrets.PR_UNBLOCK_CLAUDE_API_KEY }}"], `key leg ${n}`);
    assert.deepEqual(credentials(sub), ["subscription-token: ${{ secrets.PR_UNBLOCK_CLAUDE_CODE_OAUTH_TOKEN }}", "fallback-ready: ${{ steps.sub.outputs.fallback-ready }}"], `subscription leg ${n}`);
    assert.deepEqual(credentials(fb), ["fallback-token: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}"], `fallback leg ${n}`);
    // Every leg writes its own lane record.
    for (const leg of [key, sub, fb]) {
      const id = field(leg, "id");
      const record = steps.find((step) => /report-lane-outcome@/.test(field(step, "uses") ?? "") && gateOf(step) === `always() && steps.${id}.outcome != 'skipped'`);
      assert.ok(record, `${id} has a lane record`);
      assert.ok(record.some((line) => line === "          lane-id: adjudicate-feedback"), `${id} record lane-id`);
    }
  }
  const credentialLines = /^ {10}(?:api-key|subscription-token|fallback-token|fallback-ready): .*\n/gm;
  const withOf = (step) => step.slice(step.indexOf("        with:")).join("\n");
  for (const judge of judges.slice(1)) {
    assert.equal(withOf(judge).replace(credentialLines, ""), withOf(judges[0]).replace(credentialLines, ""), "every slot's model call has the same inputs and grants");
  }
  assert.match(withOf(judges[0]), /\n {10}allowed-tools: Read\(\.\/adjudicate\/\*\*\)\n/, "Read is allowed in the slot alone");
  assert.match(withOf(judges[0]), /\n {10}tools: Read\n/, "the judge's one tool is Read");
  const denied = withOf(judges[0]).match(/\n {10}disallowed-tools: \|\n((?: {12}.*\n)+)/)?.[1].trim().split(/\n\s*/) ?? [];
  for (const rule of ["Read(./.base/**)", "Read(/${{ runner.temp }}/**)", "Glob", "Grep", "mcp__*", "Bash", "WebFetch"]) {
    assert.ok(denied.includes(rule), `the judge denies ${rule}`);
  }
});

test("pr-unblock.yml: apply-feedback-patch runs only on a written patch with replies from the leg that answered, not after a skip or an empty patch", () => {
  const { gate } = jobGate(UNBLOCK, "apply-feedback-patch");
  const runs = (subResult, sub, first, replies = "1", fbResult = "skipped", fb = "") =>
    evaluate(gate, {
      "needs.address-feedback-fallback.result": fbResult,
      "needs.address-feedback-subscription.result": subResult,
      "needs.address-feedback-fallback.outputs.scan-patch-state": fb,
      "needs.address-feedback-subscription.outputs.scan-patch-state": sub,
      "needs.address-feedback.outputs.scan-patch-state": first,
      "needs.address-feedback-fallback.outputs.feedback-attempt": fbResult === "skipped" ? "" : replies,
      "needs.address-feedback-subscription.outputs.feedback-attempt": fbResult === "skipped" && subResult !== "skipped" ? replies : "",
      "needs.address-feedback.outputs.feedback-attempt": fbResult === "skipped" && subResult === "skipped" ? replies : "",
    });
  assert.equal(runs("skipped", "", "written"), true, "the key call's patch, its subscription call skipped");
  assert.equal(runs("success", "written", ""), true, "the subscription call's patch after a handoff");
  assert.equal(runs("success", "", "written"), false, "the key call's patch is not taken once the subscription call ran");
  assert.equal(runs("success", "", "", "1", "success", "written"), true, "the fallback call's patch after a second handoff");
  assert.equal(runs("success", "written", "", "1", "success", ""), false, "the subscription call's patch is not taken once the fallback call ran");
  assert.equal(runs("skipped", "", "written", ""), false, "a patch with no replies");
  assert.equal(runs("skipped", "", "empty"), false);
  assert.equal(runs("skipped", "", ""), false);
});

const DEPENDENCY_JOBS = [
  "review-dependency-select",
  "review-dependency-not-run",
  "review-dependency",
  "review-dependency-handoff",
  "review-dependency-subscription",
  "review-dependency-subscription-handoff",
  "review-dependency-fallback",
  "apply-dependency-patch",
  "apply-dependency-verdict",
];

// As for address-feedback: a job that needs a skipped subscription call and
// lacks !cancelled() is skipped too, so the push and the verdict would never run.
test("pr-unblock.yml: every review-dependency job after a model call starts its if: with !cancelled()", () => {
  const after = DEPENDENCY_JOBS.filter((job) => jobGate(UNBLOCK, job).needs.some((need) => need === "review-dependency" || need === "review-dependency-subscription" || need === "review-dependency-fallback"));
  assert.deepEqual(after, ["review-dependency-handoff", "review-dependency-subscription", "review-dependency-subscription-handoff", "review-dependency-fallback", "apply-dependency-patch", "apply-dependency-verdict"]);
  for (const job of [...after, "review-dependency", "review-dependency-not-run"]) {
    assert.match(jobGate(UNBLOCK, job).gate, /^\$\{\{ !cancelled\(\) && /, job);
  }
});

// The verdict job decides on the select job's proceed alone: a hostile model
// job can forge a handoff, a neutral check or any output of its own, and the
// round still posts its marker, so the round cap holds.
test("pr-unblock.yml: apply-dependency-verdict runs exactly when the select job proceeded, whatever a model call reports", () => {
  const { gate, needs } = jobGate(UNBLOCK, "apply-dependency-verdict");
  assert.deepEqual(needs, ["review-dependency-select", "review-dependency", "review-dependency-subscription", "review-dependency-fallback", "apply-dependency-patch"]);
  // The evaluator refuses any reference left unset: the gate reads nothing else.
  for (const [proceed, runs] of [["true", true], ["false", false], ["", false]]) {
    assert.equal(evaluate(gate, { "needs.review-dependency-select.outputs.proceed": proceed }), runs, JSON.stringify(proceed));
  }
});

// A select that does not proceed posts the review-dependency check neutral on
// the head it read, so dependency-dispatch.mjs does not send that head again.
test("pr-unblock.yml: review-dependency-not-run posts only when the select job decided not to proceed on a head it read", () => {
  const { gate, needs } = jobGate(UNBLOCK, "review-dependency-not-run");
  assert.deepEqual(needs, ["review-dependency-select"]);
  const runs = (proceed, head, activity = "review-dependency") =>
    evaluate(gate, {
      "inputs.activity": activity,
      "needs.review-dependency-select.outputs.proceed": proceed,
      "needs.review-dependency-select.outputs.head-sha": head,
    });
  assert.equal(runs("false", "a".repeat(40)), true);
  assert.equal(runs("true", "a".repeat(40)), false);
  assert.equal(runs("", ""), false, "a kill-switch stop reads no head");
  assert.equal(runs("false", ""), false);
  assert.equal(runs("false", "a".repeat(40), "fix-ci"), false);
});

test("pr-unblock.yml: apply-dependency-patch runs only on a written patch beside a fix verdict from the leg that answered", () => {
  const { gate } = jobGate(UNBLOCK, "apply-dependency-patch");
  const runs = (subResult, sub, first, fbResult = "skipped", fb = []) =>
    evaluate(gate, {
      "needs.review-dependency-fallback.result": fbResult,
      "needs.review-dependency-fallback.outputs.scan-patch-state": fb[0] ?? "",
      "needs.review-dependency-fallback.outputs.dependency-verdict": fb[1] ?? "",
      "needs.review-dependency-subscription.result": subResult,
      "needs.review-dependency-subscription.outputs.scan-patch-state": sub[0] ?? "",
      "needs.review-dependency-subscription.outputs.dependency-verdict": sub[1] ?? "",
      "needs.review-dependency.outputs.scan-patch-state": first[0] ?? "",
      "needs.review-dependency.outputs.dependency-verdict": first[1] ?? "",
    });
  assert.equal(runs("skipped", [], ["written", "fix"]), true, "the key call's fix, its subscription call skipped");
  assert.equal(runs("success", ["written", "fix"], []), true, "the subscription call's fix after a handoff");
  assert.equal(runs("success", [], ["written", "fix"]), false, "the key call's fix is not taken once the subscription call ran");
  assert.equal(runs("success", ["written", ""], ["written", "fix"]), false, "one leg's patch never pairs with the other's verdict");
  assert.equal(runs("success", [], [], "success", ["written", "fix"]), true, "the fallback call's fix after a second handoff");
  assert.equal(runs("success", ["written", "fix"], [], "success", []), false, "the subscription call's fix is not taken once the fallback call ran");
  for (const verdict of ["merge", "close", "escalate", ""]) assert.equal(runs("skipped", [], ["written", verdict]), false, verdict);
  assert.equal(runs("skipped", [], ["empty", "fix"]), false);
  assert.equal(runs("skipped", [], ["", "fix"]), false);
});

const CONFLICT_JOBS = [
  "resolve-conflicts-select",
  "resolve-conflicts-not-run",
  "resolve-conflicts",
  "resolve-conflicts-handoff",
  "resolve-conflicts-subscription",
  "resolve-conflicts-subscription-handoff",
  "resolve-conflicts-fallback",
  "apply-conflict-patch",
  "report-stop-status",
];

// As for review-dependency: a job that needs a skipped subscription call and
// lacks !cancelled() is skipped too, so a clean merge would never be pushed.
test("pr-unblock.yml: every resolve-conflicts job after the select job starts its if: with !cancelled()", () => {
  for (const job of CONFLICT_JOBS.slice(1)) {
    assert.match(jobGate(UNBLOCK, job).gate, /^\$\{\{ !cancelled\(\) && /, job);
  }
  assert.deepEqual(jobGate(UNBLOCK, "apply-conflict-patch").needs, ["resolve-conflicts-select", "resolve-conflicts", "resolve-conflicts-subscription", "resolve-conflicts-fallback"]);
});

// The push job decides on the select job's merge state, proceed and the
// answering leg's scanned patch state; a forged run-job output reaches none.
// The evaluator refuses any reference left unset, so the gate reads nothing else.
test("pr-unblock.yml: apply-conflict-patch runs on a clean merge or a conflicted one with the answering leg's patch, whatever else a model call reports", () => {
  const { gate } = jobGate(UNBLOCK, "apply-conflict-patch");
  const runs = (state, proceed, subResult = "skipped", sub = "", first = "", fbResult = "skipped", fb = "") =>
    evaluate(gate, {
      "needs.resolve-conflicts-select.outputs.merge-state": state,
      "needs.resolve-conflicts-select.outputs.proceed": proceed,
      "needs.resolve-conflicts-fallback.result": fbResult,
      "needs.resolve-conflicts-fallback.outputs.scan-patch-state": fb,
      "needs.resolve-conflicts-subscription.result": subResult,
      "needs.resolve-conflicts-subscription.outputs.scan-patch-state": sub,
      "needs.resolve-conflicts.outputs.scan-patch-state": first,
    });
  assert.equal(runs("clean", "false"), true);
  assert.equal(runs("conflicted", "true", "skipped", "", "written"), true);
  assert.equal(runs("conflicted", "true", "skipped", "", "empty"), true);
  assert.equal(runs("conflicted", "true", "success", "written"), true);
  assert.equal(runs("conflicted", "true", "success", "", "written"), false);
  assert.equal(runs("conflicted", "true", "success", "", "", "success", "written"), true, "the fallback call's patch");
  assert.equal(runs("conflicted", "true", "success", "written", "", "success", ""), false, "not the subscription call's once the fallback call ran");
  assert.equal(runs("escalate", "false", "skipped", "", "written"), false);
  assert.equal(runs("", "", "skipped", "", "written"), false, "a kill-switch stop");
  assert.equal(runs("conflicted", "true", "skipped", "", "garbage"), false);
});

// A reply or verdict job can stop after its activity's push job moved the
// head; a failing status on the head before the push leaves the PR's head
// with none, so ci-status passes and pr-merge arms over the stop.
test("pr-unblock.yml: report-stop-status posts on the commit the activity's push job pushed, else its select head", () => {
  const step = stepBlock(UNBLOCK, "report-stop-status", "Post the stop status");
  const at = step.indexOf("          HEAD_SHA: >-");
  assert.notEqual(at, -1, "the step folds HEAD_SHA");
  const end = step.findIndex((line, i) => i > at && !line.startsWith("            "));
  const expression = step
    .slice(at + 1, end)
    .map((line) => line.trim())
    .join(" ");
  const activities = [
    ["apply-conflict-patch", "resolve-conflicts-select"],
    ["apply-feedback-patch", "address-feedback-select"],
    ["apply-dependency-patch", "review-dependency-select"],
    ["apply-dependency-pin", "review-dependency-select"],
    [null, "fix-ci-context"],
    [null, "sync-shared-copies-select"],
  ];
  const block = jobBlock(UNBLOCK, "report-stop-status");
  const needs = block.slice(block.indexOf("    needs:") + 1, block.findIndex((line) => /^ {4}if: /.test(line))).map((line) => line.replace(/^ {6}- /, ""));
  const blank = {};
  for (const [push, select] of activities) {
    blank[`needs.${select}.outputs.head-sha`] = "";
    if (push) {
      blank[`needs.${push}.outputs.pushed-commit`] = "";
      assert.ok(needs.includes(push), `report-stop-status needs ${push}`);
    }
  }
  for (const [push, select] of activities) {
    const selected = { ...blank, [`needs.${select}.outputs.head-sha`]: "before" };
    assert.equal(evaluate(expression, selected), "before", `${select} with no push`);
    if (push) {
      assert.equal(evaluate(expression, { ...selected, [`needs.${push}.outputs.pushed-commit`]: "pushed" }), "pushed", `${push} over ${select}`);
    }
  }
});

test("pr-unblock.yml: the resolve-conflicts model calls run only when the select job found a conflicted merge", () => {
  const { gate, needs } = jobGate(UNBLOCK, "resolve-conflicts");
  assert.deepEqual(needs, ["resolve-conflicts-select"]);
  for (const [proceed, runs] of [["true", true], ["false", false], ["", false]]) {
    assert.equal(evaluate(gate, { "needs.resolve-conflicts-select.outputs.proceed": proceed }), runs, JSON.stringify(proceed));
  }
});

const FIX_CI_JOBS = [
  "fix-ci-context",
  "fix-ci",
  "fix-ci-handoff",
  "fix-ci-subscription",
  "fix-ci-subscription-handoff",
  "fix-ci-fallback",
  "apply-patch",
  "fix-ci-rung-up",
  "fix-ci-rung-up-handoff",
  "fix-ci-rung-up-subscription",
  "fix-ci-rung-up-subscription-handoff",
  "fix-ci-rung-up-fallback",
  "apply-patch-rung-up",
  "fix-ci-unreported",
];
const FIX_CI_CALLS = ["fix-ci", "fix-ci-subscription", "fix-ci-fallback", "fix-ci-rung-up", "fix-ci-rung-up-subscription", "fix-ci-rung-up-fallback"];

// As for address-feedback: a job that needs a skipped call and lacks
// !cancelled() is skipped too, so the fallback, the push and the unreported
// post would never run.
test("pr-unblock.yml: every fix-ci job after a model call starts its if: with !cancelled()", () => {
  const after = FIX_CI_JOBS.filter((job) => jobGate(UNBLOCK, job).needs.some((need) => FIX_CI_CALLS.includes(need)));
  assert.deepEqual(after, [
    "fix-ci-handoff",
    "fix-ci-subscription",
    "fix-ci-subscription-handoff",
    "fix-ci-fallback",
    "apply-patch",
    "fix-ci-rung-up-handoff",
    "fix-ci-rung-up-subscription",
    "fix-ci-rung-up-subscription-handoff",
    "fix-ci-rung-up-fallback",
    "apply-patch-rung-up",
    "fix-ci-unreported",
  ]);
  for (const job of after) assert.match(jobGate(UNBLOCK, job).gate, /^\$\{\{ !cancelled\(\) && /, job);
});

// A hostile model job can forge handed-off, lane-class, credential-present or
// any output of its own. The fallback calls start on the handoff jobs' reads,
// and the unreported post on fix-ci-context alone, so no forged output turns them.
test("pr-unblock.yml: fix-ci's fallback calls and unreported post decide on base jobs alone, whatever a model call reports", () => {
  const forged = /needs\.fix-ci(?:-rung-up)?(?:-subscription|-fallback)?\.outputs\./;
  for (const job of [
    "fix-ci-handoff",
    "fix-ci-subscription",
    "fix-ci-subscription-handoff",
    "fix-ci-fallback",
    "fix-ci-rung-up-handoff",
    "fix-ci-rung-up-subscription",
    "fix-ci-rung-up-subscription-handoff",
    "fix-ci-rung-up-fallback",
    "fix-ci-unreported",
  ]) {
    assert.doesNotMatch(jobGate(UNBLOCK, job).gate, forged, job);
  }
  // The evaluator refuses any reference left unset: each gate reads nothing else.
  const sub = (posted, proceed = "true") =>
    evaluate(jobGate(UNBLOCK, "fix-ci-subscription").gate, { "needs.fix-ci-context.outputs.proceed": proceed, "needs.fix-ci-handoff.outputs.posted": posted });
  assert.equal(sub("false"), true);
  assert.equal(sub("true"), false);
  assert.equal(sub("false", "false"), false);
  const rungUp = (result, posted) =>
    evaluate(jobGate(UNBLOCK, "fix-ci-rung-up-subscription").gate, {
      "needs.fix-ci-context.outputs.proceed": "true",
      "needs.fix-ci-rung-up.result": result,
      "needs.fix-ci-rung-up-handoff.outputs.posted": posted,
    });
  assert.equal(rungUp("success", "false"), true);
  assert.equal(rungUp("success", "true"), false);
  assert.equal(rungUp("skipped", ""), false, "no rung-up call, no rung-up fallback");
  for (const [proceed, runs] of [["true", true], ["false", false], ["", false]]) {
    assert.equal(evaluate(jobGate(UNBLOCK, "fix-ci-unreported").gate, { "needs.fix-ci-context.outputs.proceed": proceed }), runs, JSON.stringify(proceed));
  }
});

test("pr-unblock.yml: apply-patch runs on a written or empty patch, or a refused collection, from the leg that answered", () => {
  const { gate } = jobGate(UNBLOCK, "apply-patch");
  const runs = (subResult, sub, first, fbResult = "skipped", fb = []) =>
    evaluate(gate, {
      "needs.fix-ci-fallback.result": fbResult,
      "needs.fix-ci-fallback.outputs.scan-patch-state": fb[0] ?? "",
      "needs.fix-ci-fallback.outputs.scan-collect-refused": fb[1] ?? "",
      "needs.fix-ci-subscription.result": subResult,
      "needs.fix-ci-subscription.outputs.scan-patch-state": sub[0] ?? "",
      "needs.fix-ci-subscription.outputs.scan-collect-refused": sub[1] ?? "",
      "needs.fix-ci.outputs.scan-patch-state": first[0] ?? "",
      "needs.fix-ci.outputs.scan-collect-refused": first[1] ?? "",
    });
  assert.equal(runs("skipped", [], ["written"]), true, "the key call's patch, its subscription call skipped");
  assert.equal(runs("skipped", [], ["empty"]), true, "an empty patch escalates");
  assert.equal(runs("success", ["written"], []), true, "the subscription call's patch after a handoff");
  assert.equal(runs("skipped", [], ["", "true"]), true, "a refused collection escalates");
  assert.equal(runs("success", ["", "true"], []), true, "the subscription call's refused collection");
  assert.equal(runs("success", [], ["written"]), false, "the key call's patch is not taken once the subscription call ran");
  assert.equal(runs("success", [], ["", "true"]), false, "nor its refusal");
  assert.equal(runs("success", [], [], "success", ["written"]), true, "the fallback call's patch after a second handoff");
  assert.equal(runs("success", ["written"], [], "success", []), false, "the subscription call's patch is not taken once the fallback call ran");
  assert.equal(runs("skipped", [], ["", ""]), false, "a call that left no patch and refused none");
});

// #9365: a hostile model job can forge lane-class, credential-present,
// handed-off or any output of its own. address-feedback's and
// review-dependency's fallback calls start on their handoff jobs' reads, so
// no forged output starts or suppresses them.
test("pr-unblock.yml: address-feedback's and review-dependency's fallback calls start on base jobs alone, whatever a model call reports", () => {
  for (const [first, handoff, sub, select] of [
    ["address-feedback", "address-feedback-handoff", "address-feedback-subscription", "address-feedback-select"],
    ["review-dependency", "review-dependency-handoff", "review-dependency-subscription", "review-dependency-select"],
  ]) {
    const forged = new RegExp(`needs\\.${first}(?:-subscription)?\\.outputs\\.`);
    assert.doesNotMatch(jobGate(UNBLOCK, sub).gate, forged, sub);
    // Every forged pair a run job can report: a credit stop, an empty key, a
    // clean run. The start follows the handoff job's read alone.
    const forgeries = [
      { "lane-class": "credit-stop", "credential-present": "true", "handed-off": "true" },
      { "lane-class": "", "credential-present": "false", "handed-off": "true" },
      { "lane-class": "", "credential-present": "true", "handed-off": "false" },
    ];
    for (const outputs of forgeries) {
      const context = (posted, proceed = "true") => ({
        ...Object.fromEntries(Object.entries(outputs).map(([name, value]) => [`needs.${first}.outputs.${name}`, value])),
        [`needs.${select}.outputs.proceed`]: proceed,
        [`needs.${handoff}.outputs.posted`]: posted,
      });
      const label = JSON.stringify(outputs);
      assert.equal(evaluate(jobGate(UNBLOCK, sub).gate, context("true")), false, `${sub} after a posted check, ${label}`);
      assert.equal(evaluate(jobGate(UNBLOCK, sub).gate, context("false")), true, `${sub} after no posted check, ${label}`);
      assert.equal(evaluate(jobGate(UNBLOCK, sub).gate, context("false", "false")), false, `${sub} with no proceed, ${label}`);
    }
    assert.deepEqual(jobGate(UNBLOCK, sub).needs, [select, first, handoff]);
    assert.doesNotMatch(jobGate(UNBLOCK, handoff).gate, forged, handoff);
    // The handoff job runs whenever the select job proceeded.
    for (const [proceed, runs] of [["true", true], ["false", false], ["", false]]) {
      assert.equal(evaluate(jobGate(UNBLOCK, handoff).gate, { [`needs.${select}.outputs.proceed`]: proceed }), runs, `${handoff} ${JSON.stringify(proceed)}`);
    }
  }
});

// A step's if:, single-line or folded, by its name.
function stepIf(file, name) {
  const lines = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8").split("\n");
  const start = lines.indexOf(`      - name: ${name}`);
  assert.notEqual(start, -1, `${file}: step ${name}`);
  const end = lines.findIndex((line, i) => i > start && /^ {6}- /.test(line));
  const step = lines.slice(start + 1, end === -1 ? undefined : end);
  const at = step.findIndex((line) => /^ {8}if: /.test(line));
  assert.notEqual(at, -1, `${file}: step ${name} has an if:`);
  return ifAt(step, at, 8);
}

// The minutes of a workflow's one `cron:` line.
function cronMinutes(file) {
  const text = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
  const crons = [...text.matchAll(/^ {4}- cron: "([0-9,]+) \* \* \* \*"$/gm)];
  assert.equal(crons.length, 1, `${file}: one hourly cron line`);
  return crons[0][1].split(",").map(Number);
}

const DISPATCHER = "pr-unblock-dispatch.yml";

// A write token the broker would refuse is decided before the select jobs, so
// no later job, publish-feedback and apply-dependency-verdict included, starts.
for (const [file, jobs] of [
  ["pr-unblock.yml", ["resolve-conflicts-select", "address-feedback-select", "review-dependency-select", "fix-ci-context"]],
  ["pr-refine.yml", ["plan", "fix-docs-head"]],
]) {
  test(`${file}: a dispatcher on an older copy of its file starts no first job`, () => {
    const text = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
    assert.match(text, /\n {2}dispatcher-current:\n(?: {4}.*\n| {6}.*\n|\n)*? {8}run: bash \.base\/\.github\/scripts\/pr-unblock\/dispatcher-current\.sh\n/);
    const blocks = text.slice(text.indexOf("\njobs:\n")).split(/\n {2}(?=[a-z-]+:\n)/).slice(1);
    const starts = blocks.filter((block) => !/^ {4}needs:/m.test(block)).map((block) => block.split(":")[0]);
    assert.deepEqual(starts, ["dispatcher-current"], "every other job waits on a job");
    for (const job of jobs) {
      // needs: dispatcher-current, alone or first in a list.
      const block = new RegExp(`\\n  ${job}:\\n    needs: (?:dispatcher-current|\\[dispatcher-current(?:, [a-z-]+)*\\])\\n    if: >-\\n((?: {6}.*\\n)+)`).exec(text);
      assert.ok(block, `${job} needs dispatcher-current`);
      assert.match(block[1], /needs\.dispatcher-current\.outputs\.stale != 'true'/, job);
    }
  });
}

test("pr-unblock-dispatch.yml gates a hand run and every re-run, and no first push or scheduled attempt", () => {
  const gate = stepIf(DISPATCHER, "Check the trigger");
  const runs = (event, attempt, kill = "true") =>
    evaluate(gate, { "steps.kill.outputs.proceed": kill, "github.event_name": event, "github.run_attempt": attempt });
  assert.equal(runs("push", "1"), false);
  assert.equal(runs("schedule", "1"), false);
  assert.equal(runs("workflow_dispatch", "1"), true);
  assert.equal(runs("push", "2"), true);
  assert.equal(runs("schedule", "2"), true);
  assert.equal(runs("schedule", "1", "false"), false);
  // A skipped gate lets the dispatch step run; a checked one must proceed.
  const dispatches = (outcome, proceed = "", paced = "false", degraded = "false") =>
    evaluate(stepIf(DISPATCHER, "Dispatch pr-unblock for conflicting, review-tier Dependabot and failing lanes App PRs"), {
      "steps.kill.outputs.proceed": "true",
      "steps.upstream.outputs.degraded": degraded,
      "steps.gate.outcome": outcome,
      "steps.gate.outputs.proceed": proceed,
      "steps.pace.outputs.paced": paced,
    });
  assert.equal(dispatches("skipped"), true);
  assert.equal(dispatches("success", "true"), true);
  assert.equal(dispatches("success", "false"), false);
  // A tick the burn-rate pacer paces dispatches nothing (log-api-budget/pace.mjs).
  assert.equal(dispatches("skipped", "", "true"), false);
  assert.equal(dispatches("skipped", "", ""), true, "a pacer that wrote nothing");
  // A degraded Actions or npm component dispatches nothing; an upstream check
  // that failed or wrote nothing fails open (check-upstream-status).
  assert.equal(dispatches("skipped", "", "false", "true"), false);
  assert.equal(dispatches("skipped", "", "false", ""), true, "an upstream check that wrote nothing");
});

test("pr-unblock-dispatch.yml installs the FAIL-cap reader only on a run that dispatches", () => {
  for (const name of ["Set up Python", "Install the pinned YAML reader"]) {
    const installs = (outcome, proceed = "", paced = "false") =>
      evaluate(stepIf(DISPATCHER, name), {
        "steps.kill.outputs.proceed": "true",
        "steps.upstream.outputs.degraded": "false",
        "steps.gate.outcome": outcome,
        "steps.gate.outputs.proceed": proceed,
        "steps.pace.outputs.paced": paced,
      });
    assert.equal(installs("skipped"), true, `${name}: a push or tick that dispatches`);
    assert.equal(installs("skipped", "", ""), true, `${name}: a pacer that wrote nothing`);
    assert.equal(installs("success", "true"), true, `${name}: a trusted hand run`);
    assert.equal(installs("skipped", "", "true"), false, `${name}: a paced tick`);
    assert.equal(installs("success", "false"), false, `${name}: a refused trigger`);
  }
});

test("pr-unblock-dispatch.yml ticks five minutes after each lost-run reconciler tick", () => {
  const reconciler = cronMinutes("maintenance-reconcile-lost-runs.yml");
  assert.deepEqual(cronMinutes(DISPATCHER), reconciler.map((minute) => (minute + 5) % 60));
});

test("pr-unblock-dispatch.yml: only a push cancels the dispatcher run going; a tick or hand run waits", () => {
  const block = jobBlock(DISPATCHER, "dispatch");
  const at = block.findIndex((line) => line === "    concurrency:");
  assert.notEqual(at, -1, "the dispatch job sets concurrency");
  assert.equal(block[at + 1], "      group: pr-unblock-dispatch");
  const cancel = /^ {6}cancel-in-progress: (.+)$/.exec(block[at + 2]);
  assert.ok(cancel, "cancel-in-progress follows the group");
  const cancels = (event) => evaluate(cancel[1], { "github.event_name": event });
  assert.equal(cancels("push"), true);
  assert.equal(cancels("schedule"), false);
  assert.equal(cancels("workflow_dispatch"), false);
  // GitHub's default keeps one pending run: a newer tick replaces a waiting one.
  const end = block.findIndex((line, i) => i > at && !line.startsWith("      "));
  const keys = block.slice(at + 1, end).map((line) => line.trim().split(":")[0]);
  assert.deepEqual(keys, ["group", "cancel-in-progress"], "the default single pending run");
});

// The owner's one automatic hop past the subscription call: each lane's
// third call starts only on its handoff jobs' reads, never on a call output a
// hostile run job could forge, and only when the handoff job found the
// fallback token set, so with the token empty neither new job runs.
const THIRD_HOPS = [
  ["pr-unblock.yml", "resolve-conflicts"],
  ["pr-unblock.yml", "address-feedback"],
  ["pr-unblock.yml", "review-dependency"],
  ["pr-unblock.yml", "fix-ci"],
  ["pr-unblock.yml", "fix-ci-rung-up"],
  ["pr-refine.yml", "fix-docs"],
  ["work-resolve-issue.yml", "resolve-issue"],
];
test("every read-runner lane starts its fallback call only on its handoff jobs' reads, with the fallback token set", () => {
  for (const [file, first] of THIRD_HOPS) {
    const sub = `${first}-subscription`;
    const handoff = `${first}-handoff`;
    const evidence = `${sub}-handoff`;
    const fallback = `${first}-fallback`;
    const forged = new RegExp(`needs\\.${first}(?:-subscription|-fallback)?\\.outputs\\.`);
    const read = jobGate(file, evidence);
    assert.deepEqual(read.needs, [handoff, sub], evidence);
    const reads = (result, ready) =>
      evaluate(read.gate, { [`needs.${sub}.result`]: result, [`needs.${handoff}.outputs.fallback-ready`]: ready });
    assert.equal(reads("success", "true"), true, `${evidence} after the subscription call`);
    assert.equal(reads("success", "false"), false, `${evidence} with the fallback token empty`);
    assert.equal(reads("success", ""), false, `${evidence} when the presence read never ran`);
    assert.equal(reads("skipped", "true"), false, `${evidence} with no subscription call`);
    const third = jobGate(file, fallback);
    assert.doesNotMatch(third.gate, forged, fallback);
    // The issue lane's third call keeps its second call's admission, Work
    // status field and slot gates (field 48484079 set to agent-ready,
    // 84879220, models.issue-status).
    const base =
      file === "work-resolve-issue.yml"
        ? {
            "github.event.issue_field.id": 48484079,
            "github.event.issue_field_value.option.id": 84879220,
            "needs.admit.outputs.proceed": "true",
            "needs.pick-slot.outputs.capped": "false",
          }
        : {};
    const starts = (handedOff, ready) =>
      evaluate(third.gate, { ...base, [`needs.${evidence}.outputs.handed-off`]: handedOff, [`needs.${handoff}.outputs.fallback-ready`]: ready });
    assert.equal(starts("true", "true"), true, fallback);
    assert.equal(starts("false", "true"), false, `${fallback} when the subscription call did not hand off`);
    assert.equal(starts("", "true"), false, `${fallback} after a failed read`);
    assert.equal(starts("true", "false"), false, `${fallback} with the fallback token empty`);
    if (file === "work-resolve-issue.yml") {
      assert.equal(
        evaluate(third.gate, { ...base, "needs.admit.outputs.proceed": "false", [`needs.${evidence}.outputs.handed-off`]: "true", [`needs.${handoff}.outputs.fallback-ready`]: "true" }),
        false,
        `${fallback} without admission`,
      );
    }
    const block = jobBlock(file, fallback).join("\n");
    assert.match(block, /\n {6}fallback: fallback\n/, fallback);
    assert.match(block, /\n {6}fallback-claude-code-oauth-token: \$\{\{ secrets\.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN \}\}\n/, fallback);
    assert.doesNotMatch(block, /claude-api-key|\n {6}claude-code-oauth-token:|\n {6}fallback-ready:/, `${fallback} holds the fallback token alone and is the last leg`);
    // The subscription call may hand off only on the presence read, a job
    // that runs no head code, and holds no fallback token itself.
    const subBlock = jobBlock(file, sub).join("\n");
    assert.match(subBlock, new RegExp(`\\n {6}fallback-ready: \\$\\{\\{ needs\\.${handoff}\\.outputs\\.fallback-ready \\}\\}\\n`), sub);
    assert.doesNotMatch(subBlock, /FALLBACK_CLAUDE_CODE_OAUTH_TOKEN/, sub);
    const handoffBlock = jobBlock(file, handoff).join("\n");
    assert.match(handoffBlock, /\n {10}PRESENT: \$\{\{ secrets\.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' \}\}\n/, handoff);
    assert.doesNotMatch(handoffBlock.replace("secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != ''", ""), /secrets\./, `${handoff} reads only whether the token is set`);
  }
});

// post-verify-notes takes a pass or pass-notes verdict as well as a fail, by
// write-verdict.mjs NAME's grammar: `-i` is a fail's alone. A verdict-shaped
// name its filter drops fails the run.
test("pr-feedback-dispatch.yml: post-verify-notes reads the names write-verdict.mjs NAME allows, pass names included", () => {
  const step = jobBlock("pr-feedback-dispatch.yml", "post-verify-notes").join("\n").split("\n      - name: ").find((text) => text.startsWith("Download the verdict"));
  assert.ok(step, "the download step");
  const listFilter = /listed=\$\(jq -r '([^']+)' <<<"\$listing"\)/.exec(step)?.[1];
  const nameFilter = /names=\$\(jq -Rr '([^']+)' <<<"\$listed"\)/.exec(step)?.[1];
  assert.ok(listFilter && nameFilter, "the step's two filters");
  const sha = "a".repeat(40);
  const digest = "79b4cc554b80dca6";
  const taken = [
    `pr-verify-42-${sha}-fail`,
    `pr-verify-42-${sha}-fail-${digest}-i7.12`,
    `pr-verify-42-${sha}-pass`,
    `pr-verify-42-${sha}-pass-notes`,
    `pr-verify-42-${sha}-pass-${digest}`,
    `pr-verify-42-${sha}-pass-notes-${digest}`,
  ];
  const refused = [`pr-verify-42-${sha}-pass-i7`, `pr-verify-42-${sha}-pass-notes-${digest}-i7`, `pr-verify-42-${sha}-passed`, `pr-verify-42-${sha}-fail-i12.7`];
  const jq = (filter, input, ...args) => {
    const result = spawnSync("jq", [...args, filter], { input, encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.split("\n").filter(Boolean);
  };
  const artifacts = JSON.stringify({ artifacts: [...taken, ...refused, "pr-verify-data", `pr-verify-42-${sha}-fail`.replace("fail", "skip")].map((name) => ({ name, expired: false })) });
  const listed = jq(listFilter, artifacts, "-r");
  assert.deepEqual(listed, [...taken, ...refused], "every verdict-shaped name is listed");
  assert.deepEqual(jq(nameFilter, `${listed.join("\n")}\n`, "-Rr"), taken, "and only NAME's are taken");
  for (const name of [...taken, ...refused]) {
    assert.equal(isVerdictName(name), taken.includes(name), name);
  }
});

test("pr-feedback-dispatch.yml: a newer completion at a head queues behind a pending one, never cancels it", () => {
  const text = readFileSync(new URL("../../workflows/pr-feedback-dispatch.yml", import.meta.url), "utf8");
  const block = /\nconcurrency:\n((?: {2}.*\n)+)/.exec(text);
  assert.ok(block, "the workflow sets top-level concurrency");
  assert.match(block[1], /^ {2}cancel-in-progress: false$/m);
  assert.match(block[1], /^ {2}queue: max$/m);
});

// A step of a job, as its lines from `- name:` to the next step.
function stepBlock(file, job, name) {
  const block = jobBlock(file, job);
  const start = block.indexOf(`      - name: ${name}`);
  assert.notEqual(start, -1, `${file}: ${job} has a step ${name}`);
  const end = block.findIndex((line, i) => i > start && /^ {6}- name: /.test(line));
  return block.slice(start, end === -1 ? undefined : end);
}

// A step's `run: |` script, indentation removed.
function stepScript(step) {
  const at = step.findIndex((line) => line === "        run: |");
  assert.notEqual(at, -1, "the step has a run: | script");
  return step
    .slice(at + 1)
    .filter((line) => line.startsWith("          ") || line === "")
    .map((line) => line.slice(10))
    .join("\n");
}

// While the switch is on, every pr-verify run fails at its own kill step and
// carries no verdict; the reconciler re-runs that run itself. Only a run that
// finished, and so may hold a verdict, is recorded by failing this job.
test("post-verify-notes fails at the kill switch only for a pr-verify run that succeeded", () => {
  const step = stepBlock("pr-feedback-dispatch.yml", "post-verify-notes", "Stop on the kill switch");
  const gate = ifAt(step, step.findIndex((line) => /^ {8}if: /.test(line)), 8);
  const fails = (proceed, conclusion) => evaluate(gate, { "steps.kill.outputs.proceed": proceed, "github.event.workflow_run.conclusion": conclusion });
  assert.equal(fails("false", "success"), true);
  assert.equal(fails("", "success"), true, "an unreadable switch stops it too");
  assert.equal(fails("false", "failure"), false, "a pr-verify run its own kill switch stopped");
  assert.equal(fails("true", "success"), false);
});

test("post-verify-notes names a deferred verdict exactly as recoverDeferred reads it", () => {
  const script = stepScript(stepBlock("pr-feedback-dispatch.yml", "post-verify-notes", "Name the deferred verdict"));
  const dir = mkdtempSync(join(tmpdir(), "deferred-name-"));
  try {
    for (const [fail, pass, verdict] of [["a".repeat(40), "", "fail"], ["", "b".repeat(40), "pass"]]) {
      const output = join(dir, `output-${verdict}`);
      writeFileSync(output, "");
      const run = spawnSync("bash", ["-e", "-c", script], { env: { PATH: process.env.PATH, FAIL_HEAD: fail, PASS_HEAD: pass, GITHUB_OUTPUT: output, RUNNER_TEMP: dir }, encoding: "utf8" });
      assert.equal(run.status, 0, run.stdout + run.stderr);
      const name = /^name=(.*)$/m.exec(readFileSync(output, "utf8"))?.[1] ?? "";
      const match = DEFERRED_RECORD.exec(name);
      assert.ok(match, name);
      assert.deepEqual([match[1], match[2]], [fail || pass, verdict]);
    }
    const bad = spawnSync("bash", ["-e", "-c", script], { env: { PATH: process.env.PATH, FAIL_HEAD: "x", PASS_HEAD: "", GITHUB_OUTPUT: join(dir, "bad"), RUNNER_TEMP: dir }, encoding: "utf8" });
    assert.notEqual(bad.status, 0);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// The dispatcher sends only same-repository PRs, but a hand dispatch can name
// any PR. The step runs against a stub gh that applies the step's own --jq
// filter to a PR payload, printing a null as the empty line gh prints.
for (const [job, written] of [
  ["resolve-conflicts-select", "\ndefault-base=true\n"],
  ["address-feedback-select", "\n"],
  ["review-dependency-select", "\n"],
]) test(`pr-unblock.yml: ${job} stops on a head outside this repository, before any sha output`, () => {
  const script = stepScript(stepBlock(UNBLOCK, job, "Read the PR head"));
  const repo = "melodic-software/claude-code-plugins";
  const sha = "a".repeat(40);
  const dir = mkdtempSync(join(tmpdir(), "pr-head-"));
  try {
    writeFileSync(join(dir, "gh"), '#!/usr/bin/env bash\nexec jq -r "$4 | . // \\"\\"" "$PR_PAYLOAD"\n', { mode: 0o755 });
    placeReader(dir);
    const read = (name, headRepo) => {
      const payload = join(dir, `${name}.json`);
      const output = join(dir, `${name}.output`);
      writeFileSync(payload, JSON.stringify({ head: { sha, repo: headRepo }, base: { ref: "main" } }));
      writeFileSync(output, "");
      const run = spawnSync("bash", ["-e", "-c", script], {
        cwd: dir,
        env: { PATH: `${dir}:${process.env.PATH}`, PR_PAYLOAD: payload, PR_NUMBER: "7", DEFAULT_BRANCH: "main", GITHUB_REPOSITORY: repo, GITHUB_OUTPUT: output, PULL_FILE: join(dir, `${name}.pull.json`) },
        encoding: "utf8",
      });
      return { status: run.status, stdout: run.stdout, written: readFileSync(output, "utf8") };
    };
    const own = read("own", { full_name: repo });
    assert.equal(own.status, 0, own.stdout);
    assert.equal(own.written, `sha=${sha}${written}`);
    if (job === "address-feedback-select") {
      // The whole answer, for the select step in place of a second read.
      assert.deepEqual(JSON.parse(readFileSync(join(dir, "own.pull.json"), "utf8")), { head: { sha, repo: { full_name: repo } }, base: { ref: "main" } });
    }
    for (const [name, headRepo] of [["fork", { full_name: "fork/claude-code-plugins" }], ["deleted-fork", null]]) {
      const refused = read(name, headRepo);
      assert.equal(refused.status, 1, name);
      assert.match(refused.stdout, /^::error::the PR's head is not in this repository$/m, name);
      assert.equal(refused.written, "", `${name} writes no output`);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// One GET /pulls/{n} serves the head check and select's hold checks: the
// select step reads the file the head step wrote (address-feedback.mjs
// pullFromFile), so the job reads the PR twice (this and resolve-config's
// labels and draft), not three times.
test("pr-unblock.yml: address-feedback-select hands the head step's PR read to the select step", () => {
  const file = (step) => /^ {10}PULL_FILE: (.+)$/m.exec(stepBlock(UNBLOCK, "address-feedback-select", step).join("\n"))?.[1];
  assert.match(file("Read the PR head") ?? "", /^\$\{\{ runner\.temp \}\}\/pr-head\.json$/);
  assert.equal(file("Select the review threads"), file("Read the PR head"));
  assert.match(stepScript(stepBlock(UNBLOCK, "address-feedback-select", "Read the PR head")), /^printf '%s\\n' "\$pr_fields" >"\$PULL_FILE"$/m);
});

// The default branch checkout's copy of the shared PR read, as the steps source it.
function placeReader(dir) {
  const target = join(dir, ".base/.github/scripts/pr-unblock");
  mkdirSync(target, { recursive: true });
  copyFileSync(new URL("./read-pr-head.bash", import.meta.url), join(target, "read-pr-head.bash"));
}

for (const job of ["resolve-conflicts-select", "sync-shared-copies-select", "address-feedback-select", "review-dependency-select"]) {
  test(`pr-unblock.yml: ${job} reads the PR head through the shared helper from the default branch checkout`, () => {
    const script = stepScript(stepBlock(UNBLOCK, job, "Read the PR head"));
    assert.match(script, /^\. \.base\/\.github\/scripts\/pr-unblock\/read-pr-head\.bash$/m);
    assert.match(script, /^read_pr_fields "\$PR_NUMBER" '[^']+' \|\| exit 1$/m);
    assert.doesNotMatch(script, /^ *\{ read .*< <\(gh api/m);
  });
}

// A failed read of the PR reports its error text and class. The stub gh answers
// from a script of one spec per call (ok, empty, or fail:<stderr>); the stub
// sleep records its argument.
test("pr-unblock.yml: resolve-conflicts-select classifies a failed PR read and retries only a transient one", () => {
  const script = stepScript(stepBlock(UNBLOCK, "resolve-conflicts-select", "Read the PR head"));
  const repo = "melodic-software/claude-code-plugins";
  const sha = "a".repeat(40);
  const dir = mkdtempSync(join(tmpdir(), "pr-read-"));
  try {
    writeFileSync(
      join(dir, "gh"),
      `#!/usr/bin/env bash
n=$(( $(cat "$STUB_DIR/calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$STUB_DIR/calls"
spec=$(sed -n "\${n}p" "$STUB_DIR/script")
case $spec in
  ok) printf '%s\\n' "${sha}" main "${repo}" ;;
  empty) ;;
  *) printf '%s\\n' "\${spec#fail:}" >&2; exit 1 ;;
esac
`,
      { mode: 0o755 },
    );
    writeFileSync(join(dir, "sleep"), '#!/usr/bin/env bash\necho "$1" >>"$STUB_DIR/sleeps"\n', { mode: 0o755 });
    placeReader(dir);
    const read = (specs) => {
      for (const file of ["calls", "sleeps", "output"]) writeFileSync(join(dir, file), "");
      writeFileSync(join(dir, "script"), specs.join("\n") + "\n");
      const run = spawnSync("bash", ["-e", "-c", script], {
        cwd: dir,
        env: { PATH: `${dir}:${process.env.PATH}`, STUB_DIR: dir, PR_NUMBER: "7", DEFAULT_BRANCH: "main", GITHUB_REPOSITORY: repo, GITHUB_OUTPUT: join(dir, "output"), TMPDIR: dir },
        encoding: "utf8",
      });
      const lines = (file) => readFileSync(join(dir, file), "utf8").split("\n").filter(Boolean);
      return { status: run.status, stdout: run.stdout, calls: lines("calls").length ? Number(lines("calls")[0]) : 0, sleeps: lines("sleeps"), written: readFileSync(join(dir, "output"), "utf8") };
    };

    for (const text of ["HTTP 502: Bad Gateway", "unexpected end of JSON input", "invalid character 'b' looking for beginning of value", "error connecting to api.github.com"]) {
      const run = read([`fail:${text}`, "ok"]);
      assert.equal(run.status, 0, `${text}: ${run.stdout}`);
      assert.equal(run.calls, 2, text);
      assert.equal(run.sleeps.length, 1, text);
      // Full jitter (outage posture element 1): a wait drawn from 0 to the 10 s cap.
      assert.ok(/^(?:[0-9]|10)$/.test(run.sleeps[0]), `${text}: waited ${run.sleeps[0]}`);
      assert.match(run.stdout, /^::warning::reading #7 failed \(transient\): /m, text);
      assert.equal(run.written, `sha=${sha}\ndefault-base=true\n`, text);
    }

    const twice = read(["fail:HTTP 503: unavailable", "fail:HTTP 503: unavailable", "ok"]);
    assert.equal(twice.status, 1);
    assert.equal(twice.calls, 2, "a transient failure is read once more, not twice");
    assert.match(twice.stdout, /^::error::the PR could not be read \(transient\): HTTP 503: unavailable$/m);
    assert.equal(twice.written, "");

    const other = read(["fail:gh: Not Found (HTTP 404)\r::error::forged%", "ok"]);
    assert.equal(other.status, 1);
    assert.equal(other.calls, 1);
    assert.deepEqual(other.sleeps, []);
    assert.match(other.stdout, /^::error::the PR could not be read \(other\): gh: Not Found \(HTTP 404\) ::error::forged%25$/m);
    assert.doesNotMatch(other.stdout, /names no head SHA/);

    for (const text of ["gh: API rate limit exceeded for installation (HTTP 403)", "gh: secondary rate limit (HTTP 403)", "gh: too many requests (HTTP 429)", "'gh api x' was not sent: GitHub's core API rate limit holds until 2026-11-04T05:00:00Z"]) {
      const limited = read([`fail:${text}`, "ok"]);
      assert.equal(limited.status, 1, text);
      assert.equal(limited.calls, 1, `${text}: a rate limit is never read again`);
      assert.deepEqual(limited.sleeps, [], text);
      assert.match(limited.stdout, /^::error::the PR could not be read \(rate-limit\): /m, text);
    }

    const bare = read(["fail:"]);
    assert.equal(bare.status, 1);
    assert.match(bare.stdout, /^::error::the PR could not be read \(other\): no error text$/m);

    const empty = read(["empty"]);
    assert.equal(empty.status, 1);
    assert.equal(empty.calls, 1);
    assert.match(empty.stdout, /^::error::the PR names no head SHA$/m);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// With no head-sha output, no later job posts a status on that head.
for (const [activity, select] of [
  ["resolve-conflicts", "resolve-conflicts-select"],
  ["address-feedback", "address-feedback-select"],
  ["review-dependency", "review-dependency-select"],
  ["fix-ci", "fix-ci-context"],
]) test(`pr-unblock.yml: ${activity}-not-run posts nothing with no head-sha output`, () => {
  const { gate } = jobGate(UNBLOCK, `${activity}-not-run`);
  for (const proceed of ["", "false"]) {
    assert.equal(
      evaluate(gate, {
        "inputs.activity": activity,
        [`needs.${select}.outputs.proceed`]: proceed,
        [`needs.${select}.outputs.skip-reason`]: "",
        [`needs.${select}.outputs.head-sha`]: "",
      }),
      false,
      proceed,
    );
  }
});

// The pull_request_target refine job of pr-unblock-dispatch.yml starts Refine
// under the four invariants of owner decision Q12 (ADR 0090). Comment lines
// are dropped, so only what the job runs is read.
const refineLines = () => jobBlock(DISPATCHER, "refine").filter((line) => !/^\s*#/.test(line));

test("pr-unblock-dispatch.yml starts the refine job on a ready same-repository PR's event into main, and the listing job never on one", () => {
  const text = readFileSync(new URL(`../../workflows/${DISPATCHER}`, import.meta.url), "utf8");
  assert.match(text, /\n {2}pull_request_target: # zizmor: ignore\[dangerous-triggers\]\n {4}types: \[opened, reopened, ready_for_review, synchronize\]\n {4}branches: \[main\]\n/);
  const refine = (event, draft = false, head = "o/r") =>
    evaluate(jobGate(DISPATCHER, "refine").gate, {
      "github.event_name": event,
      "github.event.pull_request.draft": draft,
      "github.event.pull_request.head.repo.full_name": head,
      "github.repository": "o/r",
    });
  assert.equal(refine("pull_request_target"), true);
  assert.equal(refine("pull_request_target", true), false, "a draft");
  assert.equal(refine("pull_request_target", false, "fork/r"), false, "a fork PR");
  assert.equal(refine("push"), false);
  // A pull_request_target run's ref is the base branch, main.
  const listing = (event) => evaluate(jobGate(DISPATCHER, "dispatch").gate, { "github.ref": "refs/heads/main", "github.event_name": event });
  assert.equal(listing("pull_request_target"), false);
  for (const event of ["push", "schedule", "workflow_dispatch"]) {
    assert.equal(listing(event), true, event);
  }
});

test("refine invariant 1: it checks out only the commit its workflow file ran from, never the PR head", () => {
  const lines = refineLines();
  const checkouts = lines.filter((line) => /^ {8}uses: actions\/checkout@/.test(line)).length;
  assert.equal(checkouts, 1, "one checkout");
  const refs = lines.filter((line) => /^\s+ref: /.test(line)).map((line) => line.trim());
  assert.deepEqual(refs, ["ref: ${{ github.workflow_sha }}"], "every ref: is the workflow commit");
  assert.ok(!lines.some((line) => /^\s+repository: /.test(line)), "no checkout of another repository");
  const body = lines.join("\n");
  assert.doesNotMatch(body, /github\.head_ref|pull_request\.head\.(?:sha|ref)|merge_commit_sha|refs\/pull\//, "no head ref or SHA");
  assert.match(body, /\n {10}persist-credentials: false\n/);
  // A run: step could fetch and check out the head itself, so each script is
  // pinned whole: any change to one needs this test changed with it.
  const runs = {};
  let step = "";
  for (let at = 0; at < lines.length; at += 1) {
    step = /^ {6}- name: (.*)$/.exec(lines[at])?.[1] ?? step;
    const inline = /^ {8}run: (.*)$/.exec(lines[at]);
    if (!inline) continue;
    const script = inline[1] === "|" ? [] : [inline[1]];
    for (const line of lines.slice(at + 1)) {
      if (line !== "" && !line.startsWith("          ")) break;
      script.push(line.slice(10));
    }
    runs[step] = script.join("\n").trimEnd();
  }
  assert.deepEqual(runs, {
    "Install resolve-config's dependencies": "npm ci --ignore-scripts --omit=dev --prefix .base/.github/actions/resolve-config",
    "Dispatch pr-refine for this PR": "node .base/.github/scripts/pr-unblock/refine-event-dispatch.mjs",
    "Name the dispatched-run record": [
      'RUN_ID=$(head -n 1 "$RUN_IDS_FILE" 2>/dev/null) || RUN_ID=""',
      'if [ -z "$RUN_ID" ]; then',
      '  echo "no run dispatched"',
      "  exit 0",
      "fi",
      'if [[ ! "$RUN_ID" =~ ^[1-9][0-9]{0,14}$ || ! "$WORKFLOW_SHA" =~ ^[0-9a-f]{40}$ ]]; then',
      '  echo "::error::the run id or the workflow commit is malformed"',
      "  exit 1",
      "fi",
      `printf '{"dispatcher_run_id":%s,"workflow_sha":"%s","run_id":%s}\\n' "$GITHUB_RUN_ID" "$WORKFLOW_SHA" "$RUN_ID" \\`,
      '  >"$RUNNER_TEMP/pr-unblock-target-dispatched.json"',
      'echo "name=pr-unblock-target-dispatched-$WORKFLOW_SHA-$RUN_ID" >>"$GITHUB_OUTPUT"',
    ].join("\n"),
  });
});

// The modules the refine job's script loads, statically or through
// import(new URL(...)), read no event text from the environment. A module
// whose own entry point reads one (feedback-dispatch.mjs's main reads its
// workflow_run event) passes only while every read sits inside its exported
// main and nothing in the graph imports that main or the whole module.
const EVENT_READ = /GITHUB_EVENT_PATH|GITHUB_HEAD_REF|GITHUB_REF_NAME/g;

function mainBody(source) {
  const start = source.search(/^export (?:async )?function main\(/m);
  if (start === -1) return null;
  const rest = source.slice(start + 1);
  const end = rest.search(/^(?:export |function |async function |const |let |if \()/m);
  return [start, end === -1 ? source.length : start + 1 + end];
}

test("refine invariant 2: refine-event-dispatch.mjs and every module it loads read no head ref or event file", () => {
  const sources = new Map();
  const imports = [];
  const queue = [new URL("./refine-event-dispatch.mjs", import.meta.url)];
  while (queue.length > 0) {
    const url = queue.pop();
    if (sources.has(url.href)) continue;
    const source = readFileSync(url, "utf8");
    sources.set(url.href, source);
    for (const match of source.matchAll(/^\s*(?:import|export)\s([^;]*?)\sfrom\s+"(\.{1,2}\/[^"]+)"/gm)) {
      imports.push({ from: url.href, names: match[1], target: new URL(match[2], url).href });
      queue.push(new URL(match[2], url));
    }
    for (const match of source.matchAll(/^\s*import\s+"(\.{1,2}\/[^"]+)"/gm)) {
      queue.push(new URL(match[1], url));
    }
    for (const match of source.matchAll(/new URL\("(\.{1,2}\/[^"]+\.mjs)", import\.meta\.url\)/g)) {
      imports.push({ from: url.href, names: "*", target: new URL(match[1], url).href });
      queue.push(new URL(match[1], url));
    }
  }
  const hrefs = [...sources.keys()];
  assert.ok(hrefs.some((href) => href.endsWith("/fix-docs-dispatch.mjs")), "the walk reaches fix-docs-dispatch.mjs");
  assert.ok(hrefs.some((href) => href.endsWith("/resolve-config.mjs")), "the walk reaches resolve-config.mjs through import(new URL(...))");
  const [entry] = hrefs;
  for (const [href, source] of sources) {
    const reads = [...source.matchAll(EVENT_READ)];
    if (reads.length === 0) continue;
    // The job runs the entry module's main, so it has no exemption.
    assert.notEqual(href, entry, `${href} reads event text`);
    const main = mainBody(source);
    assert.ok(main && reads.every((read) => read.index > main[0] && read.index < main[1]), `${href} reads event text outside its main`);
    for (const edge of imports.filter((entry) => entry.target === href)) {
      assert.doesNotMatch(edge.names, /\*|\bmain\b/, `${edge.from} loads ${href}'s main`);
    }
  }
});

test("refine invariant 2: no PR text reaches a step; run: holds no expression and env: only numbers and SHAs", () => {
  const lines = refineLines();
  // Every run: script, inline or block, is free of ${{ }}.
  for (let at = 0; at < lines.length; at += 1) {
    if (/^ {8}run: /.test(lines[at])) {
      const script = [lines[at]];
      for (const line of lines.slice(at + 1)) {
        if (line !== "" && !line.startsWith("          ")) break;
        script.push(line);
      }
      assert.doesNotMatch(script.join("\n"), /\$\{\{/, `run: at line ${at}`);
    }
  }
  // Each expression is one the job needs; the event supplies two numbers alone.
  const allowed = new Set([
    "github.event.pull_request.number",
    "github.event.sender.id",
    "github.run_attempt",
    "github.workflow_sha",
    "github.token",
    "github.workspace",
    "runner.temp",
    "vars.AUTOMATION_LANES_APP_SENDER_ID",
    "vars.CLAUDE_LANES_DISABLED",
    "vars.CLAUDE_LANES_REPO_DISABLED",
    "steps.record.outputs.name",
  ]);
  const used = [...lines.join("\n").matchAll(/\$\{\{([\s\S]*?)\}\}/g)].map((match) => match[1].trim());
  assert.ok(used.includes("github.event.pull_request.number"));
  for (const expression of used) {
    assert.ok(allowed.has(expression), `expression ${expression} is not one the refine job may read`);
  }
});

test("refine invariant 3: exactly actions: write and contents: read, on the job, with no workflow-level grant", () => {
  const text = readFileSync(new URL(`../../workflows/${DISPATCHER}`, import.meta.url), "utf8");
  assert.deepEqual(text.match(/^permissions:.*$/gm), ["permissions: {}"], "the workflow grants nothing");
  const lines = refineLines();
  const at = lines.indexOf("    permissions:");
  assert.notEqual(at, -1, "the job sets permissions");
  const grants = [];
  for (const line of lines.slice(at + 1)) {
    if (!line.startsWith("      ")) break;
    grants.push(line.trim().replace(/\s*#.*$/, ""));
  }
  assert.deepEqual(grants.sort(), ["actions: write", "contents: read"]);
  assert.equal(lines.filter((line) => /^\s+permissions:/.test(line)).length, 1, "no other permissions block");
});

test("refine invariant 4: no secret and no token beyond GITHUB_TOKEN; only the listed actions run", () => {
  const lines = refineLines();
  const body = lines.join("\n");
  assert.doesNotMatch(body, /secrets\.|secrets\[|id-token|toJSON\(secrets\)/);
  const uses = lines.filter((line) => /^\s+(?:- )?uses: /.test(line)).map((line) => line.trim().replace(/^- /, "").replace(/\s*#.*$/, ""));
  const allowed = /^uses: (?:actions\/(?:checkout|upload-artifact)@[0-9a-f]{40}|\.\/\.base\/\.github\/actions\/(?:setup-pinned-node|check-kill-switch|scan-upload|log-api-budget))$/;
  for (const use of uses) {
    assert.match(use, allowed, `${use} is not an action the refine job may run`);
  }
  const tokens = [...body.matchAll(/^\s+([A-Z_]*TOKEN): (.*)$/gm)].map((match) => `${match[1]}: ${match[2]}`);
  assert.deepEqual(tokens, ["GITHUB_TOKEN: ${{ github.token }}", "API_BUDGET_TOKEN: github-token"]);
});

test("refine: the record is named from the workflow commit and the dispatched run id alone", () => {
  const step = stepBlock(DISPATCHER, "refine", "Name the dispatched-run record");
  const env = step.slice(step.indexOf("        env:") + 1, step.findIndex((line) => line.startsWith("        run:"))).map((line) => line.trim());
  assert.deepEqual(env, ["WORKFLOW_SHA: ${{ github.workflow_sha }}", "RUN_IDS_FILE: ${{ runner.temp }}/pr-refine-run-id"]);
  assert.ok(stepBlock(DISPATCHER, "refine", "Dispatch pr-refine for this PR").includes("          RUN_IDS_FILE: ${{ runner.temp }}/pr-refine-run-id"));
  const dir = mkdtempSync(join(tmpdir(), "refine-record-"));
  try {
    const record = (id, sha = "b".repeat(40)) => {
      writeFileSync(join(dir, "ids"), id);
      writeFileSync(join(dir, "out"), "");
      const result = spawnSync("bash", ["--noprofile", "--norc", "-e", "-c", stepScript(step)], {
        env: { PATH: process.env.PATH, WORKFLOW_SHA: sha, RUN_IDS_FILE: join(dir, "ids"), RUNNER_TEMP: dir, GITHUB_OUTPUT: join(dir, "out"), GITHUB_RUN_ID: "42" },
        encoding: "utf8",
      });
      return { status: result.status, out: readFileSync(join(dir, "out"), "utf8") };
    };
    // ADR 0090's form, pr-unblock-target-dispatched-<commit>-<run id>.
    assert.deepEqual(record("9001\n"), { status: 0, out: `name=pr-unblock-target-dispatched-${"b".repeat(40)}-9001\n` });
    assert.deepEqual(JSON.parse(readFileSync(join(dir, "pr-unblock-target-dispatched.json"), "utf8")), { dispatcher_run_id: 42, workflow_sha: "b".repeat(40), run_id: 9001 });
    assert.deepEqual(record(""), { status: 0, out: "" }, "no dispatch, no record");
    assert.equal(record("9001x\n").status, 1, "a malformed id");
    assert.equal(record("9001\n", "main").status, 1, "a malformed commit");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("refine: one run per PR at a time, a newer event cancelling the run going, within a time limit", () => {
  const lines = jobBlock(DISPATCHER, "refine");
  const at = lines.indexOf("    concurrency:");
  assert.deepEqual(lines.slice(at + 1, at + 3), ["      group: pr-unblock-dispatch-refine-${{ github.event.pull_request.number }}", "      cancel-in-progress: true"]);
  assert.ok(lines.includes("    timeout-minutes: 10"));
});
