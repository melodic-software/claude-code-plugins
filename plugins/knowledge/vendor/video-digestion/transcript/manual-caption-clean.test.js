import { describe, expect, it } from "vitest";

import { stripCaptionHtmlEntities } from "./manual-caption-clean.js";

describe("stripCaptionHtmlEntities", () => {
  it("decodes exactly one entity layer", () => {
    expect(stripCaptionHtmlEntities("&amp;lt;script&amp;gt;")).toBe(
      "&lt;script&gt;",
    );
  });

  it("decodes entity names case-insensitively", () => {
    expect(stripCaptionHtmlEntities("A&NBSP;B &LT; C")).toBe("A B < C");
  });
});
