import { describe, expect, it } from "vitest";

import {
  acquireYouTubeMedia,
  extractVideoId,
  listWorkDirFiles,
  resolveMediaArtifacts,
} from "./acquire.js";

const DRIVER_WATCH_URL = "https://www.youtube.com/watch?v=7zZy1QTvokM";
const DRIVER_SHORT_URL = "https://youtu.be/7zZy1QTvokM";
const DRIVER_LIVE_URL = "https://www.youtube.com/live/abcdefghijk";
const DRIVER_LIVE_VIDEO_ID = "abcdefghijk";

describe("extractVideoId", () => {
  it("parses watch URLs", () => {
    expect(extractVideoId(DRIVER_WATCH_URL)).toBe("7zZy1QTvokM");
  });

  it("parses youtu.be URLs", () => {
    expect(extractVideoId(DRIVER_SHORT_URL)).toBe("7zZy1QTvokM");
  });

  it("parses youtube.com/live URLs", () => {
    expect(extractVideoId(DRIVER_LIVE_URL)).toBe(DRIVER_LIVE_VIDEO_ID);
  });

  it("parses youtube.com/shorts URLs", () => {
    expect(extractVideoId("https://www.youtube.com/shorts/7zZy1QTvokM")).toBe("7zZy1QTvokM");
  });
});

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
      { workDir, mode: "transcript" },
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
      { workDir: "/tmp/fake-work", mode: "transcript" },
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
