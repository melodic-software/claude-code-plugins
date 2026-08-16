/**
 * Compatibility resolution for the extraction env namespace: every `VIDEO_DIGEST_*`
 * variable has a deprecated `YOUTUBE_*`-prefixed legacy spelling that keeps working.
 */

/** @type {Set<string>} */
const warnedLegacyNames = new Set();

/**
 * Resolve a configuration value from `newName`, falling back to the deprecated
 * `oldName`. The new name wins when both are set. A value read from the old
 * name still works but writes a deprecation warning to stderr once per process
 * per legacy variable. `run.mjs` re-execs the target script as a child process,
 * so "once per process" deliberately allows the launcher and its child to warn
 * once each — the warning is per-process by design, not deduplicated across
 * the re-exec boundary.
 *
 * @param {string} newName
 * @param {string} oldName
 * @param {NodeJS.ProcessEnv} [env]
 * @returns {string|undefined} the raw resolved value, or undefined when neither is set
 */
export function resolveEnvWithLegacy(newName, oldName, env = process.env) {
  const current = env[newName];
  if (current) return current;

  const legacy = env[oldName];
  if (legacy) {
    if (!warnedLegacyNames.has(oldName)) {
      warnedLegacyNames.add(oldName);
      process.stderr.write(`Warning: ${oldName} is deprecated; use ${newName} instead.\n`);
    }
    return legacy;
  }
  return undefined;
}

/**
 * Test seam: clear the per-process legacy-warning dedupe set.
 */
export function resetLegacyEnvWarnings() {
  warnedLegacyNames.clear();
}
