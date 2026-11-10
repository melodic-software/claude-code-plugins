// The sweep gap (sweep-gap.mjs): a sweep a finished work-resolve-issue run
// starts is skipped when a sweep run uploaded work-unblock-verdicts under
// limits.sweep-gap-minutes (15) ago, and runs otherwise; a schedule, a close
// or a dispatch never skips. Times are picked by hand around the 2026-11-10
// hour of seven full sweeps, 19:55Z to 20:55Z.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { main } from "./sweep-gap.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const NOW = Date.parse("2026-11-10T20:55:00Z");
const PATH = ".github/workflows/work-unblock.yml";
const REPO = "o/r";
const THIS_RUN = 42898100951;

const runAt = (id, updatedAt, extra = {}) => ({
  id,
  path: PATH,
  event: "workflow_run",
  head_branch: "main",
  head_repository: { full_name: REPO },
  status: "completed",
  conclusion: "success",
  updated_at: updatedAt,
  ...extra,
});
const verdicts = (id, expired = false) => ({ id, name: "work-unblock-verdicts", expired });

// A GitHub stand-in: the workflow's run listing, then each run's artifacts.
const fakeGitHub = (runs, artifactsByRun) => {
  const calls = [];
  const github = async (method, path) => {
    calls.push(`${method} ${path}`);
    if (path.includes("/actions/workflows/work-unblock.yml/runs?")) {
      return { total_count: runs.length, workflow_runs: runs };
    }
    const id = /\/actions\/runs\/(\d+)\/artifacts/.exec(path)?.[1];
    if (id !== undefined) {
      const artifacts = artifactsByRun[id] ?? [];
      return { total_count: artifacts.length, artifacts };
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { github, calls };
};

const run = async (env, github, limits = { "sweep-gap-minutes": 15 }) => {
  const dir = tempDir("sweep-gap-");
  const output = join(dir, "output");
  writeFileSync(output, "");
  const config = join(dir, "resolved-config.json");
  if (limits !== undefined) writeFileSync(config, JSON.stringify({ limits }));
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    await main(
      { ACTIONS_TOKEN: "t", GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: String(THIS_RUN), GITHUB_OUTPUT: output, RESOLVED_CONFIG: config, EVENT_NAME: "workflow_run", ...env },
      { github, now: () => NOW },
    );
  } finally {
    console.log = log;
  }
  return { output: readFileSync(output, "utf8"), lines };
};

test("a work-resolve-issue run's sweep 5 minutes after a full sweep skips, naming that run, in two calls", async () => {
  const { github, calls } = fakeGitHub([runAt(THIS_RUN, "2026-11-10T20:55:00Z", { status: "in_progress", conclusion: null }), runAt(42897142652, "2026-11-10T20:50:00Z")], {
    42897142652: [verdicts(1)],
  });
  const result = await run({}, github);
  assert.equal(result.output, "skip=true\n");
  assert.equal(result.lines.length, 1);
  assert.match(result.lines[0], /^::notice title=sweep-gap::run 42897142652 finished a full sweep at 2026-11-10T20:50:00Z, under 15 minutes ago/);
  assert.equal(calls.length, 2, "one run listing and one artifact listing");
});

// A skipped sweep ends green with no artifact, so each one since the last full
// sweep costs an artifact listing before the full sweep is found.
test("three skipped sweeps ahead of a full one in the gap: the sweep skips, in five calls", async () => {
  const skipped = [42897900003, 42897900002, 42897900001].map((id, i) => runAt(id, `2026-11-10T20:5${4 - i}:00Z`));
  const { github, calls } = fakeGitHub([...skipped, runAt(42897142652, "2026-11-10T20:45:00Z")], { 42897142652: [verdicts(1)] });
  assert.equal((await run({}, github)).output, "skip=true\n");
  assert.equal(calls.length, 5, "one run listing and four artifact listings");
});

test("the gap is sweep-gap-minutes: a sweep exactly 15 minutes ago skips, one 15 minutes and a second ago runs", async () => {
  const at = (updatedAt) => fakeGitHub([runAt(42897000001, updatedAt)], { 42897000001: [verdicts(1)] }).github;
  assert.equal((await run({}, at("2026-11-10T20:40:00Z"))).output, "skip=true\n");
  assert.equal((await run({}, at("2026-11-10T20:39:59Z"))).output, "skip=false\n");
  assert.equal((await run({}, at("2026-11-10T20:30:00Z"))).output, "skip=false\n");
  // A shorter configured gap lets the 10-minute-old sweep run; a longer one skips the 25-minute-old one.
  assert.equal((await run({}, at("2026-11-10T20:45:00Z"), { "sweep-gap-minutes": 5 })).output, "skip=false\n");
  assert.equal((await run({}, at("2026-11-10T20:30:00Z"), { "sweep-gap-minutes": 30 })).output, "skip=true\n");
  // With no resolved config, the default gap is 15 minutes.
  assert.equal((await run({}, at("2026-11-10T20:41:00Z"), undefined)).output, "skip=true\n");
  assert.equal((await run({}, at("2026-11-10T20:39:00Z"), undefined)).output, "skip=false\n");
});

test("a scheduled or red full sweep counts; a newer run with no verdicts artifact does not", async () => {
  const scheduled = fakeGitHub([runAt(42897000002, "2026-11-10T20:47:30Z", { event: "schedule" })], { 42897000002: [verdicts(2)] });
  assert.equal((await run({}, scheduled.github)).output, "skip=true\n", "the hourly sweep");
  const red = fakeGitHub([runAt(42897000003, "2026-11-10T20:50:00Z", { conclusion: "failure" })], { 42897000003: [verdicts(3)] });
  assert.equal((await run({}, red.github)).output, "skip=true\n", "a sweep that ended red still spent its calls");
  // A held sweep uploads no file: it is not a full sweep, and the older full one decides.
  const held = runAt(42897900000, "2026-11-10T20:52:00Z");
  const old = fakeGitHub([held, runAt(42897000004, "2026-11-10T20:30:00Z")], { 42897000004: [verdicts(4)] });
  assert.equal((await run({}, old.github)).output, "skip=false\n");
  const recent = fakeGitHub([held, runAt(42897000005, "2026-11-10T20:45:00Z")], { 42897000005: [verdicts(5)] });
  assert.equal((await run({}, recent.github)).output, "skip=true\n");
});

test("an expired artifact, or one from an issue close, a fork, another branch, a cancelled or unfinished run, does not count", async () => {
  const at = "2026-11-10T20:50:00Z";
  const cases = {
    expired: [runAt(42897000006, at), [verdicts(6, true)]],
    "an issue close": [runAt(42897000006, at, { event: "issues" }), [verdicts(6)]],
    "another workflow path": [runAt(42897000006, at, { path: ".github/workflows/other.yml" }), [verdicts(6)]],
    "a fork": [runAt(42897000006, at, { head_repository: { full_name: "someone/r" } }), [verdicts(6)]],
    "a branch other than main": [runAt(42897000006, at, { head_branch: "feature" }), [verdicts(6)]],
    "a cancelled run": [runAt(42897000006, at, { conclusion: "cancelled" }), [verdicts(6)]],
    "a skipped run": [runAt(42897000006, at, { conclusion: "skipped" }), [verdicts(6)]],
    "a run still in progress": [runAt(42897000006, at, { status: "in_progress", conclusion: null }), [verdicts(6)]],
  };
  for (const [name, [listed, artifacts]] of Object.entries(cases)) {
    const { github } = fakeGitHub([listed], { 42897000006: artifacts });
    assert.equal((await run({}, github)).output, "skip=false\n", name);
  }
  // This run's own artifact never counts.
  const own = fakeGitHub([runAt(THIS_RUN, at)], { [THIS_RUN]: [verdicts(7)] });
  assert.equal((await run({}, own.github)).output, "skip=false\n", "this run");
});

test("a schedule, an issue close, a dispatch or a gap of 0 runs the sweep without reading anything", async () => {
  const { github, calls } = fakeGitHub([runAt(42897142652, "2026-11-10T20:50:00Z")], { 42897142652: [verdicts(1)] });
  assert.equal((await run({}, github)).output, "skip=true\n", "the same reads skip a work-resolve-issue run's sweep");
  calls.length = 0;
  for (const event of ["schedule", "issues", "workflow_dispatch"]) {
    assert.equal((await run({ EVENT_NAME: event }, github)).output, "skip=false\n", event);
  }
  assert.equal((await run({}, github, { "sweep-gap-minutes": 0 })).output, "skip=false\n", "gap 0");
  assert.deepEqual(calls, []);
});

test("a failed read runs the sweep, with a warning", async () => {
  const down = async () => {
    throw new Error("502 Bad Gateway");
  };
  const result = await run({}, down);
  assert.equal(result.output, "skip=false\n");
  assert.deepEqual(result.lines, ["::warning::the sweep-gap check could not read the last sweep (502 Bad Gateway); the sweep runs"]);
});

// The workflow wiring: the check runs after the config and before the token
// request, never fails the job, and a skip stops the mint and so the sweep.
test("work-unblock.yml gates the lane token on the check, after the config", () => {
  const text = readFileSync(new URL("../../workflows/work-unblock.yml", import.meta.url), "utf8");
  const job = text.split("\n  sync-status:\n")[0];
  const steps = job.split(/\n(?= {6}- name: )/).slice(1).map((s) => ({ name: /^ {6}- name: (.*)$/m.exec(s)[1], s: s.replace(/(\n *(#[^\n]*)?)+$/, "") }));
  const at = (name) => steps.findIndex((step) => step.name === name);
  const check = steps[at("Skip a sweep right after a full sweep")]?.s ?? "";
  assert.match(check, /\n {8}id: gap\n/);
  assert.match(check, /\n {8}continue-on-error: true\n/);
  assert.match(check, /\n {8}if: steps\.config\.outcome == 'success' && steps\.config\.outputs\.applies == 'true'\n/);
  assert.match(check, /\n {10}EVENT_NAME: \$\{\{ github\.event_name \}\}\n/);
  assert.match(check, /\n {10}RESOLVED_CONFIG: \$\{\{ runner\.temp \}\}\/resolved-config\.json\n/);
  assert.match(check, /\n {10}ACTIONS_TOKEN: \$\{\{ github\.token \}\}\n/);
  assert.match(check, /\n {8}run: node \.base\/\.github\/scripts\/work-unblock\/sweep-gap\.mjs$/);
  assert.ok(at("Resolve the config") < at("Skip a sweep right after a full sweep"), "the check reads the resolved config");
  assert.ok(at("Skip a sweep right after a full sweep") < at("Request the lane token"));
  assert.match(steps[at("Request the lane token")].s, /\n {8}if: steps\.config\.outcome == 'success' && steps\.config\.outputs\.applies == 'true' && steps\.gap\.outputs\.skip != 'true'\n/);
  assert.match(steps[at("Label the unblocked issues")].s, /\n {8}if: steps\.lane-token\.outputs\.token != ''\n/, "no token, no sweep");
});
