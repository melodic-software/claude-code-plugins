// grok-capture-agent — dry-run spawn contract

import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { captureProfileViaGrok } from "./lib/grok-capture-agent.js";
import { createTestReporter } from "./lib/terminal.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const reporter = createTestReporter();
const { ok } = reporter;

async function testDryRun() {
  const r = await captureProfileViaGrok({
    handle: "@xai",
    cutoffIso: "2026-06-01T00:00:00.000Z",
    dryRun: true,
  });
  ok("dry-run returns empty posts", r.posts.n === 0);
  ok("slugifies handle", r.slug === "xai");
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
  ok(`init exit 0 (got ${r.status})`, r.status === 0);
  const json = JSON.parse(r.stdout.trim().split("\n").pop());
  ok("grok_preload boolean in config", typeof json.config.grok_preload === "boolean");
  ok("grok_preload_requested tracked", json.config.grok_preload_requested === true);
}

async function testGrokCheck() {
  const runner = path.join(__dirname, "per-profile-runner.js");
  const r = spawnSync(process.execPath, [runner, "grok-check"], {
    encoding: "utf-8",
    cwd: __dirname,
  });
  ok("grok-check exit 0", r.status === 0);
  const json = JSON.parse(r.stdout.trim());
  ok("grok-check has ready", typeof json.ready === "boolean");
  ok("grok not required for briefing", json.required_for_briefing === false);
}

await testDryRun();
await testRunnerSubcommandDryRun();
await testGrokCheck();
reporter.printResults();
process.exit(reporter.fail > 0 ? 1 : 0);
