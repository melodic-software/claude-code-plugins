import { describe, expect, it } from "vitest";

import { mergeFrameCandidates } from "./merge-frame-candidates.js";

/**
 * @param {string} file
 * @param {number|null} timestampSec
 * @param {object} [extra]
 */
function frame(file, timestampSec, extra = {}) {
  return { path: `/frames/${file}`, file, timestampSec, ...extra };
}

describe("mergeFrameCandidates", () => {
  it("orders frames by time with untimed frames after every timed one", () => {
    const merged = mergeFrameCandidates([
      frame("scene_0003.png", null),
      frame("anchor_00073000_0001.png", 73, { timestampSource: "anchor" }),
      frame("scene_0001.png", 12.5, { timestampSource: "scene-detection" }),
      frame("interval_0003.png", 60, { timestampSource: "estimated", timestampErrorSec: 15 }),
    ]);

    expect(merged.map((f) => [f.file, f.timestampSec])).toEqual([
      ["scene_0001.png", 12.5],
      ["interval_0003.png", 60],
      ["anchor_00073000_0001.png", 73],
      ["scene_0003.png", null],
    ]);
    expect(merged[1].timestampSource).toBe("estimated");
  });

  it("keeps the timed entry when a file appears both with and without a time", () => {
    const merged = mergeFrameCandidates([
      frame("scene_0001.png", 12.5, { timestampSource: "scene-detection" }),
      frame("scene_0001.png", null),
    ]);

    expect(merged).toHaveLength(1);
    expect(merged[0].timestampSec).toBe(12.5);
  });
});
