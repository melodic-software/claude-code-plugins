#!/usr/bin/env node
/**
 * Orchestrate the deterministic post-vision sub-chains for a watch slice.
 *
 * Usage: node watch/finalize-vision.js [--dry-run] <slice-dir>
 *
 * Wraps ONLY the mechanical sub-chains that aggregate/render LLM-authored facts,
 * in order: merge → validate → render-triage-log, then render-quality-audit, then
 * render-key-frames-manifest. Judgment steps (Pass-2 PNG detail reads, promotion
 * verdicts) stay inline in the skill session — they are NOT part of this orchestrator.
 */

import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { mergeTriageJson } from "./merge-triage-json.js";
import { renderKeyFramesManifest } from "./render-key-frames-manifest.js";
import { renderQualityAudit } from "./render-quality-audit.js";
import { renderTriageLog } from "./render-triage-log.js";
import { runValidateTriageJson } from "./validate-triage-json.js";

/**
 * The ordered, mechanical sub-chains. Each step is `{ name, run }` where `run`
 * throws on failure so the sequential driver can short-circuit uniformly.
 *
 * `runValidateTriageJson` returns a non-zero exit code instead of throwing, so it
 * is wrapped to normalize the mixed error model into one throw-on-failure contract.
 *
 * @param {string} sliceDir
 * @returns {{ name: string, run: () => void }[]}
 */
export function finalizeVisionSteps(sliceDir) {
  return [
    { name: "merge-triage-json", run: () => mergeTriageJson(sliceDir) },
    {
      name: "validate-triage-json",
      run: () => {
        if (runValidateTriageJson(sliceDir) !== 0) {
          throw new Error("triage manifest validation failed");
        }
      },
    },
    { name: "render-triage-log", run: () => renderTriageLog(sliceDir) },
    { name: "render-quality-audit", run: () => renderQualityAudit(sliceDir) },
    { name: "render-key-frames-manifest", run: () => renderKeyFramesManifest(sliceDir) },
  ];
}

/**
 * Run the post-vision sub-chains in order, short-circuiting on the first failure.
 *
 * @param {string} sliceDir
 * @param {object} [options]
 * @param {boolean} [options.dryRun] - list the sub-chains without running them
 * @param {{ name: string, run: () => void }[]} [options.steps] - injectable for tests
 * @returns {number} 0 on success (or dry-run), 1 on the first failing sub-chain
 */
export function finalizeVision(
  sliceDir,
  { dryRun = false, steps = finalizeVisionSteps(sliceDir) } = {},
) {
  if (dryRun) {
    writeStdout(`finalize-vision sub-chains (dry-run, no writes) for ${sliceDir}:\n`);
    for (const step of steps) {
      writeStdout(`- ${step.name}\n`);
    }
    return 0;
  }

  for (const step of steps) {
    try {
      step.run();
      writeStdout(`finalize-vision: ${step.name} ok\n`);
    } catch (error) {
      writeStderr(
        `finalize-vision: ${step.name} failed: ${error instanceof Error ? error.message : String(error)}\n`,
      );
      return 1;
    }
  }
  return 0;
}

const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  const args = process.argv.slice(2);
  const dryRun = args.includes("--dry-run");
  const sliceDir = args.find((a) => !a.startsWith("--"));
  if (!sliceDir) {
    writeStderr("Usage: node watch/finalize-vision.js [--dry-run] <slice-dir>\n");
    process.exitCode = 2;
  } else {
    process.exitCode = finalizeVision(sliceDir, { dryRun });
  }
}
