#!/usr/bin/env node
/**
 * The knowledge plugin's one work-root rule (reference/work-root.md), as a CLI for
 * skills and an export for node code.
 *
 *   node work-root.mjs [--library-dir <value>]   print the absolute work root
 *   node work-root.mjs --progress-key            print the distill progress key
 *
 * The session root is `git rev-parse --show-toplevel` run in the working directory,
 * or that directory itself outside git. The work root is the session root joined
 * with a `library_dir` value. Pass the value in single quotes: this script expands
 * `~` and `${NAME}` / `%NAME%` itself and fails on an unset variable, where a shell
 * would substitute an empty string.
 *
 * Exit: 0 printed; 1 the value cannot resolve (an unset variable); 2 usage.
 */
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { realpathSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { insideGitEntry } from "./repo-visibility.mjs";

const ENV_REF = /\$\{([A-Za-z_][A-Za-z0-9_]*)\}|%([A-Za-z_][A-Za-z0-9_]*)%/g;
const UNSUBSTITUTED = /^\$\{user_config\.[A-Za-z0-9_]+\}$/;

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
 * POSIX/Windows absolute-path test that holds on any host, where `path.isAbsolute`
 * follows only the running platform's form.
 *
 * @param {string} p
 * @returns {boolean}
 */
function isAbsolutePath(p) {
  return p.startsWith("/") || p.startsWith("\\\\") || /^[A-Za-z]:[\\/]/.test(p);
}

/**
 * `env` without the variables that point git at another repository (GIT_DIR,
 * GIT_WORK_TREE, GIT_INDEX_FILE) or inject config entries (GIT_CONFIG_PARAMETERS,
 * GIT_CONFIG_COUNT, GIT_CONFIG_KEY_<n>, GIT_CONFIG_VALUE_<n>). The user's global
 * and system config files still apply.
 *
 * @param {NodeJS.ProcessEnv} env
 * @returns {NodeJS.ProcessEnv}
 */
function sessionGitEnv(env) {
  const dropped = /^GIT_(DIR|WORK_TREE|INDEX_FILE|CONFIG_PARAMETERS|CONFIG_COUNT|CONFIG_KEY_\d+|CONFIG_VALUE_\d+)$/;
  return Object.fromEntries(Object.entries(env).filter(([name]) => !dropped.test(name.toUpperCase())));
}

/**
 * The checkout the session writes to: the git top-level of `cwd`, else `cwd` when
 * neither `cwd` nor any ancestor holds a `.git`. Git failing where a `.git` exists
 * (dubious ownership, a corrupt repository, git missing) throws.
 *
 * @param {string} [cwd]
 * @param {NodeJS.ProcessEnv} [env]
 * @returns {string} an absolute path in the platform's own separator form
 */
export function sessionRoot(cwd = process.cwd(), env = process.env) {
  const dir = path.resolve(cwd);
  let top = "";
  let failure;
  try {
    top = execFileSync("git", ["rev-parse", "--show-toplevel"], {
      cwd: dir,
      env: sessionGitEnv(env),
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch (error) {
    failure = error;
  }
  if (top) return path.resolve(top);
  if (!insideGitEntry(dir)) return dir;
  const detail = String(failure?.stderr ?? failure?.message ?? "no top-level printed").trim();
  throw new Error(`git could not read the repository holding \`${dir}\`: ${detail}`);
}

/**
 * The absolute work root for a `library_dir` value. A missing or empty value, `.`,
 * or a value that is exactly one `${user_config.<key>}` token Claude Code left
 * unsubstituted means the default. Any other value holding `${user_config.`
 * throws: it is a token Claude Code did not substitute, not a directory name.
 *
 * @param {object} [options]
 * @param {string} [options.libraryDir]
 * @param {string} [options.cwd]
 * @param {NodeJS.ProcessEnv} [options.env]
 * @param {string} [options.homedir]
 * @returns {string}
 */
export function workRoot({ libraryDir, cwd = process.cwd(), env = process.env, homedir = os.homedir() } = {}) {
  const root = sessionRoot(cwd);
  const value = libraryDir?.trim() ?? "";
  if (!value || value === "." || UNSUBSTITUTED.test(value)) return root;
  if (value.includes("${user_config.")) {
    throw new Error(`work-root value \`${value}\` holds an unsubstituted \`\${user_config.…}\` token`);
  }
  return path.resolve(root, expandPathValue(value, env, homedir));
}

/**
 * The distill progress key for a session root: its basename reduced to lowercase
 * alphanumerics and single hyphens, `-`, and the first 8 hex of the SHA-256 of the
 * root path's UTF-8 bytes.
 *
 * @param {string} root
 * @returns {string}
 */
export function progressKey(root) {
  const slug = path
    .basename(root)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return `${slug}-${createHash("sha256").update(root).digest("hex").slice(0, 8)}`;
}

/**
 * @param {string[]} argv
 * @returns {number}
 */
function main(argv) {
  const usage = "Usage: node work-root.mjs [--library-dir <value>] | --progress-key\n";
  let libraryDir;
  let wantKey = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--progress-key") {
      wantKey = true;
    } else if (argv[i] === "--library-dir" && i + 1 < argv.length) {
      libraryDir = argv[++i];
    } else {
      process.stderr.write(usage);
      return 2;
    }
  }
  if (wantKey && libraryDir !== undefined) {
    process.stderr.write(`--progress-key takes no --library-dir\n${usage}`);
    return 2;
  }
  try {
    process.stdout.write(`${wantKey ? progressKey(sessionRoot()) : workRoot({ libraryDir })}\n`);
    return 0;
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    return 1;
  }
}

/** @returns {boolean} whether this module is the script node was started with */
function isMain() {
  try {
    return Boolean(process.argv[1]) && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMain()) {
  process.exitCode = main(process.argv.slice(2));
}
