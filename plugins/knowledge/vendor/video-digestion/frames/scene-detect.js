/**
 * Scene-detected frame extraction from video URLs via ffmpeg.
 *
 * Uses ffmpeg scene-change filter with interval fallback when too few frames
 * are detected. Provider-agnostic — consumers pass HLS or file URLs.
 *
 * Frame times come from the `showinfo` filter's `pts_time`, which ffmpeg
 * already reports relative to the input start (`-copyts` is the opt-out), so
 * they are used as is.
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { createLogger } from "../shared/logger.js";
import { normalizeSpawnPath, resolveSpawnInputPath, spawnAsync } from "../shared/process.js";

/** @typedef {import('./models.js').FrameCandidate} FrameCandidate */
/** @typedef {import('./models.js').SceneDetectResult} SceneDetectResult */
/** @typedef {Pick<FrameCandidate, "timestampSec"|"timestampSource"|"timestampMethod"|"timestampErrorSec">} FrameTimeFields */

const FFMPEG_ERROR_PATTERN = /error|403|401|invalid|denied/i;
const REMOTE_VIDEO_INPUT = /^https?:\/\//i;
const SHOWINFO_FRAME_LINE = /Parsed_showinfo.*\bn:\s*\d+.*\bpts_time:\s*(\S+)/;

export const DEFAULT_SCENE_THRESHOLD = 0.15;
export const DEFAULT_INTERVAL_FPS = "1/30";
export const DEFAULT_MIN_FRAMES_FOR_SCENE = 5;
export const DEFAULT_SCALE_FILTER = "1280:-1";
export const DEFAULT_FFMPEG_USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36";

/** Sidecar in the frames directory mapping each frame file to its time fields. */
export const FRAME_TIMES_FILE = "frame-times.json";

/**
 * Frame filename for a 1-based index, matching ffmpeg's `%04d` output pattern.
 * @param {string} prefix
 * @param {number} index
 * @returns {string}
 */
function frameFileName(prefix, index) {
  return `${prefix}_${String(index).padStart(4, "0")}.png`;
}

/**
 * Count sequentially numbered frame files in a directory.
 *
 * Deliberately unbounded — the sequence ends at the first missing file, never
 * at a frame ceiling, so a long recording is not silently truncated.
 * @param {string} dir
 * @param {string} prefix
 * @returns {number}
 */
export function countFrameFiles(dir, prefix) {
  let count = 0;
  while (existsSync(join(dir, frameFileName(prefix, count + 1)))) {
    count++;
  }
  return count;
}

/**
 * Presentation times from ffmpeg `showinfo` stderr, one entry per output frame
 * in order; `null` where ffmpeg printed no usable time (for example `NOPTS`).
 *
 * @param {string} stderr
 * @returns {(number|null)[]}
 */
export function parseShowinfoPtsTimes(stderr) {
  /** @type {(number|null)[]} */
  const times = [];
  for (const line of (stderr || "").split("\n")) {
    const match = line.match(SHOWINFO_FRAME_LINE);
    if (!match) continue;
    const value = Number(match[1]);
    times.push(Number.isFinite(value) ? value : null);
  }
  return times;
}

/**
 * Seconds between interval captures for an ffmpeg `fps=` value such as `1/30`.
 *
 * @param {string} intervalFps
 * @returns {number|null}
 */
export function intervalSecondsFromFps(intervalFps) {
  const [num, den = 1] = String(intervalFps).split("/").map(Number);
  const seconds = den / num;
  return Number.isFinite(seconds) && seconds > 0 ? seconds : null;
}

/**
 * Time fields for the frame at a 0-based position: the measured `pts_time`
 * when ffmpeg reported one; for an interval frame without one, an estimate
 * from its position, within half an interval; otherwise untimed.
 *
 * @param {number|null|undefined} ptsTime
 * @param {number} position
 * @param {boolean} isInterval
 * @param {number|null} intervalSec
 * @returns {FrameTimeFields}
 */
function frameTimeFields(ptsTime, position, isInterval, intervalSec) {
  if (ptsTime != null) {
    return { timestampSec: ptsTime, timestampSource: isInterval ? "interval" : "scene-detection" };
  }
  if (isInterval && intervalSec != null) {
    return {
      timestampSec: position * intervalSec,
      timestampSource: "estimated",
      timestampMethod: "interval-index",
      timestampErrorSec: intervalSec / 2,
    };
  }
  return { timestampSec: null, timestampSource: null };
}

/**
 * Build FrameCandidate descriptors from numbered PNG outputs.
 * @param {string} outputDir
 * @param {string} prefix
 * @param {boolean} isInterval
 * @param {object} [timing]
 * @param {(number|null)[]} [timing.ptsTimes] - showinfo times in output order
 * @param {number|null} [timing.intervalSec] - capture spacing, the basis for estimates
 * @returns {FrameCandidate[]}
 */
export function listFrameCandidates(
  outputDir,
  prefix,
  isInterval = false,
  { ptsTimes = [], intervalSec = null } = {},
) {
  const count = countFrameFiles(outputDir, prefix);
  /** @type {FrameCandidate[]} */
  const frames = [];
  for (let i = 1; i <= count; i++) {
    const file = frameFileName(prefix, i);
    frames.push({
      path: join(outputDir, file),
      file,
      ...frameTimeFields(ptsTimes[i - 1], i - 1, isInterval, intervalSec),
      sceneScore: null,
      isInterval,
    });
  }
  return frames;
}

/**
 * Write the frame-times sidecar so a recovery can reload the times.
 *
 * @param {string} outputDir
 * @param {FrameCandidate[]} frames
 */
export function writeFrameTimes(outputDir, frames) {
  const entries = frames.map(
    ({ file, timestampSec, timestampSource, timestampMethod, timestampErrorSec }) => [
      file,
      { timestampSec, timestampSource, timestampMethod, timestampErrorSec },
    ],
  );
  writeFileSync(
    join(outputDir, FRAME_TIMES_FILE),
    `${JSON.stringify(Object.fromEntries(entries), null, 2)}\n`,
    "utf8",
  );
}

/**
 * Read the frame-times sidecar; `{}` when the directory has none or it is unreadable.
 *
 * @param {string} outputDir
 * @returns {Record<string, FrameTimeFields>}
 */
export function readFrameTimes(outputDir) {
  try {
    return JSON.parse(readFileSync(join(outputDir, FRAME_TIMES_FILE), "utf8"));
  } catch {
    return {};
  }
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
 * Run ffmpeg with the given video filter, writing one image per filtered frame.
 * @param {import('../shared/process.js').spawnAsync} spawn
 * @param {import('../shared/logger.js').PipelineLogger} log
 * @param {string} videoUrl
 * @param {string} outputPattern
 * @param {string} vfFilter
 * @param {object} [options]
 * @param {string} [options.referer=""]
 * @param {string} [options.userAgent]
 * @returns {Promise<{ success: boolean, stderr: string }>}
 */
// biome-ignore lint/complexity/useMaxParams: ffmpeg spawn seam keeps process/logger injectors separate from capture args
export async function runSceneFfmpeg(
  spawn,
  log,
  videoUrl,
  outputPattern,
  vfFilter,
  { referer = "", userAgent = DEFAULT_FFMPEG_USER_AGENT } = {},
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
    "-fps_mode",
    "vfr",
    normalizeFfmpegPath(outputPattern),
  );

  const result = await spawn("ffmpeg", ffmpegArgs);
  const stderr = result.stderr || "";
  if (!result.success) {
    const errorLines = stderr.split("\n").filter((line) => FFMPEG_ERROR_PATTERN.test(line));
    if (errorLines.length > 0) {
      log.warn(`ffmpeg error: ${errorLines[0].trim().substring(0, 120)}`);
    }
  }
  return { success: result.success, stderr };
}

/**
 * Frames for one capture, timed from its showinfo output; warns when ffmpeg
 * reported a different number of times than frames written.
 *
 * @param {import('../shared/logger.js').PipelineLogger} log
 * @param {string} outputDir
 * @param {string} prefix
 * @param {string} stderr
 * @param {object} [options]
 * @param {boolean} [options.isInterval=false]
 * @param {number|null} [options.intervalSec=null]
 * @returns {FrameCandidate[]}
 */
// biome-ignore lint/complexity/useMaxParams: logger injector kept separate from capture args
function timedFrameCandidates(
  log,
  outputDir,
  prefix,
  stderr,
  { isInterval = false, intervalSec = null } = {},
) {
  const ptsTimes = parseShowinfoPtsTimes(stderr);
  const frames = listFrameCandidates(outputDir, prefix, isInterval, { ptsTimes, intervalSec });
  if (ptsTimes.length !== frames.length) {
    log.warn(
      `scene-detect: ${ptsTimes.length} showinfo times for ${frames.length} ${prefix} frames`,
    );
  }
  return frames;
}

/**
 * Extract scene-detected frames from a video URL, with interval fallback.
 *
 * @param {string} videoUrl - HLS or direct video URL
 * @param {string} outputDir - Directory for extracted PNG frames and `frame-times.json`
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
  const sceneFilter = [`select='gt(scene,${sceneThreshold})'`, "showinfo", `scale=${scale}`].join(
    ",",
  );

  const sceneRun = await runSceneFfmpeg(spawn, log, videoUrl, scenePattern, sceneFilter, {
    referer,
    userAgent,
  });
  const sceneFrames = timedFrameCandidates(log, outputDir, "scene", sceneRun.stderr);
  const sceneCount = sceneRun.success ? sceneFrames.length : 0;

  if (!sceneRun.success) {
    log.warn("scene-detect: scene filter failed — falling back to interval capture");
  }

  if (sceneCount < minFramesForScene) {
    log.info(
      `scene-detect: ${sceneCount} frames (below ${minFramesForScene}) — adding interval capture`,
    );
    const intervalPattern = join(outputDir, "interval_%04d.png");
    const intervalFilter = [`fps=${intervalFps}`, "showinfo", `scale=${scale}`].join(",");
    const intervalRun = await runSceneFfmpeg(
      spawn,
      log,
      videoUrl,
      intervalPattern,
      intervalFilter,
      { referer, userAgent },
    );

    const intervalFrames = timedFrameCandidates(log, outputDir, "interval", intervalRun.stderr, {
      isInterval: true,
      intervalSec: intervalSecondsFromFps(intervalFps),
    });
    const intervalCount = intervalFrames.length;
    const frames = [...sceneFrames, ...intervalFrames];
    writeFrameTimes(outputDir, frames);

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

  const frames = sceneFrames;
  writeFrameTimes(outputDir, frames);
  log.info(`scene-detect: complete method=scene-detection count=${frames.length}`);

  return {
    method: "scene-detection",
    sceneCount,
    count: frames.length,
    frames,
  };
}
