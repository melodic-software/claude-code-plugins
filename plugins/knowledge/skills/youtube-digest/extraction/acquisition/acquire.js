/**
 * YouTube media acquisition via yt-dlp.
 */

import fs from "node:fs/promises";
import path from "node:path";

import { spawnAsync } from "@melodic/video-digestion/shared/process";
import { fail, ok } from "@melodic/video-digestion/shared/result";

import { CAPTION_ONLY_SLEEP_SUBTITLES_SEC, sleepMs } from "./acquire-retry-policy.js";
import { withAcquireThrottle } from "./acquire-throttle.js";
import { spawnFailureDetail } from "./acquire-with-retry.js";
import { buildYtDlpArgs } from "./build-yt-dlp-args.js";
import { selectCaptionFile } from "./select-caption.js";
import { spawnYtDlpWithAuthFallback } from "./spawn-yt-dlp-with-auth-fallback.js";
import { parseVideoMetadata } from "./video-metadata.js";

/** @typedef {import('@melodic/video-digestion/shared/media-artifacts').MediaArtifacts} MediaArtifacts */
/** @typedef {import('./video-metadata.js').VideoMetadata} VideoMetadata */
/** @typedef {import('./build-yt-dlp-args.js').AcquisitionMode} AcquisitionMode */

const DEFAULT_ACQUIRE_PHASE_GAP_MS = 3000;
const ACQUIRE_PHASE_GAP_ENV = "YOUTUBE_ACQUIRE_PHASE_GAP_SEC";

/**
 * @typedef {Object} AcquisitionResult
 * @property {MediaArtifacts} artifacts
 * @property {VideoMetadata} metadata
 * @property {import('./select-caption.js').CaptionSelection} caption
 * @property {string} workDir
 * @property {object} [acquireMetrics]
 */

/**
 * @typedef {Object} AcquireDeps
 * @property {(command: string, args: string[], options?: object) => ReturnType<typeof spawnAsync>} spawn
 * @property {(dir: string) => Promise<string[]>} listFiles
 * @property {(filePath: string) => Promise<string>} readFile
 * @property {(ms: number) => Promise<void>} [sleep]
 * @property {<T>(fn: () => Promise<T>) => Promise<T>} [withThrottle]
 */

const YOUTU_BE_PATH_PREFIX = /^\//;

/** @type {AcquireDeps} */
const DEFAULT_DEPS = {
  spawn: spawnAsync,
  listFiles: listWorkDirFiles,
  readFile: (/** @type {string} */ filePath) => fs.readFile(filePath, "utf8"),
  sleep: sleepMs,
};

/**
 * @returns {number}
 */
export function resolveAcquirePhaseGapMs() {
  const raw = process.env[ACQUIRE_PHASE_GAP_ENV];
  if (!raw) return DEFAULT_ACQUIRE_PHASE_GAP_MS;
  const parsed = Number.parseFloat(raw);
  if (!Number.isFinite(parsed) || parsed < 0) return DEFAULT_ACQUIRE_PHASE_GAP_MS;
  return Math.round(parsed * 1000);
}

/**
 * List files recursively under a working directory.
 *
 * @param {string} dir
 * @returns {Promise<string[]>}
 */
export async function listWorkDirFiles(dir) {
  /** @type {string[]} */
  const files = [];
  /** @type {string[]} */
  const pending = [dir];

  while (pending.length > 0) {
    const current = pending.pop();
    if (!current) continue;

    let entries;
    try {
      entries = await fs.readdir(current, { withFileTypes: true });
    } catch {
      continue;
    }

    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        pending.push(fullPath);
      } else {
        files.push(fullPath);
      }
    }
  }

  return files;
}

const YOUTUBE_VIDEO_ID_PATTERN = /^[\w-]{11}$/;

/**
 * @param {string} segment
 * @returns {string|null}
 */
function normalizeYouTubeVideoIdSegment(segment) {
  const trimmed = segment.replace(/\/$/, "");
  return YOUTUBE_VIDEO_ID_PATTERN.test(trimmed) ? trimmed : null;
}

/**
 * @param {string} url
 * @returns {string|null}
 */
export function extractVideoId(url) {
  try {
    const parsed = new URL(url);
    if (parsed.hostname.includes("youtu.be")) {
      return normalizeYouTubeVideoIdSegment(parsed.pathname.replace(YOUTU_BE_PATH_PREFIX, ""));
    }

    const queryId = parsed.searchParams.get("v");
    if (queryId) {
      return normalizeYouTubeVideoIdSegment(queryId);
    }

    const pathSegments = parsed.pathname.split("/").filter(Boolean);
    const pathPrefixes = new Set(["live", "embed", "shorts", "v"]);
    if (pathSegments.length >= 2 && pathPrefixes.has(pathSegments[0])) {
      return normalizeYouTubeVideoIdSegment(pathSegments[1]);
    }

    return null;
  } catch {
    return null;
  }
}

/**
 * @param {string[]} files
 * @param {string} videoId
 * @returns {MediaArtifacts}
 */
export function resolveMediaArtifacts(files, videoId) {
  const captionPaths = files.filter((filePath) => filePath.endsWith(".vtt"));
  const metadataPath =
    files.find((filePath) => filePath.endsWith(".info.json")) ??
    files.find((filePath) => filePath.includes(videoId) && filePath.endsWith(".json")) ??
    "";
  const videoPath =
    files.find(
      (filePath) =>
        filePath.endsWith(".mp4") || filePath.endsWith(".mkv") || filePath.endsWith(".webm"),
    ) ?? "";

  return { videoPath, captionPaths, metadataPath };
}

/**
 * @param {{
 *   spawn: AcquireDeps['spawn'],
 *   url: string,
 *   workDir: string,
 *   mode: AcquisitionMode,
 *   sleepSubtitlesSec?: number,
 *   env?: NodeJS.ProcessEnv,
 * }} params
 */
async function runYtDlpAcquire({
  spawn,
  url,
  workDir,
  mode,
  sleepSubtitlesSec,
  env = process.env,
}) {
  const outputTemplate = path.join(workDir, "%(id)s.%(ext)s");
  const buildArgs = (authOverride = {}) =>
    buildYtDlpArgs(url, { mode, outputTemplate, workDir, sleepSubtitlesSec, env, authOverride });
  return spawnYtDlpWithAuthFallback(spawn, buildArgs, { cwd: workDir, env });
}

/**
 * @param {AcquireDeps} deps
 * @param {string} url
 * @param {string} workDir
 * @param {{ mode: AcquisitionMode, sleepSubtitlesSec?: number }} pass
 */
async function runAcquirePass(deps, url, workDir, { mode, sleepSubtitlesSec }) {
  const { spawn, listFiles } = deps;
  const spawnResult = await runYtDlpAcquire({ spawn, url, workDir, mode, sleepSubtitlesSec });
  if (!spawnResult.success) {
    return {
      spawnResult,
      detail: spawnFailureDetail(spawnResult),
      files: /** @type {string[]} */ ([]),
    };
  }
  const files = await listFiles(workDir);
  return { spawnResult, detail: "", files };
}

/**
 * @param {AcquireDeps} deps
 * @param {string} url
 * @param {string} workDir
 * @param {string} videoId
 */
async function acquireFullStaged(deps, url, workDir, videoId) {
  const { sleep = sleepMs } = deps;
  const videoStarted = Date.now();

  const throttle = deps.withThrottle ?? withAcquireThrottle;
  const videoPass = await throttle(() =>
    runAcquirePass(deps, url, workDir, { mode: "video-only" }),
  );
  if (!videoPass.spawnResult.success) {
    return {
      ok: false,
      error: videoPass.detail || "yt-dlp video-only pass failed",
      acquireMetrics: { stagedAcquire: true, videoPassMs: Date.now() - videoStarted },
    };
  }

  let artifacts = resolveMediaArtifacts(videoPass.files, videoId);
  if (!artifacts.videoPath) {
    return {
      ok: false,
      error: "yt-dlp did not download video file",
      acquireMetrics: { stagedAcquire: true, videoPassMs: Date.now() - videoStarted },
    };
  }

  const videoPassMs = Date.now() - videoStarted;
  await sleep(resolveAcquirePhaseGapMs());

  const captionStarted = Date.now();
  const captionPass = await throttle(() =>
    runAcquirePass(deps, url, workDir, {
      mode: "captions-only",
      sleepSubtitlesSec: CAPTION_ONLY_SLEEP_SUBTITLES_SEC,
    }),
  );

  let files = videoPass.files;
  if (captionPass.spawnResult.success) {
    files = await deps.listFiles(workDir);
    artifacts = resolveMediaArtifacts(files, videoId);
  }

  const captionPassMs = Date.now() - captionStarted;

  return {
    ok: true,
    files,
    artifacts,
    acquireMetrics: { stagedAcquire: true, videoPassMs, captionPassMs },
  };
}

export async function acquireYouTubeMedia(url, { workDir, mode = "full" }, deps = {}) {
  const started = Date.now();
  const mergedDeps = { ...DEFAULT_DEPS, ...deps };
  const { readFile, withThrottle = withAcquireThrottle } = mergedDeps;
  const throttle = /** @type {<T>(fn: () => Promise<T>) => Promise<T>} */ (withThrottle);
  const videoId = extractVideoId(url);

  if (!videoId) {
    return fail(
      "Could not extract YouTube video id from URL",
      "acquire-youtube-media",
      { label: url },
      Date.now() - started,
    );
  }

  /** @param {string} message */
  const failVideo = (message) =>
    fail(message, "acquire-youtube-media", { label: videoId }, Date.now() - started);

  /** @type {string[]} */
  let files = [];
  /** @type {MediaArtifacts} */
  let artifacts = { videoPath: "", captionPaths: [], metadataPath: "" };
  /** @type {object | undefined} */
  let acquireMetrics;

  if (mode === "full") {
    const staged = await acquireFullStaged(
      { ...mergedDeps, withThrottle: throttle },
      url,
      workDir,
      videoId,
    );
    acquireMetrics = staged.acquireMetrics;
    if (!staged.ok) {
      return failVideo(staged.error ?? "staged acquire failed");
    }
    files = staged.files;
    artifacts = staged.artifacts;
  } else {
    const single = await throttle(() => runAcquirePass(mergedDeps, url, workDir, { mode }));
    if (!single.spawnResult.success) {
      return failVideo(single.detail || "yt-dlp failed");
    }
    files = single.files;
    artifacts = resolveMediaArtifacts(files, videoId);
  }

  let captionResult = selectCaptionFile(artifacts.captionPaths);

  if (!captionResult.success && mode === "full" && artifacts.videoPath) {
    const captionRetry = await throttle(() =>
      runAcquirePass(mergedDeps, url, workDir, {
        mode: "captions-only",
        sleepSubtitlesSec: CAPTION_ONLY_SLEEP_SUBTITLES_SEC,
      }),
    );
    if (captionRetry.spawnResult.success) {
      files = await mergedDeps.listFiles(workDir);
      artifacts = resolveMediaArtifacts(files, videoId);
      captionResult = selectCaptionFile(artifacts.captionPaths);
    }
  }

  if (!captionResult.success) {
    return failVideo(captionResult.error);
  }

  if (!artifacts.metadataPath) {
    return failVideo("yt-dlp did not write info JSON");
  }

  if (mode === "full" && !artifacts.videoPath) {
    return failVideo("yt-dlp did not download video file");
  }

  if (mode === "transcript" && artifacts.videoPath) {
    return failVideo("Transcript mode must not download video");
  }

  let metadata;
  try {
    metadata = parseVideoMetadata(JSON.parse(await readFile(artifacts.metadataPath)));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return failVideo(`Invalid info JSON: ${message}`);
  }

  return ok(
    {
      artifacts,
      metadata,
      caption: captionResult.selection,
      workDir,
      acquireMetrics,
    },
    "acquire-youtube-media",
    { label: videoId },
    Date.now() - started,
  );
}
