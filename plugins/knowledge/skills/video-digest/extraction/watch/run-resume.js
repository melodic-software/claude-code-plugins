#!/usr/bin/env node
/**
 * CLI: resume interrupted `/video-digest watch` from phase-map state.
 *
 * Usage: node watch/run-resume.js <slice-slug>
 *
 * A video id, or a ranged row's `<id>-r<from>-<to>` key, in place of the slug resumes
 * the one slice that matches; when a bare id matches several slices (one per range),
 * it fails and lists their slugs.
 */

import fs from "node:fs";
import path from "node:path";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { runMain } from "../lib/run-main.js";
import { normalizePortableTempPath, resolveTempSession } from "../lib/temp-session-paths.js";
import { rangedSliceKey } from "../lib/time-range.js";
import { resolveWorkRoot } from "../lib/work-root.js";
import { resolveWorkSliceDir, YOUTUBE_WATCH_EPIC_DIR } from "../transcript/derive-video-slug.js";
import {
  detectRecoverableBootstrap,
  formatRecoverCommand,
} from "./detect-recoverable-bootstrap.js";
import {
  continuationPromptPath,
  findNextPhase,
  readWatchState,
  writeContinuationPrompt,
} from "./watch-state.js";

/** Temp-session dirs vision reads its frames and contact sheets from. */
const VISION_TEMP_KEYS = /** @type {const} */ (["framesDir", "contactSheetsDir"]);

/**
 * Recorded vision temp dirs that no longer exist, in portable `{tmp}` form.
 *
 * @param {{ workDir?: string, framesDir?: string, contactSheetsDir?: string }|undefined} tempSession
 * @returns {string[]}
 */
function missingTempSessionDirs(tempSession) {
  if (!tempSession) return [];
  const resolved = resolveTempSession(tempSession);
  return VISION_TEMP_KEYS.filter((key) => {
    const dir = resolved[key];
    return dir !== undefined && !fs.existsSync(dir);
  }).map((key) => String(normalizePortableTempPath(tempSession[key])));
}

/**
 * Slugs of the slices whose watch.json records `key` as its video id, or as its video id
 * plus range suffix (a ranged `QUEUE.md` row's `video-id` cell), sorted. One video can
 * have several slices, one per range.
 *
 * @param {string} workRoot
 * @param {string} key
 * @returns {Promise<string[]>}
 */
async function slicesForKey(workRoot, key) {
  const epicDir = path.join(workRoot, ".work", YOUTUBE_WATCH_EPIC_DIR);
  const dirs = fs.existsSync(epicDir)
    ? fs.readdirSync(epicDir, { withFileTypes: true }).filter((entry) => entry.isDirectory())
    : [];
  const matches = [];
  for (const dir of dirs) {
    const state = await readWatchState(path.join(epicDir, dir.name));
    if (!state) continue;
    if (state.videoId === key || rangedSliceKey(state.videoId, state.timeRange) === key) {
      matches.push(dir.name);
    }
  }
  return matches.sort();
}

/**
 * @param {string[]} argv
 */
export async function runResumeCli(argv) {
  let videoSlug = argv[2];
  if (!videoSlug) {
    writeStderr("Usage: node watch/run-resume.js <slice-slug>");
    return 1;
  }

  const workRoot = resolveWorkRoot();
  let sliceDir;
  try {
    sliceDir = resolveWorkSliceDir(workRoot, videoSlug);
  } catch (error) {
    writeStderr(error instanceof Error ? error.message : String(error));
    return 1;
  }
  let state = await readWatchState(sliceDir);

  // Not a slug: take it as a video id, or id plus range, when exactly one slice matches.
  if (!state) {
    const matches = await slicesForKey(workRoot, videoSlug);
    if (matches.length > 1) {
      writeStderr(
        `${videoSlug} matches ${matches.length} slices, one per range; resume one by its slug: ${matches.join(", ")}`,
      );
      return 1;
    }
    if (matches.length === 1) {
      videoSlug = matches[0];
      sliceDir = resolveWorkSliceDir(workRoot, videoSlug);
      state = await readWatchState(sliceDir);
    }
  }

  if (!state) {
    writeStderr(`No watch.json found at ${sliceDir}`);
    return 1;
  }

  const nextPhase = findNextPhase(state.phases);
  const summary = { videoSlug, sliceDir, status: state.status, nextPhase };

  // A closed slice has nothing to resume, and its prompt may be committed: leave it as is.
  if (state.status === "complete") {
    writeStdout(JSON.stringify({ ...summary, nothingToResume: true }, null, 2));
    return 0;
  }

  const missingTempDirs = missingTempSessionDirs(state.tempSession);
  const tempSessionPresent = missingTempDirs.length === 0;

  if (nextPhase === "vision" && !tempSessionPresent) {
    writeStdout(JSON.stringify({ ...summary, tempSessionPresent, missingTempDirs }, null, 2));
    writeStderr(
      `resume: temp session dirs are gone (${missingTempDirs.join(", ")}) and vision reads its frames from them. Re-run run-watch.js for this slice, then resume.`,
    );
    return 1;
  }

  const continuationPrompt = await writeContinuationPrompt(sliceDir, state);
  const recovery = detectRecoverableBootstrap(sliceDir);

  writeStdout(
    JSON.stringify(
      {
        ...summary,
        target: state.target ?? null,
        frameSelection: state.frameSelection ?? null,
        tempSessionPresent,
        missingTempDirs,
        continuationPromptPath: continuationPromptPath(sliceDir),
        continuationPrompt,
        recoverableBootstrap: recovery.recoverable,
        recoverCommand: recovery.recoverable ? formatRecoverCommand(sliceDir) : null,
      },
      null,
      2,
    ),
  );

  return 0;
}

runMain(import.meta.url, runResumeCli);
