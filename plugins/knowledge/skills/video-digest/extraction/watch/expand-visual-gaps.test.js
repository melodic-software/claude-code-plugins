import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { expandVisualGaps } from "./expand-visual-gaps.js";

const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  tempDirs.length = 0;
});

/**
 * Seed a slice with the two inputs expandVisualGaps reads.
 *
 * `promotedMinutes` are written in the `| ~Nm |` row shape that
 * parsePromotedTimestampsSec parses. With no promoted PNGs under
 * key-frames/frames/, these minute rows are the only promoted times.
 *
 * @param {{startSec: number, endSec: number, reason: string}[]} densificationWindows
 * @param {number[]} promotedMinutes
 * @returns {string} slice dir
 */
function seedSlice(densificationWindows, promotedMinutes) {
  const sliceDir = fs.mkdtempSync(path.join(os.tmpdir(), "visual-gaps-"));
  tempDirs.push(sliceDir);

  const keyFrames = path.join(sliceDir, "key-frames");
  fs.mkdirSync(keyFrames, { recursive: true });
  fs.writeFileSync(
    path.join(keyFrames, "selection.json"),
    JSON.stringify({ densificationWindows }),
  );

  const rows = promotedMinutes.map(
    (m) => `| ~${m}m | frame_${m}.png | promoted |`,
  );
  fs.writeFileSync(
    path.join(keyFrames, "visual-frames.md"),
    `# Visual frames\n\n| Region | Frame | Status |\n| --- | --- | --- |\n${rows.join("\n")}\n`,
  );

  return sliceDir;
}

/**
 * Add the inputs the exact promoted-timestamp loader reads: a promoted PNG under
 * key-frames/frames/, its promotion-map entry, and the selected frame carrying
 * the measured time.
 *
 * @param {string} sliceDir
 * @param {{ promotedFile: string, sourceFile: string, timestampSec: number }[]} promotions
 */
function seedExactPromotions(sliceDir, promotions) {
  const keyFrames = path.join(sliceDir, "key-frames");
  const framesDir = path.join(keyFrames, "frames");
  fs.mkdirSync(framesDir, { recursive: true });
  const selectionPath = path.join(keyFrames, "selection.json");
  const selection = JSON.parse(fs.readFileSync(selectionPath, "utf8"));
  selection.selectedFrames = promotions.map((p) => ({
    file: p.sourceFile,
    timestampSec: p.timestampSec,
    timestampSource: "scene-detection",
  }));
  fs.writeFileSync(selectionPath, JSON.stringify(selection));
  const promotionMap = {};
  for (const p of promotions) {
    fs.writeFileSync(path.join(framesDir, p.promotedFile), "");
    promotionMap[p.promotedFile] = { sourceFile: p.sourceFile };
  }
  fs.writeFileSync(path.join(keyFrames, "promotion-map.json"), JSON.stringify(promotionMap));
}

/** @param {string} outPath */
function gapRows(outPath) {
  return fs
    .readFileSync(outPath, "utf8")
    .split("\n")
    .filter((line) => line.startsWith("| ~"));
}

describe("expandVisualGaps", () => {
  it("logs a window with no promoted frame and skips one that has a frame", () => {
    const sliceDir = seedSlice(
      [
        { startSec: 300, endSec: 360, reason: "dense diagram" },
        { startSec: 600, endSec: 660, reason: "code walkthrough" },
      ],
      [10],
    );

    const result = expandVisualGaps(sliceDir);

    expect(result.total).toBe(2);
    expect(result.gapCount).toBe(1);
    expect(result.outPath).toBe(
      path.join(sliceDir, "key-frames", "visual-gaps.md"),
    );

    const rows = gapRows(result.outPath);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toBe(
      "| ~5m (300.0-360.0s) | dense diagram | No synthesis frame in window; transcript-only |",
    );
  });

  it("treats both window boundaries as covered and one second outside as a gap", () => {
    // The filter is `ts >= startSec && ts <= endSec`, so a frame landing exactly
    // on either edge closes the window. Minute rows parse as whole minutes, so
    // the windows here are minute-aligned to let a frame sit on each edge.
    const covering = expandVisualGaps(
      seedSlice(
        [
          { startSec: 300, endSec: 420, reason: "lower edge" },
          { startSec: 480, endSec: 600, reason: "upper edge" },
        ],
        [5, 10],
      ),
    );
    expect(covering.gapCount).toBe(0);

    const missing = expandVisualGaps(
      seedSlice(
        [
          { startSec: 300, endSec: 420, reason: "just below" },
          { startSec: 480, endSec: 600, reason: "just above" },
        ],
        [4, 11],
      ),
    );
    expect(missing.gapCount).toBe(2);
  });

  it("keeps window order and rounds the region label to the nearest minute", () => {
    // 90s rounds to 2m, not 1m: the label is Math.round, not a floor.
    const result = expandVisualGaps(
      seedSlice(
        [
          { startSec: 90, endSec: 100, reason: "second" },
          { startSec: 30, endSec: 40, reason: "first" },
        ],
        [],
      ),
    );

    expect(
      gapRows(result.outPath).map((line) => line.split("|")[1].trim()),
    ).toEqual(["~2m (90.0-100.0s)", "~1m (30.0-40.0s)"]);
  });

  it("counts a window covered by a promoted frame's exact time, not its minute label", () => {
    // The frame sits at 318s; its visual-frames label floors to ~5m (300s),
    // which is outside the 312-324s window.
    const sliceDir = seedSlice([{ startSec: 312, endSec: 324, reason: "slide" }], [5]);
    seedExactPromotions(sliceDir, [
      { promotedFile: "at-5m18s-scene_0007.png", sourceFile: "scene_0007.png", timestampSec: 318 },
    ]);

    expect(expandVisualGaps(sliceDir).gapCount).toBe(0);
  });

  it("ignores minute labels when exact promoted times exist", () => {
    // The ~5m label would cover 300-310s; the frame's exact time, 318s, does not.
    const sliceDir = seedSlice([{ startSec: 300, endSec: 310, reason: "slide" }], [5]);
    seedExactPromotions(sliceDir, [
      { promotedFile: "at-5m18s-scene_0007.png", sourceFile: "scene_0007.png", timestampSec: 318 },
    ]);

    const result = expandVisualGaps(sliceDir);

    expect(result.gapCount).toBe(1);
    expect(gapRows(result.outPath)).toEqual([
      "| ~5m (300.0-310.0s) | slide | No synthesis frame in window; transcript-only |",
    ]);
  });

  it("writes a table with no rows when every window is covered", () => {
    const sliceDir = seedSlice(
      [{ startSec: 300, endSec: 360, reason: "covered" }],
      [5],
    );
    const result = expandVisualGaps(sliceDir);

    expect(result).toEqual({
      outPath: path.join(sliceDir, "key-frames", "visual-gaps.md"),
      gapCount: 0,
      total: 1,
    });
    expect(gapRows(result.outPath)).toHaveLength(0);
    expect(fs.readFileSync(result.outPath, "utf8")).toContain(
      "| Region | Trigger | Status |",
    );
  });

  it("reports zero of zero when there are no densification windows", () => {
    const result = expandVisualGaps(seedSlice([], [5]));

    expect(result.gapCount).toBe(0);
    expect(result.total).toBe(0);
    expect(gapRows(result.outPath)).toHaveLength(0);
  });
});
