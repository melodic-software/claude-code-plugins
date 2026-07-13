/**
 * Resolve the base directory under which the watch pipeline lands its
 * `.work/<epic>/…` artifacts in the CONSUMING project.
 *
 * Under plugin cache isolation the pipeline scripts live in a per-version cache
 * dir, so a climb from the script location no longer reaches the consumer's
 * repo. The base is resolved from the environment instead, honoring the
 * knowledge plugin's `library_dir` seam:
 *
 * 1. `YOUTUBE_WORK_ROOT` — explicit override the invoking skill wires in from the
 *    resolved `library_dir` (when it is not the repo-root default) by passing
 *    `run.mjs --work-root <dir>`, which sets this var for the extraction child.
 * 2. `CLAUDE_PROJECT_DIR` — the consuming project root the harness provides.
 * 3. `process.cwd()` — fallback when invoked directly from the project root.
 *
 * @returns {string}
 */
export function resolveWorkRoot() {
  return process.env.YOUTUBE_WORK_ROOT || process.env.CLAUDE_PROJECT_DIR || process.cwd();
}
