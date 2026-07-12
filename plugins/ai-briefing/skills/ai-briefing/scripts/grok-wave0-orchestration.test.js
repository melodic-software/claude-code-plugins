// Wave 0 orchestration — grok-capture skip/complete path + S3 merge (no live grok -p).

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

const reporter = createTestReporter();
const { ok, section } = reporter;

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

async function writeCaptures(handle) {
  const bare = slugifyHandle(handle);
  const fp = path.join(__dirname, `.tmp-captures-${bare}.json`);
  const data = {
    posts: {
      a: handle,
      n: 0,
      oldest: "2026-06-03T10:00:00Z",
      stable_iterations: 3,
      tw: [],
    },
    replies: null,
  };
  await fs.writeFile(fp, JSON.stringify(data, null, 2));
  return fp;
}

async function cleanupRun(runId) {
  if (!runId) return;
  await fs.rm(path.join(RUN_DIR_BASE, runId), { recursive: true, force: true });
}

async function run() {
  section("grok Wave 0 orchestration (dry-run, index 0)\n");

  let runId;
  try {
    const init = runCmd([
      "init",
      "--scope=test",
      "--dry-run",
      "--grok-preload",
      "--cutoff=2026-06-01T00:00:00.000Z",
      "--force",
    ]);
    runId = init.json.run_id;
    const resume = [`--resume=${runId}`];
    const handle = init.json.ordered_handles[0];
    ok("init returns run_id", !!runId);
    ok("grok_preload_requested tracked", init.json.config.grok_preload_requested === true);

    const grok = runCmd(["grok-capture", "--index=0", ...resume]);
    if (init.json.config.grok_preload) {
      ok("grok-capture not skipped when preload enabled", grok.json.skipped !== true);
      ok("S0 records post_count", typeof grok.json.post_count === "number");
    } else {
      ok("grok-capture skipped when probe not ready", grok.json.skipped === true);
    }

    const capturesFile = await writeCaptures(handle);
    const s1 = runCmd(["commit-s1", "--index=0", `--captures=${capturesFile}`, ...resume]);
    ok("commit-s1 s2_passed", s1.json.s2_passed === true);

    const s3 = runCmd(["synthesize", "--index=0", ...resume]);
    ok("synthesize succeeded", s3.json.s3_status === "complete");

    await fs.rm(capturesFile, { force: true });
  } finally {
    await cleanupRun(runId);
    const entries = await fs.readdir(__dirname);
    await Promise.all(
      entries
        .filter((e) => e.startsWith(".tmp-captures-"))
        .map((e) => fs.rm(path.join(__dirname, e), { force: true })),
    );
  }

  const failCount = reporter.printResults();
  process.exit(failCount > 0 ? 1 : 0);
}

run().catch((e) => {
  writelnStderr(String(e));
  process.exit(2);
});
