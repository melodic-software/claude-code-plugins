import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { rebuildVisualFrames, resolveSourceFile } from "./rebuild-visual-frames.js";

/** @type {string[]} */
const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

describe("resolveSourceFile", () => {
  it("reads source from promotion-map.json entries", () => {
    const map = { "demo-slide.png": { sourceFile: "scene_0042.png" } };
    expect(resolveSourceFile("demo-slide.png", map)).toBe("scene_0042.png");
  });

  it("parses at-timestamp fallback names", () => {
    expect(resolveSourceFile("at-12m30s-scene_0048.png", {})).toBe("scene_0048.png");
  });

  it("parses untimed fallback names", () => {
    expect(resolveSourceFile("untimed-scene_0048.png", {})).toBe("scene_0048.png");
  });

  it("does not use video-specific legacy maps", () => {
    expect(resolveSourceFile("arbitrary-semantic-name.png", {})).toBeUndefined();
  });
});

describe("rebuildVisualFrames", () => {
  it("labels estimated rows and lists untimed rows last, never at minute 0", () => {
    const sliceDir = fs.mkdtempSync(path.join(os.tmpdir(), "visual-frames-"));
    tempDirs.push(sliceDir);
    const framesDir = lanePath(sliceDir, LANES.keyFrames, "frames");
    fs.mkdirSync(framesDir, { recursive: true });
    for (const file of ["code.png", "diagram.png", "slide.png"]) {
      fs.writeFileSync(path.join(framesDir, file), "");
    }
    fs.writeFileSync(
      lanePath(sliceDir, LANES.keyFrames, "promotion-map.json"),
      JSON.stringify({
        "code.png": { sourceFile: "scene_0003.png" },
        "diagram.png": { sourceFile: "scene_0001.png" },
        "slide.png": { sourceFile: "interval_0021.png" },
      }),
    );
    fs.writeFileSync(
      lanePath(sliceDir, LANES.keyFrames, "selection.json"),
      JSON.stringify({
        selectedFrames: [
          { file: "scene_0001.png", timestampSec: 300, timestampSource: "scene-detection" },
          { file: "interval_0021.png", timestampSec: 600, timestampSource: "estimated" },
          { file: "scene_0003.png", timestampSec: null },
        ],
      }),
    );

    const body = fs.readFileSync(rebuildVisualFrames(sliceDir), "utf8");
    const rows = body.split("\n").filter((line) => line.includes("`frames/"));

    expect(rows).toEqual([
      "| ~5m | `frames/diagram.png` | scene_0001.png |",
      "| ~10m, estimated | `frames/slide.png` | interval_0021.png |",
      "| untimed | `frames/code.png` | scene_0003.png |",
    ]);
  });
});
