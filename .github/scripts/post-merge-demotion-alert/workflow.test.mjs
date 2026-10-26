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
  assert.match(job, /needs\.alert\.outputs\.name == 'pr-require-checks'/);
  assert.match(job, /contains\(fromJSON\('\["schedule", "workflow_dispatch"\]'\), needs\.alert\.outputs\.event\)/);
  assert.match(job, /needs\.alert\.outputs\.conclusion == 'failure'/);
  assert.match(job, /needs\.alert\.outputs\.branch == 'main'/);
  assert.match(job, /needs\.alert\.outputs\.repo == github\.repository/);
});

test("the report reads the run from the alert job's outputs, never the event, so a dispatch reaches it", () => {
  assert.doesNotMatch(job, /github\.event\.workflow_run/);
  for (const [env, output] of [
    ["RUN_ID", "id"],
    ["RUN_SHA", "sha"],
    ["RUN_URL", "url"],
    ["RUN_WORKFLOW_ID", "workflow-id"],
    ["RUN_CREATED", "created"],
  ]) {
    assert.match(job, new RegExp(`\\n {10}${env}: \\$\\{\\{ needs\\.alert\\.outputs\\.${output} \\}\\}\\n`));
  }
  const alert = text.slice(text.indexOf("\n  alert:\n"), text.indexOf("\n  report-red-main:\n"));
  for (const output of [
    "name",
    "event",
    "conclusion",
    "branch",
    "repo",
    "sha",
    "url",
    "id",
    "workflow-id",
    "created",
  ]) {
    assert.match(alert, new RegExp(`\\n {6}${output}: \\$\\{\\{ steps\\.run\\.outputs\\.${output} \\}\\}\\n`));
  }
});

test("no report runs when the judge excused the run", () => {
  assert.match(job, /needs\.alert\.outputs\.excused != 'true'/);
  const alert = text.slice(text.indexOf("\n  alert:\n"), text.indexOf("\n  report-red-main:\n"));
  assert.match(alert, /\n {6}excused: \$\{\{ steps\.file\.outputs\.excused \}\}\n/);
});

test("no report runs when the alert found main already recovered", () => {
  assert.match(job, /needs\.alert\.outputs\.recovered != 'true'/);
  const alert = text.slice(text.indexOf("\n  alert:\n"), text.indexOf("\n  report-red-main:\n"));
  assert.match(alert, /\n {6}recovered: \$\{\{ steps\.file\.outputs\.recovered \}\}\n/);
  assert.match(alert, /\n {8}id: file\n/);
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
  const runs = [...job.matchAll(/\n {8}run: (.*)/g)].map((match) => match[1]);
  assert.ok(runs.includes("node .base/.github/scripts/post-merge-demotion-alert/report.mjs"), runs.join("\n"));
  for (const run of runs) {
    assert.doesNotMatch(run, /\$\{\{/);
  }
});

// Records are one per signal and SHA, found by a read before a create, so
// every sighting of one signal and SHA must wait on the others: a dispatch
// and a workflow_run event of the same run, and two runs of one SHA.
test("the alert's group keys on signal and head SHA, the same for a dispatch and a workflow_run event", () => {
  const alert = text.slice(text.indexOf("\n  alert:\n"), text.indexOf("\n  report-red-main:\n"));
  const block = /\n {4}concurrency:\n {6}group: (.*)\n {6}cancel-in-progress: false\n/.exec(alert);
  assert.ok(block, "a job-level concurrency block that cancels nothing");
  assert.doesNotMatch(block[1], /workflow_run\.id|run-id/);
  const group = (ctx) =>
    block[1].replace(/\$\{\{ (.*?) \}\}/g, (_, expr) => {
      for (const alt of expr.split(" || ")) {
        const value = /^'(.*)'$/.exec(alt)?.[1] ?? ctx[alt];
        if (value) return value;
      }
      return "";
    });
  const sha = "0123456789abcdef0123456789abcdef01234567";
  const sighting = group({
    "github.event.workflow_run.name": "pr-require-checks",
    "github.event.workflow_run.event": "workflow_dispatch",
    "github.event.workflow_run.head_sha": sha,
  });
  assert.equal(sighting, `post-merge-demotion-alert-pr-require-checks-workflow_dispatch-${sha}`);
  assert.equal(group({ "inputs['head-sha']": sha }), sighting);
});

test("reports run one at a time across the repository, so two cannot both read the log before writing", () => {
  assert.match(job, /\n {4}concurrency:\n {6}group: red-main-report\n {6}cancel-in-progress: false\n/);
});
