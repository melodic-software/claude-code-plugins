/**
 * Optional local ASR rung (T5 posture (ii)): faster-whisper `large-v3` via
 * batched inference (`batch_size=8`), invoked through the machine's Python.
 *
 * Delivery contract (user-approved FALLBACK decision): the toolchain is a
 * DOCUMENTED OPTIONAL PREREQUISITE detected at runtime — never auto-installed,
 * by this module or anything it spawns. Absent toolchain = capability absent;
 * the strategy seam then degrades explicitly (`transcriptDegradation`).
 */

import path from "node:path";
import { fileURLToPath } from "node:url";

import { spawnAsync } from "@melodic/video-digestion/shared/process";

/** @import { VttCue } from '@melodic/video-digestion/transcript/vtt-parser' */
/** @import { SpawnResult } from '@melodic/video-digestion/shared/process' */

export const ASR_MODEL = "large-v3";
export const ASR_BATCH_SIZE = 8;

/** Interpreter candidates probed in order; first importable wins. */
const PYTHON_CANDIDATES = Object.freeze(["python", "python3", "py"]);

const DETECT_ARGS = Object.freeze([
  "-c",
  "import faster_whisper; print(faster_whisper.__version__)",
]);

const ASR_SCRIPT_PATH = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "asr_transcribe.py",
);

/**
 * @typedef {Object} AsrDetection
 * @property {boolean} available
 * @property {string|null} python - interpreter command that imports faster-whisper
 * @property {string|null} version - detected faster-whisper version
 * @property {string} detail - human-readable detection summary
 */

/** @type {AsrDetection|null} */
let cachedDetection = null;

/** Reset the per-process detection cache (tests only). */
export function resetAsrDetectionCache() {
  cachedDetection = null;
}

/**
 * @typedef {(command: string, args: string[], options?: object) => Promise<SpawnResult>} SpawnFn
 */

/**
 * Detect the optional ASR toolchain: the first Python interpreter on PATH that
 * imports `faster_whisper`. Cached per process (detection spawns interpreters).
 *
 * @param {{ spawn?: SpawnFn }} [deps]
 * @returns {Promise<AsrDetection>}
 */
export async function detectAsrCapability({ spawn = spawnAsync } = {}) {
  if (cachedDetection) {
    return cachedDetection;
  }
  /** @type {string[]} */
  const attempts = [];
  for (const candidate of PYTHON_CANDIDATES) {
    // spawnAsync never rejects — a spawn failure resolves success:false + error.
    const result = await spawn(candidate, [...DETECT_ARGS], { timeout: 30_000 });
    if (result.success) {
      const version = (result.stdout ?? "").trim() || null;
      cachedDetection = {
        available: true,
        python: candidate,
        version,
        detail: `faster-whisper ${version ?? "(unknown version)"} via ${candidate}`,
      };
      return cachedDetection;
    }
    attempts.push(
      `${candidate}: ${(result.stderr ?? "").trim() || result.error || "not importable"}`,
    );
  }
  cachedDetection = {
    available: false,
    python: null,
    version: null,
    detail: `faster-whisper not detected (${attempts.join("; ")})`,
  };
  return cachedDetection;
}

/**
 * @typedef {Object} AsrTranscription
 * @property {boolean} success
 * @property {VttCue[]} [cues] - segment-level cues (start/end seconds + text)
 * @property {{ startSec: number, endSec: number, word: string }[]} [words] -
 *   word-level timestamps when the model produced them
 * @property {string} [language]
 * @property {string} [error]
 */

/**
 * Transcribe a media file through the detected toolchain. The caller supplies
 * the interpreter from {@link detectAsrCapability}; this function never probes
 * and never installs.
 *
 * @param {Object} options
 * @param {string} options.mediaPath
 * @param {string} options.python - interpreter command (from detection)
 * @param {string|null} [options.initialPrompt] - vocabulary-biasing prompt
 *   (lexicon feed; see the T5-ASR-LEXICON probe outcome in the PLAN)
 * @param {SpawnFn} [options.spawn]
 * @returns {Promise<AsrTranscription>}
 */
export async function runAsrTranscription({
  mediaPath,
  python,
  initialPrompt = null,
  spawn = spawnAsync,
}) {
  const args = [
    ASR_SCRIPT_PATH,
    "--media",
    mediaPath,
    "--model",
    ASR_MODEL,
    "--batch-size",
    String(ASR_BATCH_SIZE),
    ...(initialPrompt ? ["--initial-prompt", initialPrompt] : []),
  ];
  // spawnAsync never rejects — a spawn failure resolves success:false + error.
  const result = await spawn(python, args, {});
  if (!result.success) {
    return {
      success: false,
      error: `ASR transcription failed: ${(result.stderr ?? "").trim() || result.error || `exit ${String(result.code ?? "unknown")}`}`,
    };
  }

  /** @type {unknown} */
  let parsed;
  try {
    parsed = JSON.parse(result.stdout ?? "");
  } catch (error) {
    return {
      success: false,
      error: `ASR output was not valid JSON: ${error instanceof Error ? error.message : String(error)}`,
    };
  }
  if (!parsed || typeof parsed !== "object" || !Array.isArray(/** @type {{segments?: unknown}} */ (parsed).segments)) {
    return { success: false, error: "ASR output JSON has no segments array" };
  }
  const record = /** @type {{ segments: unknown[], language?: unknown }} */ (parsed);

  /** @type {VttCue[]} */
  const cues = [];
  /** @type {{ startSec: number, endSec: number, word: string }[]} */
  const words = [];
  for (const segment of record.segments) {
    if (!segment || typeof segment !== "object") continue;
    const seg = /** @type {Record<string, unknown>} */ (segment);
    if (
      typeof seg.start !== "number" ||
      typeof seg.end !== "number" ||
      typeof seg.text !== "string"
    ) {
      return { success: false, error: "ASR segment missing start/end/text" };
    }
    const text = seg.text.trim();
    if (text) {
      cues.push({ startSec: seg.start, endSec: seg.end, text });
    }
    if (Array.isArray(seg.words)) {
      for (const wordEntry of seg.words) {
        if (!wordEntry || typeof wordEntry !== "object") continue;
        const word = /** @type {Record<string, unknown>} */ (wordEntry);
        if (
          typeof word.start === "number" &&
          typeof word.end === "number" &&
          typeof word.word === "string"
        ) {
          words.push({ startSec: word.start, endSec: word.end, word: word.word });
        }
      }
    }
  }

  return {
    success: true,
    cues,
    words,
    ...(typeof record.language === "string" ? { language: record.language } : {}),
  };
}
