// test-scope: .github/actions/resolve-config/package.json .github/workflows/maintenance-scan-architecture.yml docs/conventions/pr-pipeline.yaml docs/conventions/pr-pipeline/pr-pipeline.schema.json
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { STANDARDS_FIXTURE } from "../lib/trusted-actors.fixtures.mjs";
import { runs } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";
import { decide, gate, lastScan, mergesSince, promptText, SCAN_DONE_JOB } from "./gate.mjs";
import { countOpen, openItemCap, SOURCE_LABEL } from "./lane.mjs";

process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const { parse } = createRequire(new URL("../../actions/resolve-config/package.json", import.meta.url))("yaml");
const REPO_ROOT = fileURLToPath(new URL("../../../", import.meta.url));
const WORKFLOW_TEXT = readFileSync(join(REPO_ROOT, ".github/workflows/maintenance-scan-architecture.yml"), "utf8");
const CONFIG = readFileSync(join(REPO_ROOT, "docs/conventions/pr-pipeline.yaml"), "utf8");
const LANE_BLOCK = "  maintenance-scan-architecture:\n    stage: maintenance\n    enabled: false\n    every-days: 1\n";
const NOW = Date.parse("2026-11-26T07:41:00Z");
const DAY = 86_400_000;
const on = { enabled: true, everyDays: 1, cap: 5, open: 0, merges: 3, now: NOW };
const scanned = (days) => ({ at: NOW - days * DAY, sha: "a".repeat(40) });

test("each of the four stops names its reason and skips the scan; a due lane scans with the room under the cap", () => {
  assert.deepEqual(decide({ ...on, enabled: false, lastScan: scanned(2) }), { run: false, reason: "lane-off", room: 5 });
  assert.deepEqual(decide({ ...on, open: 5, lastScan: scanned(2) }), { run: false, reason: "at-cap", room: 0 });
  assert.deepEqual(decide({ ...on, open: 7, lastScan: scanned(2) }), { run: false, reason: "at-cap", room: 0 });
  assert.deepEqual(decide({ ...on, everyDays: 3, lastScan: scanned(2) }), { run: false, reason: "not-due", room: 5 });
  assert.deepEqual(decide({ ...on, merges: 0, lastScan: scanned(2) }), { run: false, reason: "no-merges", room: 5 });
  assert.deepEqual(decide({ ...on, open: 2, lastScan: scanned(2) }), { run: true, reason: "due", room: 3 });
});

test("the cadence counts calendar days: three days after a scan is due under every-days 3, two is not", () => {
  assert.equal(decide({ ...on, everyDays: 3, lastScan: scanned(3) }).run, true);
  assert.equal(decide({ ...on, everyDays: 3, lastScan: scanned(2) }).reason, "not-due");
  assert.equal(decide({ ...on, everyDays: 1, lastScan: { ...scanned(0), at: NOW - 23 * 3_600_000 } }).run, true, "yesterday's run 23 hours ago is a day back");
});

test("with no earlier scan the lane scans whatever merged, and cap 0 stops it", () => {
  assert.deepEqual(decide({ ...on, merges: null, lastScan: null }), { run: true, reason: "first-scan", room: 5 });
  assert.deepEqual(decide({ ...on, cap: 0, merges: null, lastScan: null }), { run: false, reason: "at-cap", room: 0 });
});

test("force skips only the lane-off and not-due stops; the cap and no-merges stops still hold", () => {
  assert.equal(decide({ ...on, enabled: false, force: true, lastScan: scanned(2) }).run, true);
  assert.equal(decide({ ...on, everyDays: 7, force: true, lastScan: scanned(2) }).run, true);
  assert.equal(decide({ ...on, open: 5, force: true, lastScan: scanned(2) }).reason, "at-cap");
  assert.equal(decide({ ...on, merges: 0, force: true, lastScan: scanned(2) }).reason, "no-merges");
});

test("the workflow's model legs are skipped whenever the gate says run=false, and the key leg starts on run=true", () => {
  const wf = workflowText(WORKFLOW_TEXT);
  const base = { "github.run_attempt": "1", "needs.gate.outputs.next-leg": "" };
  for (const reason of ["lane-off", "at-cap", "not-due", "no-merges"]) {
    const ctx = { ...base, "needs.gate.outputs.run": "false", "needs.gate.outputs.reason": reason, "needs.gate.outputs.next-leg": "subscription" };
    for (const job of ["find-candidates", "find-candidates-subscription", "find-candidates-fallback"]) {
      assert.equal(runs(wf.jobIf(job), { ...ctx, "needs.find-candidates-subscription.outputs.credential-present": "false" }), false, `${job} on ${reason}`);
    }
  }
  assert.equal(runs(wf.jobIf("find-candidates"), { ...base, "needs.gate.outputs.run": "true" }), true);
  assert.equal(runs(wf.jobIf("find-candidates-subscription"), { ...base, "needs.gate.outputs.run": "true", "needs.find-candidates.outputs.next-leg": "subscription" }), true);
});

test("the gate is the first job, runs a script and no model, and every model leg needs it", () => {
  const workflow = parse(WORKFLOW_TEXT);
  const [first] = Object.keys(workflow.jobs);
  assert.equal(first, "gate");
  const gateSteps = workflow.jobs.gate.steps;
  assert.ok(gateSteps.some((step) => /gate\.mjs gate$/.test(step.run ?? "")), "the gate step runs gate.mjs");
  assert.ok(!gateSteps.some((step) => /run-claude-cli|claude-code-action/.test(step.uses ?? "") || /\bclaude\s+-p\b/.test(step.run ?? "")));
  for (const leg of ["find-candidates", "find-candidates-subscription", "find-candidates-fallback"]) {
    assert.ok([workflow.jobs[leg].needs].flat().includes("gate"), leg);
    assert.match(workflow.jobs[leg].if, /needs\.gate\.outputs\.run == 'true'/, leg);
  }
});

test("the workflow runs only on its daily schedule and a dispatch, with no push trigger", () => {
  const workflow = parse(WORKFLOW_TEXT);
  assert.deepEqual(Object.keys(workflow.on).sort(), ["schedule", "workflow_dispatch"]);
  assert.equal(workflow.on.schedule.length, 1);
  assert.match(workflow.on.schedule[0].cron, /^\d+ \d+ \* \* \*$/, "once a day");
  assert.equal(workflow.on.workflow_dispatch.inputs.force.type, "boolean");
  assert.match(WORKFLOW_TEXT, /FORCE: \$\{\{ github\.event_name == 'workflow_dispatch' && inputs\.force && 'true' \|\| 'false' \}\}/);
});

test("the prompt carries the room and the source label, and refuses no room", () => {
  const text = promptText(3);
  assert.match(text, /File at most 3 items/);
  assert.match(text, /`source: architecture-improve`/);
  assert.match(text, /\/architecture:improve deepening --unattended/);
  assert.throws(() => promptText(0), /positive integer/);
});

test("the open count leaves out pull requests and reads pages until it passes the cap", async () => {
  const pages = [];
  const call = async (method, path) => {
    pages.push(path);
    const page = Number(/&page=(\d+)/.exec(path)[1]);
    return page === 1 ? [...Array.from({ length: 99 }, (_, i) => ({ number: i })), { number: 99, pull_request: {} }] : [{ number: 200 }];
  };
  assert.equal(await countOpen(call, "o/r", SOURCE_LABEL, 200), 100);
  assert.equal(pages.length, 2);
  assert.match(pages[0], /labels=source%3A%20architecture-improve/);
  pages.length = 0;
  assert.equal(await countOpen(call, "o/r", SOURCE_LABEL, 5), 99, "a count already past the cap reads no more pages");
  assert.equal(pages.length, 1);
});

test("the last scan is the newest completed main run whose Scan job, which checked the sealed findings, succeeded", async () => {
  const jobs = { 3: [{ name: SCAN_DONE_JOB, conclusion: "skipped" }], 2: [{ name: "Gate", conclusion: "success" }], 1: [{ name: SCAN_DONE_JOB, conclusion: "success" }] };
  const call = async (method, path) =>
    path.includes("/workflows/")
      ? { workflow_runs: [3, 2, 1].map((id) => ({ id, created_at: `2026-11-2${id}T07:41:00Z`, head_sha: String(id).repeat(40) })) }
      : { jobs: jobs[/runs\/(\d+)\/jobs/.exec(path)[1]] };
  assert.deepEqual(await lastScan(call, "o/r"), { at: Date.parse("2026-11-21T07:41:00Z"), sha: "1".repeat(40), run: 1 });
  assert.equal(await lastScan(async (method, path) => (path.includes("/workflows/") ? { workflow_runs: [] } : null), "o/r"), null);
});

function repo() {
  const dir = tempDir("scan-gate-");
  const git = (...args) => execFileSync("git", ["-C", dir, ...args], { encoding: "utf8" }).trim();
  git("init", "-q", "-b", "main");
  git("config", "user.email", "t@example.invalid");
  git("config", "user.name", "t");
  git("commit", "-q", "--allow-empty", "-m", "scanned");
  const sha = git("rev-parse", "HEAD");
  return { dir, git, sha };
}

test("merges since the last scan count first-parent commits after its head", () => {
  const { dir, git, sha } = repo();
  assert.equal(mergesSince(dir, { sha, at: NOW }), 0);
  git("commit", "-q", "--allow-empty", "-m", "merged one");
  git("commit", "-q", "--allow-empty", "-m", "merged two");
  assert.equal(mergesSince(dir, { sha, at: NOW }), 2);
});

test("the open cap reads find_open_item_cap from the improvement config cascade, default 5", () => {
  const dir = tempDir("scan-cap-");
  const home = join(dir, "docs/conventions");
  mkdirSync(home, { recursive: true });
  assert.deepEqual(openItemCap(dir), { cap: 5, source: "default", warnings: [] });
  writeFileSync(join(home, "improvement.yaml"), "find_open_item_cap: 2\n");
  assert.deepEqual(openItemCap(dir), { cap: 2, source: "team", warnings: [] });
  writeFileSync(join(home, "improvement.local.yaml"), "find_open_item_cap: 1\n");
  assert.deepEqual(openItemCap(dir), { cap: 1, source: "personal", warnings: [] });
  writeFileSync(join(home, "improvement.local.yaml"), "find_open_item_cap: 9\n");
  const raised = openItemCap(dir);
  assert.equal(raised.cap, 2, "a personal layer never raises the cap");
  assert.match(raised.warnings[0], /only lowers it/);
  writeFileSync(join(home, "improvement.yaml"), "find_open_item_cap: many\n");
  writeFileSync(join(home, "improvement.local.yaml"), "{}\n");
  const malformed = openItemCap(dir);
  assert.deepEqual([malformed.cap, malformed.source], [5, "default"]);
  assert.match(malformed.warnings[0], /not a non-negative integer/);
});

function configRoot({ enabled = true, everyDays = 1, cap } = {}) {
  const { dir, git, sha } = repo();
  mkdirSync(join(dir, "docs/conventions/pr-pipeline"), { recursive: true });
  assert.ok(CONFIG.includes(LANE_BLOCK), "the lane block reads as the test expects");
  const block = LANE_BLOCK.replace("enabled: false", `enabled: ${enabled}`).replace("every-days: 1", `every-days: ${everyDays}`);
  writeFileSync(join(dir, "docs/conventions/pr-pipeline.yaml"), CONFIG.replace(LANE_BLOCK, block));
  copyFileSync(join(REPO_ROOT, "docs/conventions/pr-pipeline/pr-pipeline.schema.json"), join(dir, "docs/conventions/pr-pipeline/pr-pipeline.schema.json"));
  if (cap !== undefined) writeFileSync(join(dir, "docs/conventions/improvement.yaml"), `find_open_item_cap: ${cap}\n`);
  git("commit", "-q", "--allow-empty", "-m", "merged since the scan");
  return { dir, sha };
}

const fakeForge = ({ open, scanAt, sha }) => async (method, path) => {
  if (path.includes("/issues?")) return /&page=1\b/.test(path) ? Array.from({ length: open }, (_, i) => ({ number: i + 1 })) : [];
  if (path.includes("/workflows/")) return { workflow_runs: [{ id: 9, created_at: new Date(scanAt).toISOString(), head_sha: sha }] };
  return { jobs: [{ name: SCAN_DONE_JOB, conclusion: "success" }] };
};

const runGate = async (root, { open = 2, scanAt = NOW - 2 * DAY, env = {} } = {}) =>
  gate({ root: root.dir, call: fakeForge({ open, scanAt, sha: root.sha }), now: NOW, env: { REPOSITORY: "o/r", STANDARDS_DIR: STANDARDS_FIXTURE, EVENT_NAME: "schedule", ...env } });

test("the shipped config keeps the lane off, so the gate stops lane-off", async () => {
  const result = await runGate(configRoot({ enabled: false }));
  assert.deepEqual([result.run, result.reason, result.cap, result.everyDays], [false, "lane-off", 5, 1]);
});

test("editing only the config files changes the gate: on/off, every-days and the cap each flip its result", async () => {
  assert.equal((await runGate(configRoot({ enabled: true }))).reason, "due");
  assert.equal((await runGate(configRoot({ enabled: false }))).reason, "lane-off");
  assert.equal((await runGate(configRoot({ everyDays: 3 }))).reason, "not-due");
  assert.equal((await runGate(configRoot({ everyDays: 2 }))).reason, "due");
  const capped = await runGate(configRoot({ cap: 2 }));
  assert.deepEqual([capped.reason, capped.cap, capped.capSource], ["at-cap", 2, "team"]);
  const roomier = await runGate(configRoot({ cap: 4 }));
  assert.deepEqual([roomier.reason, roomier.room], ["due", 2]);
});

test("the gate honors force only on a dispatch, never on a schedule run", async () => {
  const root = configRoot({ enabled: false });
  assert.equal((await runGate(root, { env: { EVENT_NAME: "workflow_dispatch", FORCE: "true" } })).run, true);
  assert.equal((await runGate(root, { env: { EVENT_NAME: "schedule", FORCE: "true" } })).reason, "lane-off");
  assert.equal((await runGate(root, { env: { EVENT_NAME: "workflow_dispatch", FORCE: "false" } })).reason, "lane-off");
});

test("the gate stops no-merges when main has not moved since the last scan", async () => {
  const root = configRoot();
  const head = execFileSync("git", ["-C", root.dir, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  assert.equal((await runGate({ ...root, sha: head })).reason, "no-merges");
});
