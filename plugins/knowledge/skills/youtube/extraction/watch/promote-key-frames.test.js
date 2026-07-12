import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  parsePromotionPair,
  promoteKeyFrames,
  sanitizeKeyFrameDestName,
} from "./promote-key-frames.js";

describe("parsePromotionPair", () => {
  it("parses posix source:dest pairs", () => {
    expect(parsePromotionPair("/tmp/frame.png:slide.png")).toEqual({
      sourcePath: "/tmp/frame.png",
      destName: "slide.png",
    });
  });

  it("parses Windows drive-letter paths with colon separator", () => {
    expect(parsePromotionPair("C:/tmp/frame.png:slide.png")).toEqual({
      sourcePath: "C:/tmp/frame.png",
      destName: "slide.png",
    });
  });

  it("parses pipe-separated pairs for backslash Windows paths", () => {
    expect(parsePromotionPair("C:\\tmp\\frame.png|slide.png")).toEqual({
      sourcePath: "C:\\tmp\\frame.png",
      destName: "slide.png",
    });
  });
});

describe("sanitizeKeyFrameDestName", () => {
  it("should append .jpg when extension missing", () => {
    expect(sanitizeKeyFrameDestName("claude-md-sections")).toBe("claude-md-sections.jpg");
  });

  it("should keep existing image extension", () => {
    expect(sanitizeKeyFrameDestName("slide-01.png")).toBe("slide-01.png");
  });

  it("should preserve frames tier prefix", () => {
    expect(sanitizeKeyFrameDestName("frames/routines-triggers-slide.png")).toBe(
      "frames/routines-triggers-slide.png",
    );
  });

  it("should preserve presentation tier prefix", () => {
    expect(sanitizeKeyFrameDestName("presentation/keynote-title-slide.png")).toBe(
      "presentation/keynote-title-slide.png",
    );
  });
});

describe("promoteKeyFrames", () => {
  let sliceDir;
  let sourcePath;

  beforeEach(() => {
    sliceDir = mkdtempSync(join(tmpdir(), "slice-"));
    sourcePath = join(sliceDir, "media", "frames", "scene_0001.png");
    mkdirSync(join(sliceDir, "media", "frames"), { recursive: true });
    writeFileSync(sourcePath, "frame");
  });

  afterEach(() => {
    rmSync(sliceDir, { recursive: true, force: true });
  });

  it("should copy curated frames into the key-frames lane", async () => {
    const promoted = await promoteKeyFrames(sliceDir, [
      { sourcePath: "media/frames/scene_0001.png", destName: "claude-md-walkthrough.png" },
    ]);

    expect(promoted).toHaveLength(1);
    expect(existsSync(join(sliceDir, "key-frames", "claude-md-walkthrough.png"))).toBe(true);
  });
});
