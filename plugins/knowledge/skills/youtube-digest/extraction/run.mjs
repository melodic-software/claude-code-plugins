#!/usr/bin/env node
/**
 * Cross-platform launcher for the youtube extraction entry points.
 *
 * The pipeline's node dependencies live in `${CLAUDE_PLUGIN_DATA}/node_modules`
 * (installed by setup-deps.mjs), not inside the cache-isolated plugin directory.
 * This launcher re-execs the target script with an ESM resolve hook that finds
 * bare specifiers like `@melodic/video-digestion` in the data directory, so
 * every documented invocation is a plain `node run.mjs <script> …` with no
 * shell-specific env-var syntax. (An inline `NODE_PATH=… node` prefix is both
 * bash-only — it fails under PowerShell — and ignored by the ESM loader, which
 * does not honor NODE_PATH at all.)
 *
 * OPTIONAL leading flags let the invoking skill wire the knowledge plugin's
 * personal userConfig options into the pipeline the same cross-platform way: each
 * double-quoted CLI arg (safe in bash and PowerShell) is translated here into the
 * env var the extraction child reads — `--work-root` → `YOUTUBE_WORK_ROOT`
 * (`resolveWorkRoot()`), plus the yt-dlp / throttle scalars. Omit a flag to keep
 * the child's own default; for `--work-root` the repo-root fallback chain applies.
 * The `--work-root` value may use the portable `library_dir` forms — a leading `~`
 * or `${NAME}` / `%NAME%` env-var references — expanded here (`expandPathValue`)
 * so machine-varying roots never require a literal path in stored configuration.
 *
 * Usage: node run.mjs [--work-root <dir>] [--js-runtimes <v>] [--cookies-file <path>]
 *   [--cookies-from-browser <name>] [--max-concurrent-acquires <n>] <relative-script.js> [args…]
 */
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { buildChildEnv, expandPathValue, parseRunArgs } from "./lib/run-args.js";

const here = path.dirname(fileURLToPath(import.meta.url));

let parsed;
const usage =
  "Usage: node run.mjs [--work-root <dir>] [--js-runtimes <v>] [--cookies-file <path>] " +
  "[--cookies-from-browser <name>] [--max-concurrent-acquires <n>] <relative-script.js> [args…]\n";

try {
  parsed = parseRunArgs(process.argv.slice(2));
  if (parsed.workRoot) {
    parsed.workRoot = expandPathValue(parsed.workRoot, process.env, os.homedir());
  }
} catch (error) {
  process.stderr.write(`${error.message}\n${usage}`);
  process.exit(2);
}
const { script, rest } = parsed;

if (!script) {
  process.stderr.write(usage);
  process.exit(2);
}

const target = path.resolve(here, script);
const rel = path.relative(here, target);
if (rel.startsWith("..") || path.isAbsolute(rel)) {
  process.stderr.write(`Refusing to run a script outside the extraction directory: ${script}\n`);
  process.exit(2);
}

const registerHook = path.join(here, "register-hook.mjs");
const result = spawnSync(
  process.execPath,
  ["--import", pathToFileURL(registerHook).href, target, ...rest],
  { stdio: "inherit", env: buildChildEnv(process.env, parsed) },
);
process.exit(result.status ?? 1);
