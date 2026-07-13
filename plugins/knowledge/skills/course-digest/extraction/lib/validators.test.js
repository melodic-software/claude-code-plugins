import { describe, expect, it } from "vitest";

import { checkMetadata, checkRegression, checkSchema, FAIL, PASS, WARN } from "./validators.js";

describe("checkMetadata", () => {
  const baseCourse = {
    title: "Test Course",
    instructor: "Jane Doe",
    platform: "dometrain",
    duration: "2h 30m",
    totalLessons: 10,
    status: "extracted",
    modules: [{ lessons: Array.from({ length: 10 }, () => ({ status: "extracted" })) }],
  };

  it("should pass for complete metadata", () => {
    const results = checkMetadata(baseCourse);
    const fails = results.filter((r) => r.severity === FAIL);
    expect(fails).toHaveLength(0);
  });

  it("should fail for missing required fields", () => {
    const course = { ...baseCourse, instructor: undefined };
    const results = checkMetadata(course);
    const instructorCheck = results.find((r) => r.message === "metadata.instructor");
    expect(instructorCheck.passed).toBe(false);
    expect(instructorCheck.severity).toBe(FAIL);
  });

  it("should warn for datePublished N/A", () => {
    const course = { ...baseCourse, metadata: { datePublished: "N/A" } };
    const results = checkMetadata(course);
    const dateCheck = results.find((r) => r.message === "metadata.datePublished");
    expect(dateCheck.passed).toBe(false);
    expect(dateCheck.severity).toBe(WARN);
  });

  it("should warn when status does not match extraction state", () => {
    const course = { ...baseCourse, status: "pending" };
    const results = checkMetadata(course);
    const statusCheck = results.find((r) => r.message === "metadata.status");
    expect(statusCheck.passed).toBe(false);
    expect(statusCheck.severity).toBe(WARN);
  });

  it("should pass when skipped lessons are counted as completed", () => {
    const course = {
      ...baseCourse,
      status: "extracted",
      modules: [
        {
          lessons: [
            ...Array.from({ length: 9 }, () => ({ status: "extracted" })),
            { status: "skipped" },
          ],
        },
      ],
    };
    const results = checkMetadata(course);
    const statusCheck = results.find((r) => r.message === "metadata.status");
    expect(statusCheck.passed).toBe(true);
  });

  it("should pass when status is analyzed", () => {
    const course = { ...baseCourse, status: "analyzed" };
    const results = checkMetadata(course);
    const statusCheck = results.find((r) => r.message === "metadata.status");
    expect(statusCheck.passed).toBe(true);
  });
});

describe("checkSchema", () => {
  it("should fail for missing required fields", () => {
    const course = {
      modules: [{ lessons: [{ title: "Lesson 1", slug: "l1", duration: "1m" }] }],
    };
    const results = checkSchema(course);
    const reqCheck = results.find((r) => r.message.startsWith("schema.required"));
    expect(reqCheck).toBeDefined();
    expect(reqCheck.severity).toBe(FAIL);
    expect(reqCheck.details.missing).toContain("position");
  });

  it("should warn on inconsistent fields across lessons", () => {
    const course = {
      modules: [
        {
          lessons: [
            { position: 1, title: "A", slug: "a", duration: "1m", hasNotes: true },
            { position: 2, title: "B", slug: "b", duration: "2m", hasDownload: false },
          ],
        },
      ],
    };
    const results = checkSchema(course);
    const consCheck = results.find((r) => r.message === "schema.consistency");
    expect(consCheck.passed).toBe(false);
    expect(consCheck.severity).toBe(WARN);
    const fields = consCheck.details.inconsistentFields.map((f) => f.field);
    expect(fields).toContain("hasNotes");
    expect(fields).toContain("hasDownload");
  });

  it("should pass for consistent schema", () => {
    const course = {
      modules: [
        {
          lessons: [
            { position: 1, title: "A", slug: "a", duration: "1m", hasTranscript: true },
            { position: 2, title: "B", slug: "b", duration: "2m", hasTranscript: false },
          ],
        },
      ],
    };
    const results = checkSchema(course);
    const consCheck = results.find((r) => r.message === "schema.consistency");
    expect(consCheck.passed).toBe(true);
  });

  it("should warn on deprecated fields", () => {
    const course = {
      modules: [
        {
          lessons: [
            { position: 1, title: "A", slug: "a", duration: "1m", resourcesDetected: true },
          ],
        },
      ],
    };
    const results = checkSchema(course);
    const depCheck = results.find((r) => r.message.startsWith("schema.deprecated"));
    expect(depCheck).toBeDefined();
    expect(depCheck.severity).toBe(WARN);
  });
});

describe("checkRegression", () => {
  it("should return empty when no previous report", () => {
    const current = { summary: { passed: 5 }, checks: [] };
    const results = checkRegression(current, null);
    expect(results).toHaveLength(0);
  });

  it("should detect pass-to-fail regression", () => {
    const previous = {
      summary: { passed: 3 },
      checks: [{ message: "transcript.cpm M1L1", passed: true, severity: PASS }],
    };
    const current = {
      summary: { passed: 2 },
      checks: [{ message: "transcript.cpm M1L1", passed: false, severity: WARN }],
    };
    const results = checkRegression(current, previous);
    expect(results.length).toBeGreaterThan(0);
    const reg = results.find((r) => r.message.includes("M1L1"));
    expect(reg).toBeDefined();
    expect(reg.passed).toBe(false);
  });

  it("should warn on pass count drop", () => {
    const previous = { summary: { passed: 10 }, checks: [] };
    const current = { summary: { passed: 7 }, checks: [] };
    const results = checkRegression(current, previous);
    const dropCheck = results.find((r) => r.message === "regression.passCountDrop");
    expect(dropCheck).toBeDefined();
    expect(dropCheck.details.drop).toBe(3);
  });
});
