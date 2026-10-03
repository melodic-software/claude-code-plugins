import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { exportSheetFrameIndex } from "./export-sheet-frame-index.js";

const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  tempDirs.length = 0;
});

describe("exportSheetFrameIndex", () => {
  it("writes sheet-frame-index.json from selection contact sheets", () => {
    const sliceDir = fs.mkdtempSync(path.join(os.tmpdir(), "sheet-index-"));
    tempDirs.push(sliceDir);

    const selection = {
      selectedFrames: [
        { file: "scene_0001.png", timestampSec: 10, textDense: false },
        { file: "scene_0002.png", timestampSec: 20, textDense: true },
      ],
      contactSheets: [
        {
          file: "sheet_001.jpg",
          path: "/tmp/sheet_001.jpg",
          inputFiles: ["scene_0001.png", "scene_0002.png"],
        },
      ],
    };

    fs.mkdirSync(path.join(sliceDir, "key-frames"), { recursive: true });
    fs.mkdirSync(path.join(sliceDir, "run-state"), { recursive: true });
    fs.writeFileSync(
      path.join(sliceDir, "key-frames", "selection.json"),
      JSON.stringify(selection),
    );
    fs.writeFileSync(
      path.join(sliceDir, "run-state", "watch.json"),
      JSON.stringify({ tempSession: {} }),
    );

    const outPath = exportSheetFrameIndex(sliceDir);
    expect(outPath).toContain("sheet-frame-index.json");
    const payload = JSON.parse(fs.readFileSync(outPath, "utf8"));
    expect(payload.sheets).toHaveLength(1);
    expect(payload.sheets[0].cells).toHaveLength(2);
  });

  it("carries each cell's time source: measured, estimated, and untimed", () => {
    const sliceDir = fs.mkdtempSync(path.join(os.tmpdir(), "sheet-index-"));
    tempDirs.push(sliceDir);
    const selection = {
      selectedFrames: [
        { file: "scene_0001.png", timestampSec: 10, timestampSource: "scene-detection" },
        { file: "interval_0003.png", timestampSec: 60, timestampSource: "estimated" },
        { file: "scene_0002.png", timestampSec: null, timestampSource: null },
      ],
      contactSheets: [
        {
          file: "sheet_001.jpg",
          inputFiles: ["scene_0001.png", "interval_0003.png", "scene_0002.png"],
        },
      ],
    };
    fs.mkdirSync(path.join(sliceDir, "key-frames"), { recursive: true });
    fs.writeFileSync(
      path.join(sliceDir, "key-frames", "selection.json"),
      JSON.stringify(selection),
    );

    const payload = JSON.parse(fs.readFileSync(exportSheetFrameIndex(sliceDir), "utf8"));

    expect(
      payload.sheets[0].cells.map((cell) => [cell.timestampSec, cell.timestampSource]),
    ).toEqual([
      [10, "scene-detection"],
      [60, "estimated"],
      [null, null],
    ]);
  });
});
