import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { parseVideoMetadata } from "../acquisition/video-metadata.js";
import {
  deduplicateHarvestedLinks,
  extractUrlsFromText,
  harvestMetadataLinks,
  mergeHarvestedLinks,
  summarizeHeatmap,
} from "./harvest-links.js";

const FIXTURES_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), "fixtures");

/**
 * @param {string} name
 */
function loadFixture(name) {
  const raw = fs.readFileSync(path.join(FIXTURES_DIR, name), "utf8");
  return parseVideoMetadata(JSON.parse(raw));
}

describe("harvestMetadataLinks", () => {
  it("tolerates null heatmap and harvests description + chapter links", () => {
    const metadata = loadFixture("null-heatmap.json");
    const heatmap = summarizeHeatmap(metadata.heatmap);
    expect(heatmap.present).toBe(false);

    const links = harvestMetadataLinks(metadata);
    const urls = links.map((link) => link.url);
    expect(urls).toContain("https://example.com/docs");
    expect(urls).toContain("https://chapter.example.com");
    expect(links.find((l) => l.source === "chapter")?.timestampSec).toBe(0);
  });

  it("handles missing pinned comment without error", () => {
    const metadata = loadFixture("no-pinned-comment.json");
    const heatmap = summarizeHeatmap(metadata.heatmap);
    expect(heatmap.present).toBe(true);
    expect(heatmap.peakCount).toBe(3);

    const links = harvestMetadataLinks(metadata);
    expect(links.some((l) => l.source === "pinned-comment")).toBe(false);
    expect(links.some((l) => l.url === "https://docs.example.com/guide")).toBe(true);
  });

  it("harvests pinned comment links when present", () => {
    const metadata = loadFixture("pinned-present.json");
    const links = harvestMetadataLinks(metadata);

    const pinned = links.filter((l) => l.source === "pinned-comment");
    expect(pinned).toHaveLength(1);
    expect(pinned[0].url).toBe("https://pinned.example.com/resources");
    expect(links.some((l) => l.url === "https://main.example.com/repo")).toBe(true);
  });
});

describe("extractUrlsFromText", () => {
  it("strips trailing punctuation from URLs", () => {
    expect(extractUrlsFromText("Visit https://example.com/page).")).toEqual([
      "https://example.com/page",
    ]);
  });
});

describe("deduplicateHarvestedLinks", () => {
  it("keeps first occurrence per URL", () => {
    const unique = deduplicateHarvestedLinks([
      { url: "https://Example.com/A", source: "description" },
      { url: "https://example.com/a", source: "chapter" },
    ]);
    expect(unique).toHaveLength(1);
    expect(unique[0].source).toBe("description");
  });
});

describe("mergeHarvestedLinks", () => {
  it("merges on-screen links with metadata links", () => {
    const merged = mergeHarvestedLinks(
      [{ url: "https://a.com", source: "description" }],
      [{ url: "https://b.com", source: "on-screen", timestampSec: 42 }],
    );
    expect(merged).toHaveLength(2);
    expect(merged.find((l) => l.source === "on-screen")?.timestampSec).toBe(42);
  });
});
