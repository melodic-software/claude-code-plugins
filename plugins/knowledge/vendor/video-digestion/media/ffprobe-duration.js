/**
 * Probe video duration via ffprobe.
 */

import { spawnAsync } from "../shared/process.js";

/**
 * @typedef {Object} VideoDurationProbe
 * @property {number} durationSec
 * @property {string|null} formatName
 */

/**
 * Parse duration from ffprobe JSON output.
 *
 * @param {string} jsonText
 * @returns {VideoDurationProbe|null}
 */
export function parseFfprobeDuration(jsonText) {
  try {
    const parsed = JSON.parse(jsonText);
    const duration = Number.parseFloat(parsed?.format?.duration ?? "");
    if (!Number.isFinite(duration) || duration <= 0) return null;
    return {
      durationSec: duration,
      formatName:
        typeof parsed?.format?.format_name === "string" ? parsed.format.format_name : null,
    };
  } catch {
    return null;
  }
}

/**
 * @param {string} videoPath
 * @param {object} [deps]
 * @param {typeof spawnAsync} [deps.spawn]
 * @returns {Promise<VideoDurationProbe|null>}
 */
export async function probeVideoDuration(videoPath, { spawn = spawnAsync } = {}) {
  const result = await spawn(
    "ffprobe",
    ["-v", "error", "-show_entries", "format=duration,format_name", "-of", "json", videoPath],
    {},
  );

  if (!result.success) return null;
  return parseFfprobeDuration(result.stdout);
}
