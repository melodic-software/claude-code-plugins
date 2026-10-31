/**
 * Shared launcher for the knowledge plugin's extraction packages.
 *
 * A package's node dependencies live in `${CLAUDE_PLUGIN_DATA}/node_modules`
 * (installed by setup-deps.mjs), not inside the cache-isolated plugin directory.
 * `launch` re-execs a package script with the ESM resolve hook beside this file,
 * which finds bare specifiers like `@melodic/video-digestion` in the data
 * directory, so every documented invocation is a plain
 * `node <package>/run.mjs <script> …` with no shell-specific env-var syntax. (An
 * inline `NODE_PATH=… node` prefix is bash-only, so it fails under PowerShell, and
 * the ESM loader does not honor NODE_PATH at all.)
 *
 * Each package keeps a short `run.mjs` entry that passes its own directory,
 * argument parser and child environment; this module holds the rest. Node
 * builtins only, imported by relative path: it runs before anything is installed.
 */
import { spawnSync } from "node:child_process";
import path from "node:path";
import { pathToFileURL } from "node:url";

const registerHook = path.join(import.meta.dirname, "register-hook.mjs");

/**
 * The knowledge plugin's data directory for a script Claude runs through the Bash tool.
 *
 * We do not rely on that tool's environment carrying this plugin's `CLAUDE_PLUGIN_DATA`,
 * and another plugin's SessionStart hook can persist its own data directory there under
 * that name, so the skill passes `--data-dir "${CLAUDE_PLUGIN_DATA}"`, substituted when
 * the skill loads, and that value wins. Without the flag an inherited value is used only
 * when its last path segment names this plugin (`knowledge-<marketplace>`), the order the
 * marketplace's on-demand-dependencies convention sets. Pointer: when deciding what the
 * Bash tool's environment holds, fetch
 * https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves
 * live. As of 2026-10-11. Recheck when that section changes what `CLAUDE_PLUGIN_DATA`
 * holds in the Bash tool's environment.
 *
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

/**
 * Split a leading `--data-dir <dir>` off an entry point's argv.
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
 * @typedef {{ dataDir?: string, script?: string, rest: string[] }} LaunchArgs
 */

/**
 * The default parser: a leading `--data-dir`, then the script and its arguments.
 *
 * @param {string[]} argv
 * @returns {LaunchArgs}
 */
export function parseDataDirArgs(argv) {
  const { dataDir, rest } = takeDataDirFlag(argv);
  const [script, ...scriptArgs] = rest;
  return { dataDir, script, rest: scriptArgs };
}

/**
 * The default child environment: the resolved data directory, when there is one.
 *
 * @param {NodeJS.ProcessEnv} inherited the environment without `CLAUDE_PLUGIN_DATA`
 * @param {LaunchArgs} parsed
 * @returns {NodeJS.ProcessEnv}
 */
export function dataDirEnv(inherited, parsed) {
  return parsed.dataDir ? { ...inherited, CLAUDE_PLUGIN_DATA: parsed.dataDir } : inherited;
}

/**
 * Run `<script>` from `packageDir` in a child node process with the resolve hook,
 * and return the exit code for the entry point to exit with.
 *
 * `parse` splits argv; its `dataDir` is resolved here (`resolvePluginData`), so the
 * child sees only an accepted value, never an inherited `CLAUDE_PLUGIN_DATA` that
 * names another plugin. `childEnv` gets the environment without that variable, the
 * parsed arguments and the full environment, and returns the child's environment.
 * A throw from either is a usage error.
 *
 * @template {LaunchArgs} T
 * @param {object} options
 * @param {string} options.packageDir directory every script must sit under
 * @param {string[]} options.argv arguments after `node run.mjs`
 * @param {string} options.usage usage text, newline-terminated
 * @param {(argv: string[]) => T} [options.parse]
 * @param {(inherited: NodeJS.ProcessEnv, parsed: T, env: NodeJS.ProcessEnv) => NodeJS.ProcessEnv} [options.childEnv]
 * @param {NodeJS.ProcessEnv} [options.env]
 * @param {{ write: (text: string) => unknown }} [options.stderr]
 * @param {typeof spawnSync} [options.spawn]
 * @returns {number}
 */
export function launch({
  packageDir,
  argv,
  usage,
  parse = /** @type {(argv: string[]) => T} */ (parseDataDirArgs),
  childEnv = dataDirEnv,
  env = process.env,
  stderr = process.stderr,
  spawn = spawnSync,
}) {
  const { CLAUDE_PLUGIN_DATA: _inherited, ...inherited } = env;
  let parsed;
  let child;
  try {
    parsed = parse(argv);
    parsed.dataDir = resolvePluginData(parsed.dataDir, env);
    child = childEnv(inherited, parsed, env);
  } catch (error) {
    stderr.write(`${error instanceof Error ? error.message : String(error)}\n${usage}`);
    return 2;
  }

  if (!parsed.script) {
    stderr.write(usage);
    return 2;
  }

  const target = path.resolve(packageDir, parsed.script);
  const rel = path.relative(packageDir, target);
  if (rel.startsWith("..") || path.isAbsolute(rel)) {
    stderr.write(`Refusing to run a script outside the extraction directory: ${parsed.script}\n`);
    return 2;
  }

  const result = spawn(
    process.execPath,
    ["--import", pathToFileURL(registerHook).href, target, ...parsed.rest],
    { stdio: "inherit", env: child },
  );
  return result.status ?? 1;
}
