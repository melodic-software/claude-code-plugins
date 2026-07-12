/**
 * Async child process utilities for video-digestion pipeline stages.
 *
 * Replaces spawnSync with a Promise-wrapped spawn() that supports
 * timeout, stderr capture, and non-blocking execution.
 */

import { spawn } from "node:child_process";
import { realpathSync } from "node:fs";

const URL_PREFIX = /^https?:\/\//i;

/**
 * Normalize a filesystem path for CLI tools that expect forward slashes (ffmpeg, magick).
 *
 * @param {string} filePath
 * @returns {string}
 */
export function normalizeSpawnPath(filePath) {
  return filePath.replaceAll("\\", "/");
}

/**
 * Resolve a local path for child-process spawn args — expands Windows 8.3 short paths
 * via realpath before normalization. Remote URLs pass through unchanged.
 *
 * @param {string} filePath
 * @param {object} [deps]
 * @param {typeof realpathSync.native} [deps.realpath]
 * @returns {string}
 */
export function resolveSpawnInputPath(filePath, { realpath = realpathSync.native } = {}) {
  if (!filePath || URL_PREFIX.test(filePath)) {
    return filePath;
  }
  try {
    return normalizeSpawnPath(realpath(filePath));
  } catch {
    return normalizeSpawnPath(filePath);
  }
}

/**
 * Run a command asynchronously with timeout and output capture.
 * Unlike spawnSync, this does not block the event loop - SIGINT
 * handling and progress reporting continue during execution.
 *
 * @param {string} command
 * @param {string[]} args
 * @param {object} [options]
 * @param {number} [options.timeout] - ms before killing (default: no limit)
 * @param {NodeJS.Signals} [options.killSignal='SIGTERM']
 * Additional properties are passed through to child_process.spawn().
 * @returns {Promise<{success: boolean, code: number|null, signal: string|null, stdout: string, stderr: string, timedOut: boolean, error?: string}>}
 */
export function spawnAsync(command, args = [], options = {}) {
  return new Promise((resolve) => {
    const { timeout, killSignal = "SIGTERM", ...spawnOptions } = options;

    let child;
    try {
      child = spawn(command, args, {
        stdio: ["ignore", "pipe", "pipe"],
        ...spawnOptions,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      resolve({
        success: false,
        code: null,
        signal: null,
        stdout: "",
        stderr: "",
        timedOut: false,
        error: message,
      });
      return;
    }

    let stdout = "";
    let stderr = "";
    let timedOut = false;
    let timeoutId = null;

    child.stdout.on("data", (data) => {
      stdout += data.toString();
    });
    child.stderr.on("data", (data) => {
      stderr += data.toString();
    });

    if (timeout && timeout > 0) {
      timeoutId = setTimeout(() => {
        timedOut = true;
        child.kill(killSignal);
      }, timeout);
    }

    child.on("close", (code, signal) => {
      if (timeoutId) clearTimeout(timeoutId);
      resolve({
        success: code === 0 && !signal,
        code,
        signal,
        stdout,
        stderr,
        timedOut,
      });
    });

    child.on("error", (err) => {
      if (timeoutId) clearTimeout(timeoutId);
      resolve({
        success: false,
        code: null,
        signal: null,
        stdout,
        stderr,
        timedOut: false,
        error: err.message,
      });
    });
  });
}
