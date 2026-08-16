import path from "node:path";

import { describe, expect, it } from "vitest";

import { LANES, lanePath } from "./slice-lanes.js";

describe("LANES", () => {
  it("exports the six approved concern-lane directory names", () => {
    expect(LANES).toEqual({
      source: "source",
      research: "research",
      keyFrames: "key-frames",
      recommendations: "recommendations",
      verification: "verification",
      runState: "run-state",
    });
  });

  it("is frozen so consumers cannot mutate the registry", () => {
    expect(Object.isFrozen(LANES)).toBe(true);
  });
});

describe("lanePath", () => {
  it("joins a lane directory under the slice root", () => {
    expect(lanePath("/slice", LANES.source)).toBe(path.join("/slice", "source"));
  });

  it("appends nested segments after the lane", () => {
    expect(lanePath("/slice", LANES.keyFrames, "triage", "batches")).toBe(
      path.join("/slice", "key-frames", "triage", "batches"),
    );
  });

  it("resolves a leaf file inside a lane", () => {
    expect(lanePath("/slice", LANES.research, "findings", "complex-types.md")).toBe(
      path.join("/slice", "research", "findings", "complex-types.md"),
    );
  });

  it("preserves an absolute slice root", () => {
    const abs = path.resolve("/work", "youtube-watch", "demo");
    expect(lanePath(abs, LANES.runState, "watch.json")).toBe(
      path.join(abs, "run-state", "watch.json"),
    );
  });
});
