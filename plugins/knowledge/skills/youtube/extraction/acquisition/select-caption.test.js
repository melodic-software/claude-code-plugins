import { describe, expect, it } from "vitest";

import { classifyCaptionRung, selectCaptionFile } from "./select-caption.js";

describe("classifyCaptionRung", () => {
  it("classifies manual English captions", () => {
    expect(classifyCaptionRung("/tmp/abc.en.vtt")).toBe("manual-en");
    expect(classifyCaptionRung("/tmp/abc.en-us.vtt")).toBe("manual-en");
  });

  it("classifies auto English captions", () => {
    expect(classifyCaptionRung("/tmp/abc.en.en-orig.vtt")).toBe("auto-en");
    expect(classifyCaptionRung("/tmp/abc.en.auto.vtt")).toBe("auto-en");
  });

  it("classifies auto-translated English captions", () => {
    expect(classifyCaptionRung("/tmp/abc.en.ja.vtt")).toBe("auto-translate-en");
    expect(classifyCaptionRung("/tmp/abc.en.tlang.vtt")).toBe("auto-translate-en");
  });
});

describe("selectCaptionFile", () => {
  it("prefers manual EN over auto EN", () => {
    const result = selectCaptionFile([
      "/tmp/7zZy1QTvokM.en.en-orig.vtt",
      "/tmp/7zZy1QTvokM.en.vtt",
    ]);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.selection.rung).toBe("manual-en");
      expect(result.selection.path).toContain(".en.vtt");
      expect(result.selection.isAutoCaption).toBe(false);
    }
  });

  it("selects auto EN when manual is absent (driver video case)", () => {
    const result = selectCaptionFile(["/tmp/7zZy1QTvokM.en.en-orig.vtt"]);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.selection.rung).toBe("auto-en");
      expect(result.selection.isAutoCaption).toBe(true);
    }
  });

  it("falls through to auto-translate EN", () => {
    const result = selectCaptionFile(["/tmp/clip.en.ja.vtt"]);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.selection.rung).toBe("auto-translate-en");
    }
  });

  it("returns error when no English captions exist", () => {
    const result = selectCaptionFile(["/tmp/clip.ja.vtt", "/tmp/clip.fr.vtt"]);
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error).toContain("ladder exhausted");
      expect(result.available).toEqual(["/tmp/clip.ja.vtt", "/tmp/clip.fr.vtt"]);
    }
  });
});
