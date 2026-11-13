// Expected values come from verdict-carry.mjs's rules: `read` takes the file
// only from a successful sweep (schedule, workflow_dispatch or workflow_run) of main's
// work-unblock.yml in this repository, and any failure leaves no file; a
// saved carry keeps at most JOBS_MAX and REFUSALS_MAX entries, newest used first.
import assert from "node:assert/strict";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { tempDir } from "../../../lib/test-tmp.mjs";

import { CARRY_ARTIFACT, codeDigest, JOBS_MAX, loadCarry, read, REFUSALS_MAX } from "./verdict-carry.mjs";

const REPO = "melodic-software/claude-code-plugins";
const sweepRun = (id, extra = {}) => ({
  id,
  path: ".github/workflows/work-unblock.yml",
  event: "workflow_run",
  head_branch: "main",
  conclusion: "success",
  head_repository: { full_name: REPO },
  ...extra,
});

// A fake Actions API: the listed runs, and one artifact per run in `withFile`.
function fakeActions(runs, withFile) {
  const calls = [];
  const actions = async (method, path) => {
    calls.push(path);
    if (path.includes("/actions/workflows/work-unblock.yml/runs")) return { workflow_runs: runs };
    const match = /\/actions\/runs\/(\d+)\/artifacts/.exec(path);
    if (match) {
      const artifacts = withFile.includes(Number(match[1])) ? [{ id: Number(match[1]) * 10, name: CARRY_ARTIFACT, expired: false }] : [];
      return { total_count: artifacts.length, artifacts };
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { actions, calls };
}

const envFor = (dir) => ({ VERDICTS_IN: join(dir, "in.json"), GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: "900" });

test("read takes the file of the newest successful sweep of main's work-unblock.yml, and of no other run", async () => {
  const dir = tempDir("verdict-carry-");
  const runs = [
    sweepRun(900),
    sweepRun(899, { event: "issues" }),
    sweepRun(898, { conclusion: "cancelled" }),
    sweepRun(897, { head_repository: { full_name: "someone/fork" } }),
    sweepRun(896, { head_branch: "feature" }),
    sweepRun(895),
    sweepRun(894, { event: "schedule" }),
  ];
  const { actions, calls } = fakeActions(runs, [900, 899, 898, 897, 896, 895, 894]);
  const asked = [];
  await read({ env: envFor(dir), actions, download: (id) => (asked.push(id), '{"jobs":{}}') });
  assert.deepEqual(asked, [8950]);
  assert.equal(readFileSync(join(dir, "in.json"), "utf8"), '{"jobs":{}}');
  // Only the one trusted run before it was asked for its artifacts.
  assert.deepEqual(calls.filter((path) => path.includes("/artifacts")), [`/repos/${REPO}/actions/runs/895/artifacts?per_page=100`]);
});

test("read takes the file of a hand-started sweep like a scheduled one", async () => {
  const dir = tempDir("verdict-carry-");
  const runs = [sweepRun(900), sweepRun(899, { event: "workflow_dispatch" }), sweepRun(898, { event: "schedule" })];
  const { actions } = fakeActions(runs, [900, 899, 898]);
  const asked = [];
  await read({ env: envFor(dir), actions, download: (id) => (asked.push(id), '{"jobs":{}}') });
  assert.deepEqual(asked, [8990]);
});

test("read leaves no file when no sweep kept one, the download is not a JSON object, or the listing fails", async () => {
  const dir = tempDir("verdict-carry-");
  const env = envFor(dir);
  const cases = [
    [fakeActions([sweepRun(895)], []).actions, () => "{}"],
    [fakeActions([sweepRun(895)], [895]).actions, () => "[1]"],
    [fakeActions([sweepRun(895)], [895]).actions, () => "{nope"],
    [async () => { throw new Error("403"); }, () => "{}"],
  ];
  for (const [actions, download] of cases) {
    // A file left there before is removed, never read.
    writeFileSync(env.VERDICTS_IN, '{"left":true}');
    await read({ env, actions, download });
    assert.equal(existsSync(env.VERDICTS_IN), false);
  }
});

test("a saved carry keeps the newest used entries up to its caps", () => {
  const dir = tempDir("verdict-carry-");
  const now = Date.parse("2026-11-10T03:00:00Z");
  const old = loadCarry(undefined, now - 60_000);
  for (let id = 1; id <= JOBS_MAX + 5; id += 1) {
    old.keepJobs({ id, run_attempt: 1, status: "completed", updated_at: "2026-11-10T01:00:00Z" }, [{ id: id * 10, name: "admit", steps: [] }]);
  }
  for (let id = 1; id <= REFUSALS_MAX + 5; id += 1) old.keepRefusal(id, "check", null);
  old.save(join(dir, "old.json"));
  // The next sweep uses run 1's entry, which is then the newest.
  const next = loadCarry(join(dir, "old.json"), now);
  assert.ok(next.jobsOf({ id: 1, run_attempt: 1, status: "completed", updated_at: "2026-11-10T01:00:00Z" }));
  next.save(join(dir, "new.json"));
  const saved = JSON.parse(readFileSync(join(dir, "new.json"), "utf8"));
  assert.equal(Object.keys(saved.jobs).length, JOBS_MAX);
  assert.equal(Object.keys(saved.refusals).length, REFUSALS_MAX);
  assert.ok(saved.jobs["1|1"]);
  // The kept job is the fields the sweep reads, no more.
  assert.deepEqual(saved.jobs["1|1"].jobs, [{ id: 10, name: "admit", conclusion: null, runner_id: null, started_at: null, steps: [] }]);
});

test("a carry kept by the same code is used, and one kept by other code is read fresh", () => {
  const dir = tempDir("verdict-carry-");
  const now = Date.parse("2026-11-10T03:00:00Z");
  const run = { id: 7, run_attempt: 1, status: "completed", updated_at: "2026-11-10T01:00:00Z" };
  const old = loadCarry(undefined, now - 60_000, "a".repeat(64));
  old.keepJobs(run, [{ id: 70, name: "admit", steps: [] }]);
  old.keepRefusal(70, "check", "kill-switch");
  old.save(join(dir, "kept.json"));
  assert.equal(JSON.parse(readFileSync(join(dir, "kept.json"), "utf8")).code, "a".repeat(64));
  const same = loadCarry(join(dir, "kept.json"), now, "a".repeat(64));
  assert.ok(same.jobsOf(run));
  assert.deepEqual(same.refusal(70, "check"), { value: "kill-switch" });
  const other = loadCarry(join(dir, "kept.json"), now, "b".repeat(64));
  assert.equal(other.jobsOf(run), undefined);
  assert.equal(other.refusal(70, "check"), undefined);
  // The file it keeps holds only what this code reads, stamped with its code.
  other.save(join(dir, "next.json"));
  assert.deepEqual(JSON.parse(readFileSync(join(dir, "next.json"), "utf8")), { code: "b".repeat(64), jobs: {}, refusals: {}, decided: {} });
});

test("a rate-limit stop's reset is carried by its job and the limit mode, and a value of another shape is read fresh", () => {
  const dir = tempDir("verdict-carry-limit-");
  const now = Date.parse("2026-11-10T03:00:00Z");
  const old = loadCarry(undefined, now - 60_000, "a".repeat(64));
  old.keepRefusal(71, "limit", "2026-11-10T03:30:00Z");
  old.keepRefusal(72, "limit", "2026-11-10 03:30");
  old.keepRefusal(73, "limit", "2026-11-10T03:30:00Z server-503");
  old.keepRefusal(74, "limit", "2026-11-10T03:30:00Z server-403");
  old.save(join(dir, "kept.json"));
  const next = loadCarry(join(dir, "kept.json"), now, "a".repeat(64));
  assert.deepEqual(next.refusal(71, "limit"), { value: "2026-11-10T03:30:00Z" });
  assert.deepEqual(next.refusal(73, "limit"), { value: "2026-11-10T03:30:00Z server-503" }, "a server error hold's reset and 5xx are kept");
  assert.equal(next.refusal(74, "limit"), undefined, "a status that is no 5xx is dropped");
  assert.equal(next.refusal(71, "check"), undefined, "the reset is kept for the limit mode only");
  assert.equal(next.refusal(72, "limit"), undefined, "a reset not in the stop line's form is dropped");
});

test("the decided times carry each issue's last decision, and a file kept before them carries none", () => {
  const dir = tempDir("verdict-carry-decided-");
  const now = Date.parse("2026-11-10T03:00:00Z");
  const first = loadCarry(undefined, now - 3_600_000, "a".repeat(64));
  first.keepDecided(30);
  first.keepDecided("not-an-issue");
  first.save(join(dir, "kept.json"));
  const next = loadCarry(join(dir, "kept.json"), now, "a".repeat(64));
  assert.equal(next.decidedAt(30), Date.parse("2026-11-10T02:00:00Z"));
  assert.equal(next.decidedAt(31), undefined);
  next.keepDecided(31);
  next.save(join(dir, "next.json"));
  assert.deepEqual(JSON.parse(readFileSync(join(dir, "next.json"), "utf8")).decided, { 30: { at: "2026-11-10T02:00:00.000Z" }, 31: { at: "2026-11-10T03:00:00.000Z" } });
  writeFileSync(join(dir, "before.json"), JSON.stringify({ code: "a".repeat(64), jobs: {}, refusals: {} }));
  const before = loadCarry(join(dir, "before.json"), now, "a".repeat(64));
  assert.equal(before.decidedAt(30), undefined);
});

test("the code digest changes with a module beside verdict-carry.mjs, never with a test file", () => {
  const dir = tempDir("verdict-carry-code-");
  writeFileSync(join(dir, "label-unblocked.mjs"), "export const A = 1;\n");
  writeFileSync(join(dir, "verdict-carry.mjs"), "export const B = 1;\n");
  const first = codeDigest(dir);
  assert.match(first, /^[0-9a-f]{64}$/);
  writeFileSync(join(dir, "verdict-carry.test.mjs"), "// a test\n");
  writeFileSync(join(dir, "notes.txt"), "not code\n");
  assert.equal(codeDigest(dir), first);
  writeFileSync(join(dir, "label-unblocked.mjs"), "export const A = 2;\n");
  assert.notEqual(codeDigest(dir), first);
  // The sweep's own checkout gives a digest too.
  assert.match(codeDigest(), /^[0-9a-f]{64}$/);
});
