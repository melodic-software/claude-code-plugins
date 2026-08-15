/**
 * Shared caption preference ladder, parameterized by the adapter's declared
 * caption provenance class (T12: the ladder is shared and editable; the
 * declaration keeps source knowledge out of it):
 *
 * - `manual-and-auto` (e.g. YouTube): manual EN → auto EN → auto-translate EN
 *   → STOP. yt-dlp filenames distinguish manual vs auto via `.en-orig` and
 *   related suffixes.
 * - `platform-asr` (e.g. X): every track is platform-generated ASR — filename
 *   shape carries NO manual/auto signal, so a bare `.en.vtt` must never
 *   classify `manual-en`. Ladder: EN → `und` (the raw unnormalized track
 *   LANGUAGE fallback) → STOP; every rung is auto-class.
 */

import path from "node:path";

/** @typedef {'manual-and-auto' | 'platform-asr'} CaptionClass */

/**
 * @typedef {'manual-en' | 'auto-en' | 'auto-translate-en' | 'platform-asr-en' | 'platform-asr-und'} CaptionRung
 */

/** @typedef {Object} CaptionSelection
 * @property {string} path
 * @property {CaptionRung} rung
 * @property {boolean} isAutoCaption
 */

/**
 * Caption provenance classes the ladder understands. Adapters declare one
 * (`captionClass`); the contract validates the declaration against this list.
 */
export const CAPTION_CLASSES = Object.freeze(
  /** @type {readonly CaptionClass[]} */ (["manual-and-auto", "platform-asr"]),
);

const MANUAL_AND_AUTO_LADDER = /** @type {readonly CaptionRung[]} */ (
  Object.freeze(["manual-en", "auto-en", "auto-translate-en"])
);
const PLATFORM_ASR_LADDER = /** @type {readonly CaptionRung[]} */ (
  Object.freeze(["platform-asr-en", "platform-asr-und"])
);

const TLANG_TRANSLATE_PATTERN = /\.(tlang|translate)/;
const EN_ORIG_PATTERN = /\.en-orig\.vtt$/;
const EN_ORIG_LOCALIZED_PATTERN = /\.en\.[a-z]{2,3}\.en-orig\.vtt$/;
const EN_AUTO_PATTERN = /\.en\.auto\.vtt$/;
const MANUAL_EN_PATTERN = /\.en(?:-[a-z]{2,3})?\.vtt$/;
const AUTO_TRANSLATE_EN_PATTERN = /\.en(?:-[a-z]{2,3})?\.[a-z]{2,3}\.vtt$/;
const PLATFORM_EN_PATTERN = /\.en(?:-[a-z]{2,3})?\.vtt$/;
const PLATFORM_UND_PATTERN = /\.und\.vtt$/;

/**
 * @param {CaptionClass} captionClass
 * @returns {readonly CaptionRung[]}
 */
function ladderForClass(captionClass) {
  switch (captionClass) {
    case "manual-and-auto":
      return MANUAL_AND_AUTO_LADDER;
    case "platform-asr":
      return PLATFORM_ASR_LADDER;
    default:
      throw new TypeError(
        `Unknown captionClass "${captionClass}" (known: ${CAPTION_CLASSES.join(", ")})`,
      );
  }
}

/**
 * @param {string} name - lowercased basename
 * @returns {CaptionRung | null}
 */
function classifyManualAndAuto(name) {
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
 * @param {string} name - lowercased basename
 * @returns {CaptionRung | null}
 */
function classifyPlatformAsr(name) {
  if (PLATFORM_EN_PATTERN.test(name)) {
    return "platform-asr-en";
  }
  if (PLATFORM_UND_PATTERN.test(name)) {
    return "platform-asr-und";
  }
  return null;
}

/**
 * Classify a caption filename into a ladder rung for the declared class.
 *
 * @param {string} filePath
 * @param {CaptionClass} [captionClass]
 * @returns {CaptionRung | null}
 */
export function classifyCaptionRung(filePath, captionClass = "manual-and-auto") {
  ladderForClass(captionClass);
  const name = path.basename(filePath).toLowerCase();
  if (!name.endsWith(".vtt")) return null;

  return captionClass === "platform-asr"
    ? classifyPlatformAsr(name)
    : classifyManualAndAuto(name);
}

/**
 * Select the best caption file from downloaded paths, walking the declared
 * class's ladder. Every platform-ASR rung is auto-class (`isAutoCaption`).
 *
 * @param {string[]} captionPaths
 * @param {CaptionClass} [captionClass]
 * @returns {{ success: true, selection: CaptionSelection } | { success: false, error: string, available: string[] }}
 */
export function selectCaptionFile(captionPaths, captionClass = "manual-and-auto") {
  const ladder = ladderForClass(captionClass);
  const vttPaths = captionPaths.filter((p) => p.toLowerCase().endsWith(".vtt"));
  /** @type {Map<CaptionRung, string>} */
  const byRung = new Map();

  for (const filePath of vttPaths) {
    const rung = classifyCaptionRung(filePath, captionClass);
    if (rung && !byRung.has(rung)) {
      byRung.set(rung, filePath);
    }
  }

  for (const rung of ladder) {
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
    error:
      captionClass === "platform-asr"
        ? "No usable captions found (platform-ASR EN → und ladder exhausted)"
        : "No English captions found (manual EN → auto EN → auto-translate EN ladder exhausted)",
    available: vttPaths,
  };
}
