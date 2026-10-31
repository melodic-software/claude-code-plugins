import { sessionRoot } from "../../../../scripts/work-root.mjs";
import { resolveEnvWithLegacy } from "./env-compat.js";

/**
 * Resolve the base directory under which the watch pipeline lands its
 * `.work/<epic>/…` artifacts in the CONSUMING project.
 *
 * Under plugin cache isolation the pipeline scripts live in a per-version cache
 * dir, so a climb from the script location cannot reach the consumer's repo.
 * The base follows the knowledge plugin's one work-root rule
 * (`reference/work-root.md`):
 *
 * 1. `VIDEO_DIGEST_WORK_ROOT`: the work root the invoking skill resolved from a
 *    non-default `library_dir` and passed as `run.mjs --work-root <dir>`, which
 *    sets this var for the extraction child.
 *    The deprecated `YOUTUBE_WORK_ROOT` spelling still works with a warning.
 * 2. The git top-level of the working directory, or that directory outside git.
 *
 * @returns {string}
 */
export function resolveWorkRoot() {
  return resolveEnvWithLegacy("VIDEO_DIGEST_WORK_ROOT", "YOUTUBE_WORK_ROOT") || sessionRoot(process.cwd());
}
