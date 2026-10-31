#!/usr/bin/env node
/**
 * Cross-platform launcher for the video-digest extraction entry points: the shared
 * launcher (`vendor/node-launcher/run.mjs`) with this package's leading flags.
 *
 * OPTIONAL leading flags let the invoking skill wire the knowledge plugin's
 * personal userConfig options into the pipeline the same cross-platform way: each
 * double-quoted CLI arg (safe in bash and PowerShell) is translated into the env
 * var the extraction child reads (`lib/run-args.js`): `--work-root` sets
 * `VIDEO_DIGEST_WORK_ROOT` (`resolveWorkRoot()`), plus the yt-dlp / throttle
 * scalars. Omit a flag to keep the child's own default; for `--work-root` the
 * repo-root fallback chain applies. The `--work-root` value may use the portable
 * `library_dir` forms, a leading `~` or `${NAME}` / `%NAME%` env-var references,
 * expanded here (`expandPathValue`) so machine-varying roots never require a
 * literal path in stored configuration.
 *
 * `--data-dir` names the plugin data directory the resolve hook finds dependencies
 * in. The child sees only the value `resolvePluginData` accepts, never an inherited
 * `CLAUDE_PLUGIN_DATA` that names another plugin.
 *
 * Usage: node run.mjs [--data-dir <dir>] [--work-root <dir>] [--js-runtimes <v>]
 *   [--cookies-file <path>] [--cookies-from-browser <name>] [--max-concurrent-acquires <n>]
 *   [--acquire-phase-gap <sec>] [--asr-python <path>] <relative-script.js> [args…]
 */
import os from "node:os";

import { launch } from "../../../vendor/node-launcher/run.mjs";
import { buildChildEnv, expandPathValue, parseRunArgs } from "./lib/run-args.js";

const usage =
  "Usage: node run.mjs [--data-dir <dir>] [--work-root <dir>] [--js-runtimes <v>] [--cookies-file <path>] " +
  "[--cookies-from-browser <name>] [--max-concurrent-acquires <n>] " +
  "[--acquire-phase-gap <sec>] [--asr-python <path>] <relative-script.js> [args…]\n";

process.exit(
  launch({
    packageDir: import.meta.dirname,
    argv: process.argv.slice(2),
    usage,
    parse: parseRunArgs,
    childEnv: (inherited, parsed, env) =>
      buildChildEnv(
        inherited,
        parsed.workRoot ? { ...parsed, workRoot: expandPathValue(parsed.workRoot, env, os.homedir()) } : parsed,
      ),
  }),
);
