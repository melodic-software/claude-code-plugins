import { describe, expect, it, vi } from "vitest";

import { orchestrateWatching } from "./orchestrate-watching.js";

/**
 * Fake deduplicator following the real one's contract: a bare path carries no
 * time, a frame keeps its time fields; nothing is marked duplicate.
 */
function passThroughDedup() {
  return vi.fn(async (inputs) => {
    const unique = inputs.map((input) =>
      typeof input === "string"
        ? { path: input, file: input.split("/").pop(), timestampSec: null }
        : { ...input },
    );
    return { frames: unique, unique, total: unique.length, duplicates: 0 };
  });
}

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

    const deduplicateFrames = passThroughDedup();

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

  it("preserves exact anchor timestamps through the second dedup pass", async () => {
    const extractSceneFrames = vi.fn(async () => ({
      method: "scene-detection",
      count: 2,
      sceneCount: 2,
      frames: [
        { path: "/tmp/scene_0001.png", file: "scene_0001.png", timestampSec: null },
        { path: "/tmp/scene_0002.png", file: "scene_0002.png", timestampSec: null },
      ],
    }));

    const deduplicateFrames = passThroughDedup();

    const createContactSheet = vi.fn(async (paths, outputPath) => ({
      outputPath,
      inputPaths: paths,
      frameCount: paths.length,
    }));
    const probeVideoDuration = vi.fn(async () => ({ durationSec: 120, formatName: "mp4" }));
    // 73s is deliberately off the ordinal grid (duration/frameCount) so a
    // fabricated timestamp could never coincidentally equal it.
    const extractAnchorFrames = vi.fn(async () => [
      { path: "/tmp/anchor_0073.png", file: "anchor_0073.png", timestampSec: 73, isInterval: false },
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

    const anchor = state.uniqueFrames.find((frame) => frame.path === "/tmp/anchor_0073.png");
    expect(anchor?.timestampSec).toBe(73);
  });

  it("keeps measured scene times through both dedup passes and leaves an untimed frame null", async () => {
    const extractSceneFrames = vi.fn(async () => ({
      method: "scene-detection",
      count: 3,
      sceneCount: 3,
      frames: [
        {
          path: "/tmp/scene_0001.png",
          file: "scene_0001.png",
          timestampSec: 12.5,
          timestampSource: "scene-detection",
        },
        {
          path: "/tmp/scene_0002.png",
          file: "scene_0002.png",
          timestampSec: 47.25,
          timestampSource: "scene-detection",
        },
        { path: "/tmp/scene_0003.png", file: "scene_0003.png", timestampSec: null },
      ],
    }));

    const deduplicateFrames = passThroughDedup();

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
        createContactSheet: vi.fn(async (paths, outputPath) => ({
          outputPath,
          inputPaths: paths,
          frameCount: paths.length,
        })),
        probeVideoDuration: vi.fn(async () => ({ durationSec: 120, formatName: "mp4" })),
        extractAnchorFrames: vi.fn(async () => [
          { path: "/tmp/anchor_0073.png", file: "anchor_0073.png", timestampSec: 73 },
        ]),
        log: { info: vi.fn(), warn: vi.fn() },
      },
    );

    const byFile = Object.fromEntries(state.uniqueFrames.map((frame) => [frame.file, frame]));
    expect(byFile["scene_0001.png"].timestampSec).toBe(12.5);
    expect(byFile["scene_0002.png"].timestampSec).toBe(47.25);
    expect(byFile["scene_0003.png"].timestampSec).toBeNull();
    expect(byFile["anchor_0073.png"].timestampSource).toBe("anchor");
  });

  /**
   * Scene frames at 0s and 200s of a 300s video plus one untimed frame, which
   * keeps the scene yield high enough that no stratified pass runs, and no cues,
   * so no densification or cue anchors are planned.
   *
   * @param {{ maxFrameGapSec?: number }} [options]
   */
  async function watchSparseScenes(options = {}) {
    const extractAnchorFrames = vi.fn(async (_videoPath, _dir, timestampsSec) =>
      timestampsSec.map((t) => ({
        path: `/tmp/anchor_${t}.png`,
        file: `anchor_${t}.png`,
        timestampSec: t,
        isInterval: true,
      })),
    );
    const state = await orchestrateWatching(
      {
        videoPath: "/tmp/video.mp4",
        framesDir: "/tmp/frames",
        contactSheetsDir: "/tmp/sheets",
        cues: [],
        ...options,
      },
      {
        extractSceneFrames: vi.fn(async () => ({
          method: "scene-detection",
          count: 3,
          sceneCount: 3,
          frames: [
            { path: "/tmp/scene_0001.png", file: "scene_0001.png", timestampSec: 0 },
            { path: "/tmp/scene_0002.png", file: "scene_0002.png", timestampSec: 200 },
            { path: "/tmp/scene_0003.png", file: "scene_0003.png", timestampSec: null },
          ],
        })),
        deduplicateFrames: passThroughDedup(),
        createContactSheet: vi.fn(async (paths, outputPath) => ({
          outputPath,
          inputPaths: paths,
          frameCount: paths.length,
        })),
        probeVideoDuration: vi.fn(async () => ({ durationSec: 300, formatName: "mp4" })),
        extractAnchorFrames,
        log: { info: vi.fn(), warn: vi.fn() },
      },
    );
    const requested = extractAnchorFrames.mock.calls.flatMap((call) => call[2]);
    return { state, requested };
  }

  it("extracts a frame inside a gap between scene frames longer than the maximum gap", async () => {
    const { state, requested } = await watchSparseScenes();

    expect(state.coveragePlan.forceStratifiedPass).toBe(false);
    expect(requested.some((t) => t > 0 && t < 200)).toBe(true);
    const filled = state.uniqueFrames.find(
      (frame) => frame.timestampSec > 0 && frame.timestampSec < 200,
    );
    expect(filled?.timestampSource).toBe("anchor");
  });

  it("never counts an untimed frame as coverage of a gap", async () => {
    // Timed frames at 0s and 100s of 300s leave 100-300s uncovered. The two
    // untimed frames (null time, and no time field) have no place on the
    // timeline, so they must not hide that gap.
    const extractAnchorFrames = vi.fn(async (_videoPath, _dir, timestampsSec) =>
      timestampsSec.map((t) => ({
        path: `/tmp/anchor_${t}.png`,
        file: `anchor_${t}.png`,
        timestampSec: t,
      })),
    );
    await orchestrateWatching(
      {
        videoPath: "/tmp/video.mp4",
        framesDir: "/tmp/frames",
        contactSheetsDir: "/tmp/sheets",
        cues: [],
      },
      {
        extractSceneFrames: vi.fn(async () => ({
          method: "scene-detection",
          count: 4,
          sceneCount: 4,
          frames: [
            { path: "/tmp/scene_0001.png", file: "scene_0001.png", timestampSec: 0 },
            { path: "/tmp/scene_0002.png", file: "scene_0002.png", timestampSec: 100 },
            { path: "/tmp/scene_0003.png", file: "scene_0003.png", timestampSec: null },
            { path: "/tmp/scene_0004.png", file: "scene_0004.png" },
          ],
        })),
        deduplicateFrames: passThroughDedup(),
        createContactSheet: vi.fn(async (paths, outputPath) => ({
          outputPath,
          inputPaths: paths,
          frameCount: paths.length,
        })),
        probeVideoDuration: vi.fn(async () => ({ durationSec: 300, formatName: "mp4" })),
        extractAnchorFrames,
        log: { info: vi.fn(), warn: vi.fn() },
      },
    );

    const requested = extractAnchorFrames.mock.calls.flatMap((call) => call[2]);
    expect(requested.filter((t) => t > 100 && t < 300).length).toBeGreaterThan(0);
  });

  it("uses a caller's maximum gap in place of the default", async () => {
    const { state, requested } = await watchSparseScenes({ maxFrameGapSec: 250 });

    expect(state.coveragePlan.maxFrameGapSec).toBe(250);
    expect(requested).toEqual([]);
  });
});
