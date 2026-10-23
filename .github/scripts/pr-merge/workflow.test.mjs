// pr-merge.yml's main-verification trigger. Expected values come from the
// owner decision of 2026-10-18 (every merge to main starts the full run,
// whoever merged), GitHub's concurrency rules (a group holds one running and
// one pending job, and a newer pending job replaces the older one unless
// `queue: max` is set), and the rule babysit_postmerge.py and
// post-merge-demotion-alert.yml share: a cancelled full run counts as red, so
// no pr-require-checks run may be cancelled by concurrency.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
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
  assert.match(merge, /\n {2}push:\n {4}branches: \[main\]\n/);
  const dispatch = job("dispatch-full-run");
  const condition = /\n {4}if: >-\n([\s\S]*?)\n {4}[a-z-]+:/.exec(dispatch)[1];
  assert.match(condition, /\(github\.event_name == 'push' && github\.ref == 'refs\/heads\/main'\)/);
  assert.doesNotMatch(dispatch, /head_commit|AUTOMATION_LANES_APP_SENDER_ID|needs\.lane-merge-landed/);
  assert.doesNotMatch(jobs, /\n {2}lane-merge-landed:\n/);
});

test("push dispatches share one group that queues one and cancels nothing", () => {
  const dispatch = job("dispatch-full-run");
  const block = /\n {4}concurrency:\n {6}group: (.*)\n {6}cancel-in-progress: (.*)\n/.exec(dispatch);
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
  assert.doesNotMatch(step, /gh run watch|--exit-status/);
});

// The wait step's body, run under bash against a stub gh (one canned run
// read, then any write logged) and a stub sleep. The alert workflow hears of
// a failed run only through this dispatch: GITHUB_TOKEN started the run, so
// it raises no workflow_run event.
const HEAD = "0123456789abcdef0123456789abcdef01234567";
const SEND = `api -X POST repos/o/r/actions/workflows/post-merge-demotion-alert.yml/dispatches -f ref=main -f inputs[run-id]=4242 -f inputs[head-sha]=${HEAD}`;
function runWait(conclusion, { dispatchFails = false } = {}) {
  const step = job("dispatch-full-run").split("\n      - name: Wait for the full run to finish\n")[1];
  const body = /\n {8}run: \|\n((?: {10}.*\n|\s*\n)+)/
    .exec(step)[1]
    .split("\n")
    .map((l) => l.slice(10))
    .join("\n");
  const dir = mkdtempSync(join(tmpdir(), "pr-merge-wait-"));
  mkdirSync(join(dir, "bin"));
  writeFileSync(join(dir, "bin", "sleep"), "#!/bin/sh\nexit 0\n", {
    mode: 0o755,
  });
  writeFileSync(
    join(dir, "bin", "gh"),
    `#!/usr/bin/env bash
printf '%s\\n' "$*" >>"${dir}/log"
case "$*" in
  *-X\\ POST*) exit ${dispatchFails ? 1 : 0} ;;
  *) jq -r "\${@: -1}" <<<'{"status": "completed", "conclusion": "${conclusion}", "head_sha": "${HEAD}"}' ;;
esac
`,
    { mode: 0o755 },
  );
  writeFileSync(join(dir, "body.sh"), body);
  const result = spawnSync("bash", ["-e", join(dir, "body.sh")], {
    env: {
      ...process.env,
      PATH: `${join(dir, "bin")}:${process.env.PATH}`,
      GH_TOKEN: "x",
      REPO: "o/r",
      RUN_ID: "4242",
    },
    encoding: "utf8",
  });
  const log = existsSync(join(dir, "log")) ? readFileSync(join(dir, "log"), "utf8") : "";
  rmSync(dir, { recursive: true, force: true });
  return {
    status: result.status,
    out: result.stdout + result.stderr,
    writes: log.split("\n").filter((l) => l.includes("-X POST")),
  };
}

// The alert serializes on signal and head SHA, so the send names the run's
// head SHA as the run reports it, not this workflow's push SHA.
test("a red full run is sent to post-merge-demotion-alert.yml by its run id and head SHA", () => {
  const { status, writes } = runWait("failure");
  assert.equal(status, 0);
  assert.deepEqual(writes, [SEND]);
});

// babysit_postmerge.py's FAILED_CONCLUSIONS, the conclusions post-merge
// demotion counts as red: a cancel on a time-budget overrun is red too.
test("every red conclusion of a full run is sent to post-merge-demotion-alert.yml", () => {
  for (const conclusion of ["failure", "timed_out", "cancelled", "startup_failure", "action_required"]) {
    const { status, writes } = runWait(conclusion);
    assert.equal(status, 0, conclusion);
    assert.deepEqual(writes, [SEND], conclusion);
  }
});

test("a green, skipped or neutral full run is sent nowhere", () => {
  for (const conclusion of ["success", "skipped", "neutral"]) {
    const { status, writes } = runWait(conclusion);
    assert.equal(status, 0, conclusion);
    assert.deepEqual(writes, [], conclusion);
  }
});

test("a send that fails fails the job", () => {
  const { status, out } = runWait("failure", { dispatchFails: true });
  assert.equal(status, 1);
  assert.match(out, /::error::could not send run 4242 to post-merge-demotion-alert\.yml/);
});

test("the dispatch job's token is actions: write and nothing else", () => {
  const block = /\n {4}permissions:\n((?: {6}[a-z-]+: [a-z]+.*\n)+)/.exec(job("dispatch-full-run"))[1];
  assert.deepEqual(
    [...block.matchAll(/ {6}([a-z-]+): ([a-z]+)/g)].map((m) => `${m[1]}: ${m[2]}`),
    ["actions: write"],
  );
});

test("pr-require-checks.yml never cancels a dispatched or scheduled run", () => {
  const checks = read("pr-require-checks.yml");
  const on = checks.slice(checks.indexOf("\non:\n"), checks.indexOf("\npermissions:\n"));
  assert.doesNotMatch(on, /\n {2}push:/);
  const group = /\nconcurrency:\n {2}group: >-\n([\s\S]*?)\n {2}cancel-in-progress:/.exec(checks)[1];
  assert.match(group, /github\.event\.pull_request\.number \|\| github\.run_id/);
});

// #9276 plan item 8: the lanes App token arms a lane pull request as soon as
// the issue lane finishes, in pr-merge.yml, the one caller the token broker
// mints `merge` for; the merge job's gate never runs on that event.
test("the issue lane finishing wakes only the enable-auto-merge job", () => {
  assert.match(merge, /\n {2}workflow_run: # zizmor: ignore\[dangerous-triggers\]\n {4}workflows: \[work-resolve-issue\]\n {4}types: \[completed\]\n/);
  assert.match(job("merge"), /\n {6}&& github\.event_name != 'workflow_run'\n/);
  const arm = job("enable-auto-merge");
  assert.doesNotMatch(/\n {4}if: >-\n([\s\S]*?)\n {4}[a-z-]+:/.exec(arm)[1], /workflow_run'\n/);
  assert.match(arm, /\n {4}concurrency:\n {6}group: pr-merge-enable-auto-merge\n {6}queue: max\n/);
});

test("enable-auto-merge asks the broker for its own activity's merge token", () => {
  const arm = job("enable-auto-merge");
  const steps = [...arm.matchAll(/\n {10}lane: (.*)\n {10}activity: (.*)\n/g)].map((m) => `${m[1]}/${m[2]}`);
  assert.deepEqual(steps, ["pr-merge/enable-auto-merge", "pr-merge/enable-auto-merge"]);
  assert.match(arm, /node \.base\/\.github\/scripts\/pr-merge\/enable-auto-merge\.mjs/);
  const block = /\n {4}permissions:\n((?: {6}[a-z-]+: [a-z]+.*\n)+)/.exec(arm)[1];
  assert.deepEqual(
    [...block.matchAll(/ {6}([a-z-]+): ([a-z]+)/g)].map((m) => `${m[1]}: ${m[2]}`),
    ["contents: read", "id-token: write"],
  );
});
