import { describe, expect, it, vi } from "vitest";

import { acquireYouTubeMedia } from "./acquire.js";

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
  /** @type {string[]} */
  const seen = [];
  return async (_cmd, args) => {
    const skipIdx = args.indexOf("--skip-download");
    const hasSubs = args.includes("--write-subs");
    const mode = skipIdx !== -1 ? "captions-only" : hasSubs ? "legacy-full" : "video-only";
    seen.push(mode);
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
      { workDir: WORK_DIR, mode: "full" },
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
      { workDir: WORK_DIR, mode: "full" },
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
});
