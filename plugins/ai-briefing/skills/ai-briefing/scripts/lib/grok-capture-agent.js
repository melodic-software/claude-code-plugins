// Wave 0 — spawn headless grok -p to capture X posts for one profile.

import { spawnSync } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";

import { probeGrokAvailability, WINDOWS_CMD_BAT_SUFFIX } from "./grok-availability.js";
import {
  bareHandle,
  buildGrokCapturePrompt,
  normalizeGrokPosts,
  parseGrokJsonPayload,
} from "./grok-normalize.js";

const DEFAULT_GROK_CAPTURE_TIMEOUT_MS = 300_000;

/** Stable session cwd keys on Windows — forward slashes only (Grok URL-encodes cwd). */
function grokSessionCwd() {
  const cwd = process.cwd();
  return process.platform === "win32" ? cwd.replace(/\\/g, "/") : cwd;
}

export async function captureProfileViaGrok({
  handle,
  cutoffIso,
  grokBin = "grok",
  grokModel,
  timeoutMs = DEFAULT_GROK_CAPTURE_TIMEOUT_MS,
  dryRun = false,
}) {
  const slug = bareHandle(handle);
  const started = Date.now();

  if (dryRun) {
    return {
      handle,
      slug,
      posts: { a: slug, n: 0, tw: [] },
      grok_model: grokModel ?? "dry-run",
      duration_ms: 0,
      skipped: false,
    };
  }

  const availability = probeGrokAvailability({ grokBin });
  if (!availability.ready) {
    const err = new Error(availability.message);
    err.code = "GROK_UNAVAILABLE";
    err.availability = availability;
    throw err;
  }

  const prompt = buildGrokCapturePrompt({ handle, cutoffIso });
  const args = [
    "--no-auto-update",
    "--always-approve",
    "--output-format",
    "json",
    "--cwd",
    grokSessionCwd(),
  ];
  if (grokModel) {
    args.push("-m", grokModel);
  }
  args.push("-p", prompt);

  const needsShell = process.platform === "win32" && WINDOWS_CMD_BAT_SUFFIX.test(availability.bin);
  const r = spawnSync(availability.bin, args, {
    encoding: "utf-8",
    timeout: timeoutMs,
    maxBuffer: 50 * 1024 * 1024,
    shell: needsShell,
  });

  if (r.status !== 0) {
    throw new Error(
      `grok -p (capture) exit ${r.status}: ${(r.stderr || r.stdout || "").substring(0, 500)}`,
    );
  }

  const parsed = parseGrokJsonPayload(r.stdout);
  const tw = normalizeGrokPosts(parsed, handle);

  return {
    handle,
    slug,
    posts: {
      a: slug,
      n: tw.length,
      tw,
    },
    grok_model: grokModel ?? "default",
    duration_ms: Date.now() - started,
  };
}

export async function writeGrokCaptureFile(runDir, slug, envelope) {
  const dir = path.join(runDir, "grok-captures");
  await fs.mkdir(dir, { recursive: true });
  const filePath = path.join(dir, `${slug}.json`);
  const body = {
    source: "grok",
    handle: envelope.handle,
    cutoff: envelope.cutoff,
    captured_at: new Date().toISOString(),
    grok_model: envelope.grok_model,
    duration_ms: envelope.duration_ms,
    posts: envelope.posts,
  };
  await fs.writeFile(filePath, JSON.stringify(body, null, 2), "utf-8");
  return filePath;
}
