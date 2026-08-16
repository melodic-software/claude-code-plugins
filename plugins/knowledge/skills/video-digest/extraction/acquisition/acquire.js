/**
 * yt-dlp acquisition machinery the source adapters compose. Source dispatch
 * lives in `adapters/registry.js` (`acquireMedia`); this module never imports
 * the registry, keeping the adapter module graph acyclic.
 */

import fs from "node:fs/promises";
import path from "node:path";

import { spawnAsync } from "@melodic/video-digestion/shared/process";
import { fail, ok } from "@melodic/video-digestion/shared/result";

import { resolveEnvWithLegacy } from "../lib/env-compat.js";
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

/**
 * Adapter-declared acquisition declarations: yt-dlp arg flags plus spawn-level
 * classification. Closed by default — omitted fields declare the behavior off.
 *
 * @typedef {import('./build-yt-dlp-args.js').YtDlpSourceOptions &
 *   import('./spawn-yt-dlp-with-auth-fallback.js').SourceSpawnClassification} SourceAcquisitionDeclarations
 */

/**
 * Map a source adapter's declared attributes onto the option bundle the shared
 * yt-dlp machinery consumes (arg flags + spawn classification). The adapter
 * declarations are the single source of truth; production never re-states them
 * in a side object.
 *
 * @param {import('../adapters/adapter-contract.js').SourceAdapter} adapter
 * @returns {SourceAcquisitionDeclarations}
 */
export function adapterSourceDeclarations(adapter) {
  return {
    writeComments: adapter.capabilities.comments === true,
    extractorArgs: adapter.extractorArgs,
    allowedExtractors: adapter.allowedExtractors,
    ignoreNoFormatsError: adapter.capabilities.mediaOptional === true,
    errorPatterns: adapter.errorPatterns,
    allowBrowserCookieProfileFallback: adapter.capabilities.browserCookieFallback === true,
  };
}

const DEFAULT_ACQUIRE_PHASE_GAP_MS = 3000;
const ACQUIRE_PHASE_GAP_ENV = "VIDEO_DIGEST_ACQUIRE_PHASE_GAP_SEC";
const LEGACY_ACQUIRE_PHASE_GAP_ENV = "YOUTUBE_ACQUIRE_PHASE_GAP_SEC";

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
  const raw = resolveEnvWithLegacy(ACQUIRE_PHASE_GAP_ENV, LEGACY_ACQUIRE_PHASE_GAP_ENV);
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
 *   source: SourceAcquisitionDeclarations,
 *   sleepSubtitlesSec?: number,
 *   env?: NodeJS.ProcessEnv,
 * }} params
 */
async function runYtDlpAcquire({
  spawn,
  url,
  workDir,
  mode,
  source,
  sleepSubtitlesSec,
  env = process.env,
}) {
  const outputTemplate = path.join(workDir, "%(id)s.%(ext)s");
  const buildArgs = (authOverride = {}) =>
    buildYtDlpArgs(url, {
      mode,
      outputTemplate,
      workDir,
      sleepSubtitlesSec,
      env,
      authOverride,
      source,
    });
  return spawnYtDlpWithAuthFallback(spawn, buildArgs, { cwd: workDir, env, source });
}

/**
 * @param {AcquireDeps} deps
 * @param {string} url
 * @param {string} workDir
 * @param {{ mode: AcquisitionMode, source: SourceAcquisitionDeclarations, sleepSubtitlesSec?: number }} pass
 */
async function runAcquirePass(deps, url, workDir, { mode, source, sleepSubtitlesSec }) {
  const { spawn, listFiles } = deps;
  const spawnResult = await runYtDlpAcquire({ spawn, url, workDir, mode, source, sleepSubtitlesSec });
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
 * @param {SourceAcquisitionDeclarations} source
 * @returns {Promise<
 *   {ok: true, files: string[], artifacts: MediaArtifacts, acquireMetrics: object} |
 *   {ok: false, error: string, acquireMetrics: object}
 * >}
 */
async function acquireFullStaged(deps, url, workDir, videoId, source) {
  const { sleep = sleepMs } = deps;
  const videoStarted = Date.now();

  const throttle = deps.withThrottle ?? withAcquireThrottle;
  const videoPass = await throttle(() =>
    runAcquirePass(deps, url, workDir, { mode: "video-only", source }),
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
      source,
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

/**
 * @param {string} url
 * @param {{workDir: string, mode?: AcquisitionMode, source?: SourceAcquisitionDeclarations, videoId?: string}} options -
 *   `videoId` is the URL-claim id the adapter derived (`matchUrl`); this driver
 *   never re-derives it
 * @param {Partial<AcquireDeps>} [deps]
 */
export async function acquireYouTubeMedia(
  url,
  { workDir, mode = "full", source = {}, videoId },
  deps = {},
) {
  const started = Date.now();
  const mergedDeps = { ...DEFAULT_DEPS, ...deps };
  const { readFile, withThrottle = withAcquireThrottle } = mergedDeps;
  const throttle = /** @type {<T>(fn: () => Promise<T>) => Promise<T>} */ (withThrottle);

  if (!videoId) {
    return fail(
      "No YouTube video id supplied for acquisition (the adapter's URL claim derives it)",
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
      source,
    );
    acquireMetrics = staged.acquireMetrics;
    if (!staged.ok) {
      return failVideo(staged.error ?? "staged acquire failed");
    }
    files = staged.files;
    artifacts = staged.artifacts;
  } else {
    const single = await throttle(() =>
      runAcquirePass(mergedDeps, url, workDir, { mode, source }),
    );
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
        source,
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
