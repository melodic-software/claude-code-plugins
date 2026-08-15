import { describe, expect, it } from "vitest";

import { YOUTUBE_BOT_CHALLENGE_PATTERNS } from "../acquisition/acquire-yt-dlp-auth.js";
import { describeSourceAdapterContract } from "./shared-adapter-suite.js";
import { adapter, YOUTUBE_UNAVAILABLE_PATTERNS } from "./youtube.js";

const WATCH_URL = "https://www.youtube.com/watch?v=7zZy1QTvokM";

describeSourceAdapterContract(adapter, {
  claimedUrls: [
    { url: WATCH_URL, sliceKey: "7zZy1QTvokM" },
    { url: "https://youtu.be/7zZy1QTvokM", sliceKey: "7zZy1QTvokM" },
    { url: "https://www.youtube.com/live/abcdefghijk", sliceKey: "abcdefghijk" },
    { url: "https://www.youtube.com/shorts/7zZy1QTvokM", sliceKey: "7zZy1QTvokM" },
  ],
  unclaimedUrls: [
    "https://www.youtube.com/@somechannel",
    "https://example.com/not-youtube",
    "not a url",
  ],
});

describe("youtube adapter declarations", () => {
  it("declares hosts, extractor args, caption class, and strategy", () => {
    expect(adapter.id).toBe("youtube");
    expect([...adapter.hosts]).toEqual(["youtube.com", "youtu.be"]);
    expect(adapter.extractorArgs).toBe("youtube:max_comments=20,all,top;comment_sort=top");
    expect(adapter.allowedExtractors).toBeNull();
    expect(adapter.captionClass).toBeTruthy();
    expect(adapter.transcriptStrategy).toBe("captions");
  });

  it("declares the comments and browser-cookie-fallback capabilities", () => {
    expect(adapter.capabilities.comments).toBe(true);
    expect(adapter.capabilities.browserCookieFallback).toBe(true);
  });

  it("declares the bot-challenge patterns as login-required and the unavailable set as fatal", () => {
    expect([...adapter.errorPatterns.loginRequired].map(String)).toEqual(
      YOUTUBE_BOT_CHALLENGE_PATTERNS.map(String),
    );
    expect([...adapter.errorPatterns.fatal].map(String)).toEqual(
      YOUTUBE_UNAVAILABLE_PATTERNS.map(String),
    );
    expect(adapter.errorPatterns.fatal.some((p) => p.test("Incomplete YouTube ID"))).toBe(true);
    expect(adapter.errorPatterns.retryable).toEqual([]);
  });
});

describe("extractSliceKey fallback", () => {
  it("falls back to metadata id only when the URL yields no id", () => {
    expect(
      adapter.extractSliceKey("https://www.youtube.com/@somechannel", {
        id: "fallbackId0",
        title: "",
        description: "",
      }),
    ).toBe("fallbackId0");
    expect(adapter.extractSliceKey("https://www.youtube.com/@somechannel", null)).toBeNull();
  });
});

describe("acceptForEnqueue rejection wording", () => {
  it("rejects a non-video URL with the queue-note wording", () => {
    expect(adapter.acceptForEnqueue("https://example.com/not-youtube")).toEqual({
      ok: false,
      note: "not a YouTube video URL",
      reason: "URL does not resolve to a YouTube video id",
    });
  });
});

describe("harvestLinks", () => {
  it("harvests description, chapter, and pinned-comment links with dedupe", () => {
    const links = adapter.harvestLinks({
      id: "7zZy1QTvokM",
      title: "T",
      description: "Docs at https://example.com/docs and https://example.com/docs again",
      chapters: [{ startSec: 30, title: "Intro https://chapter.example.com" }],
      heatmap: null,
      comments: [
        { text: "unpinned https://nope.example.com", is_pinned: false },
        { text: "pinned https://pinned.example.com/resources", is_pinned: true },
      ],
    });

    const urls = links.map((link) => link.url);
    expect(urls).toContain("https://example.com/docs");
    expect(urls.filter((url) => url === "https://example.com/docs")).toHaveLength(1);
    expect(links.find((link) => link.source === "chapter")?.timestampSec).toBe(30);
    const pinned = links.filter((link) => link.source === "pinned-comment");
    expect(pinned).toHaveLength(1);
    expect(pinned[0].url).toBe("https://pinned.example.com/resources");
    expect(urls).not.toContain("https://nope.example.com");
  });
});
