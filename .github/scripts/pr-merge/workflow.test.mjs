// pr-merge.yml's main-verification trigger. Expected values come from the
// owner decision of 2026-10-18 (every merge to main starts the full run,
// whoever merged), GitHub's concurrency rules (a group holds one running and
// one pending job, and a newer pending job replaces the older one unless
// `queue: max` is set), and the rule babysit_postmerge.py and
// post-merge-demotion-alert.yml share: a cancelled full run counts as red, so
// no pr-require-checks run may be cancelled by concurrency.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const read = (name) => readFileSync(new URL(`../../workflows/${name}`, import.meta.url), "utf8");
const merge = read("pr-merge.yml");
const jobs = merge.slice(merge.indexOf("\njobs:\n"));
const job = (id) => {
  const match = new RegExp(`\\n  ${id}:\\n([\\s\\S]*?)(?=\\n  [a-z-]+:\\n|$)`).exec(jobs);
  assert.ok(match, `job ${id}`);
  return match[1];
};

test("every push to main reaches the dispatch job, with no author filter", () => {
  assert.match(merge, /\n  push:\n    branches: \[main\]\n/);
  const dispatch = job("dispatch-full-run");
  const condition = /\n    if: >-\n([\s\S]*?)\n    [a-z-]+:/.exec(dispatch)[1];
  assert.match(condition, /\(github\.event_name == 'push' && github\.ref == 'refs\/heads\/main'\)/);
  assert.doesNotMatch(dispatch, /head_commit|AUTOMATION_LANES_APP_SENDER_ID|needs\.lane-merge-landed/);
  assert.doesNotMatch(jobs, /\n  lane-merge-landed:\n/);
});

test("push dispatches share one group that queues one and cancels nothing", () => {
  const dispatch = job("dispatch-full-run");
  const block = /\n    concurrency:\n      group: (.*)\n      cancel-in-progress: (.*)\n/.exec(dispatch);
  assert.ok(block, "a job-level concurrency block");
  assert.match(block[1], /github\.event_name == 'push' && '[a-z-]+'/);
  assert.match(block[1], /github\.run_id/);
  assert.equal(block[2], "false");
  assert.doesNotMatch(dispatch, /\n {6}queue:/);
});

test("a push job holds the group until the dispatched run finishes", () => {
  const dispatch = job("dispatch-full-run");
  const record = dispatch.indexOf("- name: Record the dispatched run");
  const wait = dispatch.indexOf("- name: Wait for the full run to finish");
  assert.ok(record >= 0 && wait > record);
  const step = dispatch.slice(wait);
  assert.match(step, /\n {8}if: github\.event_name == 'push'\n/);
  assert.match(step, /--jq \.status/);
  assert.doesNotMatch(step, /gh run watch|--exit-status/);
});

test("pr-require-checks.yml never cancels a dispatched or scheduled run", () => {
  const checks = read("pr-require-checks.yml");
  const on = checks.slice(checks.indexOf("\non:\n"), checks.indexOf("\npermissions:\n"));
  assert.doesNotMatch(on, /\n  push:/);
  const group = /\nconcurrency:\n  group: >-\n([\s\S]*?)\n  cancel-in-progress:/.exec(checks)[1];
  assert.match(group, /github\.event\.pull_request\.number \|\| github\.run_id/);
});
