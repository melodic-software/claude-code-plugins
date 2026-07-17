import { describe, expect, it } from "vitest";

import {
  findPinnedComment,
  parseChapters,
  parseComments,
  parseVideoMetadata,
} from "./video-metadata.js";

describe("parseVideoMetadata", () => {
  it("parses chapters, description, heatmap, and pinned comments", () => {
    const metadata = parseVideoMetadata({
      id: "7zZy1QTvokM",
      title: "Sample Talk",
      description: "Talk description",
      heatmap: { values: [1, 2, 3] },
      chapters: [
        { start_time: 0, title: "Intro" },
        { start_time: 120.5, title: "Demo" },
      ],
      comments: [
        { text: "Regular comment", is_pinned: false },
        { text: "Pinned link: https://example.com", is_pinned: true },
      ],
    });

    expect(metadata.id).toBe("7zZy1QTvokM");
    expect(metadata.title).toBe("Sample Talk");
    expect(metadata.description).toBe("Talk description");
    expect(metadata.heatmap).toEqual({ values: [1, 2, 3] });
    expect(metadata.chapters).toEqual([
      { startSec: 0, title: "Intro" },
      { startSec: 120.5, title: "Demo" },
    ]);
    expect(findPinnedComment(metadata.comments)).toBe("Pinned link: https://example.com");
  });

  it("tolerates missing optional fields", () => {
    const metadata = parseVideoMetadata({ id: "abc", title: "Only title" });
    expect(metadata.description).toBe("");
    expect(metadata.chapters).toEqual([]);
    expect(metadata.heatmap).toBeNull();
    expect(metadata.comments).toEqual([]);
  });
});

describe("parseChapters", () => {
  it("drops invalid chapter entries", () => {
    expect(parseChapters([{ start_time: 5 }, { title: "Valid", start_time: 1 }])).toEqual([
      { startSec: 1, title: "Valid" },
    ]);
  });
});

describe("parseComments", () => {
  it("defaults is_pinned to false", () => {
    expect(parseComments([{ text: "hello" }])).toEqual([{ text: "hello", is_pinned: false }]);
  });
});
