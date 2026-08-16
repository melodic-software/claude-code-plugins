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
});
