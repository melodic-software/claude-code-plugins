import fsSync from "node:fs";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  reclaimStaleSlot,
  refreshSlot,
  resolveMaxConcurrentAcquires,
  withAcquireThrottle,
} from "./acquire-throttle.js";

/**
 * @param {string} slotPath
 * @returns {Promise<void>}
 */
async function makeStale(slotPath) {
  await fs.mkdir(slotPath);
  const longAgo = new Date(Date.now() - 20 * 60 * 1000);
  await fs.utimes(slotPath, longAgo, longAgo);
}

/**
 * @param {string} dir
 * @returns {Promise<number>}
 */
async function countOccupiedSlots(dir) {
  const names = await fs.readdir(dir);
  return names.filter((name) => /^slot-\d+$/.test(name)).length;
}

/** @type {string} */
let baseDir;

beforeEach(async () => {
  baseDir = await fs.mkdtemp(path.join(os.tmpdir(), "acquire-throttle-test-"));
});

afterEach(async () => {
  await fs.rm(baseDir, { recursive: true, force: true });
});

describe("withAcquireThrottle", () => {
  it("runs fn while holding a slot, then releases it", async () => {
    const result = await withAcquireThrottle(async () => "done", {
      maxSlots: 1,
      heartbeatMs: 0,
      baseDir,
    });

    expect(result).toBe("done");
    expect(fsSync.existsSync(path.join(baseDir, "slot-0"))).toBe(false);
  });

  it("reclaims a stale slot and proceeds", async () => {
    const stale = path.join(baseDir, "slot-0");
    await makeStale(stale);

    const fn = vi.fn(async () => "reclaimed");
    const result = await withAcquireThrottle(fn, {
      maxSlots: 1,
      heartbeatMs: 0,
      baseDir,
      sleep: async () => {},
    });

    expect(fn).toHaveBeenCalledTimes(1);
    expect(result).toBe("reclaimed");
  });

  it("interleaved reclaim and acquire never exceed maxSlots", async () => {
    await makeStale(path.join(baseDir, "slot-0"));
    await makeStale(path.join(baseDir, "slot-1"));

    let current = 0;
    let peakFn = 0;
    let peakSlots = 0;

    const worker = () =>
      withAcquireThrottle(
        async () => {
          current += 1;
          peakFn = Math.max(peakFn, current);
          peakSlots = Math.max(peakSlots, await countOccupiedSlots(baseDir));
          await new Promise((resolve) => setTimeout(resolve, 25));
          current -= 1;
        },
        {
          maxSlots: 2,
          heartbeatMs: 0,
          baseDir,
          timeoutMs: 60_000,
          sleep: () => new Promise((resolve) => setTimeout(resolve, 5)),
        },
      );

    await Promise.all(Array.from({ length: 6 }, () => worker()));

    expect(peakFn).toBeGreaterThan(0);
    expect(peakFn).toBeLessThanOrEqual(2);
    expect(peakSlots).toBeLessThanOrEqual(2);
    expect(await countOccupiedSlots(baseDir)).toBe(0);
  });

  it("throws a descriptive timeout when a fresh slot stays held", async () => {
    const held = path.join(baseDir, "slot-0");
    await fs.mkdir(held); // fresh mtime — never stale during the test

    await expect(
      withAcquireThrottle(async () => "never", {
        maxSlots: 1,
        heartbeatMs: 0,
        baseDir,
        timeoutMs: 1000,
        sleep: async () => {},
      }),
    ).rejects.toThrow(/timed out after \d+ms/);
  });
});

describe("reclaimStaleSlot", () => {
  it("leaves a live slot in place", async () => {
    const slot = path.join(baseDir, "slot-0");
    await fs.mkdir(slot);
    await fs.writeFile(path.join(slot, "pid"), "live\n");

    expect(await reclaimStaleSlot(slot)).toBe(false);
    expect(await fs.readFile(path.join(slot, "pid"), "utf8")).toBe("live\n");
  });

  it("steals a stale leftover reclaim lock so a crashed reclaimer cannot wedge the slot", async () => {
    const slot = path.join(baseDir, "slot-0");
    await makeStale(slot);
    const reclaim = `${slot}.reclaim`;
    await makeStale(reclaim);

    expect(await reclaimStaleSlot(slot)).toBe(true);
    expect(fsSync.existsSync(slot)).toBe(false);
    expect(fsSync.existsSync(reclaim)).toBe(false);
  });

  it("concurrent steal of a leftover reclaim lock does not evict a live holder", async () => {
    const slot = path.join(baseDir, "slot-0");
    await makeStale(slot);
    const reclaim = `${slot}.reclaim`;
    await makeStale(reclaim);

    /** @type {boolean[]} */
    const removed = [];
    await Promise.all(
      Array.from({ length: 8 }, () =>
        (async () => {
          const won = await reclaimStaleSlot(slot);
          removed.push(won);
          if (won) {
            await fs.mkdir(slot);
            await fs.writeFile(path.join(slot, "pid"), "live\n");
          }
        })(),
      ),
    );

    expect(removed.filter(Boolean)).toHaveLength(1);
    expect(await fs.readFile(path.join(slot, "pid"), "utf8")).toBe("live\n");
    expect(await countOccupiedSlots(baseDir)).toBe(1);
  });

  it("does not evict a live holder that appears after the first of two reclaimers wins", async () => {
    const slot = path.join(baseDir, "slot-0");
    await makeStale(slot);

    /** @type {boolean[]} */
    const removed = [];
    await Promise.all(
      Array.from({ length: 8 }, () =>
        (async () => {
          const won = await reclaimStaleSlot(slot);
          removed.push(won);
          if (won) {
            await fs.mkdir(slot);
            await fs.writeFile(path.join(slot, "pid"), "live\n");
          }
        })(),
      ),
    );

    expect(removed.filter(Boolean)).toHaveLength(1);
    expect(await fs.readFile(path.join(slot, "pid"), "utf8")).toBe("live\n");
    expect(await countOccupiedSlots(baseDir)).toBe(1);
  });
});

describe("refreshSlot", () => {
  it("bumps a slot's mtime toward now", async () => {
    const slot = path.join(baseDir, "slot-0");
    await makeStale(slot);
    const before = (await fs.stat(slot)).mtimeMs;

    const ok = await refreshSlot(slot);

    expect(ok).toBe(true);
    expect((await fs.stat(slot)).mtimeMs).toBeGreaterThan(before);
  });

  it("returns false for a missing slot", async () => {
    expect(await refreshSlot(path.join(baseDir, "nope"))).toBe(false);
  });
});

describe("resolveMaxConcurrentAcquires env resolution", () => {
  afterEach(() => {
    delete process.env.VIDEO_DIGEST_MAX_CONCURRENT_ACQUIRES;
    delete process.env.YOUTUBE_MAX_CONCURRENT_ACQUIRES;
  });

  it("reads the new VIDEO_DIGEST_ name", () => {
    process.env.VIDEO_DIGEST_MAX_CONCURRENT_ACQUIRES = "2";
    expect(resolveMaxConcurrentAcquires()).toBe(2);
  });

  it("still honors the deprecated YOUTUBE_ name", () => {
    process.env.YOUTUBE_MAX_CONCURRENT_ACQUIRES = "3";
    expect(resolveMaxConcurrentAcquires()).toBe(3);
  });

  it("prefers the new name when both are set", () => {
    process.env.VIDEO_DIGEST_MAX_CONCURRENT_ACQUIRES = "2";
    process.env.YOUTUBE_MAX_CONCURRENT_ACQUIRES = "3";
    expect(resolveMaxConcurrentAcquires()).toBe(2);
  });
});
