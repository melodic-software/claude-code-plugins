/**
 * Cross-pipeline artifact contract for acquired video media.
 *
 * Acquisition stages yield paths to durable working-dir files; downstream
 * transcript and frame modules consume these paths without knowing the source.
 *
 * @typedef {Object} MediaArtifacts
 * @property {string} videoPath - path to downloaded video file (mp4)
 * @property {string[]} captionPaths - ordered caption file paths (.vtt)
 * @property {string} metadataPath - path to yt-dlp info JSON
 */

export {};
