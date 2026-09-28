import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { stripCaptionHtmlEntities } from "./manual-caption-clean.js";

describe("stripCaptionHtmlEntities", () => {
  it("decodes exactly one entity layer", () => {
    assert.equal(
      stripCaptionHtmlEntities("&amp;lt;script&amp;gt;"),
      "&lt;script&gt;",
    );
  });

  it("decodes entity names case-insensitively", () => {
    assert.equal(stripCaptionHtmlEntities("A&NBSP;B &LT; C"), "A B < C");
  });
});
