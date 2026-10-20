// The report-red-main job's hardening (README.md, "Red main"): it runs only
// for a failed full run on main, never for an event the lanes App sent; it
// holds the job's own token, writes only issues and mints no token; and the
// kill switch stops it before it reads.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const text = readFileSync(new URL("../../workflows/post-merge-demotion-alert.yml", import.meta.url), "utf8");
const job = text.slice(text.indexOf("\n  report-red-main:\n"));

test("the report job runs only after the alert, for a failed full run on main", () => {
  assert.match(job, /\n {4}needs: \[alert\]\n/);
  assert.match(job, /github\.event\.workflow_run\.name == 'pr-require-checks'/);
  assert.match(job, /contains\(fromJSON\('\["schedule", "workflow_dispatch"\]'\), github\.event\.workflow_run\.event\)/);
  assert.match(job, /github\.event\.workflow_run\.conclusion == 'failure'/);
  assert.match(job, /github\.event\.workflow_run\.head_branch == 'main'/);
});

test("an event the lanes App sent is skipped", () => {
  assert.match(job, /format\('\{0\}', github\.event\.sender\.id\) != vars\.AUTOMATION_LANES_APP_SENDER_ID/);
});

test("the token writes issues and nothing else, and the job mints no token", () => {
  const block = /\n {4}permissions:\n((?: {6}[a-z-]+: [a-z]+.*\n)+)/.exec(job)[1];
  assert.deepEqual(Object.fromEntries([...block.matchAll(/ {6}([a-z-]+): ([a-z]+)/g)].map((m) => [m[1], m[2]])), {
    actions: "read",
    checks: "read",
    contents: "read",
    issues: "write",
    "pull-requests": "read",
  });
  assert.doesNotMatch(job, /id-token|request-lane-token|create-github-app-token|secrets\.|claude-code-action/);
});

test("the kill switch is checked before the report reads anything", () => {
  const kill = job.indexOf("check-kill-switch");
  const work = job.indexOf("node .base/.github/scripts/post-merge-demotion-alert/report.mjs");
  assert.ok(kill > 0 && work > kill);
  assert.match(job, /value: \$\{\{ vars\.CLAUDE_LANES_DISABLED \}\}/);
  for (const step of job.split("\n      - name: ").filter((s) => /^(Install|Report the culprit)/.test(s))) {
    assert.match(step, /\n {8}if: steps\.kill\.outputs\.proceed == 'true'\n/);
  }
});

test("main's tip is checked out without credentials, and every action is pinned", () => {
  assert.match(job, /ref: refs\/heads\/main\n/);
  assert.match(job, /persist-credentials: false\n/);
  for (const [, ref] of job.matchAll(/uses: ([^\s]+)/g)) {
    if (ref.startsWith("./")) continue;
    assert.match(ref, /@[0-9a-f]{40}$/, ref);
  }
});

test("the run step takes every event field through env", () => {
  const run = /\n {8}run: (.*)\n?$/.exec(job)[1];
  assert.doesNotMatch(run, /\$\{\{/);
});
