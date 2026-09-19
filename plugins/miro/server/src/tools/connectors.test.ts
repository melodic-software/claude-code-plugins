import { describe, expect, it } from "vitest";

import { strokeColorSchema } from "./connectors.js";

describe("strokeColorSchema", () => {
  it("should default to #000000 when omitted", () => {
    expect(strokeColorSchema.parse(undefined)).toBe("#000000");
  });

  it("should accept a 6-digit hex color", () => {
    expect(strokeColorSchema.parse("#1a2B3c")).toBe("#1a2B3c");
  });

  it("should reject a 3-digit hex color", () => {
    expect(() => strokeColorSchema.parse("#abc")).toThrow();
  });

  it("should reject a hex color without the leading hash", () => {
    expect(() => strokeColorSchema.parse("000000")).toThrow();
  });

  it("should reject a named color", () => {
    expect(() => strokeColorSchema.parse("black")).toThrow();
  });

  it("should reject an 8-digit hex color", () => {
    expect(() => strokeColorSchema.parse("#000000ff")).toThrow();
  });
});
