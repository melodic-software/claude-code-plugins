/**
 * Reduce a `--target` value to the portable name `watch.json` records (SKILL.md "Synthesis
 * target resolution"): a local checkout path never reaches the slice.
 */

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

import { parseGitHubUrl } from "@melodic/repo-analysis";

/** @param {string} dir */
function isDirectory(dir) {
  try {
    return fs.statSync(dir).isDirectory();
  } catch {
    return false;
  }
}

/**
 * @param {string} dir
 * @returns {string|null}
 */
function originUrl(dir) {
  try {
    return execFileSync("git", ["-C", dir, "remote", "get-url", "origin"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}

/**
 * A directory on disk becomes `owner/repo` from its GitHub `origin`, else its directory name. An
 * absolute path that is not a directory here becomes its last segment. Anything else is already a
 * name and is returned unchanged.
 *
 * @param {string} target
 * @param {{ isDirectory?: (dir: string) => boolean, originUrl?: (dir: string) => string|null }} [deps]
 * @returns {string}
 */
export function portableTargetName(target, deps = {}) {
  const { isDirectory: isDir = isDirectory, originUrl: origin = originUrl } = deps;
  if (isDir(target)) {
    const parsed = parseGitHubUrl(origin(target) ?? "");
    return parsed ? `${parsed.owner}/${parsed.repo}` : path.basename(path.resolve(target));
  }
  if (path.isAbsolute(target) || path.win32.isAbsolute(target)) {
    return path.win32.basename(target);
  }
  return target;
}
