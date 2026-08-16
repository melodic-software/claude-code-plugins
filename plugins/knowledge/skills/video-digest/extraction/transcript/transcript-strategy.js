/**
 * Transcript-strategy seam (T5): the adapter declares a per-source default
 * (`transcriptStrategy`), the pipeline may override it explicitly, and the
 * resolution below picks what actually runs per media entry given what exists —
 * a selected caption, a media file, and the optional local ASR capability.
 *
 * Selection rule (binding):
 * - caption present → the requested caption-based strategy runs unchanged;
 * - caption absent → `asr` WHENEVER the ASR capability is available and the
 *   media file exists;
 * - otherwise → explicit degradation: the digest proceeds without a transcript
 *   and the reason travels in the named provenance field
 *   (`transcriptDegradation`), never silently.
 *
 * An explicit pipeline override always wins over the adapter default; when the
 * override cannot run (no captions for a caption strategy, no ASR for `asr`),
 * the resolution degrades or falls back EXPLICITLY — the unmet override is
 * always named in the degradation reason.
 */

import { TRANSCRIPT_STRATEGIES } from "../adapters/adapter-contract.js";

/** @import { TranscriptStrategy } from '../adapters/adapter-contract.js' */

/**
 * @typedef {Object} TranscriptPlan
 * @property {TranscriptStrategy|null} strategy - what runs; null = no transcript
 * @property {string|null} degradation - non-null whenever the resolved strategy
 *   is not what the request wanted (including strategy null); the value is the
 *   human-readable reason recorded in the `transcriptDegradation` provenance field
 */

/**
 * @param {unknown} value
 * @returns {value is TranscriptStrategy}
 */
export function isTranscriptStrategy(value) {
  return (
    typeof value === "string" &&
    TRANSCRIPT_STRATEGIES.includes(/** @type {TranscriptStrategy} */ (value))
  );
}

/**
 * Parse the explicit `--transcript-strategy` pipeline override out of argv
 * (shared by the watch and transcript CLIs).
 *
 * @param {string[]} argv
 * @returns {{ ok: true, override: TranscriptStrategy|null } | { ok: false, error: string }}
 */
export function parseTranscriptStrategyOverride(argv) {
  const flagIndex = argv.indexOf("--transcript-strategy");
  if (flagIndex === -1) {
    return { ok: true, override: null };
  }
  const value = argv[flagIndex + 1];
  if (!value || !isTranscriptStrategy(value)) {
    return {
      ok: false,
      error: `--transcript-strategy requires one of: ${TRANSCRIPT_STRATEGIES.join(", ")}`,
    };
  }
  return { ok: true, override: value };
}

/**
 * Why the ASR rung cannot run right now.
 *
 * @param {boolean} mediaAvailable
 * @returns {string}
 */
function asrBlockedReason(mediaAvailable) {
  if (!mediaAvailable) {
    return "the ASR rung needs the media file, which this mode did not download (run the watch action for an ASR transcript)";
  }
  return "the optional ASR capability (faster-whisper) is not installed — install the documented optional prerequisite to enable the ASR rung";
}

/**
 * Resolve the transcript strategy for one media entry.
 *
 * @param {Object} inputs
 * @param {TranscriptStrategy} inputs.adapterDefault - the adapter's declared default
 * @param {TranscriptStrategy|null} [inputs.override] - explicit pipeline override (wins)
 * @param {boolean} inputs.captionPresent - a caption was selected for the entry
 * @param {boolean} inputs.mediaAvailable - the entry's media file exists on disk
 * @param {boolean} inputs.asrAvailable - the local ASR toolchain was detected
 * @returns {TranscriptPlan}
 */
export function resolveTranscriptStrategy({
  adapterDefault,
  override = null,
  captionPresent,
  mediaAvailable,
  asrAvailable,
}) {
  if (!isTranscriptStrategy(adapterDefault)) {
    throw new TypeError(
      `adapterDefault must be one of: ${TRANSCRIPT_STRATEGIES.join(", ")} (got ${JSON.stringify(adapterDefault)})`,
    );
  }
  if (override !== null && !isTranscriptStrategy(override)) {
    throw new TypeError(
      `override must be null or one of: ${TRANSCRIPT_STRATEGIES.join(", ")} (got ${JSON.stringify(override)})`,
    );
  }
  const requested = override ?? adapterDefault;

  if (requested === "asr") {
    if (asrAvailable && mediaAvailable) {
      return { strategy: "asr", degradation: null };
    }
    if (captionPresent) {
      // ASR cannot run but a caption exists: fall back to the adapter's
      // caption-based strategy rather than discarding a usable transcript —
      // explicitly, never silently.
      const fallback = adapterDefault === "asr" ? "captions" : adapterDefault;
      return {
        strategy: fallback,
        degradation: `transcript strategy "asr" could not run (${asrBlockedReason(mediaAvailable)}); fell back to "${fallback}" over the selected caption`,
      };
    }
    return {
      strategy: null,
      degradation: `no captions were selected and ${asrBlockedReason(mediaAvailable)} — digest proceeds without a transcript`,
    };
  }

  if (captionPresent) {
    return { strategy: requested, degradation: null };
  }

  if (override !== null) {
    // An explicit caption-based override with no caption is honored as a
    // degradation, never silently escalated to ASR against the request.
    return {
      strategy: null,
      degradation: `transcript strategy "${override}" was explicitly requested but no captions were selected — digest proceeds without a transcript`,
    };
  }

  if (asrAvailable && mediaAvailable) {
    return { strategy: "asr", degradation: null };
  }
  return {
    strategy: null,
    degradation: `no captions were selected and ${asrBlockedReason(mediaAvailable)} — digest proceeds without a transcript`,
  };
}
