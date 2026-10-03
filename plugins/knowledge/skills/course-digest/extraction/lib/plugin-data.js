/**
 * The knowledge plugin's data directory for `run.mjs` and `setup-deps.mjs`, which
 * Claude runs through the Bash tool. That tool's environment does not carry
 * `CLAUDE_PLUGIN_DATA`, and another plugin's SessionStart hook can persist its own
 * data directory there under that name, so the skill passes a leading
 * `--data-dir "${CLAUDE_PLUGIN_DATA}"`, substituted when the skill loads, and that
 * value wins. Without the flag an inherited value is used only when its last path
 * segment names this plugin (`knowledge-<marketplace>`), the order the marketplace's
 * on-demand-dependencies convention sets. Basis: plugins reference, "Where each
 * variable resolves", as of 2026-10-02.
 *
 * Pure, so the launcher's contract is unit-testable without spawning a process.
 */

/**
 * Split a leading `--data-dir <dir>` off the launcher's argv.
 *
 * @param {string[]} argv
 * @returns {{ dataDir: string|undefined, rest: string[] }}
 */
export function takeDataDirFlag(argv) {
  if (argv[0] !== "--data-dir") {
    return { dataDir: undefined, rest: [...argv] };
  }
  if (argv.length < 2) {
    throw new Error("`--data-dir` requires a directory value");
  }
  return { dataDir: argv[1], rest: argv.slice(2) };
}

/**
 * @param {string|undefined} flagValue
 * @param {NodeJS.ProcessEnv} env
 * @returns {string|undefined} undefined when neither source names this plugin
 */
export function resolvePluginData(flagValue, env) {
  if (flagValue) {
    if (flagValue.includes("${") || flagValue.includes("<plugin-data>")) {
      throw new Error(`\`--data-dir\` got an unsubstituted placeholder: \`${flagValue}\``);
    }
    return flagValue;
  }
  const inherited = env.CLAUDE_PLUGIN_DATA;
  const lastSegment = inherited?.replace(/[\\/]+$/, "").split(/[\\/]/).pop() ?? "";
  return /^knowledge(-|$)/.test(lastSegment) ? inherited : undefined;
}
