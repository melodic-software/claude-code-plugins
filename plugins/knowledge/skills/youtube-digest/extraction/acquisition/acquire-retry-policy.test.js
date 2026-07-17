import { describe, expect, it, vi } from "vitest";

import { computeAcquireBackoffMs, isRetryableAcquireError } from "./acquire-retry-policy.js";
import { spawnWithAcquireRetry } from "./acquire-with-retry.js";

describe("isRetryableAcquireError", () => {
  it("matches HTTP 429 subtitle failures", () => {
    expect(isRetryableAcquireError("HTTP Error 429: Too Many Requests")).toBe(true);
  });

  it("rejects ladder exhausted errors", () => {
    expect(isRetryableAcquireError("caption ladder exhausted")).toBe(false);
  });
});

describe("computeAcquireBackoffMs", () => {
  it("grows with attempt index", () => {
    const first = computeAcquireBackoffMs(0, { baseMs: 1000, maxMs: 60_000 });
    const second = computeAcquireBackoffMs(1, { baseMs: 1000, maxMs: 60_000 });
    expect(second).toBeGreaterThanOrEqual(first);
  });
});

describe("spawnWithAcquireRetry", () => {
  it("retries on 429 then succeeds", async () => {
    const spawn = vi
      .fn()
      .mockResolvedValueOnce({
        success: false,
        code: 1,
        signal: null,
        stdout: "",
        stderr: "HTTP Error 429: Too Many Requests",
        timedOut: false,
      })
      .mockResolvedValueOnce({
        success: true,
        code: 0,
        signal: null,
        stdout: "",
        stderr: "",
        timedOut: false,
      });

    const result = await spawnWithAcquireRetry(spawn, "yt-dlp", ["--version"], {
      sleep: async () => {},
    });

    expect(result.success).toBe(true);
    expect(spawn).toHaveBeenCalledTimes(2);
  });
});
