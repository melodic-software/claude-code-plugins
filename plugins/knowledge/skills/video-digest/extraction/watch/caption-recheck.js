#!/usr/bin/env node
/**
 * Caption re-check for a `QUEUE.md` row held in `awaiting_captions`: one caption-only
 * acquisition (the transcript-mode caption passes, no video download), then the row's verdict.
 *
 * Usage: node watch/caption-recheck.js <video-url> --caption-wait-deadline <iso>
 *
 * Prints `{ result, ... }` and exits:
 *   0 `captions-ready`: resume the row to `pending`; the watch run then uses the captions
 *   0 `wait-ended` with `notes`: resume the row with those notes; the watch run falls through
 *   3 `captions-pending` with `nextCheckAt` and `deadline`: hold the row again
 *   1 `failed` with `error`, `nextCheckAt` and `deadline`: any other acquisition failure
 *     before the deadline; hold the row again. One after the deadline is `wait-ended`, so a
 *     failing re-check never holds a row past its deadline.
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import {
  CAPTION_WAIT_CHECK_INTERVAL_MS,
  CAPTIONS_PENDING_EXIT,
  captionsPendingReport,
  captionWaitEndedNote,
  parseCaptionWaitDeadline,
} from "../acquisition/caption-wait.js";
import { UnsupportedSourceError } from "../adapters/adapter-contract.js";
import { acquireMedia } from "../adapters/registry.js";
import { runMain } from "../lib/run-main.js";

/**
 * @typedef {{ result: 'captions-ready' } |
 *   ({ result: 'captions-pending' } & ReturnType<typeof captionsPendingReport>) |
 *   { result: 'wait-ended', notes: string } |
 *   { result: 'failed', error: string, nextCheckAt: string, deadline: string }} RecheckResult
 */

/**
 * @param {string} url
 * @param {{ deadline: string, acquire?: typeof acquireMedia, now?: () => number }} options -
 *   `deadline` is the one the held row recorded
 * @returns {Promise<RecheckResult>}
 */
export async function recheckCaptions(url, { deadline, acquire = acquireMedia, now = Date.now }) {
  const workDir = await fs.mkdtemp(path.join(os.tmpdir(), "video-caption-recheck-"));
  try {
    const outcome = await acquire(url, { workDir, mode: "transcript", captionWaitDeadline: deadline });
    if (outcome.success) {
      return { result: "captions-ready" };
    }
    const wait = outcome.captionWait;
    if (wait?.state === "wait") {
      return { result: "captions-pending", ...captionsPendingReport(wait) };
    }
    if (wait?.state === "expired") {
      return { result: "wait-ended", notes: captionWaitEndedNote(wait) };
    }
    const error = outcome.error ?? "Acquisition failed";
    const nowMs = now();
    const deadlineMs = Date.parse(deadline);
    if (nowMs >= deadlineMs) {
      return {
        result: "wait-ended",
        notes: `caption wait ended at deadline ${deadline}; last re-check failed (${error}); falls through to ASR or transcriptDegradation`,
      };
    }
    return {
      result: "failed",
      error,
      nextCheckAt: new Date(Math.min(nowMs + CAPTION_WAIT_CHECK_INTERVAL_MS, deadlineMs)).toISOString(),
      deadline,
    };
  } finally {
    await fs.rm(workDir, { recursive: true, force: true });
  }
}

/**
 * @param {RecheckResult['result']} result
 * @returns {number}
 */
export function recheckExitCode(result) {
  if (result === "captions-pending") return CAPTIONS_PENDING_EXIT;
  return result === "failed" ? 1 : 0;
}

/**
 * @param {string[]} argv
 * @returns {Promise<number>}
 */
async function main(argv) {
  const url = argv[2];
  const waitArg = parseCaptionWaitDeadline(argv);
  if (!waitArg.ok) {
    writeStderr(waitArg.error);
    return 1;
  }
  if (!url || url.startsWith("--") || !waitArg.deadline) {
    writeStderr("Usage: node watch/caption-recheck.js <video-url> --caption-wait-deadline <iso>");
    return 1;
  }
  try {
    const outcome = await recheckCaptions(url, { deadline: waitArg.deadline });
    writeStdout(JSON.stringify(outcome, null, 2));
    return recheckExitCode(outcome.result);
  } catch (error) {
    if (error instanceof UnsupportedSourceError) {
      writeStderr(error.message);
      return 1;
    }
    throw error;
  }
}

runMain(import.meta.url, main);
