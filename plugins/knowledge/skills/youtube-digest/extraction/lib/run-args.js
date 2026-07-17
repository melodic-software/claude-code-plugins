/**
 * Argument + environment helpers for the youtube extraction launcher (`run.mjs`).
 *
 * The launcher accepts an OPTIONAL leading `--work-root <dir>` flag ahead of the
 * target script. It exists so the invoking skill can wire the knowledge plugin's
 * `library_dir` seam into the pipeline WITHOUT a shell-specific env prefix:
 * `YOUTUBE_WORK_ROOT=… node …` is bash-only (it fails under PowerShell), so a
 * cross-platform double-quoted CLI arg is passed instead and translated here into
 * the `YOUTUBE_WORK_ROOT` environment variable `resolveWorkRoot()` reads.
 *
 * Both helpers are pure so the launcher's contract is unit-testable without
 * spawning a child process.
 */

/**
 * Split the launcher's argv (already sliced past `node run.mjs`) into an optional
 * work root, the target script, and its remaining arguments.
 *
 * @param {string[]} argv
 * @returns {{ workRoot: string | undefined, script: string | undefined, rest: string[] }}
 */
export function parseRunArgs(argv) {
  const args = [...argv];
  let workRoot;
  if (args[0] === "--work-root") {
    // A bare `--work-root` with no following value is a caller bug — surface it
    // rather than silently swallowing the next token as an empty root.
    if (args.length < 2) {
      throw new Error("`--work-root` requires a directory value");
    }
    workRoot = args[1];
    args.splice(0, 2);
  }
  const [script, ...rest] = args;
  return { workRoot, script, rest };
}

/**
 * Build the child process environment, layering `YOUTUBE_WORK_ROOT` on top of the
 * inherited environment only when a non-empty work root was supplied. An empty or
 * missing work root leaves the environment untouched so `resolveWorkRoot()` keeps
 * its `CLAUDE_PROJECT_DIR` → `process.cwd()` fallback.
 *
 * @param {NodeJS.ProcessEnv} baseEnv
 * @param {string | undefined} workRoot
 * @returns {NodeJS.ProcessEnv}
 */
export function buildChildEnv(baseEnv, workRoot) {
  if (!workRoot) {
    return baseEnv;
  }
  return { ...baseEnv, YOUTUBE_WORK_ROOT: workRoot };
}
