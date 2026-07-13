/**
 * Domain models for the frames capability slice.
 *
 * @typedef {Object} FrameCandidate
 * @property {string} path - Absolute or relative path to the frame image
 * @property {string} file - Basename of the frame file
 * @property {number|null} [timestampSec] - Source timestamp when known
 * @property {number|null} [sceneScore] - Scene-change score when known
 * @property {boolean} [isInterval] - Whether frame came from interval fallback capture
 * @property {string|null} [phash] - Perceptual hash when computed
 * @property {boolean} [likelyDuplicate] - Set by dedup stage
 */

/**
 * @typedef {Object} FrameSet
 * @property {FrameCandidate[]} frames - All input frames with metadata
 * @property {FrameCandidate[]} unique - Frames kept after dedup
 * @property {number} total - Input frame count
 * @property {number} duplicates - Frames marked duplicate
 * @property {string} [method] - Extraction method label (scene, interval, hybrid)
 */

/**
 * @typedef {Object} ContactSheet
 * @property {string} outputPath - Path to generated contact sheet image
 * @property {string[]} inputPaths - Source frame paths included in the sheet
 * @property {string} tile - Montage tile layout (e.g. "4x4")
 * @property {number} frameCount - Number of frames composited
 */

/**
 * @typedef {Object} SceneDetectResult
 * @property {'scene-detection'|'hybrid'} method - Extraction method used
 * @property {number} count - Total frames written
 * @property {number} sceneCount - Scene-detected frame count
 * @property {number} [intervalCount] - Interval fallback frame count when hybrid
 * @property {FrameCandidate[]} frames - Written frame descriptors
 */

export {};
