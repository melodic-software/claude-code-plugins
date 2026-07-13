// grok-capture-agent — dry-run spawn contract

import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { captureProfileViaGrok } from "./lib/grok-capture-agent.js";
import { createTestReporter } from "./lib/terminal.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const { ok, printResults } = createTestReporter();

async function testDryRun() {
  const r = await captureProfileViaGrok({
    handle: "@xai",
    cutoffIso: "2026-06-01T00:00:00.000Z",
    dryRun: true,
  });
  ok(r.posts.n === 0, "dry-run returns empty posts");
  ok(r.slug === "xai", "slugifies handle");
}

async function testRunnerSubcommandDryRun() {
  const runner = path.join(__dirname, "per-profile-runner.js");
  const r = spawnSync(
    process.execPath,
    [
      runner,
      "init",
      "--scope=test",
      "--force",
      "--dry-run",
      "--grok-preload",
      "--cutoff=2026-06-01T00:00:00.000Z",
    ],
    { encoding: "utf-8", cwd: __dirname },
  );
  ok(r.status === 0, `init exit 0 (got ${r.status})`);
  const json = JSON.parse(r.stdout.trim().split("\n").pop());
  ok(typeof json.config.grok_preload === "boolean", "grok_preload boolean in config");
  ok(json.config.grok_preload_requested === true, "grok_preload_requested tracked");
}

async function testGrokCheck() {
  const runner = path.join(__dirname, "per-profile-runner.js");
  const r = spawnSync(process.execPath, [runner, "grok-check"], {
    encoding: "utf-8",
    cwd: __dirname,
  });
  ok(r.status === 0, "grok-check exit 0");
  const json = JSON.parse(r.stdout.trim());
  ok(typeof json.ready === "boolean", "grok-check has ready");
  ok(json.required_for_briefing === false, "grok not required for briefing");
}

await testDryRun();
await testRunnerSubcommandDryRun();
await testGrokCheck();
const failCount = printResults("grok-capture-agent.test.js");
process.exit(failCount > 0 ? 1 : 0);
