import fsSync from "node:fs";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { refreshSlot, withAcquireThrottle } from "./acquire-throttle.js";

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
    await fs.mkdir(stale);
    const longAgo = new Date(Date.now() - 20 * 60 * 1000); // older than the 15-min TTL
    await fs.utimes(stale, longAgo, longAgo);

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

describe("refreshSlot", () => {
  it("bumps a slot's mtime toward now", async () => {
    const slot = path.join(baseDir, "slot-0");
    await fs.mkdir(slot);
    const longAgo = new Date(Date.now() - 20 * 60 * 1000);
    await fs.utimes(slot, longAgo, longAgo);
    const before = (await fs.stat(slot)).mtimeMs;

    const ok = await refreshSlot(slot);

    expect(ok).toBe(true);
    expect((await fs.stat(slot)).mtimeMs).toBeGreaterThan(before);
  });

  it("returns false for a missing slot", async () => {
    expect(await refreshSlot(path.join(baseDir, "nope"))).toBe(false);
  });
});
