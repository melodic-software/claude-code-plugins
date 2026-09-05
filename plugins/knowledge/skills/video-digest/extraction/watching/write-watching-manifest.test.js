import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { writeWatchingManifest } from "./write-watching-manifest.js";

const TEMP_ROOT = join(tmpdir(), "yt-work");
const TEMP_SESSION = {
  workDir: join(TEMP_ROOT, "work"),
  framesDir: join(TEMP_ROOT, "frames"),
  contactSheetsDir: join(TEMP_ROOT, "sheets"),
  acquiredAt: "2026-06-11T00:00:00.000Z",
};

describe("writeWatchingManifest", () => {
  let sliceDir;

  beforeEach(() => {
    sliceDir = mkdtempSync(join(tmpdir(), "slice-"));
  });

  afterEach(() => {
    rmSync(sliceDir, { recursive: true, force: true });
  });

  it("writes selection and coverage manifests without copying frames", async () => {
    const watching = {
      targetMinFrames: 40,
      highVolume: false,
      candidateCount: 42,
      durationSec: 600,
      densificationWindows: [{ startSec: 0, endSec: 10, densityMultiplier: 2, reason: "code" }],
      coveragePlan: {
        durationSec: 600,
        stratifiedIntervalSec: 45,
        densificationWindowCount: 1,
        targetMinFrames: 40,
        targetMaxFrames: null,
        forceStratifiedPass: false,
        rationale: "test",
      },
      selectedFrames: [
        {
          path: join(TEMP_ROOT, "frames", "scene_0001.png"),
          file: "scene_0001.png",
          timestampSec: 12.5,
          priorityScore: 3,
          textDense: true,
          readResolution: "1920x1080",
        },
      ],
      contactSheets: [
        {
          outputPath: join(TEMP_ROOT, "sheets", "sheet_001.jpg"),
          inputPaths: [join(TEMP_ROOT, "frames", "scene_0001.png")],
          tile: "4x4",
          frameCount: 1,
        },
      ],
      interleavedTimeline: [{ kind: "frame", timestampSec: 12.5 }],
    };

    const result = await writeWatchingManifest(sliceDir, watching, TEMP_SESSION);

    expect(result.frameCount).toBe(1);
    expect(existsSync(join(sliceDir, "media", "frames"))).toBe(false);

    const selection = JSON.parse(
      readFileSync(join(sliceDir, "key-frames", "selection.json"), "utf8"),
    );
    expect(selection.tempSession.framesDir).toMatch(/^\{tmp\}\//);
    expect(selection.selectedFrames[0].path).toBeUndefined();
  });

  it("strips frame.path from interleavedTimeline — no temp path leaks", async () => {
    const watching = {
      targetMinFrames: 40,
      highVolume: false,
      candidateCount: 1,
      durationSec: 600,
      densificationWindows: [],
      selectedFrames: [],
      contactSheets: [],
      interleavedTimeline: [
        {
          kind: "frame",
          timestampSec: 12.5,
          frame: {
            path: join(TEMP_ROOT, "frames", "interval_0001.png"),
            file: "interval_0001.png",
            timestampSec: 12.5,
          },
        },
        { kind: "transcript", timestampSec: 13, transcriptText: "hello" },
      ],
    };

    await writeWatchingManifest(sliceDir, watching, TEMP_SESSION);

    const raw = readFileSync(join(sliceDir, "key-frames", "selection.json"), "utf8");
    const selection = JSON.parse(raw);

    expect(selection.interleavedTimeline[0].frame.path).toBeUndefined();
    expect(selection.interleavedTimeline[0].frame.file).toBe("interval_0001.png");
    expect(selection.interleavedTimeline[1]).toEqual({
      kind: "transcript",
      timestampSec: 13,
      transcriptText: "hello",
    });
    expect(raw).not.toContain('"path"');
  });
});
