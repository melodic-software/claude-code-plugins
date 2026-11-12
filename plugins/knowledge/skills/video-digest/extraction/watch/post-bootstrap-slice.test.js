import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { postBootstrapSlice } from "./post-bootstrap-slice.js";

/** @type {string[]} */
const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs) fs.rmSync(dir, { recursive: true, force: true });
  tempDirs.length = 0;
});

/**
 * Write the watch.json and selection.json a bootstrap leaves for `frameCount` frames on one sheet.
 *
 * @param {string} sliceDir
 * @param {number} frameCount
 */
function writeBootstrap(sliceDir, frameCount) {
  const files = Array.from({ length: frameCount }, (_, i) => `scene_${i + 1}.png`);
  const done = (/** @type {object} */ metrics = {}) => ({
    completedAt: "2026-11-11T00:00:00.000Z",
    metrics,
  });
  fs.mkdirSync(path.join(sliceDir, "run-state"), { recursive: true });
  fs.writeFileSync(
    path.join(sliceDir, "run-state", "watch.json"),
    JSON.stringify({
      phases: {
        acquire: done(),
        transcript: done(),
        watching: done({ frameCount, contactSheetCount: 1, densificationWindows: 0 }),
        harvest: done(),
      },
    }),
  );
  fs.mkdirSync(path.join(sliceDir, "key-frames"), { recursive: true });
  fs.writeFileSync(
    path.join(sliceDir, "key-frames", "selection.json"),
    JSON.stringify({
      durationSec: 208,
      highVolume: false,
      selectedFrames: files.map((file, i) => ({ file, timestampSec: i * 10 })),
      contactSheets: [{ file: "sheet_001.jpg", inputFiles: files }],
      densificationWindows: [],
    }),
  );
}

describe("postBootstrapSlice", () => {
  it("refreshes generated checklist evidence on a re-bootstrap and keeps agent ticks", () => {
    const sliceDir = fs.mkdtempSync(path.join(os.tmpdir(), "post-bootstrap-"));
    tempDirs.push(sliceDir);
    writeBootstrap(sliceDir, 2);
    const checklistPath = postBootstrapSlice(sliceDir).checklistPath;
    const first = fs.readFileSync(checklistPath, "utf8");
    expect(first).toContain("2 frames, 1 contact sheets");
    fs.writeFileSync(
      checklistPath,
      first
        .split("\n")
        .flatMap((line) =>
          line.startsWith("- [ ] **0.1**")
            ? [line.replace("- [ ]", "- [x]"), "  - evidence: setup-deps exit 0"]
            : [line],
        )
        .join("\n"),
    );

    writeBootstrap(sliceDir, 5);
    const lines = fs.readFileSync(postBootstrapSlice(sliceDir).checklistPath, "utf8").split("\n");
    const setupRow = lines.findIndex((line) => line.startsWith("- [x] **0.1**"));

    expect(lines.join("\n")).toContain("5 frames, 1 contact sheets");
    expect(lines.join("\n")).not.toContain("2 frames, 1 contact sheets");
    expect(setupRow).toBeGreaterThan(-1);
    expect(lines[setupRow + 1]).toBe("  - evidence: setup-deps exit 0");
  });
});
