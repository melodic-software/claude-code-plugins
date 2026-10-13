/**
 * Reduce a `--target` value to the portable name `watch.json` records (context/watch-pipeline.md
 * "Synthesis target resolution"): a local checkout path never reaches the slice.
 */

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

import { parseGitHubUrl } from "@melodic/repo-analysis";

/** @param {string[]} args */
function git(args) {
  try {
    return execFileSync("git", args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}

/**
 * The `origin` of `dir` when `dir` is the root of a git checkout, else null. A subdirectory is not
 * a checkout: `git -C` would walk up to the enclosing repository.
 *
 * @param {string} dir
 * @returns {{ origin: string|null } | null}
 */
function checkoutOrigin(dir) {
  let real;
  try {
    if (!fs.statSync(dir).isDirectory()) return null;
    real = fs.realpathSync(dir);
  } catch {
    return null;
  }
  const top = git(["-C", dir, "rev-parse", "--show-toplevel"]);
  if (!top || fs.realpathSync(top) !== real) return null;
  return { origin: git(["-C", dir, "remote", "get-url", "origin"]) };
}

/**
 * Rewrite the GitHub origin forms the vendor parser rejects (`ssh://`, https with credentials)
 * into ones it reads. The credentials are dropped, never recorded.
 *
 * @param {string} url
 */
function normalizeOrigin(url) {
  return url
    .replace(/^ssh:\/\/git@github\.com\//i, "git@github.com:")
    .replace(/^https:\/\/[^/@]+@github\.com\//i, "https://github.com/");
}

/**
 * A checkout root becomes `owner/repo` from its GitHub `origin`, else its directory name. A path
 * (absolute, or starting with `.` or `~`) that is not a checkout here becomes its last segment.
 * Anything else is already a name and is returned unchanged.
 *
 * @param {string} target
 * @param {{ cwd?: string, checkoutOrigin?: (dir: string) => { origin: string|null } | null }} [deps]
 * @returns {string}
 */
export function portableTargetName(target, deps = {}) {
  const { cwd = process.cwd(), checkoutOrigin: readCheckout = checkoutOrigin } = deps;
  const resolved = path.resolve(cwd, target);
  const checkout = readCheckout(resolved);
  if (checkout) {
    const parsed = parseGitHubUrl(normalizeOrigin(checkout.origin ?? ""));
    if (parsed) return `${parsed.owner}/${parsed.repo}`;
    if (path.basename(resolved)) return path.basename(resolved);
  }
  const isPath =
    path.isAbsolute(target) ||
    path.win32.isAbsolute(target) ||
    /^[.~]/.test(target);
  if (!isPath) return target;
  const name = path.win32.basename(target.replace(/[\\/]+$/, ""));
  if (!name || name === "." || name === ".." || name === "~") {
    throw new Error(`\`--target\` ${JSON.stringify(target)} has no name in it`);
  }
  return name;
}
