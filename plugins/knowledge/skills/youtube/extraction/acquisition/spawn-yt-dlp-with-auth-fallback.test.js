import { describe, expect, it, vi } from "vitest";

import { spawnYtDlpWithAuthFallback } from "./spawn-yt-dlp-with-auth-fallback.js";

const BOT_ERROR = "ERROR: Sign in to confirm you're not a bot";

describe("spawnYtDlpWithAuthFallback", () => {
  it("retries with browser cookies after bot challenge", async () => {
    const spawn = vi
      .fn()
      .mockResolvedValueOnce({
        success: false,
        code: 1,
        signal: null,
        stdout: "",
        stderr: BOT_ERROR,
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

    const buildArgs = vi.fn((override = {}) => {
      if (override.cookiesFromBrowser) {
        return ["--cookies-from-browser", override.cookiesFromBrowser, "https://example.com"];
      }
      return ["https://example.com"];
    });

    const result = await spawnYtDlpWithAuthFallback(spawn, buildArgs, {
      env: {},
      cwd: "/tmp/work",
    });

    expect(result.success).toBe(true);
    expect(buildArgs).toHaveBeenCalledWith({ cookiesFromBrowser: expect.any(String) });
    expect(spawn.mock.calls.some((call) => call[1]?.includes("--cookies-from-browser"))).toBe(true);
  });

  it("does not retry cookies when explicit env is configured", async () => {
    const spawn = vi.fn().mockResolvedValue({
      success: false,
      code: 1,
      signal: null,
      stdout: "",
      stderr: BOT_ERROR,
      timedOut: false,
    });

    const buildArgs = () => ["--cookies-from-browser", "chrome", "https://example.com"];

    await spawnYtDlpWithAuthFallback(spawn, buildArgs, {
      env: { YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER: "chrome" },
    });

    expect(spawn).toHaveBeenCalledTimes(1);
  });

  it("returns non-bot failures without cookie fallback", async () => {
    const spawn = vi.fn().mockResolvedValue({
      success: false,
      code: 1,
      signal: null,
      stdout: "",
      stderr: "video unavailable",
      timedOut: false,
    });

    const buildArgs = () => ["https://example.com"];

    const result = await spawnYtDlpWithAuthFallback(spawn, buildArgs, { env: {} });

    expect(result.success).toBe(false);
    expect(spawn).toHaveBeenCalledTimes(1);
  });
});
