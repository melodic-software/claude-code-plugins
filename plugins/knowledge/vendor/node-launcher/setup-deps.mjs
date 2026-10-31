#!/usr/bin/env node
/**
 * Install an extraction package's node dependencies into
 * `${CLAUDE_PLUGIN_DATA}/node_modules`, the per-plugin directory we keep state in
 * (its lifetime: https://code.claude.com/docs/en/plugins/manifest-reference#environment-variables,
 * as of 2026-10-11; recheck when that section changes when it is kept), and, for a
 * package that asks for it, provision Playwright's Chromium into
 * `${CLAUDE_PLUGIN_DATA}/ms-playwright`. The plugin ships without a committed
 * `node_modules`; this runs once on first use and again after an update whose
 * `package.json` or `vendor/` tree changed.
 *
 * Each package names its own install in the `setupDeps` field of its
 * `package.json`: `stamp` (the fingerprint file in the data directory), `label`
 * (how the messages name it), `sentinel` (a module path under `node_modules`,
 * such as `@melodic/video-digestion`, whose absence forces a reinstall; without
 * it, `node_modules` itself must exist) and `chromium` (provision the browser too).
 *
 * Idempotent: a stored fingerprint gates node reinstalls, and Chromium is
 * (re)installed only when the browsers path lacks it. Because the `file:` vendor
 * packages are installed from bundled SOURCE (not fetched by version), the
 * fingerprint hashes `package.json` AND the entire shared `vendor/` tree: a plugin
 * update that changes vendored code without touching the package manifest must
 * still trigger a reinstall. `--install-links` packs the vendored packages as real
 * installs so they resolve from the data directory rather than a symlink back
 * into the plugin cache. `npm install` does not download the Chromium binary;
 * `playwright install chromium` does, with `PLAYWRIGHT_BROWSERS_PATH` pinned to
 * the value the package's `run.mjs` sets at launch.
 *
 * The data directory comes from `--data-dir`, resolved like `run.mjs` resolves it
 * (`resolvePluginData`), and nothing is written until it resolves.
 *
 * Usage: node setup-deps.mjs --data-dir <dir> --package <extraction-package-dir>
 * (a package's own `setup-deps.mjs` entry passes its directory and takes only
 * `--data-dir <dir>`).
 */
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { resolvePluginData, takeDataDirFlag } from "./run.mjs";

const vendorRoot = path.resolve(import.meta.dirname, "..");
const pluginRoot = fs.realpathSync(path.resolve(vendorRoot, ".."));
const entryUsage = "Usage: node setup-deps.mjs --data-dir <dir>\n";
const cliUsage = "Usage: node setup-deps.mjs --data-dir <dir> --package <extraction-package-dir>\n";

/**
 * @typedef {{ stamp: string, label: string, sentinel?: string, chromium?: boolean }} SetupConfig
 * @typedef {{ write: (text: string) => unknown }} Stream
 * @typedef {{ status: number | null }} SpawnResult
 * @typedef {(command: string, options: object) => SpawnResult} ShellSpawn
 */

/**
 * Fingerprint the install inputs: the package's package.json and every file under
 * vendor/, named relative to the package so the hash order is fixed.
 *
 * @param {string} packageDir
 * @param {string} [vendorDir] the tree to walk, the plugin's vendor/ unless given
 * @returns {string}
 */
export function computeStamp(packageDir, vendorDir = vendorRoot) {
  const hash = createHash("sha256");
  const files = ["package.json"];
  if (fs.existsSync(vendorDir)) {
    // Traversal order is irrelevant: files.sort() below fixes the hash order.
    const walk = (/** @type {string} */ dir) => {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const abs = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(abs);
        else files.push(path.relative(packageDir, abs).split(path.sep).join("/"));
      }
    };
    walk(vendorDir);
  }
  for (const rel of files.sort()) {
    hash.update(rel);
    hash.update("\0");
    hash.update(fs.readFileSync(path.join(packageDir, rel)));
    hash.update("\0");
  }
  return hash.digest("hex");
}

/**
 * The `setupDeps` field of a package's package.json.
 *
 * @param {string} packageDir
 * @returns {SetupConfig}
 */
export function readSetupConfig(packageDir) {
  const manifest = JSON.parse(fs.readFileSync(path.join(packageDir, "package.json"), "utf8"));
  const config = manifest.setupDeps;
  if (!config || typeof config.stamp !== "string" || typeof config.label !== "string") {
    throw new Error(`${packageDir}/package.json has no setupDeps { stamp, label }`);
  }
  const { sentinel } = config;
  if (
    sentinel !== undefined &&
    (typeof sentinel !== "string" || sentinel === "" || path.isAbsolute(sentinel) || sentinel.split(/[\\/]/).includes(".."))
  ) {
    throw new Error(`${packageDir}/package.json setupDeps.sentinel must be a module path under node_modules`);
  }
  return config;
}

/**
 * Install `packageDir`'s dependencies into the resolved data directory and return
 * the exit code.
 *
 * @param {object} options
 * @param {string} options.packageDir the extraction package, a plugin-owned path
 * @param {string|undefined} options.dataDir the `--data-dir` value, unresolved
 * @param {NodeJS.ProcessEnv} [options.env]
 * @param {Stream} [options.stdout]
 * @param {Stream} [options.stderr]
 * @param {ShellSpawn} [options.spawn]
 * @param {string} [options.vendorDir] the tree the stamp walks, the plugin's vendor/ unless given
 * @returns {number}
 */
export function installPackageDeps({
  packageDir,
  dataDir,
  env = process.env,
  stdout = process.stdout,
  stderr = process.stderr,
  spawn = spawnSync,
  vendorDir = vendorRoot,
}) {
  const config = readSetupConfig(packageDir);
  const data = resolvePluginData(dataDir, env);
  if (!data) {
    stderr.write(
      'The knowledge plugin data directory is unknown. Pass --data-dir "${CLAUDE_PLUGIN_DATA}" from the skill; ' +
        "an inherited CLAUDE_PLUGIN_DATA that names another plugin is ignored.\n",
    );
    return 1;
  }

  fs.mkdirSync(data, { recursive: true });

  const browsersPath = env.PLAYWRIGHT_BROWSERS_PATH || path.join(data, "ms-playwright");
  const chromiumReady = () =>
    !config.chromium ||
    (fs.existsSync(browsersPath) &&
      fs
        .readdirSync(browsersPath)
        .some((name) => name.startsWith("chromium-") || name.startsWith("chromium_headless_shell-")));

  const stamp = computeStamp(packageDir, vendorDir);
  const stampPath = path.join(data, config.stamp);
  const depsCurrent =
    fs.existsSync(path.join(data, "node_modules", ...(config.sentinel ?? "").split("/"))) &&
    fs.existsSync(stampPath) &&
    fs.readFileSync(stampPath, "utf8") === stamp;

  if (depsCurrent && chromiumReady()) {
    stdout.write(`${config.label} deps${config.chromium ? " and Chromium" : ""} already current.\n`);
    return 0;
  }

  // npm is a `.cmd` shim on Windows, which node refuses to spawn without a shell
  // (CVE-2024-27980); a shell with a separate args array trips DEP0190. Passing a
  // single command string with shell:true satisfies both. JSON.stringify wraps
  // `packageDir` in double quotes, which keeps a path with spaces one argument in
  // cmd.exe and POSIX sh; it is not shell escaping: sh still expands `$` and
  // backticks inside double quotes, cmd.exe still expands `%VAR%`, and its `\"`
  // is not a quote escape in cmd.exe. What keeps the command safe is that
  // `packageDir` is a plugin-owned path (runCli rejects one outside the plugin).
  if (!depsCurrent) {
    const npmCommand = process.platform === "win32" ? "npm.cmd" : "npm";
    const result = spawn(`${npmCommand} install --omit=dev --install-links ${JSON.stringify(packageDir)}`, {
      cwd: data,
      stdio: "inherit",
      shell: true,
    });
    if (result.status !== 0) {
      stderr.write("npm install failed; see output above.\n");
      return result.status ?? 1;
    }
    fs.writeFileSync(stampPath, stamp);
    stdout.write(`${config.label} deps installed to ${path.join(data, "node_modules")}.\n`);
  }

  if (!chromiumReady()) {
    const npxCommand = process.platform === "win32" ? "npx.cmd" : "npx";
    const browser = spawn(`${npxCommand} playwright install chromium`, {
      cwd: data,
      stdio: "inherit",
      shell: true,
      env: { ...env, PLAYWRIGHT_BROWSERS_PATH: browsersPath },
    });
    if (browser.status !== 0) {
      stderr.write("playwright install chromium failed; see output above.\n");
      return browser.status ?? 1;
    }
    stdout.write(`Chromium provisioned into ${browsersPath}.\n`);
  }
  return 0;
}

/**
 * A package's own `setup-deps.mjs` entry: argv takes only `--data-dir <dir>`.
 *
 * @param {object} options
 * @param {string} options.packageDir
 * @param {string[]} options.argv
 * @param {Stream} [options.stderr]
 * @returns {number}
 */
export function runPackageSetup({ packageDir, argv, stderr = process.stderr }) {
  let dataDir;
  try {
    const taken = takeDataDirFlag(argv);
    if (taken.rest.length > 0) {
      throw new Error("setup-deps.mjs takes only `--data-dir <dir>`");
    }
    dataDir = taken.dataDir;
    // Resolve before installing so a bad --data-dir is a usage error that writes nothing.
    resolvePluginData(dataDir, process.env);
  } catch (error) {
    stderr.write(`${error instanceof Error ? error.message : String(error)}\n${entryUsage}`);
    return 2;
  }
  return installPackageDeps({ packageDir, dataDir, stderr });
}

/**
 * The shared CLI: `--data-dir <dir> --package <dir>` in either order, where the
 * package is a plugin directory whose package.json carries `setupDeps`.
 *
 * @param {string[]} argv
 * @param {Stream} [stderr]
 * @returns {number}
 */
export function runCli(argv, stderr = process.stderr) {
  /** @type {Record<string, string>} */
  const flags = {};
  const args = [...argv];
  let packageDir;
  try {
    while (args.length > 0) {
      const flag = args.shift();
      if (flag !== "--data-dir" && flag !== "--package") {
        throw new Error(`unknown argument \`${flag}\``);
      }
      const value = args.shift();
      if (value === undefined) throw new Error(`\`${flag}\` requires a directory value`);
      flags[flag] = value;
    }
    if (!flags["--package"]) throw new Error("`--package` is required");
    // Real paths on both sides: Node resolves this module's own path through symlinks.
    packageDir = fs.realpathSync(path.resolve(flags["--package"]));
    const rel = path.relative(pluginRoot, packageDir);
    if (rel === "" || rel.startsWith("..") || path.isAbsolute(rel)) {
      throw new Error(`\`--package\` must name a directory inside the knowledge plugin: ${flags["--package"]}`);
    }
    readSetupConfig(packageDir);
    resolvePluginData(flags["--data-dir"], process.env);
  } catch (error) {
    stderr.write(`${error instanceof Error ? error.message : String(error)}\n${cliUsage}`);
    return 2;
  }
  return installPackageDeps({ packageDir, dataDir: flags["--data-dir"], stderr });
}

/** True when this file is the process entry point, compared as real paths (a symlinked plugin root). */
function isMain() {
  try {
    return Boolean(process.argv[1]) && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMain()) {
  process.exit(runCli(process.argv.slice(2)));
}
