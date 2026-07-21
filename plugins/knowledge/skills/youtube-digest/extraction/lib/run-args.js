/**
 * Argument + environment helpers for the youtube extraction launcher (`run.mjs`).
 *
 * The launcher accepts OPTIONAL leading flags ahead of the target script that
 * wire the knowledge plugin's personal userConfig options (`library_dir` and the
 * yt-dlp / throttle scalars) into the pipeline WITHOUT a shell-specific env prefix:
 * `YOUTUBE_WORK_ROOT=… node …` is bash-only (it fails under PowerShell), so each
 * option is passed as a cross-platform double-quoted CLI arg and translated here
 * into the environment variable the extraction child already reads. The env vars
 * are an internal launcher-to-child interface, not a consumer-facing channel.
 *
 * Both helpers are pure so the launcher's contract is unit-testable without
 * spawning a child process.
 */

/**
 * Leading launcher flags, each mapped to the parsed-result key it fills and the
 * environment variable the extraction child reads it from. `valueLabel` shapes the
 * missing-value error message.
 */
const LEADING_FLAGS = {
  "--work-root": { key: "workRoot", env: "YOUTUBE_WORK_ROOT", valueLabel: "directory value" },
  "--js-runtimes": { key: "jsRuntimes", env: "YOUTUBE_YT_DLP_JS_RUNTIMES", valueLabel: "value" },
  "--cookies-file": { key: "cookiesFile", env: "YOUTUBE_YT_DLP_COOKIES_FILE", valueLabel: "value" },
  "--cookies-from-browser": {
    key: "cookiesFromBrowser",
    env: "YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER",
    valueLabel: "value",
  },
  "--max-concurrent-acquires": {
    key: "maxConcurrentAcquires",
    env: "YOUTUBE_MAX_CONCURRENT_ACQUIRES",
    valueLabel: "value",
  },
};

/**
 * @typedef {object} RunArgs
 * @property {string} [workRoot]
 * @property {string} [jsRuntimes]
 * @property {string} [cookiesFile]
 * @property {string} [cookiesFromBrowser]
 * @property {string} [maxConcurrentAcquires]
 * @property {string} [script]
 * @property {string[]} rest
 */

/**
 * Split the launcher's argv (already sliced past `node run.mjs`) into any leading
 * option flags, the target script, and its remaining arguments. Flags are honored
 * only in the leading position and in any order; the first token that is not a
 * known flag is the script, so a script argument that happens to match a flag name
 * is left untouched.
 *
 * @param {string[]} argv
 * @returns {RunArgs}
 */
export function parseRunArgs(argv) {
  const args = [...argv];
  /** @type {Record<string, string>} */
  const flags = {};
  while (args.length > 0 && Object.hasOwn(LEADING_FLAGS, args[0])) {
    const flag = LEADING_FLAGS[args[0]];
    // A bare flag with no following value is a caller bug — surface it rather than
    // silently swallowing the next token (or the script) as an empty value.
    if (args.length < 2) {
      throw new Error(`\`${args[0]}\` requires a ${flag.valueLabel}`);
    }
    flags[flag.key] = args[1];
    args.splice(0, 2);
  }
  const [script, ...rest] = args;
  return { ...flags, script, rest };
}

/**
 * Build the child process environment, layering each supplied launcher flag onto
 * the inherited environment as the variable the extraction child reads. Empty or
 * missing flags are skipped, so an unset option leaves the environment untouched
 * and the child's own default/fallback applies.
 *
 * @param {NodeJS.ProcessEnv} baseEnv
 * @param {RunArgs} [flags]
 * @returns {NodeJS.ProcessEnv}
 */
export function buildChildEnv(baseEnv, flags = {}) {
  /** @type {Record<string, string>} */
  const overlay = {};
  for (const { key, env } of Object.values(LEADING_FLAGS)) {
    const value = flags[key];
    if (value) {
      overlay[env] = value;
    }
  }
  if (Object.keys(overlay).length === 0) {
    return baseEnv;
  }
  return { ...baseEnv, ...overlay };
}

const ENV_REF = /\$\{([A-Za-z_][A-Za-z0-9_]*)\}|%([A-Za-z_][A-Za-z0-9_]*)%/g;

/**
 * Expand the portable `library_dir` value forms in a `--work-root` value:
 * a leading `~` (the invoking user's home directory) and `${NAME}` / `%NAME%`
 * environment-variable references anywhere in the value. These forms let a
 * consumer point the seam at a machine-varying root while keeping the stored
 * configuration value portable.
 *
 * Fail-loud contract: an unset or empty referenced variable throws (a silent
 * literal or empty substitution would land artifacts in a wrong directory),
 * and a value that used either form must expand to an absolute path. Values
 * without either form pass through untouched, preserving the existing
 * literal-path behavior.
 *
 * @param {string} value
 * @param {NodeJS.ProcessEnv} env
 * @param {string} homedir
 * @returns {string}
 */
export function expandPathValue(value, env, homedir) {
  let expanded = value;
  let sawForm = false;
  if (expanded === "~" || expanded.startsWith("~/") || expanded.startsWith("~\\")) {
    sawForm = true;
    expanded = homedir + expanded.slice(1);
  }
  expanded = expanded.replace(ENV_REF, (reference, braced, percent) => {
    sawForm = true;
    const name = braced ?? percent;
    const resolved = env[name];
    if (!resolved) {
      throw new Error(
        `\`${reference}\` in work-root value \`${value}\` references an unset or empty environment variable`,
      );
    }
    return resolved;
  });
  if (sawForm && !isAbsolutePath(expanded)) {
    throw new Error(`work-root value \`${value}\` expanded to a non-absolute path: \`${expanded}\``);
  }
  return expanded;
}

/**
 * POSIX/Windows absolute-path test without importing node:path, keeping this
 * module dependency-free and pure for unit tests.
 *
 * @param {string} p
 * @returns {boolean}
 */
function isAbsolutePath(p) {
  return p.startsWith("/") || p.startsWith("\\\\") || /^[A-Za-z]:[\\/]/.test(p);
}
