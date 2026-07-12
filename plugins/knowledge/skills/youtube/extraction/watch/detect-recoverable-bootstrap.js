#!/usr/bin/env node
/**
 * Detect whether a watch slice can recover bootstrap from surviving temp dirs.
 *
 * Usage: node watch/detect-recoverable-bootstrap.js <slice-dir> [--json]
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { resolveTempSession } from "../lib/temp-session-paths.js";
import { watchStatePath } from "./watch-state.js";

/**
 * @param {string} workDir
 * @returns {boolean}
 */
function workDirComplete(workDir) {
  if (!workDir || !fs.existsSync(workDir)) return false;
  const entries = fs.readdirSync(workDir);
  return (
    entries.some((n) => n.endsWith(".mp4")) &&
    entries.some((n) => n.endsWith(".vtt") && !n.includes("-orig")) &&
    entries.some((n) => n.endsWith(".info.json"))
  );
}

/**
 * @param {string} sliceDir
 * @returns {{
 *   recoverable: boolean,
 *   reason: string,
 *   watchingComplete: boolean,
 *   tempSession?: { workDir?: string, framesDir?: string, contactSheetsDir?: string },
 *   sheetCount?: number,
 *   frameCount?: number,
 * }}
 */
export function detectRecoverableBootstrap(sliceDir) {
  const absSlice = path.resolve(sliceDir);
  const watchPath = watchStatePath(absSlice);
  const selectionPath = lanePath(absSlice, LANES.keyFrames, "selection.json");

  if (!fs.existsSync(watchPath)) {
    return { recoverable: false, reason: "watch.json missing", watchingComplete: false };
  }

  const watch = JSON.parse(fs.readFileSync(watchPath, "utf8"));
  const watchingComplete = Boolean(watch.phases?.watching?.completedAt);
  const selectionExists = fs.existsSync(selectionPath);

  if (watchingComplete && selectionExists) {
    return {
      recoverable: false,
      reason: "watching phase already complete",
      watchingComplete: true,
    };
  }

  const tempSession = resolveTempSession(watch.tempSession ?? {});
  const workDir = tempSession.workDir;
  const framesDir = tempSession.framesDir;
  const contactSheetsDir = tempSession.contactSheetsDir;

  const hasWork = workDirComplete(workDir);
  const frameCount =
    framesDir && fs.existsSync(framesDir)
      ? fs.readdirSync(framesDir).filter((n) => n.endsWith(".png")).length
      : 0;
  const sheetCount =
    contactSheetsDir && fs.existsSync(contactSheetsDir)
      ? fs.readdirSync(contactSheetsDir).filter((n) => /^sheet_\d+\.jpg$/i.test(n)).length
      : 0;

  const hasFrames = frameCount > 0;
  const hasSheets = sheetCount > 0;
  const recoverable = hasFrames && hasSheets;

  let reason;
  if (recoverable && hasWork) {
    reason = "temp dirs have video, frames, and contact sheets";
  } else if (recoverable) {
    reason = "temp dirs have frames and contact sheets (transcript may exist in slice)";
  } else {
    reason = `insufficient temp artifacts (frames=${frameCount}, sheets=${sheetCount}, work=${hasWork})`;
  }

  return {
    recoverable,
    reason,
    watchingComplete: false,
    tempSession: { workDir, framesDir, contactSheetsDir },
    sheetCount,
    frameCount,
  };
}

/**
 * @param {string} sliceDir
 * @returns {string}
 */
export function formatRecoverCommand(sliceDir) {
  const detection = detectRecoverableBootstrap(sliceDir);
  if (!detection.recoverable || !detection.tempSession) {
    return "";
  }
  const { workDir, framesDir, contactSheetsDir } = detection.tempSession;
  return `node "\${CLAUDE_PLUGIN_ROOT}/skills/youtube/extraction/watch/recover-watch-bootstrap.js" "${sliceDir}" "${workDir}" "${framesDir}" "${contactSheetsDir}"`;
}

/**
 * @param {string[]} argv
 * @returns {number}
 */
export function runDetectRecoverableBootstrapCli(argv) {
  const sliceDir = argv[2];
  const asJson = argv.includes("--json");
  if (!sliceDir) {
    writeStderr("Usage: node watch/detect-recoverable-bootstrap.js <slice-dir> [--json]");
    return 2;
  }

  const result = detectRecoverableBootstrap(sliceDir);
  const payload = {
    ...result,
    recoverCommand: result.recoverable ? formatRecoverCommand(sliceDir) : null,
  };

  if (asJson) {
    writeStdout(`${JSON.stringify(payload, null, 2)}\n`);
  } else if (result.recoverable) {
    writeStdout(`RECOVERABLE: ${result.reason}\n${payload.recoverCommand}\n`);
  } else {
    writeStdout(`NOT_RECOVERABLE: ${result.reason}\n`);
  }

  return result.recoverable ? 0 : 1;
}

const isMain =
  process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isMain) {
  process.exitCode = runDetectRecoverableBootstrapCli(process.argv);
}
