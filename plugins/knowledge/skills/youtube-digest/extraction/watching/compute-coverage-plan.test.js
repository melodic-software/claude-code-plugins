import { describe, expect, it } from "vitest";

import {
  computeCoveragePlan,
  cueAnchorTimestamps,
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
