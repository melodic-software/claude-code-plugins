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
 * Usage: node run.mjs <relative-script.js> [args…]
 */
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const [script, ...rest] = process.argv.slice(2);

if (!script) {
  process.stderr.write("Usage: node run.mjs <relative-script.js> [args…]\n");
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
  { stdio: "inherit" },
);
process.exit(result.status ?? 1);
