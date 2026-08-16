import { describe, expect, it, vi } from "vitest";

import { finalizeVision, finalizeVisionSteps } from "./finalize-vision.js";

describe("finalize-vision orchestrator", () => {
  it("wraps the 5 mechanical sub-chains in order", () => {
    const steps = finalizeVisionSteps("/tmp/slice");
    expect(steps.map((s) => s.name)).toEqual([
      "merge-triage-json",
      "validate-triage-json",
      "render-triage-log",
      "render-quality-audit",
      "render-key-frames-manifest",
    ]);
  });

  it("runs the sub-chains sequentially in order", () => {
    const order = [];
    const steps = ["a", "b", "c"].map((name) => ({ name, run: () => order.push(name) }));
    const code = finalizeVision("/tmp/slice", { steps });
    expect(code).toBe(0);
    expect(order).toEqual(["a", "b", "c"]);
  });

  it("lists sub-chains on --dry-run without running them", () => {
    const run = vi.fn();
    const steps = ["a", "b"].map((name) => ({ name, run }));
    const code = finalizeVision("/tmp/slice", { dryRun: true, steps });
    expect(code).toBe(0);
    expect(run).not.toHaveBeenCalled();
  });

  it("short-circuits on the first failing sub-chain", () => {
    const order = [];
    const steps = [
      { name: "a", run: () => order.push("a") },
      {
        name: "b",
        run: () => {
          throw new Error("boom");
        },
      },
      { name: "c", run: () => order.push("c") },
    ];
    const code = finalizeVision("/tmp/slice", { steps });
    expect(code).toBe(1);
    // "c" must NOT run after "b" throws.
    expect(order).toEqual(["a"]);
  });
});
