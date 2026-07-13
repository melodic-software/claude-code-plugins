import { describe, expect, it } from "vitest";

import { createAdapter, validateAdapter } from "./adapter-contract.js";

describe("validateAdapter", () => {
  const validAdapter = {
    extractTranscript: async () => {},
    extractHlsUrl: async () => {},
    detectResources: async () => {},
    deriveLandingUrl: () => "",
    buildLessonUrl: () => "",
  };

  it("should accept adapter with all required methods", () => {
    const result = validateAdapter(validAdapter, "test");
    expect(result.success).toBe(true);
  });

  it("should reject adapter missing extractTranscript", () => {
    const { extractTranscript, ...partial } = validAdapter;
    const result = validateAdapter(partial, "test");
    expect(result.success).toBe(false);
    expect(result.error).toContain("extractTranscript");
  });

  it("should reject adapter missing deriveLandingUrl", () => {
    const { deriveLandingUrl, ...partial } = validAdapter;
    const result = validateAdapter(partial, "test");
    expect(result.success).toBe(false);
    expect(result.error).toContain("deriveLandingUrl");
  });

  it("should reject adapter with non-function method", () => {
    const bad = { ...validAdapter, extractTranscript: "not a function" };
    const result = validateAdapter(bad, "test");
    expect(result.success).toBe(false);
    expect(result.error).toContain("extractTranscript");
  });
});

describe("createAdapter", () => {
  it("should return fail for unknown platform", async () => {
    const result = await createAdapter("nonexistent", {});
    expect(result.success).toBe(false);
    expect(result.error).toContain("nonexistent");
  });
});
