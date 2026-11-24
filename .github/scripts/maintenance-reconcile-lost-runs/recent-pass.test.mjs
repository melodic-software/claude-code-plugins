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
  assert.equal((await run({ MIN_GAP_MINUTES: "15" }, at("2026-11-10T14:22:00Z"))).output, "skip=false\n");
});

test("a newer run with no settled artifact (a paced, kill-switch or idle tick) is not a full pass", async () => {
  const pacedTick = runAt(42837900000, "2026-11-10T14:35:00Z", { event: "schedule" });
  const old = fakeGitHub([pacedTick, runAt(42837000002, "2026-11-10T14:10:00Z")], { 42837000002: [settled(2)] });
  assert.equal((await run({}, old.github)).output, "skip=false\n");
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
  const own = fakeGitHub([runAt(THIS_RUN, "2026-11-10T14:50:00Z")], { [THIS_RUN]: [settled(5)] });
  assert.equal((await run({}, own.github)).output, "skip=false\n", "this run");
});

test("force, another event or a gap of 0 runs the pass without reading anything", async () => {
  const { github, calls } = fakeGitHub([runAt(42837468246, "2026-11-10T14:48:00Z")], { 42837468246: [settled(1)] });
  assert.equal((await run({}, github)).output, "skip=true\n", "the same reads skip an unforced dispatch");
  calls.length = 0;
  for (const env of [{ FORCE: "true" }, { EVENT_NAME: "push" }, { MIN_GAP_MINUTES: "0" }, { MIN_GAP_MINUTES: "" }, { MIN_GAP_MINUTES: "x" }]) {
    assert.equal((await run(env, github)).output, "skip=false\n", JSON.stringify(env));
  }
  assert.deepEqual(calls, []);
});

const PASS_AFTER = String(Date.parse("2026-11-10T14:30:00Z") / 1000);
const startedAt = (id, startedIso, updatedIso) => runAt(id, updatedIso, { event: "schedule", run_started_at: startedIso });

test("a due tick skips when a full pass started after its window's reset, naming that run", async () => {
  const { github } = fakeGitHub([startedAt(42837000010, "2026-11-10T14:34:00Z", "2026-11-10T14:35:10Z")], { 42837000010: [settled(10)] });
  const result = await run({ EVENT_NAME: "schedule", PASS_AFTER }, github);
  assert.equal(result.output, "skip=true\n");
  assert.deepEqual(result.lines, ["::notice title=recent-pass::run 42837000010 started a full pass at 2026-11-10T14:34:00Z, after this token window's reset; this tick skips its work"]);
});

test("a due tick runs when the last full pass started before its window's reset, though it finished after", async () => {
  const { github } = fakeGitHub([startedAt(42837000011, "2026-11-10T14:29:50Z", "2026-11-10T14:31:00Z")], { 42837000011: [settled(11)] });
  assert.equal((await run({ EVENT_NAME: "schedule", PASS_AFTER }, github)).output, "skip=false\n");
});

test("a tick with no pass-after skips only when a full pass finished under the gap ago", async () => {
  const { github } = fakeGitHub([startedAt(42837000012, "2026-11-10T14:20:00Z", "2026-11-10T14:22:00Z")], { 42837000012: [settled(12)] });
  const result = await run({ EVENT_NAME: "schedule" }, github);
  assert.equal(result.output, "skip=true\n", "29 minutes under the 30-minute gap");
  assert.match(result.lines[0], /under 30 minutes ago; this tick skips its work$/);
  assert.equal((await run({ EVENT_NAME: "schedule", MIN_GAP_MINUTES: "15" }, github)).output, "skip=false\n");
});

test("a failed read runs the pass, with a warning", async () => {
  const down = async () => {
    throw new Error("502 Bad Gateway");
  };
  const result = await run({}, down);
  assert.equal(result.output, "skip=false\n");
  assert.deepEqual(result.lines, ["::warning::the recent-pass check could not read the last pass (502 Bad Gateway); the dispatch runs"]);
});

test("the reconciler workflow gates its plan and act steps on the check, after the pacer", () => {
  const text = readFileSync(new URL("../../workflows/maintenance-reconcile-lost-runs.yml", import.meta.url), "utf8");
  assert.match(text, /\n {2}workflow_dispatch:\n {4}inputs:\n {6}force:\n[^\n]*\n {8}type: boolean\n {8}default: false\n/);
  const steps = text.split(/\n(?= {6}- name: )/).slice(1).map((s) => ({ name: /^ {6}- name: (.*)$/m.exec(s)[1], s: s.replace(/(\n *(#[^\n]*)?)+$/, "") }));
  const at = (name) => steps.findIndex((step) => step.name === name);
  const check = steps[at("Skip a run right after a full pass")]?.s ?? "";
  assert.match(check, /\n {8}id: recent\n/);
  assert.match(check, /\n {8}continue-on-error: true\n/);
  assert.match(check, /\n {8}if: steps\.reset\.outputs\.due != 'false' \|\| steps\.reset\.outputs\.pass-after != ''\n/, "the check runs on every due run, and on a late tick that names its window");
  assert.match(check, /\n {10}MIN_GAP_MINUTES: "60"\n/, "the gap is an hour, one token window");
  assert.match(check, /\n {10}PASS_AFTER: \$\{\{ steps\.reset\.outputs\.pass-after \}\}\n/);
  assert.match(check, /\n {10}FORCE: \$\{\{ inputs\.force \}\}\n/);
  assert.match(check, /\n {10}EVENT_NAME: \$\{\{ github\.event_name \}\}\n/);
  assert.match(check, /\n {10}FOLLOWUP_PATH: \$\{\{ runner\.temp \}\}\/reconcile-followup\.json\n/);
  assert.match(check, /\n {8}run: node \.base\/\.github\/scripts\/maintenance-reconcile-lost-runs\/recent-pass\.mjs$/);
  assert.ok(at("Check the token window's reset") < at("Skip a run right after a full pass"), "the reset is read first");
  assert.ok(at("Skip a run right after a full pass") < at("Check the kill switch"), "a follow-up tick knows it has a queue before the budget gate");
  assert.match(steps[at("Check the kill switch")].s, /\n {8}if: steps\.reset\.outputs\.due != 'false' \|\| steps\.recent\.outputs\.followup == 'true'\n/, "the budget gate stops a follow-up too");
  assert.match(steps[at("Check the kill switch")].s, /\n {10}budget: "true"$/);
  const followPath = /\n {10}FOLLOWUP_PATH: \$\{\{ runner\.temp \}\}\/reconcile-followup\.json\n/;
  assert.match(steps[at("Find lost runs")].s, /\n {10}FOLLOWUP: \$\{\{ steps\.recent\.outputs\.followup \}\}\n/);
  assert.match(steps[at("Find lost runs")].s, followPath, "the plan reads the queue the check wrote");
  for (const name of ["Find lost runs", "Re-run lost runs"]) {
    assert.ok(at(name) > at("Skip a run right after a full pass"), `${name} follows the check`);
    assert.match(
      steps[at(name)].s,
      /\n {8}if: \(steps\.reset\.outputs\.due != 'false' && steps\.pace\.outputs\.paced != 'true' && steps\.recent\.outputs\.skip != 'true'\) \|\| steps\.recent\.outputs\.followup == 'true'\n/,
      `${name}: the full pass's gate, unchanged, or a follow-up`,
    );
  }
  const carry = steps.filter((step) => step.name === "Carry the settled runs" || /\n {8}id: scan-upload-4\n/.test(step.s));
  assert.equal(carry.length, 2);
  for (const step of carry) {
    assert.match(step.s, /steps\.recent\.outputs\.followup != 'true'/, `${step.name}: a follow-up uploads no marker, so it never reads as the window's full pass`);
  }
});

const WRITTEN = JSON.parse(readFileSync(new URL("./fixtures/settled-waiting.json", import.meta.url), "utf8"));
const WAITING = WRITTEN.waiting_reviews;
const carryAs = (change) => {
  const carry = structuredClone(WRITTEN);
  change(carry);
  return JSON.stringify(carry);
};

const followRun = async (carryText, { artifactId = 77, env = {} } = {}) => {
  const dir = tempDir("recent-pass-follow-");
  const followPath = join(dir, "followup.json");
  const { github, calls } = fakeGitHub([startedAt(42837000020, "2026-11-10T14:34:00Z", "2026-11-10T14:35:10Z")], { 42837000020: [settled(artifactId)] });
  const downloads = [];
  const download = (id) => {
    downloads.push(id);
    if (carryText instanceof Error) {
      throw carryText;
    }
    return carryText;
  };
  const output = join(dir, "output");
  writeFileSync(output, "");
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    await main(
      { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: WRITTEN.repository, GITHUB_RUN_ID: String(THIS_RUN), GITHUB_OUTPUT: output, EVENT_NAME: "schedule", MIN_GAP_MINUTES: "60", PASS_AFTER, FOLLOWUP_PATH: followPath, ...env },
      { github, now: () => NOW, download },
    );
  } finally {
    console.log = log;
  }
  let queued;
  try {
    queued = JSON.parse(readFileSync(followPath, "utf8"));
  } catch {}
  return { output: readFileSync(output, "utf8"), lines, downloads, calls, queued };
};

test("a late tick whose window's full pass left reviews waiting downloads that pass's artifact by id and queues them for the follow-up", async () => {
  assert.equal(WAITING.length, 2, "the captured full pass left two reviews waiting");
  const result = await followRun(JSON.stringify(WRITTEN));
  assert.equal(result.output, "skip=true\nfollowup=true\n");
  assert.deepEqual(result.downloads, [77], "the archive is fetched once, by the artifact id the listing gave");
  assert.deepEqual(result.queued, { run_id: 42837000020, waiting_reviews: WAITING });
  assert.ok(result.lines.includes("::notice title=recent-pass::run 42837000020 left 2 reviews waiting on a checks run; this tick follows them up"));
});

test("an empty, missing or unreadable queue follows up nothing, and the tick still skips", async () => {
  for (const [label, text] of [
    ["an empty queue", carryAs((c) => (c.waiting_reviews = []))],
    ["a carry from before the queue", carryAs((c) => delete c.waiting_reviews)],
    ["a row naming a lane that is not a hosted review", carryAs((c) => (c.waiting_reviews[1].path = ".github/workflows/pr-verify.yml"))],
    ["a row with no checks run", carryAs((c) => delete c.waiting_reviews[0].checksRunId)],
    ["a row with a short head", carryAs((c) => (c.waiting_reviews[0].head = c.waiting_reviews[0].head.slice(1)))],
    ["queue rows that are not a list", carryAs((c) => (c.waiting_reviews = c.waiting_reviews[0]))],
    ["another settled version", carryAs((c) => (c.version += 1))],
    ["another repository's carry", carryAs((c) => (c.repository = "x/y"))],
    ["a failed download", new Error("HTTP 410")],
  ]) {
    const result = await followRun(text);
    assert.equal(result.output, "skip=true\n", label);
    assert.equal(result.queued, undefined, label);
  }
});

test("only a scheduled tick matched by its window follows up: a gap hit, or no FOLLOWUP_PATH, downloads nothing", async () => {
  const gapHit = await followRun(JSON.stringify(WRITTEN), { env: { PASS_AFTER: "" } });
  assert.deepEqual([gapHit.output, gapHit.downloads], ["skip=true\n", []]);
  const unset = await followRun(JSON.stringify(WRITTEN), { env: { FOLLOWUP_PATH: "" } });
  assert.deepEqual([unset.output, unset.downloads], ["skip=true\n", []]);
});
