import { describe, expect, it } from "vitest";

import { soleElement } from "../test-support/assertions.js";
import { detectOverlaps } from "./overlaps.js";

describe("detectOverlaps", () => {
  it("should return empty array when no items", () => {
    expect(detectOverlaps([], 195)).toEqual([]);
  });

  it("should return empty array for single item", () => {
    const items = [{ id: "1", content: "Test", x: 0, y: 0 }];
    expect(detectOverlaps(items, 195)).toEqual([]);
  });

  it("should detect items at same position as overlapping", () => {
    const items = [
      { id: "1", content: "Item A", x: 100, y: 100 },
      { id: "2", content: "Item B", x: 100, y: 100 },
    ];
    const result = detectOverlaps(items, 195);
    const pair = soleElement(result);
    expect(pair.a.id).toBe("1");
    expect(pair.b.id).toBe("2");
    expect(pair.dx).toBe(0);
    expect(pair.dy).toBe(0);
  });

  it("should detect items within threshold as overlapping", () => {
    const items = [
      { id: "1", content: "Item A", x: 0, y: 0 },
      { id: "2", content: "Item B", x: 100, y: 80 },
    ];
    const pair = soleElement(detectOverlaps(items, 195));
    expect(pair.dx).toBe(100);
    expect(pair.dy).toBe(80);
  });

  it("should NOT detect items beyond threshold", () => {
    const items = [
      { id: "1", content: "Item A", x: 0, y: 0 },
      { id: "2", content: "Item B", x: 300, y: 0 },
    ];
    expect(detectOverlaps(items, 195)).toEqual([]);
  });

  it("should NOT detect items close on X but far on Y", () => {
    const items = [
      { id: "1", content: "Item A", x: 0, y: 0 },
      { id: "2", content: "Item B", x: 50, y: 500 },
    ];
    expect(detectOverlaps(items, 195)).toEqual([]);
  });

  it("should detect the v12 reactor row problem (80px y-offset)", () => {
    // The exact scenario that caused 212 overlaps: primary at y=0, reactor at y=80
    const items = [
      { id: "primary", content: "[DSP] Clocked in", x: 1500, y: 500 },
      { id: "reactor", content: "[DSP] Picked up shift", x: 1500, y: 580 },
    ];
    expect(soleElement(detectOverlaps(items, 195)).dy).toBe(80);
  });

  it("should NOT flag items with proper 500px persona spacing", () => {
    const items = [
      { id: "1", content: "[DSP] Event", x: 1500, y: 500 },
      { id: "2", content: "[Billing] Event", x: 1500, y: 1000 },
    ];
    expect(detectOverlaps(items, 195)).toEqual([]);
  });

  it("should handle many items efficiently", () => {
    // 100 items in a grid — no overlaps with 250px spacing
    const items = Array.from({ length: 100 }, (_, i) => ({
      id: String(i),
      content: `Item ${i}`,
      x: (i % 10) * 250,
      y: Math.floor(i / 10) * 250,
    }));
    expect(detectOverlaps(items, 195)).toEqual([]);
  });

  it("should detect all overlaps in a dense cluster", () => {
    // 4 items at same position = 6 pairs (4 choose 2)
    const items = [
      { id: "1", content: "A", x: 0, y: 0 },
      { id: "2", content: "B", x: 0, y: 0 },
      { id: "3", content: "C", x: 0, y: 0 },
      { id: "4", content: "D", x: 0, y: 0 },
    ];
    expect(detectOverlaps(items, 195)).toHaveLength(6);
  });

  it("should respect custom threshold", () => {
    const items = [
      { id: "1", content: "A", x: 0, y: 0 },
      { id: "2", content: "B", x: 100, y: 0 },
    ];
    // Threshold 50: not overlapping (dx=100 > 50)
    expect(detectOverlaps(items, 50)).toEqual([]);
    // Threshold 150: overlapping (dx=100 < 150)
    expect(detectOverlaps(items, 150)).toHaveLength(1);
  });

  it("should detect boundary case at exactly threshold - 1", () => {
    const items = [
      { id: "1", content: "A", x: 0, y: 0 },
      { id: "2", content: "B", x: 194, y: 0 },
    ];
    // 194 < 195 = overlap
    expect(detectOverlaps(items, 195)).toHaveLength(1);
  });

  it("should NOT detect at exactly threshold", () => {
    const items = [
      { id: "1", content: "A", x: 0, y: 0 },
      { id: "2", content: "B", x: 195, y: 0 },
    ];
    // 195 is NOT < 195 = no overlap
    expect(detectOverlaps(items, 195)).toEqual([]);
  });
});
