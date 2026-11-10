// The dispatch gap (recent-pass.mjs): a hand-started pass is skipped when a
// trusted run finished a full pass, one that uploaded reconcile-settled-runs,
// under MIN_GAP_MINUTES ago, and runs otherwise. Times are picked by hand
// around the 2026-11-10 pair of dispatches, 14:46Z and 14:51Z.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { main } from "./recent-pass.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const NOW = Date.parse("2026-11-10T14:51:00Z");
const PATH = ".github/workflows/maintenance-reconcile-lost-runs.yml";
const THIS_RUN = 42838338856;

const runAt = (id, updatedAt, extra = {}) => ({ id, path: PATH, event: "workflow_dispatch", head_branch: "main", status: "completed", updated_at: updatedAt, ...extra });
const settled = (id, expired = false) => ({ id, name: "reconcile-settled-runs", expired });

// A GitHub stand-in: the workflow's run listing, then each run's artifacts.
const fakeGitHub = (runs, artifactsByRun) => {
  const calls = [];
  const github = async (method, path) => {
    calls.push(`${method} ${path}`);
    if (path.includes("/actions/workflows/maintenance-reconcile-lost-runs.yml/runs?")) {
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

const run = async (env, github) => {
  const dir = tempDir("recent-pass-");
  const output = join(dir, "output");
  writeFileSync(output, "");
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    await main(
      { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: String(THIS_RUN), GITHUB_OUTPUT: output, EVENT_NAME: "workflow_dispatch", FORCE: "false", MIN_GAP_MINUTES: "30", ...env },
      { github, now: () => NOW },
    );
  } finally {
    console.log = log;
  }
  return { output: readFileSync(output, "utf8"), lines };
};

test("a dispatch 3 minutes after a full pass skips its work, naming that run", async () => {
  const { github } = fakeGitHub([runAt(THIS_RUN, "2026-11-10T14:51:00Z", { status: "in_progress" }), runAt(42837468246, "2026-11-10T14:48:00Z")], {
    42837468246: [settled(1)],
  });
  const result = await run({}, github);
  assert.equal(result.output, "skip=true\n");
  assert.equal(result.lines.length, 1);
  assert.match(result.lines[0], /^::notice title=recent-pass::run 42837468246 finished a full pass at 2026-11-10T14:48:00Z, under 30 minutes ago/);
});

test("the gap is MIN_GAP_MINUTES: a pass 29 minutes ago skips, one 31 minutes ago runs", async () => {
  const at = (updatedAt) => fakeGitHub([runAt(42837000001, updatedAt)], { 42837000001: [settled(1)] }).github;
  assert.equal((await run({}, at("2026-11-10T14:22:00Z"))).output, "skip=true\n");
  assert.equal((await run({}, at("2026-11-10T14:20:00Z"))).output, "skip=false\n");
  // A shorter configured gap lets the 29-minute-old pass run.
  assert.equal((await run({ MIN_GAP_MINUTES: "15" }, at("2026-11-10T14:22:00Z"))).output, "skip=false\n");
});

test("a newer run with no settled artifact (a paced, kill-switch or idle tick) is not a full pass", async () => {
  const pacedTick = runAt(42837900000, "2026-11-10T14:35:00Z", { event: "schedule" });
  // The only full pass is 41 minutes old: the dispatch runs.
  const old = fakeGitHub([pacedTick, runAt(42837000002, "2026-11-10T14:10:00Z")], { 42837000002: [settled(2)] });
  assert.equal((await run({}, old.github)).output, "skip=false\n");
  // The same paced tick ahead of a full pass 20 minutes old: the dispatch skips.
  const recent = fakeGitHub([pacedTick, runAt(42837000003, "2026-11-10T14:31:00Z", { event: "schedule" })], { 42837000003: [settled(3)] });
  assert.equal((await run({}, recent.github)).output, "skip=true\n");
});

test("an expired settled artifact, or one from an untrusted or unfinished run, does not count", async () => {
  const cases = {
    expired: [runAt(42837000004, "2026-11-10T14:48:00Z"), [settled(4, true)]],
    "another workflow path": [runAt(42837000004, "2026-11-10T14:48:00Z", { path: ".github/workflows/other.yml" }), [settled(4)]],
    "a branch other than main": [runAt(42837000004, "2026-11-10T14:48:00Z", { head_branch: "feature" }), [settled(4)]],
    "a pull_request event": [runAt(42837000004, "2026-11-10T14:48:00Z", { event: "pull_request" }), [settled(4)]],
    "a run still in progress": [runAt(42837000004, "2026-11-10T14:48:00Z", { status: "in_progress" }), [settled(4)]],
  };
  for (const [name, [listed, artifacts]] of Object.entries(cases)) {
    const { github } = fakeGitHub([listed], { 42837000004: artifacts });
    assert.equal((await run({}, github)).output, "skip=false\n", name);
  }
  // This run's own artifact never counts.
  const own = fakeGitHub([runAt(THIS_RUN, "2026-11-10T14:50:00Z")], { [THIS_RUN]: [settled(5)] });
  assert.equal((await run({}, own.github)).output, "skip=false\n", "this run");
});

test("force, a schedule tick or a gap of 0 runs the pass without reading anything", async () => {
  const { github, calls } = fakeGitHub([runAt(42837468246, "2026-11-10T14:48:00Z")], { 42837468246: [settled(1)] });
  assert.equal((await run({}, github)).output, "skip=true\n", "the same reads skip an unforced dispatch");
  calls.length = 0;
  for (const env of [{ FORCE: "true" }, { EVENT_NAME: "schedule", FORCE: "" }, { MIN_GAP_MINUTES: "0" }, { MIN_GAP_MINUTES: "" }, { MIN_GAP_MINUTES: "x" }]) {
    assert.equal((await run(env, github)).output, "skip=false\n", JSON.stringify(env));
  }
  assert.deepEqual(calls, []);
});

test("a failed read runs the pass, with a warning", async () => {
  const down = async () => {
    throw new Error("502 Bad Gateway");
  };
  const result = await run({}, down);
  assert.equal(result.output, "skip=false\n");
  assert.deepEqual(result.lines, ["::warning::the recent-pass check could not read the last pass (502 Bad Gateway); the dispatch runs"]);
});

// The workflow wiring: the check runs before the work, never fails the job,
// gates both spending steps, and takes force from the dispatch input.
test("the reconciler workflow gates its plan and act steps on the check, after the pacer", () => {
  const text = readFileSync(new URL("../../workflows/maintenance-reconcile-lost-runs.yml", import.meta.url), "utf8");
  assert.match(text, /\n {2}workflow_dispatch:\n {4}inputs:\n {6}force:\n[^\n]*\n {8}type: boolean\n {8}default: false\n/);
  const steps = text.split(/\n(?= {6}- name: )/).slice(1).map((s) => ({ name: /^ {6}- name: (.*)$/m.exec(s)[1], s: s.replace(/(\n *(#[^\n]*)?)+$/, "") }));
  const at = (name) => steps.findIndex((step) => step.name === name);
  const check = steps[at("Skip a dispatch right after a full pass")]?.s ?? "";
  assert.match(check, /\n {8}id: recent\n/);
  assert.match(check, /\n {8}continue-on-error: true\n/);
  assert.doesNotMatch(check, /\n {8}if: /, "the check runs on every event");
  assert.match(check, /\n {10}MIN_GAP_MINUTES: "30"\n/, "the gap is the cron's 30-minute cadence");
  assert.match(check, /\n {10}FORCE: \$\{\{ inputs\.force \}\}\n/);
  assert.match(check, /\n {10}EVENT_NAME: \$\{\{ github\.event_name \}\}\n/);
  assert.match(check, /\n {8}run: node \.base\/\.github\/scripts\/maintenance-reconcile-lost-runs\/recent-pass\.mjs$/);
  assert.match(text, /\n {4}- cron: "4,34 \* \* \* \*"\n/, "the cron the gap matches");
  for (const name of ["Find lost runs", "Re-run lost runs"]) {
    assert.ok(at(name) > at("Skip a dispatch right after a full pass"), `${name} follows the check`);
    assert.match(steps[at(name)].s, /\n {8}if: steps\.pace\.outputs\.paced != 'true' && steps\.recent\.outputs\.skip != 'true'\n/, name);
  }
});
