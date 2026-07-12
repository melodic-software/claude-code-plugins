/**
 * Process-wide throttle for concurrent yt-dlp acquisition runs.
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { sleepMs } from "./acquire-retry-policy.js";

const DEFAULT_MAX_CONCURRENT = 1;
const ABSOLUTE_MAX_CONCURRENT = 3;
const LOCK_STALE_MS = 15 * 60 * 1000;
const LOCK_POLL_MS = 250;

/**
 * @returns {number}
 */
export function resolveMaxConcurrentAcquires() {
  const raw = process.env.YOUTUBE_MAX_CONCURRENT_ACQUIRES;
  if (!raw) return DEFAULT_MAX_CONCURRENT;
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed < 1) return DEFAULT_MAX_CONCURRENT;
  return Math.min(parsed, ABSOLUTE_MAX_CONCURRENT);
}

/**
 * @returns {string}
 */
function lockDirPath() {
  return path.join(os.tmpdir(), "youtube-extraction-acquire-locks");
}

/**
 * @param {string} slotPath
 * @returns {Promise<boolean>}
 */
async function tryAcquireSlot(slotPath) {
  try {
    await fs.mkdir(slotPath);
    await fs.writeFile(path.join(slotPath, "pid"), `${process.pid}\n`, "utf8");
    return true;
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "EEXIST") {
      return false;
    }
    throw error;
  }
}

/**
 * @param {string} slotPath
 * @returns {Promise<void>}
 */
async function releaseSlot(slotPath) {
  await fs.rm(slotPath, { recursive: true, force: true });
}

/**
 * @param {string} slotPath
 * @returns {Promise<boolean>}
 */
async function isStaleSlot(slotPath) {
  try {
    const stat = await fs.stat(slotPath);
    return Date.now() - stat.mtimeMs > LOCK_STALE_MS;
  } catch {
    return true;
  }
}

/**
 * Run `fn` while holding one of `maxSlots` file-based acquire slots.
 *
 * @template T
 * @param {() => Promise<T>} fn
 * @param {object} [options]
 * @param {number} [options.maxSlots]
 * @param {typeof sleepMs} [options.sleep]
 * @returns {Promise<T>}
 */
export async function withAcquireThrottle(
  fn,
  { maxSlots = resolveMaxConcurrentAcquires(), sleep = sleepMs } = {},
) {
  const baseDir = lockDirPath();
  await fs.mkdir(baseDir, { recursive: true });

  /** @type {string[]} */
  const slotPaths = Array.from({ length: maxSlots }, (_, index) =>
    path.join(baseDir, `slot-${index}`),
  );

  // biome-ignore lint/suspicious/noUnnecessaryConditions: intentional lock poll loop
  while (true) {
    for (const slotPath of slotPaths) {
      if (await tryAcquireSlot(slotPath)) {
        try {
          return await fn();
        } finally {
          await releaseSlot(slotPath);
        }
      }

      if (await isStaleSlot(slotPath)) {
        await releaseSlot(slotPath);
      }
    }

    await sleep(LOCK_POLL_MS);
  }
}
