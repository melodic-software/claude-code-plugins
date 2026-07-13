// Grok headless spawn helpers — argv/cwd/session contracts + bounded concurrency (Wave 0 perf spikes).

import { spawnSync } from "node:child_process";
import { mkdtempSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { WINDOWS_CMD_BAT_SUFFIX } from "./grok-availability.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const INSTRUCTION_PATH_HEURISTIC = /Agents\.md|AGENTS\.md|CLAUDE\.md/gi;

/** Default scripts dir for skill-scoped cwd (still inside git; walks to repo AGENTS.md). */
export const DEFAULT_SKILL_SCRIPTS_DIR = path.resolve(__dirname, "..");

export const GROK_CAPTURE_CWD_MODES = ["process", "skill-scripts", "isolated"];

/** Normalize cwd for Grok CLI (forward slashes on Windows). */
export function formatGrokCwd(rawPath) {
  const raw = String(rawPath || "");
  return process.platform === "win32" ? raw.replace(/\\/g, "/") : raw;
}

/**
 * Resolve `--cwd` for headless grok -p.
 *
 * - process: caller cwd (legacy Wave 0 default)
 * - skill-scripts: ai-briefing/scripts (narrower tree walk)
 * - isolated: empty temp dir outside repo workflow (spike / opt-in perf)
 */
export function resolveGrokCaptureCwd(mode, options = {}) {
  return formatGrokCwd(resolveGrokSpawnCwd(mode, options));
}

/** Native filesystem path for spawnSync `cwd` (not URL-encoded for grok --cwd). */
export function resolveGrokSpawnCwd(mode, options = {}) {
  const resolvedMode = GROK_CAPTURE_CWD_MODES.includes(mode) ? mode : "process";
  switch (resolvedMode) {
    // biome-ignore lint/suspicious/noUnnecessaryConditions: resolvedMode is value-narrowed from the runtime `mode` arg, so this case fires when mode === "skill-scripts"; Biome's literal-narrowing to "process" ignores the value boundary.
    case "skill-scripts":
      return options.skillScriptsDir ?? DEFAULT_SKILL_SCRIPTS_DIR;
    // biome-ignore lint/suspicious/noUnnecessaryConditions: same root cause as the "skill-scripts" case — resolvedMode is value-checked against the runtime `mode` arg, so this case fires when mode === "isolated".
    case "isolated":
      if (!options.isolatedDir) {
        // biome-ignore lint/security/noSecrets: false positive on error message string
        throw new Error("isolated cwd mode requires isolatedDir (use createIsolatedGrokCwd())");
      }
      return options.isolatedDir;
    default:
      return options.processCwd ?? process.cwd();
  }
}

/** Create an empty directory suitable for isolated --cwd (no project instructions). */
export function createIsolatedGrokCwd(prefix = "grok-capture-") {
  return mkdtempSync(path.join(os.tmpdir(), prefix));
}

/**
 * Build argv for `grok -p` capture. Prompt must be last (`-p` then prompt).
 * Flags before `-p`: --no-auto-update, --always-approve, --output-format, --cwd, optional session/model.
 */
export function buildGrokCaptureArgv({ prompt, cwd, grokModel, sessionId, resume }) {
  if (!prompt) {
    throw new Error("prompt is required");
  }
  if (!cwd) {
    throw new Error("cwd is required");
  }

  const args = ["--no-auto-update", "--always-approve", "--output-format", "json", "--cwd", cwd];

  if (sessionId) {
    args.push("--session-id", sessionId);
  }
  if (resume) {
    args.push("--resume", resume);
  }
  if (grokModel) {
    args.push("-m", grokModel);
  }

  args.push("-p", prompt);
  return args;
}

/** Build argv for `grok inspect --json` (cheap instruction-load probe). Use spawn `cwd` option — inspect has no --cwd flag. */
export function buildGrokInspectArgv() {
  return ["--no-auto-update", "inspect", "--json"];
}

/** Count instruction paths from grok inspect --json stdout (best-effort). */
export function countGrokInspectInstructions(stdout) {
  const raw = String(stdout || "").trim();
  if (!raw) {
    return { instruction_count: null, parse_error: "empty stdout" };
  }

  try {
    const data = JSON.parse(raw);
    const paths =
      data.instructions ??
      data.project_instructions ??
      data.instruction_paths ??
      data.instructionPaths ??
      null;

    if (Array.isArray(paths)) {
      return { instruction_count: paths.length, parse_error: null };
    }

    const nested = data.environment?.instructions ?? data.project?.instructions;
    if (Array.isArray(nested)) {
      return { instruction_count: nested.length, parse_error: null };
    }

    const text = JSON.stringify(data);
    const pathMatches = text.match(INSTRUCTION_PATH_HEURISTIC);
    return {
      instruction_count: pathMatches ? pathMatches.length : null,
      parse_error: "no instruction array in inspect JSON",
    };
  } catch (e) {
    return { instruction_count: null, parse_error: String(e.message || e) };
  }
}

export function grokSpawnNeedsShell(bin) {
  return process.platform === "win32" && WINDOWS_CMD_BAT_SUFFIX.test(bin);
}

export function runGrokCommand({ bin, args, timeoutMs = 300_000, needsShell, spawnCwd }) {
  const shell = needsShell ?? grokSpawnNeedsShell(bin);
  return spawnSync(bin, args, {
    encoding: "utf-8",
    timeout: timeoutMs,
    maxBuffer: 50 * 1024 * 1024,
    shell,
    cwd: spawnCwd,
  });
}

/** Run tasks with a concurrency cap (rate-limit cautious fan-out). */
export async function mapWithConcurrency(items, fn, concurrency) {
  const limit = Math.max(1, Math.floor(concurrency));
  if (!items.length) {
    return [];
  }

  const results = new Array(items.length);
  let nextIndex = 0;

  async function worker() {
    for (;;) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= items.length) {
        return;
      }
      // biome-ignore lint/performance/noAwaitInLoops: worker pool dequeue loop
      results[index] = await fn(items[index], index);
    }
  }

  const workerCount = Math.min(limit, items.length);
  await Promise.all(Array.from({ length: workerCount }, () => worker()));
  return results;
}

/** Pause between live spike calls (subscription throttle guard). */
export function spikePauseMs() {
  const raw = process.env.GROK_SPIKE_PAUSE_MS;
  const parsed = raw ? Number.parseInt(raw, 10) : 8_000;
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 8_000;
}

export function spikeMaxLiveCaptures() {
  if (process.env.GROK_PERF_SPIKE_AGGRESSIVE === "1") {
    return 6;
  }
  return 3;
}

export function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}
