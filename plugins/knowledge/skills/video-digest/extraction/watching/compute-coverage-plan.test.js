import { describe, expect, it } from "vitest";

import {
  computeCoveragePlan,
  cueAnchorTimestamps,
  gapFillTimestamps,
  MAX_FRAME_GAP_SEC,
  parseMaxFrameGapSecOverride,
  stratifiedSampleTimestamps,
} from "./compute-coverage-plan.js";

describe("computeCoveragePlan", () => {
  it("plans denser stratified sampling for short videos", () => {
    const plan = computeCoveragePlan({
      durationSec: 60,
      densificationWindows: [],
      sceneCandidateCount: 1,
    });

    expect(plan.stratifiedIntervalSec).toBe(5);
    expect(plan.targetMinFrames).toBeGreaterThan(10);
  });

  it("forces stratified pass when scene yield is sparse", () => {
    const plan = computeCoveragePlan({
      durationSec: 720,
      densificationWindows: [{ startSec: 100, endSec: 120, densityMultiplier: 3, reason: "code" }],
      sceneCandidateCount: 2,
    });

    expect(plan.forceStratifiedPass).toBe(true);
    expect(plan.densificationWindowCount).toBe(1);
  });

  it("defaults the maximum frame gap and lets a caller override it", () => {
    const input = { durationSec: 3600, densificationWindows: [], sceneCandidateCount: 100 };

    expect(computeCoveragePlan(input).maxFrameGapSec).toBe(MAX_FRAME_GAP_SEC);
    expect(computeCoveragePlan({ ...input, maxFrameGapSec: 30 }).maxFrameGapSec).toBe(30);
  });

  it("names stratified sampling in the rationale only when the pass is forced", () => {
    const plan = computeCoveragePlan({
      durationSec: 3600,
      densificationWindows: [],
      sceneCandidateCount: 100,
    });

    expect(plan.forceStratifiedPass).toBe(false);
    expect(plan.rationale).not.toContain("stratified");
  });
});

/**
 * Largest interval between consecutive points, counting 0 and the end.
 *
 * @param {number[]} points
 * @param {number} durationSec
 */
function largestGap(points, durationSec) {
  const sorted = [0, ...[...points].sort((a, b) => a - b), durationSec];
  return Math.max(...sorted.slice(1).map((t, i) => t - sorted[i]));
}

describe("gapFillTimestamps", () => {
  it("fills a gap over the limit and leaves gaps at or under it alone", () => {
    const frames = [0, 81, 235.2, 300];
    const fill = gapFillTimestamps(frames, 300, 60);

    expect(fill.some((t) => t > 81 && t < 235.2)).toBe(true);
    expect(largestGap([...frames, ...fill], 300)).toBeLessThanOrEqual(60);
    expect(gapFillTimestamps([0, 60, 100, 160], 160, 60)).toEqual([]);
  });

  it("fills from 0 to the first frame and from the last frame to the end", () => {
    // One 100s gap at each edge; the midpoint splits each into two 50s gaps.
    expect(gapFillTimestamps([100, 150], 250, 60)).toEqual([50, 200]);
  });

  it("samples a video with no timed frames across its whole length", () => {
    const fill = gapFillTimestamps([], 300, 60);

    expect(fill.length).toBeGreaterThan(0);
    expect(largestGap(fill, 300)).toBeLessThanOrEqual(60);
  });
});

describe("parseMaxFrameGapSecOverride", () => {
  it("reads --max-frame-gap-sec and rejects a missing or non-positive value", () => {
    expect(parseMaxFrameGapSecOverride(["node", "run-watch.js", "url"])).toEqual({
      ok: true,
      override: null,
    });
    expect(parseMaxFrameGapSecOverride(["url", "--max-frame-gap-sec", "45"])).toEqual({
      ok: true,
      override: 45,
    });
    expect(parseMaxFrameGapSecOverride(["url", "--max-frame-gap-sec"]).ok).toBe(false);
    expect(parseMaxFrameGapSecOverride(["url", "--max-frame-gap-sec", "0"]).ok).toBe(false);
    expect(parseMaxFrameGapSecOverride(["url", "--max-frame-gap-sec", "abc"]).ok).toBe(false);
  });
});

describe("stratifiedSampleTimestamps", () => {
  it("returns timestamps across duration", () => {
    const stamps = stratifiedSampleTimestamps(120, 30);
    expect(stamps.length).toBeGreaterThan(0);
    expect(stamps[0]).toBeGreaterThan(0);
  });
});

describe("cueAnchorTimestamps", () => {
  it("captures code and screen cues", () => {
    const stamps = cueAnchorTimestamps([
      { startSec: 10, endSec: 12, text: "look at the code on screen" },
      { startSec: 20, endSec: 22, text: "thanks for watching" },
    ]);
    expect(stamps).toHaveLength(1);
  });
});
