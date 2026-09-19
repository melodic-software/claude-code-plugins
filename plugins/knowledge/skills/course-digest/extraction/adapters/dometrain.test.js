import { describe, expect, it } from "vitest";

import { defaults, deriveLandingUrl, preflight } from "./dometrain.js";

describe("deriveLandingUrl", () => {
  const platformCfg = {
    landingUrlPattern: "/take/course/ -> /course/",
  };

  it("should strip /take/ prefix, lesson slug, and numeric courseId", () => {
    const url =
      "https://dometrain.com/take/course/from-zero-to-hero-tdd-csharp-2732006/welcome-54128298/";
    const result = deriveLandingUrl(url, platformCfg);
    expect(result).toBe("https://dometrain.com/course/from-zero-to-hero-tdd-csharp/");
  });

  it("should handle URL without numeric courseId suffix", () => {
    const url = "https://dometrain.com/take/course/some-course-slug/lesson-slug/";
    const result = deriveLandingUrl(url, platformCfg);
    expect(result).toBe("https://dometrain.com/course/some-course-slug/");
  });

  it("should return original URL when no landing pattern", () => {
    const url = "https://dometrain.com/take/course/foo/bar/";
    const result = deriveLandingUrl(url, {});
    expect(result).toBe(url);
  });
});

describe("nullish platformConfig", () => {
  const page = { evaluate: async () => ({}) };

  it("should raise a TypeError rather than fall back to the default selector", async () => {
    await expect(preflight(page, null)).rejects.toThrowError(TypeError);
    await expect(preflight(page, null)).rejects.toThrow(
      "Cannot read properties of null (reading 'videoPlayerSelector')",
    );
  });

  it("should raise the same TypeError for an undefined platformConfig", async () => {
    await expect(preflight(page, undefined)).rejects.toThrow(
      "Cannot read properties of undefined (reading 'videoPlayerSelector')",
    );
  });
});

describe("defaults", () => {
  it("should have mux-player as video selector", () => {
    expect(defaults.videoPlayerSelector).toBe("mux-player");
  });

  it("should have resource button labels", () => {
    expect(defaults.resourceButtons.download).toBe("Download course files");
    expect(defaults.resourceButtons.transcript).toBe("Transcript");
  });

  it("should have frame extraction defaults", () => {
    expect(defaults.frameExtraction.sceneThreshold).toBe(0.1);
    expect(defaults.frameExtraction.intervalFps).toBe("1/15");
    expect(defaults.frameExtraction.minFramesForScene).toBe(5);
  });
});
