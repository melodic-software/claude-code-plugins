/**
 * Caption preference ladder: manual EN → auto EN → auto-translate EN → STOP.
 *
 * yt-dlp filenames distinguish manual vs auto via `.en-orig` and related suffixes.
 */

import path from "node:path";

/** @typedef {'manual-en' | 'auto-en' | 'auto-translate-en'} CaptionRung */

/** @typedef {Object} CaptionSelection
 * @property {string} path
 * @property {CaptionRung} rung
 * @property {boolean} isAutoCaption
 */

const CAPTION_LADDER = /** @type {const} */ (["manual-en", "auto-en", "auto-translate-en"]);

const TLANG_TRANSLATE_PATTERN = /\.(tlang|translate)/;
const EN_ORIG_PATTERN = /\.en-orig\.vtt$/;
const EN_ORIG_LOCALIZED_PATTERN = /\.en\.[a-z]{2,3}\.en-orig\.vtt$/;
const EN_AUTO_PATTERN = /\.en\.auto\.vtt$/;
const MANUAL_EN_PATTERN = /\.en(?:-[a-z]{2,3})?\.vtt$/;
const AUTO_TRANSLATE_EN_PATTERN = /\.en(?:-[a-z]{2,3})?\.[a-z]{2,3}\.vtt$/;

/**
 * Classify a caption filename into a ladder rung.
 *
 * @param {string} filePath
 * @returns {CaptionRung | null}
 */
export function classifyCaptionRung(filePath) {
  const name = path.basename(filePath).toLowerCase();
  if (!name.endsWith(".vtt")) return null;

  if (TLANG_TRANSLATE_PATTERN.test(name)) {
    return "auto-translate-en";
  }

  if (EN_ORIG_PATTERN.test(name) || EN_ORIG_LOCALIZED_PATTERN.test(name)) {
    return "auto-en";
  }

  if (EN_AUTO_PATTERN.test(name)) {
    return "auto-en";
  }

  if (MANUAL_EN_PATTERN.test(name) && !name.includes("en-orig")) {
    return "manual-en";
  }

  if (AUTO_TRANSLATE_EN_PATTERN.test(name)) {
    return "auto-translate-en";
  }

  return null;
}

/**
 * Select the best English caption file from downloaded paths.
 *
 * @param {string[]} captionPaths
 * @returns {{ success: true, selection: CaptionSelection } | { success: false, error: string, available: string[] }}
 */
export function selectCaptionFile(captionPaths) {
  const vttPaths = captionPaths.filter((p) => p.toLowerCase().endsWith(".vtt"));
  /** @type {Map<CaptionRung, string>} */
  const byRung = new Map();

  for (const filePath of vttPaths) {
    const rung = classifyCaptionRung(filePath);
    if (rung && !byRung.has(rung)) {
      byRung.set(rung, filePath);
    }
  }

  for (const rung of CAPTION_LADDER) {
    const match = byRung.get(rung);
    if (match) {
      return {
        success: true,
        selection: {
          path: match,
          rung,
          isAutoCaption: rung !== "manual-en",
        },
      };
    }
  }

  return {
    success: false,
    error: "No English captions found (manual EN → auto EN → auto-translate EN ladder exhausted)",
    available: vttPaths,
  };
}
