// test-scope: .github/actions/resolve-config/package.json .github/workflows/maintenance-scan-architecture.yml docs/conventions/pr-pipeline.yaml docs/conventions/pr-pipeline/pr-pipeline.schema.json .github/scripts/maintenance-scan-architecture/model-tools.json
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
import { forge } from "./forge.fixtures.mjs";
import { decide, gate, lastScan, mergesSince, modelTools, promptText, statusLine } from "./gate.mjs";
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

const LEGS = ["find-candidates", "find-candidates-subscription", "find-candidates-fallback"];
const NETWORK = /^(curl|wget|nc|ncat|socat|ssh|scp|telnet|ftp|python\S*|perl|ruby|php|env|printenv|npm|npx|pip\S*|gh|git (push|fetch|clone|pull|remote|ls-remote|submodule))\b/;

test("every model leg runs sandboxed, and its Bash rules allow no network-capable or interpreter command", () => {
  const workflow = parse(WORKFLOW_TEXT);
  const { allowed, disallowed } = modelTools("/runner/work/r/r");
  for (const leg of LEGS) {
    const steps = workflow.jobs[leg].steps;
    const launch = steps.find((step) => /run-claude-cli@/.test(step.uses ?? ""));
    assert.equal(launch.with.sandbox, "true", `${leg} sandbox`);
    assert.equal(launch.with["permission-mode"], "dontAsk", leg);
    assert.equal(launch.with["allowed-tools"], "${{ steps.stage.outputs.allowed-tools }}", leg);
    assert.equal(launch.with["disallowed-tools"], "${{ steps.stage.outputs.disallowed-tools }}", leg);
    assert.ok(steps.some((step) => step.id === "stage" && /gate\.mjs prompt/.test(step.run ?? "")), `${leg} stages the tool rules from model-tools.json`);
  }
  assert.ok(!allowed.includes("Bash") && !allowed.includes("Write"), "no unscoped Bash or Write");
  for (const rule of allowed.filter((r) => r.startsWith("Bash("))) {
    const command = /^Bash\((.*)\)$/.exec(rule)[1];
    assert.doesNotMatch(command, NETWORK, rule);
    if (/^(bash|node) /.test(command)) assert.match(command, /^(bash|node) \/runner\/work\/r\/r\/\.lane\/plugins\/\*$/, `${rule} runs only staged plugin scripts`);
  }
  for (const deny of ["Bash(curl *)", "Bash(wget *)", "Bash(env*)", "Bash(printenv*)", "Bash(node -e *)", "Bash(python* -c *)", "Bash(cat /proc/*)", "Bash(gh *)", "Bash(git push *)", "WebFetch", "WebSearch"]) {
    assert.ok(disallowed.includes(deny), deny);
  }
  assert.throws(() => modelTools("relative/path"), /absolute path/);
});

test("with the lane off, a forced scan files nothing: File Findings runs only when the gate reads the lane on", () => {
  const wf = workflowText(WORKFLOW_TEXT);
  const ctx = (enabled) => ({ "needs.gate.outputs.enabled": enabled, "needs.scan.result": "success", "needs.scan.outputs.artifact-id": "42" });
  assert.equal(runs(wf.jobIf("file-findings"), ctx("false")), false);
  assert.equal(runs(wf.jobIf("file-findings"), ctx("")), false, "an unread setting files nothing");
  assert.equal(runs(wf.jobIf("file-findings"), ctx("true")), true);
  assert.equal(decide({ ...on, enabled: false, force: true, lastScan: scanned(2) }).run, true, "the forced scan itself still runs");
});

test("File Findings holds only issues write and contents read, files on the job's own GITHUB_TOKEN, and requests no lane token", () => {
  const job = parse(WORKFLOW_TEXT).jobs["file-findings"];
  assert.deepEqual(job.permissions, { contents: "read", issues: "write" });
  const file = job.steps.find((step) => /file-findings\.mjs file$/.test(step.run ?? ""));
  assert.equal(file.env.GITHUB_TOKEN, "${{ github.token }}");
  assert.ok(!job.steps.some((step) => /request-lane-token|revoke-lane-token/.test(`${step.uses ?? ""} ${step.run ?? ""}`)));
  assert.ok(!/request-lane-token/.test(WORKFLOW_TEXT));
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

test("the open count leaves out the captured page's pull requests and reads pages until it passes the cap", async () => {
  const { call, calls } = forge({ open: 150 });
  assert.equal(await countOpen(call, "o/r", SOURCE_LABEL, 200), 150);
  assert.equal(calls.length, 2, "152 items, two of them pull requests, take two pages of 100");
  assert.match(calls[0], /labels=source%3A%20architecture-improve/);
  const capped = forge({ open: 150 });
  assert.equal(await countOpen(capped.call, "o/r", SOURCE_LABEL, 5), 98, "a count already past the cap reads no more pages");
  assert.equal(capped.calls.length, 1);
});

const daysBack = (days, sha = "a".repeat(40)) => ({ at: NOW - days * DAY, sha });

test("the last scan is the newest completed main run whose Scan job succeeded; a skipped, failed or absent Scan is no scan", async () => {
  const runsList = [
    { ...daysBack(1), scan: "skipped" },
    { ...daysBack(2), scan: "failure" },
    { ...daysBack(3), scan: "absent" },
    { ...daysBack(4, "4".repeat(40)), scan: "success" },
  ];
  const found = await lastScan(forge({ runs: runsList }).call, "o/r");
  assert.deepEqual([found.at, found.sha], [NOW - 4 * DAY, "4".repeat(40)]);
  assert.equal(await lastScan(forge({ runs: runsList.slice(0, 3) }).call, "o/r"), null, "a history with no successful Scan job is a first scan");
  assert.equal(await lastScan(forge().call, "o/r"), null);
});

test("a scan behind more stopped runs than one page holds is still found, and only an exhausted history is a first scan", async () => {
  const stopped = Array.from({ length: 140 }, (_, i) => ({ ...daysBack(i + 1), scan: "skipped" }));
  const behind = forge({ runs: [...stopped, { ...daysBack(141, "b".repeat(40)), scan: "success" }] });
  assert.equal((await lastScan(behind.call, "o/r")).sha, "b".repeat(40));
  assert.equal(behind.calls.filter((c) => c.includes("/actions/workflows/")).length, 2, "the second runs page was read");
  assert.equal(await lastScan(forge({ runs: stopped }).call, "o/r"), null);
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

const runGate = async (root, { open = 2, scanAt = NOW - 2 * DAY, before = [], env = {}, fake = forge({ open, runs: [...before, { at: scanAt, sha: root.sha }] }) } = {}) =>
  gate({ root: root.dir, call: fake.call, now: NOW, env: { REPOSITORY: "o/r", STANDARDS_DIR: STANDARDS_FIXTURE, EVENT_NAME: "schedule", ...env } });

test("lane-off and a cap of 0 stop the gate before any API read, and its status line says what was not read", async () => {
  for (const [config, reason] of [[{ enabled: false }, "lane-off"], [{ cap: 0 }, "at-cap"]]) {
    const fake = forge();
    const result = await runGate(configRoot(config), { fake });
    assert.deepEqual([result.run, result.reason, fake.calls], [false, reason, []], reason);
    assert.match(statusLine(result), /open n\/a of cap .* merges since the last scan n\/a/);
  }
});

test("forty stopped runs before the last scan still leave it not-due or no-merges, never a first scan", async () => {
  const stopped = Array.from({ length: 40 }, (_, i) => ({ at: NOW - (i + 1) * 3_600_000, sha: "c".repeat(40), scan: "skipped" }));
  const root = configRoot({ everyDays: 3 });
  assert.equal((await runGate(root, { before: stopped })).reason, "not-due");
  const quiet = configRoot();
  const head = execFileSync("git", ["-C", quiet.dir, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  assert.equal((await runGate({ ...quiet, sha: head }, { before: stopped })).reason, "no-merges");
});

test("every-days above forty holds until that many days passed since the last scan", async () => {
  const root = configRoot({ everyDays: 60 });
  const stopped = Array.from({ length: 50 }, (_, i) => ({ at: NOW - (i + 1) * DAY, sha: root.sha, scan: "skipped" }));
  assert.equal((await runGate(root, { before: stopped, scanAt: NOW - 55 * DAY })).reason, "not-due");
  assert.equal((await runGate(root, { before: stopped, scanAt: NOW - 60 * DAY })).reason, "due");
});

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
