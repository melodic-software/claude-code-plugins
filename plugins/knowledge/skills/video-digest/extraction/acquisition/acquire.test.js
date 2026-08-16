import { afterEach, describe, expect, it } from "vitest";

import {
  acquireYouTubeMedia,
  listWorkDirFiles,
  resolveAcquirePhaseGapMs,
  resolveMediaArtifacts,
} from "./acquire.js";

const DRIVER_WATCH_URL = "https://www.youtube.com/watch?v=7zZy1QTvokM";
const DRIVER_VIDEO_ID = "7zZy1QTvokM";

describe("resolveMediaArtifacts", () => {
  it("collects caption, metadata, and video paths", () => {
    const artifacts = resolveMediaArtifacts(
      ["/tmp/7zZy1QTvokM.en.en-orig.vtt", "/tmp/7zZy1QTvokM.info.json", "/tmp/7zZy1QTvokM.mp4"],
      "7zZy1QTvokM",
    );

    expect(artifacts.captionPaths).toHaveLength(1);
    expect(artifacts.metadataPath).toContain(".info.json");
    expect(artifacts.videoPath).toContain(".mp4");
  });
});

const NO_THROTTLE = { withThrottle: (/** @type {() => Promise<unknown>} */ fn) => fn() };

describe("acquireYouTubeMedia", () => {
  it("uses injected spawn and file readers without real yt-dlp", async () => {
    const workDir = "/tmp/fake-work";
    const infoJson = JSON.stringify({
      id: "7zZy1QTvokM",
      title: "Driver Video",
      description: "desc",
      chapters: [],
      comments: [],
    });

    const result = await acquireYouTubeMedia(
      DRIVER_WATCH_URL,
      { workDir, mode: "transcript", videoId: DRIVER_VIDEO_ID },
      {
        ...NO_THROTTLE,
        spawn: async () => ({
          success: true,
          code: 0,
          signal: null,
          stdout: "",
          stderr: "",
          timedOut: false,
        }),
        listFiles: async () => [
          `${workDir}/7zZy1QTvokM.en.en-orig.vtt`,
          `${workDir}/7zZy1QTvokM.info.json`,
        ],
        readFile: async (filePath) => {
          if (filePath.endsWith(".info.json")) return infoJson;
          return "WEBVTT\n\n";
        },
      },
    );

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data?.caption.rung).toBe("auto-en");
      expect(result.data?.metadata.title).toBe("Driver Video");
      expect(result.data?.artifacts.videoPath).toBe("");
    }
  });

  it("surfaces caption ladder failure", async () => {
    const result = await acquireYouTubeMedia(
      DRIVER_WATCH_URL,
      { workDir: "/tmp/fake-work", mode: "transcript", videoId: DRIVER_VIDEO_ID },
      {
        ...NO_THROTTLE,
        spawn: async () => ({
          success: true,
          code: 0,
          signal: null,
          stdout: "",
          stderr: "",
          timedOut: false,
        }),
        listFiles: async () => ["/tmp/fake-work/7zZy1QTvokM.info.json"],
        readFile: async () => JSON.stringify({ id: "7zZy1QTvokM", title: "Driver Video" }),
      },
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain("ladder exhausted");
  });
});

describe("listWorkDirFiles", () => {
  it("lists files in the real temp directory for integration smoke", async () => {
    const files = await listWorkDirFiles("/tmp");
    expect(Array.isArray(files)).toBe(true);
  });
});

describe("resolveAcquirePhaseGapMs env resolution", () => {
  afterEach(() => {
    delete process.env.VIDEO_DIGEST_ACQUIRE_PHASE_GAP_SEC;
    delete process.env.YOUTUBE_ACQUIRE_PHASE_GAP_SEC;
  });

  it("reads the new VIDEO_DIGEST_ name", () => {
    process.env.VIDEO_DIGEST_ACQUIRE_PHASE_GAP_SEC = "1.5";
    expect(resolveAcquirePhaseGapMs()).toBe(1500);
  });

  it("still honors the deprecated YOUTUBE_ name", () => {
    process.env.YOUTUBE_ACQUIRE_PHASE_GAP_SEC = "2";
    expect(resolveAcquirePhaseGapMs()).toBe(2000);
  });

  it("prefers the new name when both are set", () => {
    process.env.VIDEO_DIGEST_ACQUIRE_PHASE_GAP_SEC = "1";
    process.env.YOUTUBE_ACQUIRE_PHASE_GAP_SEC = "9";
    expect(resolveAcquirePhaseGapMs()).toBe(1000);
  });
});
