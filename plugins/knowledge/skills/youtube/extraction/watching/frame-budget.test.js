import { describe, expect, it } from "vitest";

import { isHighVolume, summarizeFrameSelection } from "./frame-budget.js";

/** @param {number} n */
function makeFrames(n) {
  return Array.from({ length: n }, (_, i) => ({
    path: `/frame_${i}.png`,
    file: `frame_${i}.png`,
    timestampSec: i,
    priorityScore: n - i,
    textDense: false,
    readResolution: /** @type {'1280x720'} */ ("1280x720"),
  }));
}

describe("isHighVolume", () => {
  it("triggers on contact sheet count", () => {
    expect(isHighVolume({ contactSheetCount: 8 })).toBe(true);
    expect(isHighVolume({ contactSheetCount: 7 })).toBe(false);
  });

  it("triggers on long duration", () => {
    expect(isHighVolume({ durationSec: 7200 })).toBe(true);
    expect(isHighVolume({ durationSec: 7199 })).toBe(false);
  });

  it("triggers on densification window count", () => {
    expect(isHighVolume({ densificationWindowCount: 30 })).toBe(true);
    expect(isHighVolume({ densificationWindowCount: 29 })).toBe(false);
  });

  it("triggers on candidate count vs target", () => {
    expect(isHighVolume({ candidateCount: 121, targetMinFrames: 40 })).toBe(true);
    expect(isHighVolume({ candidateCount: 120, targetMinFrames: 40 })).toBe(false);
  });

  it("matches long multi-session conference signals", () => {
    expect(
      isHighVolume({
        candidateCount: 800,
        targetMinFrames: 750,
        contactSheetCount: 50,
        durationSec: 32000,
        densificationWindowCount: 100,
      }),
    ).toBe(true);
  });
});

describe("summarizeFrameSelection", () => {
  it("keeps all frames without truncation", () => {
    const result = summarizeFrameSelection(makeFrames(200), { targetMinFrames: 40 });
    expect(result.selected).toHaveLength(200);
    expect(result.overCap).toBe(false);
    expect(result.highVolume).toBe(true);
  });

  it("sorts selected frames chronologically", () => {
    const frames = [
      {
        path: "/late.png",
        file: "late.png",
        timestampSec: 100,
        priorityScore: 10,
        textDense: false,
        readResolution: /** @type {'1280x720'} */ ("1280x720"),
      },
      {
        path: "/early.png",
        file: "early.png",
        timestampSec: 5,
        priorityScore: 1,
        textDense: false,
        readResolution: /** @type {'1280x720'} */ ("1280x720"),
      },
    ];
    const result = summarizeFrameSelection(frames);
    expect(result.selected[0].timestampSec).toBe(5);
    expect(result.selected[1].timestampSec).toBe(100);
  });
});
