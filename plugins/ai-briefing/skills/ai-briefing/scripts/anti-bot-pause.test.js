// Anti-bot pause cycle —
// init scope=test --anti-bot-cap=4. After 2 profiles (4 navs since with_replies
// fires on high_signal handles), commit-and-checkoff on profile 1 returns
// {paused: true} and exits 1. Verify master.status='paused'.
// Then `resume-paused` resets state. Process remaining profile. Final summary
// status=complete.

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

function runCmd(args, { allowExit1 = false } = {}) {
  const r = spawnSync(process.execPath, [RUNNER, ...args], { encoding: "utf-8", cwd: __dirname });
  if (r.status !== 0 && r.status !== 1 && !allowExit1) {
    throw new Error(`runner ${args.join(" ")} exit ${r.status}: ${r.stderr?.substring(0, 400)}`);
  }
  let parsed;
  try {
    parsed = JSON.parse(r.stdout.trim().split("\n").pop());
  } catch {
    throw new Error(`runner ${args.join(" ")} stdout not JSON: ${r.stdout?.substring(0, 400)}`);
  }
  return { exit: r.status, json: parsed };
}

async function writeMockCaptures(handle) {
  const fp = path.join(__dirname, `.tmp-pause-${slugifyHandle(handle)}.json`);
  const data = {
    posts: { a: handle, n: 0, oldest: null, stable_iterations: 3, tw: [] },
    replies: { a: handle, surface: "with_replies", n: 0, stable_iterations: 3, tw: [] },
  };
  await fs.writeFile(fp, JSON.stringify(data));
  return fp;
}

async function processProfile(idx, handle, { expectPause = false } = {}) {
  const captures = await writeMockCaptures(handle);
  runCmd(["commit-s1", `--index=${idx}`, `--captures=${captures}`]);
  runCmd(["synthesize", `--index=${idx}`]);
  runCmd(["categorize", `--index=${idx}`]);
  const s56 = runCmd(["commit-and-checkoff", `--index=${idx}`], { allowExit1: expectPause });
  await fs.rm(captures, { force: true });
  return s56;
}

async function run() {
  section("anti-bot pause cycle (cap=4, 3 profiles)\n");

  // 1. init with cap=4 — high-signal profiles fire posts+replies (2 navs each),
  // so after 2 profiles we've used 4 navs and should pause
  const init = runCmd([
    "init",
    "--scope=test",
    "--dry-run",
    "--cutoff=2026-04-24T19:00:00Z",
    "--anti-bot-cap=4",
    "--force",
  ]);
  const runId = init.json.run_id;
  const handles = init.json.ordered_handles;
  ok("init creates run with cap=4", init.json.anti_bot.cap === 4);

  try {
    // 2. profile 0 — should NOT pause (navs goes 0 → 2)
    const next0 = runCmd(["next-handle"]);
    ok("next-handle returns profile 0", next0.json.handle === handles[0]);
    const s56_0 = await processProfile(0, handles[0]);
    ok(
      "profile 0 NOT paused (navs=2 < cap=4)",
      s56_0.json.paused === false,
      `paused=${s56_0.json.paused} navs=${s56_0.json.anti_bot.navs_used}`,
    );
    ok("profile 0 navs_used=2", s56_0.json.anti_bot.navs_used === 2);

    // 3. profile 1 — SHOULD pause (navs goes 2 → 4 → cap reached)
    const next1 = runCmd(["next-handle"]);
    ok("next-handle returns profile 1", next1.json.handle === handles[1]);
    const s56_1 = await processProfile(1, handles[1], { expectPause: true });
    ok("profile 1 paused=true", s56_1.json.paused === true, `paused=${s56_1.json.paused}`);
    ok("profile 1 exit code 1", s56_1.exit === 1);
    ok("master.anti_bot.navs_used=4", s56_1.json.anti_bot.navs_used === 4);

    // 4. status confirms paused
    const status = runCmd(["status"]);
    ok("status reports status=paused", status.json.status === "paused");

    // 5. next-handle while paused returns {paused:true} exit 1
    const nextPaused = runCmd(["next-handle"], { allowExit1: true });
    ok("next-handle while paused returns paused=true", nextPaused.json.paused === true);

    // 6. resume-paused resets the pause
    const resumed = runCmd(["resume-paused"]);
    ok("resume-paused returns status=in_progress", resumed.json.status === "in_progress");
    ok("resume-paused resets navs_used=0", resumed.json.anti_bot.navs_used === 0);
    ok("resume-paused bumps session_count to 2", resumed.json.anti_bot.session_count === 2);

    // 7. finish profile 2 in resumed session
    const next2 = runCmd(["next-handle"]);
    ok(
      "after resume, next-handle returns profile 2",
      next2.json.handle === handles[2] && next2.json.index === 2,
    );
    await processProfile(2, handles[2]);

    // 8. summary should be complete
    const summary = runCmd(["summary"]);
    ok("final status=complete", summary.json.status === "complete");
    ok(
      "final by_status.complete=3",
      summary.json.by_status.complete === 3,
      JSON.stringify(summary.json.by_status),
    );
  } finally {
    await fs.rm(path.join(RUN_DIR_BASE, runId), { recursive: true, force: true });
    const tmps = await fs.readdir(__dirname);
    await Promise.all(
      tmps
        .filter((e) => e.startsWith(".tmp-pause-"))
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
