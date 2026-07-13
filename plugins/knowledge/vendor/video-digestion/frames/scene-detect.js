/**
 * Scene-detected frame extraction from video URLs via ffmpeg.
 *
 * Uses ffmpeg scene-change filter with interval fallback when too few frames
 * are detected. Provider-agnostic — consumers pass HLS or file URLs.
 */

import { existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

import { createLogger } from "../shared/logger.js";
import { normalizeSpawnPath, resolveSpawnInputPath, spawnAsync } from "../shared/process.js";

/** @typedef {import('./models.js').FrameCandidate} FrameCandidate */
/** @typedef {import('./models.js').SceneDetectResult} SceneDetectResult */

const FFMPEG_ERROR_PATTERN = /error|403|401|invalid|denied/i;
const REMOTE_VIDEO_INPUT = /^https?:\/\//i;

export const DEFAULT_SCENE_THRESHOLD = 0.15;
export const DEFAULT_INTERVAL_FPS = "1/30";
export const DEFAULT_MIN_FRAMES_FOR_SCENE = 5;
export const DEFAULT_SCALE_FILTER = "1280:-1";
export const DEFAULT_FFMPEG_USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36";

/**
 * Count sequentially numbered frame files in a directory.
 * @param {string} dir
 * @param {string} prefix
 * @param {number} [max]
 * @returns {number}
 */
export function countFrameFiles(dir, prefix, max = 500) {
  let count = 0;
  for (let i = 1; i <= max; i++) {
    if (existsSync(join(dir, `${prefix}_${String(i).padStart(4, "0")}.png`))) {
      count++;
    } else {
      break;
    }
  }
  return count;
}

/**
 * Build FrameCandidate descriptors from numbered PNG outputs.
 * @param {string} outputDir
 * @param {string} prefix
 * @param {boolean} isInterval
 * @returns {FrameCandidate[]}
 */
export function listFrameCandidates(outputDir, prefix, isInterval = false) {
  const count = countFrameFiles(outputDir, prefix);
  /** @type {FrameCandidate[]} */
  const frames = [];
  for (let i = 1; i <= count; i++) {
    const file = `${prefix}_${String(i).padStart(4, "0")}.png`;
    frames.push({
      path: join(outputDir, file),
      file,
      timestampSec: null,
      sceneScore: null,
      isInterval,
    });
  }
  return frames;
}

/**
 * Normalize ffmpeg output paths for cross-platform spawn (Windows forward slashes).
 * @param {string} pattern
 * @returns {string}
 */
export function normalizeFfmpegPath(pattern) {
  return normalizeSpawnPath(pattern);
}

/**
 * Remote HLS/HTTP inputs need Referer/user-agent; local files must not (ffmpeg 8+).
 *
 * @param {string} videoInput
 * @returns {boolean}
 */
export function isRemoteVideoInput(videoInput) {
  return REMOTE_VIDEO_INPUT.test(videoInput);
}

/**
 * Run ffmpeg with the given video filter.
 * @param {import('../shared/process.js').spawnAsync} spawn
 * @param {import('../shared/logger.js').PipelineLogger} log
 * @param {string} videoUrl
 * @param {string} outputPattern
 * @param {string} vfFilter
 * @param {object} [options]
 * @param {boolean} [options.vsyncVfr=false]
 * @param {string} [options.referer=""]
 * @param {string} [options.userAgent]
 * @returns {Promise<boolean>}
 */
// biome-ignore lint/complexity/useMaxParams: ffmpeg spawn seam keeps process/logger injectors separate from capture args
export async function runSceneFfmpeg(
  spawn,
  log,
  videoUrl,
  outputPattern,
  vfFilter,
  { vsyncVfr = false, referer = "", userAgent = DEFAULT_FFMPEG_USER_AGENT } = {},
) {
  const resolvedInput = resolveSpawnInputPath(videoUrl);
  const ffmpegArgs = ["-y"];
  if (isRemoteVideoInput(videoUrl)) {
    ffmpegArgs.push("-user_agent", userAgent, "-headers", `Referer: ${referer}\r\n`);
  }
  ffmpegArgs.push(
    "-i",
    resolvedInput,
    "-vf",
    vfFilter,
    ...(vsyncVfr ? ["-vsync", "vfr"] : []),
    normalizeFfmpegPath(outputPattern),
  );

  const result = await spawn("ffmpeg", ffmpegArgs);
  if (!result.success) {
    const errorLines = (result.stderr || "")
      .split("\n")
      .filter((line) => FFMPEG_ERROR_PATTERN.test(line));
    if (errorLines.length > 0) {
      log.warn(`ffmpeg error: ${errorLines[0].trim().substring(0, 120)}`);
    }
    return false;
  }
  return true;
}

/**
 * Extract scene-detected frames from a video URL, with interval fallback.
 *
 * @param {string} videoUrl - HLS or direct video URL
 * @param {string} outputDir - Directory for extracted PNG frames
 * @param {object} [options]
 * @param {number} [options.sceneThreshold=0.15]
 * @param {string} [options.intervalFps="1/30"]
 * @param {number} [options.minFramesForScene=5]
 * @param {string} [options.referer=""]
 * @param {string} [options.userAgent]
 * @param {string} [options.scale="1280:-1"]
 * @param {object} [deps]
 * @param {import('../shared/process.js').spawnAsync} [deps.spawn]
 * @param {import('../shared/logger.js').PipelineLogger} [deps.log]
 * @returns {Promise<SceneDetectResult>}
 */
export async function extractSceneFrames(
  videoUrl,
  outputDir,
  {
    sceneThreshold = DEFAULT_SCENE_THRESHOLD,
    intervalFps = DEFAULT_INTERVAL_FPS,
    minFramesForScene = DEFAULT_MIN_FRAMES_FOR_SCENE,
    referer = "",
    userAgent = DEFAULT_FFMPEG_USER_AGENT,
    scale = DEFAULT_SCALE_FILTER,
  } = {},
  { spawn = spawnAsync, log = createLogger() } = {},
) {
  mkdirSync(outputDir, { recursive: true });

  log.info(`scene-detect: starting (threshold=${sceneThreshold}, min=${minFramesForScene})`);

  const scenePattern = join(outputDir, "scene_%04d.png");
  const sceneFilter = `select='gt(scene,${sceneThreshold})',scale=${scale}`;

  const sceneOk = await runSceneFfmpeg(spawn, log, videoUrl, scenePattern, sceneFilter, {
    vsyncVfr: true,
    referer,
    userAgent,
  });
  const sceneCount = sceneOk ? countFrameFiles(outputDir, "scene") : 0;

  if (!sceneOk) {
    log.warn("scene-detect: scene filter failed — falling back to interval capture");
  }

  if (sceneCount < minFramesForScene) {
    log.info(
      `scene-detect: ${sceneCount} frames (below ${minFramesForScene}) — adding interval capture`,
    );
    const intervalPattern = join(outputDir, "interval_%04d.png");
    const intervalFilter = `fps=${intervalFps},scale=${scale}`;
    await runSceneFfmpeg(spawn, log, videoUrl, intervalPattern, intervalFilter, {
      referer,
      userAgent,
    });

    const intervalCount = countFrameFiles(outputDir, "interval");
    const sceneFrames = listFrameCandidates(outputDir, "scene", false);
    const intervalFrames = listFrameCandidates(outputDir, "interval", true);
    const frames = [...sceneFrames, ...intervalFrames];

    log.info(
      `scene-detect: complete method=hybrid scene=${sceneCount} interval=${intervalCount} total=${frames.length}`,
    );

    return {
      method: "hybrid",
      sceneCount,
      intervalCount,
      count: frames.length,
      frames,
    };
  }

  const frames = listFrameCandidates(outputDir, "scene", false);
  log.info(`scene-detect: complete method=scene-detection count=${frames.length}`);

  return {
    method: "scene-detection",
    sceneCount,
    count: frames.length,
    frames,
  };
}
