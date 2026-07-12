import { describe, expect, it, vi } from "vitest";

import { orchestrateWatching } from "./orchestrate-watching.js";

describe("orchestrateWatching", () => {
  it("composes probe, scene-detect, anchors, and contact sheets with DI fakes", async () => {
    const extractSceneFrames = vi.fn(async () => ({
      method: "scene-detection",
      count: 3,
      sceneCount: 3,
      frames: [
        { path: "/tmp/scene_0001.png", file: "scene_0001.png", timestampSec: null },
        { path: "/tmp/scene_0002.png", file: "scene_0002.png", timestampSec: null },
        { path: "/tmp/scene_0003.png", file: "scene_0003.png", timestampSec: null },
      ],
    }));

    const deduplicateFrames = vi.fn(async (paths) => ({
      frames: paths,
      unique: paths.map((framePath, index) => ({
        path: framePath,
        file: `scene_${String(index + 1).padStart(4, "0")}.png`,
        timestampSec: null,
      })),
      total: paths.length,
      duplicates: 0,
    }));

    const createContactSheet = vi.fn(async (paths, outputPath) => ({
      outputPath,
      inputPaths: paths,
      tile: "4x4",
      frameCount: paths.length,
    }));

    const probeVideoDuration = vi.fn(async () => ({ durationSec: 120, formatName: "mp4" }));
    const extractAnchorFrames = vi.fn(async () => [
      { path: "/tmp/anchor_0001.png", file: "anchor_0001.png", timestampSec: 60, isInterval: true },
    ]);

    const state = await orchestrateWatching(
      {
        videoPath: "/tmp/video.mp4",
        framesDir: "/tmp/frames",
        contactSheetsDir: "/tmp/sheets",
        cues: [{ startSec: 10, endSec: 20, text: "Let me show you this code demo" }],
      },
      {
        extractSceneFrames,
        deduplicateFrames,
        createContactSheet,
        probeVideoDuration,
        extractAnchorFrames,
        log: { info: vi.fn(), warn: vi.fn() },
      },
    );

    expect(probeVideoDuration).toHaveBeenCalledOnce();
    expect(extractSceneFrames).toHaveBeenCalledOnce();
    expect(extractAnchorFrames).toHaveBeenCalledOnce();
    expect(state.selectedFrames.length).toBeGreaterThan(0);
    expect(state.densificationWindows.length).toBeGreaterThan(0);
    expect(state.coveragePlan).toBeDefined();
    expect(state.contactSheets).toHaveLength(1);
    expect(state.overCap).toBe(false);
  });
});
