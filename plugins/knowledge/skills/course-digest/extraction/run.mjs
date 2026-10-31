#!/usr/bin/env node
/**
 * Cross-platform launcher for the course-digest extraction entry points: the shared
 * launcher (`vendor/node-launcher/run.mjs`) with this package's child environment.
 *
 * It pins `PLAYWRIGHT_BROWSERS_PATH` to the data-directory location setup-deps.mjs
 * installs Chromium into, so the browser binary resolves at runtime no matter what
 * cwd the pipeline runs from. Setting it at the single choke point every script
 * launch passes through keeps install path and lookup path in lockstep. An explicit
 * value already in the environment wins (honored, not overwritten).
 *
 * The leading `--data-dir` names the data directory. The child sees only the value
 * `resolvePluginData` accepts, never an inherited `CLAUDE_PLUGIN_DATA` that names
 * another plugin.
 *
 * Usage: node run.mjs [--data-dir <dir>] <relative-script.js> [args…]
 */
import path from "node:path";

import { dataDirEnv, launch } from "../../../vendor/node-launcher/run.mjs";

process.exit(
  launch({
    packageDir: import.meta.dirname,
    argv: process.argv.slice(2),
    usage: "Usage: node run.mjs [--data-dir <dir>] <relative-script.js> [args…]\n",
    childEnv: (inherited, parsed) =>
      parsed.dataDir
        ? {
            ...dataDirEnv(inherited, parsed),
            PLAYWRIGHT_BROWSERS_PATH: inherited.PLAYWRIGHT_BROWSERS_PATH || path.join(parsed.dataDir, "ms-playwright"),
          }
        : inherited,
  }),
);
