/**
 * Extract single-frame PNG snapshots at explicit timestamps via ffmpeg.
 */

import { existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

import {
  normalizeSpawnPath,
  resolveSpawnInputPath,
  spawnAsync,
} from "@melodic/video-digestion/shared/process";

const REMOTE_VIDEO_INPUT = /^https?:\/\//i;

/** @typedef {import('@melodic/video-digestion/frames/models.js').FrameCandidate} FrameCandidate */

const DEFAULT_SCALE_FILTER = "1280:-1";

/**
 * @param {number} index
 * @param {number} timestampSec
 * @returns {string}
 */
export function anchorFrameFileName(index, timestampSec) {
  const stamp = String(Math.round(timestampSec * 1000)).padStart(8, "0");
  return `anchor_${stamp}_${String(index).padStart(4, "0")}.png`;
}

export const ANCHOR_HEARTBEAT_INTERVAL = 25;
export const ANCHOR_STALE_SILENCE_MS = 10 * 60 * 1000;

/**
 * @param {number} sec
 * @returns {string}
 */
export function formatElapsedMinutes(sec) {
  const minutes = Math.floor(sec / 60);
  const seconds = Math.floor(sec % 60);
  return `${minutes}m${String(seconds).padStart(2, "0")}s`;
}

/**
 * Extract PNG frames at explicit timestamps.
 *
 * @param {string} videoPath
 * @param {string} outputDir
 * @param {number[]} timestampsSec
 * @param {object} [options]
 * @param {string} [options.scale]
 * @param {typeof spawnAsync} [options.spawn]
 * @param {number} [options.heartbeatInterval]
 * @param {number} [options.staleSilenceMs]
 * @param {{ info: (msg: string) => void, warn?: (msg: string) => void }} [options.log]
 * @returns {Promise<FrameCandidate[]>}
 */
export async function extractAnchorFrames(
  videoPath,
  outputDir,
  timestampsSec,
  {
    scale = DEFAULT_SCALE_FILTER,
    spawn = spawnAsync,
    heartbeatInterval = ANCHOR_HEARTBEAT_INTERVAL,
    staleSilenceMs = ANCHOR_STALE_SILENCE_MS,
    log,
  } = {},
) {
  mkdirSync(outputDir, { recursive: true });
  const inputPath = resolveSpawnInputPath(videoPath);
  const remote = REMOTE_VIDEO_INPUT.test(inputPath);
  /** @type {FrameCandidate[]} */
  const frames = [];

  const uniqueTimestamps = [...new Set(timestampsSec)].sort((a, b) => a - b);
  const total = uniqueTimestamps.length;
  const phaseStartMs = Date.now();
  let lastLogMs = phaseStartMs;

  const emitHeartbeat = (index, timestampSec) => {
    if (!log) return;
    const elapsedSec = (Date.now() - phaseStartMs) / 1000;
    log.info(
      `watching: anchor ${index + 1}/${total} @ ${formatElapsedMinutes(timestampSec)} elapsed ${formatElapsedMinutes(elapsedSec)}`,
    );
    lastLogMs = Date.now();
  };

  for (let index = 0; index < uniqueTimestamps.length; index++) {
    const timestampSec = uniqueTimestamps[index];
    if (log && staleSilenceMs > 0 && Date.now() - lastLogMs >= staleSilenceMs && index > 0) {
      const warn = log.warn ?? log.info;
      warn(
        `watching: anchor extraction silent >${Math.round(staleSilenceMs / 60000)}m — still running (${index}/${total})`,
      );
      lastLogMs = Date.now();
    }
    if (index === 0 || (index + 1) % heartbeatInterval === 0 || index === total - 1) {
      emitHeartbeat(index, timestampSec);
    }

    const file = anchorFrameFileName(index + 1, timestampSec);
    const outputPath = join(outputDir, file);
    /** @type {string[]} */
    const args = ["-hide_banner", "-loglevel", "error", "-y"];

    if (remote) {
      args.push("-user_agent", "Mozilla/5.0");
    }

    args.push(
      "-ss",
      String(timestampSec),
      "-i",
      normalizeSpawnPath(inputPath),
      "-frames:v",
      "1",
      "-vf",
      `scale=${scale}`,
      normalizeSpawnPath(outputPath),
    );

    const result = await spawn("ffmpeg", args, {});
    if (!result.success || !existsSync(outputPath)) continue;

    frames.push({
      path: outputPath,
      file,
      timestampSec,
      sceneScore: null,
      isInterval: true,
    });
  }

  return frames;
}
