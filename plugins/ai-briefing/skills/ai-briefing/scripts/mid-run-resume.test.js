// Mid-run resume — init scope=test (3 profiles), process profile 0, kill, auto-resume.
// Init scope=test (3 profiles). Process profile 0 fully. Don't continue —
// simulate "kill". Re-call next-handle (no flags) — should auto-resume to
// profile 1. Process 1+2. Final summary status=complete, by_status.complete=3.

import { spawnSync } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { slugifyHandle } from "./lib/state.js";
import { createTestReporter, writelnStderr } from "./lib/terminal.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SKILL_ROOT = path.resolve(__dirname, "..");
const RUNNER = path.join(__dirname, "per-profile-runner.js");
const RUN_DIR_BASE = path.join(SKILL_ROOT, "context", "runs");

const { ok, section, printResults, fail } = createTestReporter();

function runCmd(args) {
  const r = spawnSync(process.execPath, [RUNNER, ...args], { encoding: "utf-8", cwd: __dirname });
  let parsed;
  try {
    parsed = JSON.parse(r.stdout.trim().split("\n").pop());
  } catch {
    throw new Error(`runner ${args.join(" ")} stdout not JSON: ${r.stdout?.substring(0, 400)}`);
  }
  return { exit: r.status, json: parsed };
}

async function writeMockCaptures(handle) {
  const fp = path.join(__dirname, `.tmp-mid-${slugifyHandle(handle)}.json`);
  const data = {
    posts: { a: handle, n: 0, oldest: null, stable_iterations: 3, tw: [] },
    replies: { a: handle, surface: "with_replies", n: 0, stable_iterations: 3, tw: [] },
  };
  await fs.writeFile(fp, JSON.stringify(data));
  return fp;
}

async function processProfile(idx, handle) {
  const captures = await writeMockCaptures(handle);
  runCmd(["commit-s1", `--index=${idx}`, `--captures=${captures}`]);
  runCmd(["synthesize", `--index=${idx}`]);
  runCmd(["categorize", `--index=${idx}`]);
  const s56 = runCmd(["commit-and-checkoff", `--index=${idx}`]);
  await fs.rm(captures, { force: true });
  return s56;
}

async function run() {
  section("mid-run resume\n");

  // 1. init
  const init = runCmd([
    "init",
    "--scope=test",
    "--dry-run",
    "--cutoff=2026-04-24T19:00:00Z",
    "--force",
  ]);
  const runId = init.json.run_id;
  const handles = init.json.ordered_handles;
  ok("init creates run", !!runId);

  try {
    // 2. process profile 0
    const next0 = runCmd(["next-handle"]);
    ok("first next-handle returns profile 0", next0.json.handle === handles[0]);
    const s56_0 = await processProfile(0, handles[0]);
    ok("profile 0 commit-and-checkoff status=complete", s56_0.json.status === "complete");

    // 3. simulate kill — just don't continue. Re-call next-handle (no --resume flag),
    // auto-resume should pick up the same run via findLatestInProgress
    const next1 = runCmd(["next-handle"]);
    ok(
      'after "kill", next-handle auto-resumes',
      next1.json.run_id === runId,
      `expected ${runId}, got ${next1.json.run_id}`,
    );
    ok(
      "next-handle returns profile 1 (correct index)",
      next1.json.handle === handles[1] && next1.json.index === 1,
    );

    // 4. process remaining
    await processProfile(1, handles[1]);
    const next2 = runCmd(["next-handle"]);
    ok(
      "after profile 1, next-handle returns profile 2",
      next2.json.handle === handles[2] && next2.json.index === 2,
    );
    await processProfile(2, handles[2]);

    // 5. next-handle should now return done
    const nextDone = runCmd(["next-handle"]);
    ok("after final profile, next-handle returns {done: true}", nextDone.json.done === true);

    // 6. summary
    const summary = runCmd(["summary"]);
    ok("summary status=complete", summary.json.status === "complete");
    ok(
      "summary by_status.complete=3",
      summary.json.by_status.complete === 3,
      JSON.stringify(summary.json.by_status),
    );
    ok("summary failed_handles empty", summary.json.failed_handles.length === 0);
  } finally {
    await fs.rm(path.join(RUN_DIR_BASE, runId), { recursive: true, force: true });
    const tmps = await fs.readdir(__dirname);
    await Promise.all(
      tmps
        .filter((e) => e.startsWith(".tmp-mid-"))
        .map((e) => fs.rm(path.join(__dirname, e), { force: true })),
    );
  }

  printResults();
  process.exit(fail > 0 ? 1 : 0);
}

run().catch((e) => {
  writelnStderr(String(e));
  process.exit(2);
});
