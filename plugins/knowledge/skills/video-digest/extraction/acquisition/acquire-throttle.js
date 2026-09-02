/**
 * Process-wide throttle for concurrent yt-dlp acquisition runs.
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { resolveEnvWithLegacy } from "../lib/env-compat.js";
import { sleepMs } from "./acquire-retry-policy.js";

const DEFAULT_MAX_CONCURRENT = 1;
const ABSOLUTE_MAX_CONCURRENT = 3;
const LOCK_STALE_MS = 15 * 60 * 1000;
const LOCK_POLL_MS = 250;
// Refresh a held slot's mtime well inside the stale TTL so a long-running
// acquisition is never misclassified as stale and reclaimed by a peer.
const SLOT_HEARTBEAT_MS = 5 * 60 * 1000;

/**
 * @returns {number}
 */
export function resolveMaxConcurrentAcquires() {
  const raw = resolveEnvWithLegacy(
    "VIDEO_DIGEST_MAX_CONCURRENT_ACQUIRES",
    "YOUTUBE_MAX_CONCURRENT_ACQUIRES",
  );
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
 * @param {unknown} error
 * @returns {boolean}
 */
function isAlreadyExists(error) {
  return Boolean(
    error && typeof error === "object" && "code" in error && error.code === "EEXIST",
  );
}

/**
 * @param {string} dirPath
 * @returns {Promise<boolean>}
 */
async function tryMkdirExclusive(dirPath) {
  try {
    await fs.mkdir(dirPath);
    return true;
  } catch (error) {
    if (isAlreadyExists(error)) {
      return false;
    }
    throw error;
  }
}

/**
 * @param {string} slotPath
 * @returns {Promise<boolean>}
 */
async function tryAcquireSlot(slotPath) {
  if (!(await tryMkdirExclusive(slotPath))) {
    return false;
  }
  await fs.writeFile(path.join(slotPath, "pid"), `${process.pid}\n`, "utf8");
  return true;
}

/**
 * @param {string} slotPath
 * @returns {Promise<void>}
 */
async function releaseSlot(slotPath) {
  await fs.rm(slotPath, { recursive: true, force: true });
}

/**
 * Missing paths count as stale so a vanished slot is treated as free.
 *
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
 * Exclusive create of `slotPath.reclaim`. A leftover lock older than the
 * slot TTL is stolen so a crashed reclaimer cannot wedge the slot forever.
 *
 * @param {string} reclaimPath
 * @returns {Promise<boolean>}
 */
async function tryAcquireReclaimLock(reclaimPath) {
  if (await tryMkdirExclusive(reclaimPath)) {
    return true;
  }
  if (!(await isStaleSlot(reclaimPath))) {
    return false;
  }
  await fs.rm(reclaimPath, { recursive: true, force: true });
  return tryMkdirExclusive(reclaimPath);
}

/**
 * Remove a stale slot only after winning an exclusive reclaim lock and
 * re-statting. A bare rm between `isStaleSlot` and `releaseSlot` lets two
 * reclaimers both pass the stale check; the first rm frees the path, a peer
 * `mkdir`s a live holder, and the second rm evicts that holder so a third
 * acquire exceeds `maxSlots`.
 *
 * Rename-then-rm of the live path is unsafe: the original holder still
 * `releaseSlot(slot-N)` in `finally` and would delete the new occupant.
 *
 * @param {string} slotPath
 * @returns {Promise<boolean>} true when this caller removed the slot
 */
export async function reclaimStaleSlot(slotPath) {
  if (!(await isStaleSlot(slotPath))) {
    return false;
  }

  const reclaimPath = `${slotPath}.reclaim`;
  if (!(await tryAcquireReclaimLock(reclaimPath))) {
    return false;
  }

  try {
    try {
      const stat = await fs.stat(slotPath);
      if (Date.now() - stat.mtimeMs <= LOCK_STALE_MS) {
        return false;
      }
    } catch {
      return false;
    }
    await fs.rm(slotPath, { recursive: true, force: true });
    return true;
  } finally {
    await fs.rm(reclaimPath, { recursive: true, force: true });
  }
}

/**
 * Bump a held slot's modification time to "now" so peers see it as live.
 *
 * @param {string} slotPath
 * @returns {Promise<boolean>} true when the mtime was refreshed
 */
export async function refreshSlot(slotPath) {
  const now = new Date();
  try {
    await fs.utimes(slotPath, now, now);
    return true;
  } catch {
    return false;
  }
}

/**
 * Start an interval that heartbeats a held slot's mtime until stopped.
 *
 * @param {string} slotPath
 * @param {number} intervalMs
 * @returns {{ stop: () => void }}
 */
function startSlotHeartbeat(slotPath, intervalMs) {
  if (!intervalMs || intervalMs <= 0) {
    return { stop() {} };
  }
  const timer = setInterval(() => {
    void refreshSlot(slotPath);
  }, intervalMs);
  if (typeof timer.unref === "function") {
    timer.unref();
  }
  return {
    stop() {
      clearInterval(timer);
    },
  };
}

/**
 * Run `fn` while holding one of `maxSlots` file-based acquire slots.
 *
 * @template T
 * @param {() => Promise<T>} fn
 * @param {object} [options]
 * @param {number} [options.maxSlots]
 * @param {typeof sleepMs} [options.sleep]
 * @param {number|null} [options.timeoutMs] - throw if total slot-wait exceeds this; null = wait forever
 * @param {number} [options.heartbeatMs] - interval to refresh the held slot's mtime
 * @param {string} [options.baseDir] - lock directory (seam for tests)
 * @returns {Promise<T>}
 */
export async function withAcquireThrottle(
  fn,
  {
    maxSlots = resolveMaxConcurrentAcquires(),
    sleep = sleepMs,
    timeoutMs = null,
    heartbeatMs = SLOT_HEARTBEAT_MS,
    baseDir = lockDirPath(),
  } = {},
) {
  await fs.mkdir(baseDir, { recursive: true });

  /** @type {string[]} */
  const slotPaths = Array.from({ length: maxSlots }, (_, index) =>
    path.join(baseDir, `slot-${index}`),
  );

  /**
   * @param {string} slotPath
   * @returns {Promise<T>}
   */
  const runHeld = async (slotPath) => {
    const heartbeat = startSlotHeartbeat(slotPath, heartbeatMs);
    try {
      return await fn();
    } finally {
      heartbeat.stop();
      await releaseSlot(slotPath);
    }
  };

  let waitedMs = 0;

  // biome-ignore lint/suspicious/noUnnecessaryConditions: intentional lock poll loop
  while (true) {
    for (const slotPath of slotPaths) {
      if (await tryAcquireSlot(slotPath)) {
        return await runHeld(slotPath);
      }

      if (await isStaleSlot(slotPath)) {
        await reclaimStaleSlot(slotPath);
        if (await tryAcquireSlot(slotPath)) {
          return await runHeld(slotPath);
        }
      }
    }

    if (timeoutMs != null && waitedMs >= timeoutMs) {
      throw new Error(
        `withAcquireThrottle: timed out after ${waitedMs}ms waiting for an acquire slot (maxSlots=${maxSlots})`,
      );
    }

    await sleep(LOCK_POLL_MS);
    waitedMs += LOCK_POLL_MS;
  }
}
