import { describe, expect, it } from "vitest";

import { fuzzyContains, normalizeTranscriptText } from "./check-transcript-goldens.js";

describe("fuzzyContains", () => {
  it("should match when most answer tokens appear in transcript", () => {
    const transcript =
      "The car wash is 50 meters away and models recommend walking instead of driving.";
    expect(
      fuzzyContains(transcript, "50 meters away; models recommend walking instead of driving."),
    ).toBe(true);
  });

  it("should reject unrelated text", () => {
    expect(fuzzyContains("hello world", "three layers spec verifier environment")).toBe(false);
  });

  it("should normalize 50 m to meters in auto captions", () => {
    const transcript = "car wash and it's 50 m away should I drive or walk";
    expect(
      fuzzyContains(transcript, "50 meters away; models recommend walking instead of driving."),
    ).toBe(true);
  });

  it("should strip html entities from captions", () => {
    expect(normalizeTranscriptText("&gt;&gt; hello")).toContain("hello");
  });
});
