import path from "node:path";

import { describe, expect, it } from "vitest";

import {
  deriveVideoSlug,
  resolveWorkSliceDir,
  slugifyTitle,
  YOUTUBE_WATCH_EPIC_DIR,
} from "./derive-video-slug.js";

describe("slugifyTitle", () => {
  it("kebab-cases titles", () => {
    expect(slugifyTitle("Hello World: Part 1")).toBe("hello-world-part-1");
  });
});

describe("deriveVideoSlug", () => {
  it("caps title portion and appends video id", () => {
    const longTitle = "A".repeat(60);
    const slug = deriveVideoSlug(longTitle, "7zZy1QTvokM");
    expect(slug.endsWith("-7zZy1QTvokM")).toBe(true);
    expect(slug.length).toBeLessThanOrEqual(40 + 1 + "7zZy1QTvokM".length);
  });

  it("falls back when title slugifies empty", () => {
    expect(deriveVideoSlug("!!!", "abc123")).toBe("video-abc123");
  });

  it("fails closed on slice keys that could traverse or terminate a path", () => {
    for (const hostile of ["../../x", "..", "a/b", "a\\b", "a.b", "", "a b"]) {
      expect(() => deriveVideoSlug("Title", hostile), hostile).toThrow(/Unsafe slice key/);
    }
  });
});

describe("resolveWorkSliceDir", () => {
  it("places slices under .work/<watch-epic>/", () => {
    expect(resolveWorkSliceDir("/repo", "talk-abc")).toBe(
      path.join("/repo", ".work", YOUTUBE_WATCH_EPIC_DIR, "talk-abc"),
    );
  });
});
