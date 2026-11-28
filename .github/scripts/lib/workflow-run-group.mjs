import assert from "node:assert/strict";
import { evaluate } from "./gate-expression.mjs";

export function workflowRunGroup(text) {
  const match = /^concurrency:\n {2}group: >-\n((?: {4}.*\n)+) {2}cancel-in-progress: (.*)$/m.exec(text);
  assert.ok(match, "a top-level concurrency block with a folded group");
  const group = match[1].replace(/\s+/g, " ").trim().replaceAll("[0]", ".0");
  return {
    cancelInProgress: match[2],
    render: (workflowRun, runId) => evaluate(group, { github: { run_id: runId, event: { workflow_run: workflowRun } } }),
  };
}

export function assertPerHeadUnlessUpstreamCancelled(text, prefix) {
  const { render, cancelInProgress } = workflowRunGroup(text);
  const sha = "a".repeat(40);
  const run = (conclusion, pulls = [{ number: 41 }]) => ({ conclusion, head_sha: sha, pull_requests: pulls });
  for (const conclusion of ["success", "failure"]) {
    assert.equal(render(run(conclusion), 7), `${prefix}-41-${sha}`, `a ${conclusion} upstream keeps the per-head group`);
    assert.equal(render(run(conclusion), 8), `${prefix}-41-${sha}`, `a ${conclusion} upstream's re-trigger shares the head's group`);
  }
  assert.equal(render(run("success", []), 7), `${prefix}-none-${sha}`, "a run with no pull request keeps the none group");
  const [first, second] = [render(run("cancelled"), 7), render(run("cancelled"), 8)];
  assert.notEqual(first, second, "each cancelled-upstream run has a group of its own");
  assert.ok(first.startsWith(`${prefix}-`), `the cancelled-upstream group stays under ${prefix}`);
  for (const group of [first, second]) {
    assert.notEqual(group, `${prefix}-41-${sha}`, "a cancelled-upstream run never joins the head's group");
    assert.notEqual(group, `${prefix}-none-${sha}`, "a cancelled-upstream run never joins the none group");
  }
  assert.equal(cancelInProgress, "false", "a running judgment is never cancelled");
}
