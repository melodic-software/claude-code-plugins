import { describe, expect, it } from "vitest";

import { buildLessonUrl, defaults, deriveLandingUrl } from "./teachable.js";

describe("defaults", () => {
  it("should have hotmart video player selector", () => {
    expect(defaults.videoPlayerSelector).toBe(".hotmart_video_player");
  });

  it("should have teachable auth provider", () => {
    expect(defaults.authProvider).toBe("teachable");
  });

  it("should have subtitle language default", () => {
    expect(defaults.subtitleLanguage).toBe("eng");
  });

  it("should have resource selectors for all Teachable attachment types", () => {
    expect(defaults.resourceSelectors.video).toBe(".lecture-attachment-type-video");
    expect(defaults.resourceSelectors.text).toBe(".lecture-attachment-type-text");
    expect(defaults.resourceSelectors.file).toBe(".lecture-attachment-type-file");
    expect(defaults.resourceSelectors.codeDisplay).toBe(".lecture-attachment-type-code_display");
    expect(defaults.resourceSelectors.pdfEmbed).toBe(".lecture-attachment-type-pdf_embed");
    expect(defaults.resourceSelectors.codeEmbed).toBe(".lecture-attachment-type-code_embed");
  });

  it("should have frame extraction defaults", () => {
    expect(defaults.frameExtraction.sceneThreshold).toBe(0.1);
    expect(defaults.frameExtraction.intervalFps).toBe("1/15");
    expect(defaults.frameExtraction.minFramesForScene).toBe(5);
  });

  it("should have playback and manifest timeouts", () => {
    expect(defaults.playbackWaitMs).toBe(5000);
    expect(defaults.manifestTimeoutMs).toBe(15000);
  });
});

describe("deriveLandingUrl", () => {
  it("should return configured landingUrl when provided", () => {
    const platformCfg = { landingUrl: "https://example.com/landing" };
    expect(deriveLandingUrl("https://example.com/courses/enrolled/123", platformCfg)).toBe(
      "https://example.com/landing",
    );
  });

  it("should strip /enrolled/ segment when no landingUrl configured", () => {
    const url = "https://courses.example.com/courses/enrolled/my-course";
    expect(deriveLandingUrl(url, {})).toBe("https://courses.example.com/courses/my-course");
  });

  it("should return original URL when no /enrolled/ and no landingUrl", () => {
    const url = "https://courses.example.com/courses/my-course";
    expect(deriveLandingUrl(url, {})).toBe(url);
  });
});

describe("buildLessonUrl", () => {
  const course = {
    url: "https://www.courses.example.com/courses/enrolled/12345",
  };

  it("should build URL from platformCfg baseUrl and courseSlug", () => {
    const lesson = { lectureId: "99999", slug: "99999" };
    const platformCfg = {
      baseUrl: "https://www.courses.example.com",
      courseSlug: "my-awesome-course",
    };

    expect(buildLessonUrl(course, lesson, platformCfg)).toBe(
      "https://www.courses.example.com/courses/my-awesome-course/lectures/99999",
    );
  });

  it("should use lectureId over slug when available", () => {
    const lesson = { lectureId: "11111", slug: "some-slug" };
    const platformCfg = {
      baseUrl: "https://www.courses.example.com",
      courseSlug: "the-course",
    };

    expect(buildLessonUrl(course, lesson, platformCfg)).toContain("/lectures/11111");
  });

  it("should fall back to slug when lectureId is missing", () => {
    const lesson = { slug: "lesson-slug" };
    const platformCfg = {
      baseUrl: "https://www.courses.example.com",
      courseSlug: "the-course",
    };

    expect(buildLessonUrl(course, lesson, platformCfg)).toContain("/lectures/lesson-slug");
  });

  it("should extract courseSlug from course URL when not in platformCfg", () => {
    const courseWithSlug = {
      url: "https://www.courses.example.com/courses/modular-monolith/lectures/123",
    };
    const lesson = { lectureId: "456" };
    const platformCfg = { baseUrl: "https://www.courses.example.com" };

    expect(buildLessonUrl(courseWithSlug, lesson, platformCfg)).toBe(
      "https://www.courses.example.com/courses/modular-monolith/lectures/456",
    );
  });
});
