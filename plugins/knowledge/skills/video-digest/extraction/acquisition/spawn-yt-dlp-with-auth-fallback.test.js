import { describe, expect, it, vi } from "vitest";

import { adapter as youtubeAdapter } from "../adapters/youtube.js";
import { adapterSourceDeclarations } from "./acquire.js";
import { spawnYtDlpWithAuthFallback } from "./spawn-yt-dlp-with-auth-fallback.js";

const BOT_ERROR = "ERROR: Sign in to confirm you're not a bot";

/** The production derivation of a fallback-capable source's classification. */
const FALLBACK_SOURCE = adapterSourceDeclarations(youtubeAdapter);

/**
 * @param {string} stderr
 * @returns {import('@melodic/video-digestion/shared/process').SpawnResult}
 */
const failedSpawn = (stderr) => ({
  success: false,
  code: 1,
  signal: null,
  stdout: "",
  stderr,
  timedOut: false,
});

describe("spawnYtDlpWithAuthFallback", () => {
  it("retries with browser cookies after login-required classification", async () => {
    const spawn = vi
      .fn()
      .mockResolvedValueOnce(failedSpawn(BOT_ERROR))
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
      source: FALLBACK_SOURCE,
    });

    expect(result.success).toBe(true);
    expect(buildArgs).toHaveBeenCalledWith({ cookiesFromBrowser: expect.any(String) });
    expect(spawn.mock.calls.some((call) => call[1]?.includes("--cookies-from-browser"))).toBe(true);
  });

  it("never iterates browser profiles when the source lacks the capability", async () => {
    const spawn = vi.fn().mockResolvedValue(failedSpawn(BOT_ERROR));

    const buildArgs = () => ["https://example.com"];

    const result = await spawnYtDlpWithAuthFallback(spawn, buildArgs, {
      env: {},
      source: { ...FALLBACK_SOURCE, allowBrowserCookieProfileFallback: false },
    });

    expect(result.success).toBe(false);
    expect(spawn).toHaveBeenCalledTimes(1);
    expect(spawn.mock.calls.some((call) => call[1]?.includes("--cookies-from-browser"))).toBe(
      false,
    );
  });

  it("does not retry cookies when explicit env is configured", async () => {
    const spawn = vi.fn().mockResolvedValue(failedSpawn(BOT_ERROR));

    const buildArgs = () => ["--cookies-from-browser", "chrome", "https://example.com"];

    await spawnYtDlpWithAuthFallback(spawn, buildArgs, {
      env: { VIDEO_DIGEST_YT_DLP_COOKIES_FROM_BROWSER: "chrome" },
      source: FALLBACK_SOURCE,
    });

    expect(spawn).toHaveBeenCalledTimes(1);
  });

  it("advances past Edge and Chrome cookie-extraction failures to Firefox on Windows", async () => {
    // stderr lines as yt-dlp prints them when Chrome holds its cookie database open.
    const stderrByBrowser = {
      edge: "ERROR: Failed to decrypt with DPAPI. See  https://github.com/yt-dlp/yt-dlp/issues/10927  for more info",
      chrome:
        "ERROR: Could not copy Chrome cookie database. See  https://github.com/yt-dlp/yt-dlp/issues/7271  for more info",
    };
    const spawn = vi.fn(async (_command, args) => {
      const index = args.indexOf("--cookies-from-browser");
      if (index === -1) return failedSpawn(BOT_ERROR);
      const stderr = stderrByBrowser[args[index + 1]];
      return stderr
        ? failedSpawn(stderr)
        : { success: true, code: 0, signal: null, stdout: "", stderr: "", timedOut: false };
    });
    const buildArgs = (override = {}) =>
      override.cookiesFromBrowser
        ? ["--cookies-from-browser", override.cookiesFromBrowser, "https://example.com"]
        : ["https://example.com"];

    const platform = Object.getOwnPropertyDescriptor(process, "platform");
    Object.defineProperty(process, "platform", { value: "win32" });
    try {
      const result = await spawnYtDlpWithAuthFallback(spawn, buildArgs, {
        env: {},
        source: FALLBACK_SOURCE,
      });

      expect(result.success).toBe(true);
      const browsersTried = spawn.mock.calls
        .map((call) => call[1])
        .filter((args) => args.includes("--cookies-from-browser"))
        .map((args) => args[args.indexOf("--cookies-from-browser") + 1]);
      expect(browsersTried).toEqual(["edge", "chrome", "firefox"]);
    } finally {
      Object.defineProperty(process, "platform", platform);
    }
  });

  it("returns non-bot failures without cookie fallback", async () => {
    const spawn = vi.fn().mockResolvedValue(failedSpawn("video unavailable"));

    const buildArgs = () => ["https://example.com"];

    const result = await spawnYtDlpWithAuthFallback(spawn, buildArgs, {
      env: {},
      source: FALLBACK_SOURCE,
    });

    expect(result.success).toBe(false);
    expect(spawn).toHaveBeenCalledTimes(1);
  });
});
