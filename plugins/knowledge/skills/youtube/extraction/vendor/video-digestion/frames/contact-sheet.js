/**
 * Contact-sheet generation via ImageMagick montage.
 *
 * Composites frame thumbnails into a labeled grid for vision triage.
 * Defaults: 4×4 tile on 1280×720 canvas per RESEARCH lane 3.
 */

import { spawnSync } from "node:child_process";
import { existsSync, statSync } from "node:fs";

import { createLogger } from "../shared/logger.js";
import { normalizeSpawnPath, resolveSpawnInputPath } from "../shared/process.js";

/** @typedef {import('./models.js').ContactSheet} ContactSheet */

export const DEFAULT_TILE = "4x4";
export const DEFAULT_CANVAS_WIDTH = 1280;
export const DEFAULT_CANVAS_HEIGHT = 720;
export const DEFAULT_CELL_PADDING = 4;
export const DEFAULT_BACKGROUND = "#1a1a1a";
export const DEFAULT_LABEL_COLOR = "white";
export const DEFAULT_POINT_SIZE = 10;
export const DEFAULT_LABEL_FORMAT = "%f";
export const DEFAULT_MAGICK_TIMEOUT_MS = 60_000;

/**
 * Compute per-cell geometry for a tile layout on a fixed canvas.
 * @param {string} tile - e.g. "4x4"
 * @param {number} canvasWidth
 * @param {number} canvasHeight
 * @param {number} padding
 * @returns {string} ImageMagick geometry argument
 */
export function computeMontageGeometry(
  tile,
  canvasWidth = DEFAULT_CANVAS_WIDTH,
  canvasHeight = DEFAULT_CANVAS_HEIGHT,
  padding = DEFAULT_CELL_PADDING,
) {
  const [cols, rows] = tile.split("x").map((part) => Number.parseInt(part, 10));
  const cellWidth = Math.floor(canvasWidth / cols);
  const cellHeight = Math.floor(canvasHeight / rows);
  return `${cellWidth}x${cellHeight}+${padding}+${padding}`;
}

/**
 * Normalize paths for ImageMagick on Windows (forward slashes).
 * @param {string} filePath
 * @returns {string}
 */
export function normalizeMagickPath(filePath) {
  return normalizeSpawnPath(filePath);
}

/**
 * Create a contact sheet from frame image paths.
 *
 * @param {string[]} framePaths - Input frame files (PNG/JPEG)
 * @param {string} outputPath - Output image path (typically .jpg)
 * @param {object} [options]
 * @param {string} [options.tile="4x4"]
 * @param {number} [options.canvasWidth=1280]
 * @param {number} [options.canvasHeight=720]
 * @param {number} [options.cellPadding=4]
 * @param {string} [options.background="#1a1a1a"]
 * @param {string} [options.labelColor="white"]
 * @param {number} [options.pointSize=10]
 * @param {string} [options.labelFormat="%f"]
 * @param {number} [options.timeoutMs=60000]
 * @param {object} [deps]
 * @param {typeof spawnSync} [deps.spawnSync]
 * @param {import('../shared/logger.js').PipelineLogger} [deps.log]
 * @returns {Promise<ContactSheet|null>}
 */
export async function createContactSheet(
  framePaths,
  outputPath,
  {
    tile = DEFAULT_TILE,
    canvasWidth = DEFAULT_CANVAS_WIDTH,
    canvasHeight = DEFAULT_CANVAS_HEIGHT,
    cellPadding = DEFAULT_CELL_PADDING,
    background = DEFAULT_BACKGROUND,
    labelColor = DEFAULT_LABEL_COLOR,
    pointSize = DEFAULT_POINT_SIZE,
    labelFormat = DEFAULT_LABEL_FORMAT,
    timeoutMs = DEFAULT_MAGICK_TIMEOUT_MS,
  } = {},
  { spawnSync: spawnMagick = spawnSync, log = createLogger() } = {},
) {
  if (framePaths.length === 0) {
    log.warn("contact-sheet: no input frames — skipping");
    return null;
  }

  log.info(`contact-sheet: starting (${framePaths.length} frames → ${outputPath})`);

  const inputFiles = framePaths.map((framePath) => resolveSpawnInputPath(framePath));
  const geometry = computeMontageGeometry(tile, canvasWidth, canvasHeight, cellPadding);

  const montageArgs = [
    "montage",
    ...inputFiles,
    "-tile",
    tile,
    "-geometry",
    geometry,
    "-background",
    background,
    "-fill",
    labelColor,
    "-pointsize",
    String(pointSize),
    "-label",
    labelFormat,
    resolveSpawnInputPath(outputPath),
  ];

  const result = spawnMagick("magick", montageArgs, {
    stdio: "pipe",
    timeout: timeoutMs,
  });

  if (result.status !== 0) {
    const err = result.stderr?.toString().substring(0, 200) || "unknown";
    log.warn(`contact-sheet: magick failed — ${err}`);
    return null;
  }

  const sizeKB = existsSync(outputPath) ? Math.round(statSync(outputPath).size / 1024) : 0;
  log.info(`contact-sheet: complete ${framePaths.length} frames → ${sizeKB}KB`);

  return {
    outputPath,
    inputPaths: [...framePaths],
    tile,
    frameCount: framePaths.length,
  };
}
