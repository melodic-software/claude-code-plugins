// Retry-failed flow — lists failed profiles, main session reprocesses via stage subcommands.
//
// Seeds a run with 3 complete + 1 failed profiles, calls retry-failed, reprocesses
// the failed profile through commit-s1 → synthesize → categorize → commit-and-checkoff,
// then summary reconciles by_status.

import { spawnSync } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { slugifyHandle } from "./lib/state.js";
import { createTestReporter, writelnStderr } from "./lib/terminal.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SKILL_ROOT = path.resolve(__dirname, "..");
const RUNNER = path.join(__dirname, "per-profile-runner.js");
const RUN_ID = "20260506T999999Z";
const RUN_DIR = path.join(SKILL_ROOT, "context", "runs", RUN_ID);

const { ok, section, printResults, fail } = createTestReporter();

function runCmd(args) {
  const r = spawnSync(process.execPath, [RUNNER, ...args], {
    encoding: "utf-8",
    cwd: __dirname,
  });
  if (r.status !== 0 && r.status !== 1 && r.status !== 3) {
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
      oldest: null,
      stable_iterations: 3,
      tw: [],
    },
    replies: null,
  };
  await fs.writeFile(fp, JSON.stringify(data, null, 2));
  return fp;
}

async function setup() {
  await fs.rm(RUN_DIR, { recursive: true, force: true });
  await fs.mkdir(path.join(RUN_DIR, "per-profile"), { recursive: true });

  const master = {
    run_id: RUN_ID,
    status: "in_progress",
    started_at: "2026-05-06T00:00:00Z",
    completed_at: null,
    cutoff: "2026-04-24T19:00:00Z",
    scope: "test",
    current_index: 4,
    ordered_handles: ["@_catwu", "@AnthropicAI", "@augmentcode", "@bcherny"],
    by_status: { complete: 3, partial: 0, failed: 1, pending: 0 },
    anti_bot: { navs_used: 8, cap: 90, session_count: 1, paused_at: null },
    config: {
      with_replies_medium: false,
      no_replies: false,
      selector_probe_interval: 10,
      retry_s1_s2: 2,
      retry_s3_s4: 1,
      delay_min_ms: 0,
      delay_max_ms: 0,
      dry_run: true,
    },
  };

  await fs.writeFile(path.join(RUN_DIR, "master.json"), JSON.stringify(master, null, 2));

  const completeProfile = (idx, handle) => ({
    handle,
    index: idx,
    priority_bucket: "high_signal_required",
    status: "complete",
    stages: {
      S1_capture: { status: "complete", posts_count: 0, replies_count: 0 },
      S2_validate: {
        status: "complete",
        cutoff_reached: false,
        oldest_captured: null,
        tweets_in_window: 0,
        passed: true,
      },
      S3_synthesize: { status: "complete", candidate_count: 0 },
      S4_categorize: { status: "complete", categorized_count: 0, dropped_apolitical: 0 },
      S5_persist: { status: "complete", items_added: 0, duplicates_dropped: 0 },
      S6_checkoff: { status: "complete" },
    },
    raw_captures: {},
    synthesized_candidates: [],
    categorized_items: [],
    errors: [],
  });

  const failedProfile = (idx, handle) => ({
    handle,
    index: idx,
    priority_bucket: "high_signal_required",
    status: "failed",
    stages: {
      S1_capture: { status: "failed", error: "simulated 404" },
    },
    raw_captures: {},
    synthesized_candidates: [],
    categorized_items: [],
    errors: [{ stage: "S1", error: "simulated 404" }],
  });

  await fs.writeFile(
    path.join(RUN_DIR, "per-profile", "001-_catwu.json"),
    JSON.stringify(completeProfile(0, "@_catwu"), null, 2),
  );
  await fs.writeFile(
    path.join(RUN_DIR, "per-profile", "002-anthropicai.json"),
    JSON.stringify(completeProfile(1, "@AnthropicAI"), null, 2),
  );
  await fs.writeFile(
    path.join(RUN_DIR, "per-profile", "003-augmentcode.json"),
    JSON.stringify(completeProfile(2, "@augmentcode"), null, 2),
  );
  await fs.writeFile(
    path.join(RUN_DIR, "per-profile", "004-bcherny.json"),
    JSON.stringify(failedProfile(3, "@bcherny"), null, 2),
  );
}

async function readJson(fp) {
  return JSON.parse(await fs.readFile(fp, "utf-8"));
}

async function cleanupTmpCaptures() {
  const entries = await fs.readdir(__dirname);
  await Promise.all(
    entries
      .filter((e) => e.startsWith(".tmp-captures-"))
      .map((e) => fs.rm(path.join(__dirname, e), { force: true })),
  );
}

async function run() {
  section("retry-failed listing + stage subcommand reprocess\n");

  try {
    await setup();

    const listed = runCmd(["retry-failed", `--resume=${RUN_ID}`]);
    ok("retry-failed returns one handle", listed.json.total === 1, `total=${listed.json.total}`);
    ok(
      "retry-failed handle is @bcherny",
      listed.json.handles?.[0]?.handle === "@bcherny",
      JSON.stringify(listed.json.handles),
    );

    const index = listed.json.handles[0].index;
    const capturesFile = await writeCaptures("@bcherny");
    const resume = [`--resume=${RUN_ID}`];

    const s1 = runCmd(["commit-s1", `--index=${index}`, `--captures=${capturesFile}`, ...resume]);
    ok("commit-s1 s2_passed", s1.json.s2_passed === true);

    const s3 = runCmd(["synthesize", `--index=${index}`, ...resume]);
    ok("synthesize succeeded", s3.json.s3_status === "complete");

    const s4 = runCmd(["categorize", `--index=${index}`, ...resume]);
    ok("categorize succeeded", s4.json.s4_status === "complete");

    const s56 = runCmd(["commit-and-checkoff", `--index=${index}`, ...resume]);
    ok("commit-and-checkoff status complete", s56.json.status === "complete");

    const summary = runCmd(["summary", `--resume=${RUN_ID}`]);
    ok('summary status === "complete"', summary.json.status === "complete", summary.json.status);
    ok("by_status.complete === 4", summary.json.by_status.complete === 4);
    ok("by_status.failed === 0", summary.json.by_status.failed === 0);

    const bcherny = await readJson(path.join(RUN_DIR, "per-profile", "004-bcherny.json"));
    ok("@bcherny status complete", bcherny.status === "complete", bcherny.status);
    ok(
      "@bcherny S1 complete",
      bcherny.stages.S1_capture.status === "complete",
      bcherny.stages.S1_capture.status,
    );
    ok(
      "@bcherny has S2..S6",
      ["S2_validate", "S3_synthesize", "S4_categorize", "S5_persist", "S6_checkoff"].every(
        (s) => bcherny.stages[s]?.status === "complete",
      ),
    );

    const catwu = await readJson(path.join(RUN_DIR, "per-profile", "001-_catwu.json"));
    ok(
      "@_catwu untouched",
      catwu.status === "complete" && catwu.stages.S1_capture.posts_count === 0,
    );
  } finally {
    await fs.rm(RUN_DIR, { recursive: true, force: true });
    await cleanupTmpCaptures();
  }

  printResults();
  process.exit(fail > 0 ? 1 : 0);
}

run().catch((e) => {
  writelnStderr(String(e));
  process.exit(2);
});
