import { describe, expect, it } from "vitest";

import { resolveSourceFile } from "./rebuild-visual-frames.js";

describe("resolveSourceFile", () => {
  it("reads source from promotion-map.json entries", () => {
    const map = { "demo-slide.png": { sourceFile: "scene_0042.png" } };
    expect(resolveSourceFile("demo-slide.png", map)).toBe("scene_0042.png");
  });

  it("parses at-timestamp fallback names", () => {
    expect(resolveSourceFile("at-12m30s-scene_0048.png", {})).toBe("scene_0048.png");
  });

  it("does not use video-specific legacy maps", () => {
    expect(resolveSourceFile("arbitrary-semantic-name.png", {})).toBeUndefined();
  });
});
