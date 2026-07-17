import { describe, expect, it } from "vitest";

import {
  densityAtTimestamp,
  findDensificationWindows,
  mergeOverlappingWindows,
  scoreFramePriority,
} from "./densification.js";

describe("findDensificationWindows", () => {
  it("detects demo and code keyword windows with padding", () => {
    const windows = findDensificationWindows([
      { startSec: 60, endSec: 65, text: "Let me show you this function in the terminal" },
      { startSec: 200, endSec: 210, text: "Back to the overview" },
    ]);

    expect(windows).toHaveLength(1);
    expect(windows[0].startSec).toBe(55);
    expect(windows[0].endSec).toBe(70);
    expect(windows[0].densityMultiplier).toBeGreaterThanOrEqual(3);
    expect(windows[0].reason).toContain("demo");
  });

  it("returns empty for talking-head cues without signals", () => {
    const windows = findDensificationWindows([
      { startSec: 0, endSec: 10, text: "Welcome everyone to today's talk" },
      { startSec: 10, endSec: 20, text: "We will cover several topics" },
    ]);
    expect(windows).toEqual([]);
  });
});

describe("mergeOverlappingWindows", () => {
  it("merges overlapping windows keeping max multiplier", () => {
    const merged = mergeOverlappingWindows([
      { startSec: 10, endSec: 30, densityMultiplier: 3, reason: "demo" },
      { startSec: 25, endSec: 50, densityMultiplier: 4, reason: "code" },
    ]);

    expect(merged).toHaveLength(1);
    expect(merged[0].startSec).toBe(10);
    expect(merged[0].endSec).toBe(50);
    expect(merged[0].densityMultiplier).toBe(4);
  });
});

describe("densityAtTimestamp", () => {
  it("returns sparse multiplier outside windows", () => {
    const windows = [{ startSec: 100, endSec: 120, densityMultiplier: 3, reason: "code" }];
    expect(densityAtTimestamp(50, windows)).toBe(1);
    expect(densityAtTimestamp(110, windows)).toBe(3);
  });
});

describe("scoreFramePriority", () => {
  it("boosts frames inside densification windows", () => {
    const windows = [{ startSec: 0, endSec: 100, densityMultiplier: 3, reason: "code" }];
    const dense = scoreFramePriority(
      { path: "/a.png", file: "a.png", timestampSec: 50, isInterval: false },
      0,
      windows,
    );
    const sparse = scoreFramePriority(
      { path: "/b.png", file: "b.png", timestampSec: 200, isInterval: false },
      1,
      windows,
    );
    expect(dense).toBeGreaterThan(sparse);
  });
});
