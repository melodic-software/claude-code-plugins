import { describe, expect, it } from "vitest";

import {
  formatTimestampSlug,
  synthesisDestName,
  synthesisNameQualityScore,
} from "./synthesis-naming.js";

describe("synthesisDestName", () => {
  it("uses promotion-decisions map when provided", () => {
    const map = { "scene_0012.png": "network-diagram.png" };
    expect(synthesisDestName("scene_0012.png", 453, map)).toBe("network-diagram.png");
  });

  it("falls back to timestamped source stem when unmapped", () => {
    expect(synthesisDestName("scene_0048.png", 1894.8, {})).toBe("at-31m35s-scene_0048.png");
  });

  it("names an untimed frame untimed, never at 0m00s", () => {
    expect(synthesisDestName("scene_0048.png", null, {})).toBe("untimed-scene_0048.png");
  });

  it("names a frame with an estimated time by that time", () => {
    expect(synthesisDestName("interval_0003.png", 60, {})).toBe("at-1m00s-interval_0003.png");
  });
});

describe("formatTimestampSlug", () => {
  it("formats minutes and seconds", () => {
    expect(formatTimestampSlug(1894.8)).toBe("31m35s");
  });
});

describe("synthesisNameQualityScore", () => {
  it("prefers semantic names over numeric collisions", () => {
    expect(synthesisNameQualityScore("network-diagram.png")).toBeGreaterThan(
      synthesisNameQualityScore("0012.png"),
    );
    expect(synthesisNameQualityScore("0012-2-3.png")).toBeLessThan(
      synthesisNameQualityScore("at-31m35s-scene_0048.png"),
    );
  });

  it("ranks a generated untimed name below a semantic one", () => {
    expect(synthesisNameQualityScore("untimed-scene_0048.png")).toBeLessThan(
      synthesisNameQualityScore("network-diagram.png"),
    );
  });
});
