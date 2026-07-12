import { describe, expect, it } from "vitest";

import {
  DEFAULT_DETAIL_RESOLUTION,
  isInTextDenseWindow,
  NATIVE_ESCALATION_RESOLUTION,
  resolveReadResolution,
  toSelectedFrame,
} from "./read-policy.js";

const CODE_WINDOW = [{ startSec: 50, endSec: 80, densityMultiplier: 3, reason: "code" }];

describe("resolveReadResolution", () => {
  it("defaults to 1280x720 outside text-dense windows", () => {
    expect(resolveReadResolution(10, CODE_WINDOW)).toBe(DEFAULT_DETAIL_RESOLUTION);
  });

  it("escalates to native 1080p inside text-dense windows", () => {
    expect(resolveReadResolution(60, CODE_WINDOW)).toBe(NATIVE_ESCALATION_RESOLUTION);
  });
});

describe("isInTextDenseWindow", () => {
  it("returns false for null timestamp", () => {
    expect(isInTextDenseWindow(null, CODE_WINDOW)).toBe(false);
  });
});

describe("toSelectedFrame", () => {
  it("marks text-dense frames and sets read resolution", () => {
    const selected = toSelectedFrame(
      { path: "/f.png", file: "f.png", timestampSec: 60 },
      5,
      CODE_WINDOW,
    );
    expect(selected.textDense).toBe(true);
    expect(selected.readResolution).toBe(NATIVE_ESCALATION_RESOLUTION);
    expect(selected.priorityScore).toBe(5);
  });
});
