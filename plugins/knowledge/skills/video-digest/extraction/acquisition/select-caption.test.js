import { describe, expect, it } from "vitest";

import { classifyCaptionRung, selectCaptionFile } from "./select-caption.js";

describe("classifyCaptionRung (platform-asr class)", () => {
  it("classifies an X-style bare .en.vtt as platform ASR, never manual-en", () => {
    expect(classifyCaptionRung("/w/1001551417340022785.en.vtt", "platform-asr")).toBe(
      "platform-asr-en",
    );
    expect(classifyCaptionRung("/w/123.en-us.vtt", "platform-asr")).toBe("platform-asr-en");
    expect(classifyCaptionRung("/w/123.en-gb.vtt", "platform-asr")).toBe("platform-asr-en");
  });

  it("classifies the raw und LANGUAGE fallback", () => {
    expect(classifyCaptionRung("/w/123.und.vtt", "platform-asr")).toBe("platform-asr-und");
  });

  it("returns null for non-English tracks and non-vtt files", () => {
    expect(classifyCaptionRung("/w/123.ja.vtt", "platform-asr")).toBeNull();
    expect(classifyCaptionRung("/w/123.en.srt", "platform-asr")).toBeNull();
  });

  it("throws on an unknown caption class", () => {
    expect(() =>
      classifyCaptionRung("/w/123.en.vtt", /** @type {never} */ ("telepathy")),
    ).toThrow(/Unknown captionClass/);
  });
});

describe("selectCaptionFile (platform-asr class)", () => {
  it("selects the EN track as auto-class (the X .en.vtt misclassification fix)", () => {
    const result = selectCaptionFile(["/w/1001551417340022785.en.vtt"], "platform-asr");
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.selection.rung).toBe("platform-asr-en");
      expect(result.selection.isAutoCaption).toBe(true);
    }
  });

  it("prefers EN over und, and falls back to und", () => {
    const preferred = selectCaptionFile(["/w/a.und.vtt", "/w/a.en.vtt"], "platform-asr");
    expect(preferred.success).toBe(true);
    if (preferred.success) {
      expect(preferred.selection.rung).toBe("platform-asr-en");
    }
    const fallback = selectCaptionFile(["/w/a.und.vtt"], "platform-asr");
    expect(fallback.success).toBe(true);
    if (fallback.success) {
      expect(fallback.selection.rung).toBe("platform-asr-und");
      expect(fallback.selection.isAutoCaption).toBe(true);
    }
  });

  it("exhausts the platform ladder on non-English-only tracks", () => {
    const result = selectCaptionFile(["/w/a.ja.vtt"], "platform-asr");
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error).toContain("platform-ASR EN → und ladder exhausted");
    }
  });
});

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

  it("prefers the original en-orig track over a bare auto .en.vtt when no manual English exists (#6740)", () => {
    const result = selectCaptionFile(["x.en.vtt", "x.en-orig.vtt"], "manual-and-auto", {
      manualLanguages: [],
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.selection.path).toBe("x.en-orig.vtt");
      expect(result.selection.rung).toBe("auto-en");
      expect(result.selection.isAutoCaption).toBe(true);
    }
  });

  it("classifies a bare .en.vtt as auto-en when info.json lists no manual English subtitles", () => {
    const result = selectCaptionFile(["/w/_U-O5lYhJ7Q.en.vtt"], "manual-and-auto", {
      manualLanguages: [],
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.selection.rung).toBe("auto-en");
      expect(result.selection.isAutoCaption).toBe(true);
      expect(result.selection.provenanceNote).toContain("_U-O5lYhJ7Q.en.vtt");
    }
  });

  it("picks the manual en track over translations of manual tracks listed before it (#6812)", () => {
    // yt-dlp keys a translation of manual track <lang> as en-<lang>; info.json `subtitles` holds en and de.
    const result = selectCaptionFile(
      ["/w/jNQXAC9IVRw.en-en.vtt", "/w/jNQXAC9IVRw.en-de.vtt", "/w/jNQXAC9IVRw.en.vtt"],
      "manual-and-auto",
      { manualLanguages: ["en", "de"] },
    );
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.selection.path).toBe("/w/jNQXAC9IVRw.en.vtt");
      expect(result.selection.rung).toBe("manual-en");
    }
  });

  it("classifies a translation of a non-English manual track as auto-translate-en", () => {
    const result = selectCaptionFile(["/w/a.en-de.vtt"], "manual-and-auto", {
      manualLanguages: ["de"],
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.selection.rung).toBe("auto-translate-en");
      expect(result.selection.isAutoCaption).toBe(true);
    }
  });

  it("keeps manual-en when info.json lists manual English subtitles", () => {
    // yt-dlp names a manual track's file by its info.json `subtitles` key.
    /** @type {Array<[string[], string[], string]>} */
    const cases = [
      [["en"], ["/w/a.en.vtt", "/w/a.en-orig.vtt"], "/w/a.en.vtt"],
      [["fr", "en-US"], ["/w/a.en.vtt", "/w/a.en-orig.vtt", "/w/a.en-US.vtt"], "/w/a.en-US.vtt"],
    ];
    for (const [manualLanguages, files, manualFile] of cases) {
      const result = selectCaptionFile(files, "manual-and-auto", { manualLanguages });
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.selection.path).toBe(manualFile);
        expect(result.selection.rung).toBe("manual-en");
        expect(result.selection.isAutoCaption).toBe(false);
        expect(result.selection.provenanceNote).toBeUndefined();
      }
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
