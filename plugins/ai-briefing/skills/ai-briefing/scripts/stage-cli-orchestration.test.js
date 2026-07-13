// Stage CLI orchestration — mocked chrome captures, dry-run synthesize/categorize.
// Asserts the per-profile loop reaches `summary.status === 'complete'` for 3 profiles.
//
// Each subcommand runs in its own subprocess (matches how the main CC session
// invokes the runner via Bash between chrome MCP calls).

import { spawnSync } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { forEachSequential } from "./lib/async-seq.js";
import { slugifyHandle } from "./lib/state.js";
import { createTestReporter, writelnStderr } from "./lib/terminal.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SKILL_ROOT = path.resolve(__dirname, "..");
const RUNNER = path.join(__dirname, "per-profile-runner.js");
const RUN_DIR_BASE = path.join(SKILL_ROOT, "context", "runs");

const { ok, section, printResults, fail } = createTestReporter();

function runCmd(args) {
  const r = spawnSync(process.execPath, [RUNNER, ...args], {
    encoding: "utf-8",
    cwd: __dirname,
  });
  if (r.status !== 0 && r.status !== 1) {
    throw new Error(
      `runner ${args.join(" ")} exit ${r.status}: stderr=${r.stderr?.substring(0, 400)}`,
    );
  }
  let parsed;
  try {
    parsed = JSON.parse(r.stdout.trim().split("\n").pop());
  } catch {
    throw new Error(`runner ${args.join(" ")} stdout not JSON: ${r.stdout?.substring(0, 400)}`);
  }
  return { exit: r.status, json: parsed };
}

async function writeCaptures(handle, postsCount = 0, repliesCount = 0) {
  const bare = slugifyHandle(handle);
  const fp = path.join(__dirname, `.tmp-captures-${bare}.json`);
  const mkTw = (n, surface) =>
    Array.from({ length: n }, (_, i) => ({
      t: `mock ${surface} ${i} for ${handle}`,
      u: `https://x.com/${bare}/status/${1000 + i}`,
      d: "2026-04-30T12:00",
    }));
  const data = {
    posts: {
      a: handle,
      n: postsCount,
      oldest: "2026-04-30T12:00",
      stable_iterations: 3,
      tw: mkTw(postsCount, "posts"),
    },
    replies: {
      a: handle,
      surface: "with_replies",
      n: repliesCount,
      stable_iterations: 3,
      tw: mkTw(repliesCount, "replies"),
    },
  };
  await fs.writeFile(fp, JSON.stringify(data, null, 2));
  return fp;
}

async function cleanupRun(runId) {
  if (!runId) return;
  const dir = path.join(RUN_DIR_BASE, runId);
  await fs.rm(dir, { recursive: true, force: true });
}

async function cleanupTmpCaptures() {
  const entries = await fs.readdir(__dirname);
  await Promise.all(
    entries
      .filter((e) => e.startsWith(".tmp-captures-"))
      .map((e) => fs.rm(path.join(__dirname, e), { force: true })),
  );
}

async function processProfile(i, handles) {
  const next = runCmd(["next-handle"]);
  ok(
    `profile ${i} next-handle returns expected handle`,
    next.json.handle === handles[i],
    `got ${next.json.handle} expected ${handles[i]}`,
  );
  ok(
    `profile ${i} next-handle has posts.url + posts.js`,
    !!next.json.posts?.url && !!next.json.posts?.js,
  );

  const capturesFile = await writeCaptures(handles[i]);

  const s1 = runCmd(["commit-s1", `--index=${i}`, `--captures=${capturesFile}`]);
  ok(`profile ${i} commit-s1 s2_passed`, s1.json.s2_passed === true);

  const s3 = runCmd(["synthesize", `--index=${i}`]);
  ok(`profile ${i} synthesize succeeded`, s3.json.s3_status === "complete");

  const s4 = runCmd(["categorize", `--index=${i}`]);
  ok(`profile ${i} categorize succeeded`, s4.json.s4_status === "complete");

  const s56 = runCmd(["commit-and-checkoff", `--index=${i}`]);
  ok(`profile ${i} commit-and-checkoff status complete`, s56.json.status === "complete");
  ok(`profile ${i} current_index advanced`, s56.json.current_index === i + 1);
}

async function run() {
  section("stage CLI orchestration loop (3 profiles, dry-run)\n");

  // 0. Cleanup any prior orphan runs from prior tests
  await cleanupTmpCaptures();

  let runId;
  try {
    // 1. init --scope=test --dry-run
    const init = runCmd([
      "init",
      "--scope=test",
      "--dry-run",
      "--cutoff=2026-04-24T19:00:00Z",
      "--force",
    ]);
    runId = init.json.run_id;
    ok("init returns run_id", !!runId, `run_id=${runId}`);
    ok("init total === 3", init.json.total === 3, `got ${init.json.total}`);
    ok('init scope === "test"', init.json.scope === "test");

    const handles = init.json.ordered_handles;
    ok("init ordered_handles has 3 entries", handles.length === 3);

    // 2. Loop 3 profiles
    await forEachSequential([0, 1, 2], (i) => processProfile(i, handles));

    // 3. summary — should be status=complete
    const summary = runCmd(["summary"]);
    ok('summary status === "complete"', summary.json.status === "complete", summary.json.status);
    ok("summary total === 3", summary.json.total === 3);
    ok(
      "summary by_status.complete === 3",
      summary.json.by_status.complete === 3,
      JSON.stringify(summary.json.by_status),
    );
    ok(
      "summary failed_handles is empty",
      Array.isArray(summary.json.failed_handles) && summary.json.failed_handles.length === 0,
    );

    // 4. status — read-only sanity check
    const status = runCmd(["status"]);
    ok("status returns same run_id", status.json.run_id === runId);
    ok("status current_index === 3", status.json.current_index === 3);
  } finally {
    await cleanupRun(runId);
    await cleanupTmpCaptures();
  }

  printResults();
  process.exit(fail > 0 ? 1 : 0);
}

run().catch((e) => {
  writelnStderr(String(e));
  process.exit(2);
});
