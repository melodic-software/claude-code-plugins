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
 * Course material is paid content kept for personal use. Before launching, every
 * `--course-dir` and `--output-dir` value (`--flag <dir>` or `--flag=<dir>`) is
 * judged by `scripts/repo-visibility.mjs`; unless each reads private, internal or
 * local, nothing launches and the exit is 1.
 *
 * Usage: node run.mjs [--data-dir <dir>] <relative-script.js> [args…]
 */
import path from "node:path";

import { directoryVisibility } from "../../../scripts/repo-visibility.mjs";
import { dataDirEnv, launch } from "../../../vendor/node-launcher/run.mjs";

const PRIVATE = new Set(["private", "internal", "local"]);
const COURSE_DIR_FLAGS = ["--course-dir", "--output-dir"];

/**
 * Every course directory `argv` names, in order.
 *
 * @param {string[]} argv
 * @returns {string[]}
 */
function courseDirs(argv) {
  const dirs = [];
  argv.forEach((arg, i) => {
    for (const flag of COURSE_DIR_FLAGS) {
      if (arg === flag && i + 1 < argv.length) dirs.push(argv[i + 1]);
      else if (arg.startsWith(`${flag}=`)) dirs.push(arg.slice(flag.length + 1));
    }
  });
  return dirs;
}

const argv = process.argv.slice(2);
for (const dir of courseDirs(argv)) {
  const target = path.resolve(dir);
  const { visibility, reason } = directoryVisibility(target);
  if (!PRIVATE.has(visibility)) {
    process.stderr.write(
      `Refusing to write course material to ${target}: it reads ${visibility} (${reason}). ` +
        "Course material is paid content kept for personal use, so it lands only where the visibility " +
        "check reads private, internal or local. Set the knowledge plugin's library_dir to a private " +
        "corpus checkout, or run from a private repository.\n",
    );
    process.exit(1);
  }
}

process.exit(
  launch({
    packageDir: import.meta.dirname,
    argv,
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
