import { describe, expect, it, vi } from "vitest";

import { acquireYouTubeMedia } from "./acquire.js";

vi.mock("./acquire-retry-policy.js", async (importOriginal) => ({
  ...(await importOriginal()),
  computeAcquireBackoffMs: () => 0,
}));

const DRIVER_WATCH_URL = "https://www.youtube.com/watch?v=7zZy1QTvokM";
const WORK_DIR = "/tmp/fake-staged-work";

const INFO_JSON = JSON.stringify({
  id: "7zZy1QTvokM",
  title: "Driver Video",
  description: "desc",
  chapters: [],
  comments: [],
});

/**
 * @param {string[]} modes
 */
function createStagedSpawn(modes) {
  return async (_cmd, args) => {
    let mode = "video-only";
    if (args.includes("--skip-download")) {
      mode = "captions-only";
    } else if (args.includes("--write-subs")) {
      mode = "legacy-full";
    }
    modes.push(mode);
    return {
      success: true,
      code: 0,
      signal: null,
      stdout: "",
      stderr: "",
      timedOut: false,
    };
  };
}

const AUTO_ONLY_INFO_JSON = JSON.stringify({ id: "7zZy1QTvokM", title: "Driver Video", subtitles: {} });

const SPAWN_OK = { success: true, code: 0, signal: null, stdout: "", stderr: "", timedOut: false };

const SUBTITLE_429 = {
  success: false,
  code: 1,
  signal: null,
  stdout: "",
  stderr: "ERROR: Unable to download video subtitles for 'en': HTTP Error 429: Too Many Requests",
  timedOut: false,
};

const NO_THROTTLE = {
  withThrottle: (/** @type {() => Promise<unknown>} */ fn) => fn(),
  sleep: async () => {},
};

describe("acquireYouTubeMedia staged full mode", () => {
  it("runs video-only then captions-only for full acquire", async () => {
    /** @type {string[]} */
    const modes = [];
    const sleep = vi.fn(async () => {});

    const result = await acquireYouTubeMedia(
      DRIVER_WATCH_URL,
      { workDir: WORK_DIR, mode: "full", videoId: "7zZy1QTvokM" },
      {
        ...NO_THROTTLE,
        spawn: createStagedSpawn(modes),
        sleep,
        listFiles: async () => [
          `${WORK_DIR}/7zZy1QTvokM.mp4`,
          `${WORK_DIR}/7zZy1QTvokM.info.json`,
          `${WORK_DIR}/7zZy1QTvokM.en.vtt`,
        ],
        readFile: async (filePath) => {
          if (filePath.endsWith(".info.json")) return INFO_JSON;
          return "WEBVTT\n\n";
        },
      },
    );

    expect(result.success).toBe(true);
    expect(modes[0]).toBe("video-only");
    expect(modes[1]).toBe("captions-only");
    expect(sleep).toHaveBeenCalled();
    if (result.success) {
      expect(result.data?.acquireMetrics?.stagedAcquire).toBe(true);
      expect(result.data?.artifacts.videoPath).toContain(".mp4");
    }
  });

  it("fails when video-only pass fails", async () => {
    const result = await acquireYouTubeMedia(
      DRIVER_WATCH_URL,
      { workDir: WORK_DIR, mode: "full", videoId: "7zZy1QTvokM" },
      {
        ...NO_THROTTLE,
        spawn: async () => ({
          success: false,
          code: 1,
          signal: null,
          stdout: "",
          stderr: "ERROR: Video unavailable",
          timedOut: false,
        }),
        listFiles: async () => [],
        readFile: async () => INFO_JSON,
      },
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain("unavailable");
  });

  it("reports a rate-limited caption download as a rate limit, not as missing captions", async () => {
    const result = await acquireYouTubeMedia(
      DRIVER_WATCH_URL,
      { workDir: WORK_DIR, mode: "full", videoId: "7zZy1QTvokM" },
      {
        ...NO_THROTTLE,
        spawn: async (_cmd, args) =>
          args.includes("--skip-download")
            ? {
                success: false,
                code: 1,
                signal: null,
                stdout: "",
                stderr:
                  "ERROR: Unable to download video subtitles for 'en': HTTP Error 429: Too Many Requests",
                timedOut: false,
              }
            : { success: true, code: 0, signal: null, stdout: "", stderr: "", timedOut: false },
        listFiles: async () => [`${WORK_DIR}/7zZy1QTvokM.mp4`, `${WORK_DIR}/7zZy1QTvokM.info.json`],
        readFile: async () => INFO_JSON,
      },
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain("HTTP Error 429");
    expect(result.error).toContain("wait several minutes and retry");
    expect(result.error).not.toContain("ladder exhausted");
  });

  it("fetches en-orig alone when the full caption request fails on the translated en track", async () => {
    /** @type {string[]} */
    const subLangsRequested = [];
    const written = [`${WORK_DIR}/7zZy1QTvokM.mp4`];
    const result = await acquireYouTubeMedia(
      DRIVER_WATCH_URL,
      { workDir: WORK_DIR, mode: "full", videoId: "7zZy1QTvokM" },
      {
        ...NO_THROTTLE,
        spawn: async (_cmd, args) => {
          if (!args.includes("--skip-download")) return SPAWN_OK;
          const subLangs = args[args.indexOf("--sub-langs") + 1];
          subLangsRequested.push(subLangs);
          if (subLangs !== "en-orig") return SUBTITLE_429;
          written.push(`${WORK_DIR}/7zZy1QTvokM.en-orig.vtt`, `${WORK_DIR}/7zZy1QTvokM.info.json`);
          return SPAWN_OK;
        },
        listFiles: async () => [...written],
        readFile: async () => AUTO_ONLY_INFO_JSON,
      },
    );

    expect(result.success).toBe(true);
    expect(subLangsRequested.at(-1)).toBe("en-orig");
    if (result.success) {
      expect(result.data?.caption.path).toBe(`${WORK_DIR}/7zZy1QTvokM.en-orig.vtt`);
      expect(result.data?.artifacts.videoPath).toContain(".mp4");
    }
  });

  it("fetches en-orig alone when a transcript run fails on the translated en track", async () => {
    /** @type {string[]} */
    const subLangsRequested = [];
    /** @type {string[]} */
    const written = [];
    const result = await acquireYouTubeMedia(
      DRIVER_WATCH_URL,
      { workDir: WORK_DIR, mode: "transcript", videoId: "7zZy1QTvokM" },
      {
        ...NO_THROTTLE,
        spawn: async (_cmd, args) => {
          const subLangs = args[args.indexOf("--sub-langs") + 1];
          subLangsRequested.push(subLangs);
          if (subLangs !== "en-orig") return SUBTITLE_429;
          written.push(`${WORK_DIR}/7zZy1QTvokM.en-orig.vtt`, `${WORK_DIR}/7zZy1QTvokM.info.json`);
          return SPAWN_OK;
        },
        listFiles: async () => [...written],
        readFile: async () => AUTO_ONLY_INFO_JSON,
      },
    );

    expect(result.success).toBe(true);
    expect(subLangsRequested[0]).toBe("en.*,-live_chat");
    expect(subLangsRequested.at(-1)).toBe("en-orig");
    if (result.success) {
      expect(result.data?.caption.path).toBe(`${WORK_DIR}/7zZy1QTvokM.en-orig.vtt`);
      expect(result.data?.artifacts.videoPath).toBe("");
    }
  });

  it("does not retry for en-orig when the failure is not a subtitle download", async () => {
    /** @type {string[][]} */
    const calls = [];
    const result = await acquireYouTubeMedia(
      DRIVER_WATCH_URL,
      { workDir: WORK_DIR, mode: "transcript", videoId: "7zZy1QTvokM" },
      {
        ...NO_THROTTLE,
        spawn: async (_cmd, args) => {
          calls.push(args);
          return { ...SUBTITLE_429, stderr: "ERROR: Video unavailable" };
        },
        listFiles: async () => [],
        readFile: async () => INFO_JSON,
      },
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain("Video unavailable");
    expect(calls.every((args) => !args.includes("en-orig"))).toBe(true);
  });
});
