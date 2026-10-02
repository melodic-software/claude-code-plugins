import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { renderKeyFramesManifest } from "./render-key-frames-manifest.js";

/** @type {string[]} */
const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

/**
 * @param {string} sliceDir
 * @param {string} name
 * @param {unknown} value
 */
function writeKeyFramesJson(sliceDir, name, value) {
  const filePath = lanePath(sliceDir, LANES.keyFrames, name);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(value));
}

describe("renderKeyFramesManifest", () => {
  it("labels measured, estimated and untimed promotions", () => {
    const sliceDir = fs.mkdtempSync(path.join(os.tmpdir(), "key-frames-manifest-"));
    tempDirs.push(sliceDir);
    writeKeyFramesJson(sliceDir, "selection.json", {
      selectedFrames: [
        { file: "scene_0001.png", timestampSec: 300, timestampSource: "scene-detection" },
        { file: "interval_0021.png", timestampSec: 600, timestampSource: "estimated" },
        { file: "scene_0003.png", timestampSec: null },
      ],
    });
    writeKeyFramesJson(sliceDir, "promotion-decisions.json", {
      decisions: [
        { verdict: "promote", sourceFile: "scene_0001.png", destName: "diagram", session: "Intro" },
        {
          verdict: "promote",
          sourceFile: "interval_0021.png",
          destName: "slide.png",
          session: "Main",
        },
        { verdict: "promote", sourceFile: "scene_0003.png", destName: "code.png", session: "Main" },
        { verdict: "reject", sourceFile: "scene_0004.png", destName: "blur.png" },
      ],
    });

    const body = fs.readFileSync(renderKeyFramesManifest(sliceDir), "utf8");

    expect(body).toContain("Vision-gated promotions (3 frames).");
    expect(body).toContain("| diagram.png | Intro | ~5m |  |");
    expect(body).toContain("| slide.png | Main | ~10m, estimated |  |");
    expect(body).toContain("| code.png | Main | untimed |  |");
  });
});
