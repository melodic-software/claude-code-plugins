/**
 * Domain models for the watching capability slice.
 *
 * @typedef {import('@melodic/video-digestion/frames/models.js').FrameCandidate} FrameCandidate
 * @typedef {import('@melodic/video-digestion/frames/models.js').ContactSheet} ContactSheet
 */

/**
 * Transcript cue used for densification window detection.
 *
 * @typedef {Object} TranscriptCue
 * @property {number} startSec
 * @property {number} endSec
 * @property {string} text
 */

/**
 * High-signal transcript window where frame sampling should densify.
 *
 * @typedef {Object} DensificationWindow
 * @property {number} startSec
 * @property {number} endSec
 * @property {number} densityMultiplier - Sampling weight multiplier (e.g. 3 for code/demo)
 * @property {string} reason - Keyword or phrase that triggered the window
 */

/**
 * Frame selected for vision absorption with read policy metadata.
 *
 * @typedef {Object} SelectedFrame
 * @property {string} path
 * @property {string} file
 * @property {number|null} timestampSec
 * @property {number} priorityScore - Higher = more likely to keep under budget
 * @property {boolean} textDense - Escalate detail read to native 1080p when true
 * @property {'1280x720'|'1920x1080'} readResolution - Per design-threads T3
 * @property {boolean} [likelyDuplicate]
 * @property {boolean} [isInterval]
 */

/**
 * Interleaved vision-read item mixing transcript and frame detail reads.
 *
 * @typedef {Object} InterleavedReadItem
 * @property {'transcript'|'frame'} kind
 * @property {number} timestampSec
 * @property {string} [transcriptText]
 * @property {SelectedFrame} [frame]
 */

/**
 * Two-pass watching selection state after deterministic pipeline stages.
 *
 * @typedef {Object} WatchingSelectionState
 * @property {FrameCandidate[]} sceneFrames - Raw scene-detected frames
 * @property {FrameCandidate[]} uniqueFrames - After phash dedup
 * @property {DensificationWindow[]} densificationWindows
 * @property {SelectedFrame[]} selectedFrames - Full scored selection (no hard cap)
 * @property {ContactSheet[]} contactSheets - Triage contact sheets (1280x720)
 * @property {InterleavedReadItem[]} interleavedTimeline - Vision absorption order
 * @property {import('./compute-coverage-plan.js').CoveragePlan} [coveragePlan]
 * @property {number} [targetMinFrames]
 * @property {boolean} [highVolume] - Advisory when frame count far exceeds plan target
 * @property {number} [durationSec]
 * @property {boolean} overCap - Legacy field; always false (no truncation)
 * @property {number} candidateCount - Unique frame count after dedup
 */

export {};
