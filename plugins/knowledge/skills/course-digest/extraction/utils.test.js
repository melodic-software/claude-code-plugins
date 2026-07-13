import { describe, expect, it } from "vitest";

import {
  courseBaseUrl,
  detectFrameMethod,
  findFirstVideoLesson,
  formatTranscriptMd,
  lessonDirName,
  parseDuration,
  resolveLogLevel,
} from "./utils.js";

describe("lessonDirName", () => {
  it("should generate zero-padded kebab-case directory name", () => {
    expect(lessonDirName(1, "Welcome")).toBe("01-welcome");
  });

  it("should zero-pad single digit positions", () => {
    expect(lessonDirName(3, "What is TDD?")).toBe("03-what-is-tdd");
  });

  it("should handle double-digit positions", () => {
    expect(lessonDirName(12, "Advanced Topics")).toBe("12-advanced-topics");
  });

  it("should truncate long titles to 60 chars", () => {
    const longTitle = "A".repeat(80);
    const result = lessonDirName(1, longTitle);
    expect(result.length).toBeLessThanOrEqual(63); // 2 (pad) + 1 (-) + 60
  });

  it("should strip special characters", () => {
    expect(lessonDirName(1, "What's the C# way?")).toBe("01-whats-the-c-way");
  });
});

describe("parseDuration", () => {
  it("should parse minutes and seconds", () => {
    expect(parseDuration("5m 30s")).toBe(330);
  });

  it("should parse zero minutes", () => {
    expect(parseDuration("0m 45s")).toBe(45);
  });

  it("should return 0 for null", () => {
    expect(parseDuration(null)).toBe(0);
  });

  it("should return 0 for invalid string", () => {
    expect(parseDuration("invalid")).toBe(0);
  });

  it("should handle minutes only", () => {
    expect(parseDuration("3m")).toBe(180);
  });
});

describe("courseBaseUrl", () => {
  it("should strip trailing lesson slug", () => {
    const url = "https://dometrain.com/take/course/tdd-csharp-2732006/welcome-54128298/";
    expect(courseBaseUrl(url)).toBe("https://dometrain.com/take/course/tdd-csharp-2732006/");
  });
});

describe("formatTranscriptMd", () => {
  it("should produce correct markdown structure", () => {
    const md = formatTranscriptMd(
      { title: "Welcome", duration: "1m 37s" },
      { title: "Course overview" },
      "[0:00] Hello world.",
    );
    expect(md).toContain("# Welcome");
    expect(md).toContain("**Duration:** 1m 37s");
    expect(md).toContain("**Module:** Course overview");
    expect(md).toContain("## Transcript");
    expect(md).toContain("[0:00] Hello world.");
  });
});

describe("resolveLogLevel", () => {
  it("should return debug when verbose is true", () => {
    expect(resolveLogLevel({ verbose: true })).toBe("debug");
  });

  it("should return warn when quiet is true", () => {
    expect(resolveLogLevel({ quiet: true })).toBe("warn");
  });

  it("should return info by default", () => {
    expect(resolveLogLevel({})).toBe("info");
  });

  it("should prefer verbose over quiet", () => {
    expect(resolveLogLevel({ verbose: true, quiet: true })).toBe("debug");
  });
});

describe("detectFrameMethod", () => {
  it("should detect hybrid when both scene and interval frames exist", () => {
    const frames = [
      { file: "scene_0001.png", isInterval: false },
      { file: "interval_0001.png", isInterval: true },
    ];
    expect(detectFrameMethod(frames)).toBe("hybrid");
  });

  it("should detect scene-only", () => {
    const frames = [{ file: "scene_0001.png", isInterval: false }];
    expect(detectFrameMethod(frames)).toBe("scene");
  });

  it("should detect interval-only", () => {
    const frames = [{ file: "interval_0001.png", isInterval: true }];
    expect(detectFrameMethod(frames)).toBe("interval");
  });

  it("should work with string filenames", () => {
    expect(detectFrameMethod(["scene_0001.png", "interval_0001.png"])).toBe("hybrid");
    expect(detectFrameMethod(["scene_0001.png"])).toBe("scene");
    expect(detectFrameMethod(["interval_0001.png"])).toBe("interval");
  });
});

describe("findFirstVideoLesson", () => {
  const makeLesson = (title, duration) => ({ title, duration });
  const makeModule = (lessons) => ({ lessons });

  it("should return the first lesson that has a duration", () => {
    const modules = [makeModule([makeLesson("Intro", null), makeLesson("Lesson 1", "5m 30s")])];
    expect(findFirstVideoLesson(modules)).toEqual(makeLesson("Lesson 1", "5m 30s"));
  });

  it("should skip intro-only first module and find lesson in second module", () => {
    const modules = [
      makeModule([makeLesson("Welcome", null)]),
      makeModule([makeLesson("Getting Started", "3m 10s")]),
    ];
    expect(findFirstVideoLesson(modules)).toEqual(makeLesson("Getting Started", "3m 10s"));
  });

  it("should skip 'Rate this course' lessons even with duration", () => {
    const modules = [
      makeModule([makeLesson("Rate this course", "1m")]),
      makeModule([makeLesson("Real Lesson", "8m")]),
    ];
    expect(findFirstVideoLesson(modules)).toEqual(makeLesson("Real Lesson", "8m"));
  });

  it("should return null when no video lessons exist", () => {
    const modules = [makeModule([makeLesson("Intro", null), makeLesson("Rate this course", "1m")])];
    expect(findFirstVideoLesson(modules)).toBeNull();
  });

  it("should return null for empty modules array", () => {
    expect(findFirstVideoLesson([])).toBeNull();
  });

  it("should return first video lesson even if not the absolute first lesson", () => {
    const lesson1 = makeLesson("Non-video intro", null);
    const lesson2 = makeLesson("Module overview", null);
    const lesson3 = makeLesson("First real lesson", "12m");
    const modules = [makeModule([lesson1, lesson2, lesson3])];
    expect(findFirstVideoLesson(modules)).toBe(lesson3);
  });
});
