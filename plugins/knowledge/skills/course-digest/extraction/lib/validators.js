/**
 * Declarative check functions for extraction artifact validation.
 *
 * Each check returns { passed, severity, message, details }.
 * Inspired by Great Expectations / dbt / Soda patterns — zero dependencies.
 */

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { lessonDirName, parseDuration } from "../utils.js";

export const PASS = "pass";
export const WARN = "warn";
export const FAIL = "fail";

const PLACEHOLDER_VALUES = ["N/A", "TBD", "Unknown", ""];
const REQUIRED_LESSON_FIELDS = ["position", "title", "slug", "duration"];
const CHARS_PER_MIN_LOW = 400;
const CHARS_PER_MIN_HIGH = 1500;
const TRANSCRIPT_TIMESTAMP_MARKER = /\[\d+:\d{2}\]/;

function check(passed, severity, message, details = {}) {
  return { passed, severity, message, details };
}

function allLessons(course) {
  return course.modules?.flatMap((m) => m.lessons) ?? [];
}

/**
 * Validate course-level metadata completeness.
 * @param {object} course — parsed course.json
 * @returns {Array<{passed, severity, message, details}>}
 */
export function checkMetadata(course) {
  const results = [];

  const required = ["title", "instructor", "platform", "duration", "totalLessons"];
  for (const field of required) {
    const value = course[field];
    const missing = value === undefined || value === null || value === "";
    results.push(
      check(!missing, missing ? FAIL : PASS, `metadata.${field}`, {
        expected: "non-empty",
        actual: value ?? null,
      }),
    );
  }

  if (course.metadata?.datePublished) {
    const isPlaceholder = PLACEHOLDER_VALUES.includes(course.metadata.datePublished);
    results.push(
      check(!isPlaceholder, isPlaceholder ? WARN : PASS, "metadata.datePublished", {
        expected: "valid date or null",
        actual: course.metadata.datePublished,
      }),
    );
  }

  const lessons = allLessons(course);
  const completedCount = lessons.filter(
    (l) => l.status === "extracted" || l.status === "skipped",
  ).length;
  let expectedStatus = "extracted";
  if (completedCount === 0) {
    expectedStatus = "pending";
  } else if (completedCount < lessons.length) {
    expectedStatus = "extracting";
  }
  const statusMatch = course.status === expectedStatus || course.status === "analyzed";
  results.push(
    check(statusMatch, statusMatch ? PASS : WARN, "metadata.status", {
      expected: expectedStatus,
      actual: course.status,
      completedCount,
      totalLessons: lessons.length,
    }),
  );

  return results;
}

/**
 * Validate transcript files for extracted lessons.
 * @param {object} course
 * @param {string} modulesDir
 * @returns {Array}
 */
export function checkTranscripts(course, modulesDir) {
  const results = [];

  for (const mod of course.modules ?? []) {
    for (const lesson of mod.lessons) {
      if (lesson.status !== "extracted") continue;

      const lessonDir = join(modulesDir, mod.slug, lessonDirName(lesson.position, lesson.title));
      const transcriptPath = join(lessonDir, "transcript.md");
      const label = `M${mod.position}L${lesson.position}`;

      if (!existsSync(transcriptPath)) {
        results.push(
          check(false, FAIL, `transcript.missing ${label}`, {
            lesson: lesson.title,
            path: transcriptPath,
          }),
        );
        continue;
      }

      const content = readFileSync(transcriptPath, "utf-8");

      if (content.trim().length < 100) {
        results.push(
          check(false, FAIL, `transcript.empty ${label}`, {
            lesson: lesson.title,
            chars: content.length,
          }),
        );
        continue;
      }

      const durationSec = parseDuration(lesson.duration);
      if (durationSec > 0) {
        const durationMin = durationSec / 60;
        const cpm = content.length / durationMin;
        const tooLow = cpm < CHARS_PER_MIN_LOW;
        const tooHigh = cpm > CHARS_PER_MIN_HIGH;
        if (tooLow || tooHigh) {
          results.push(
            check(false, WARN, `transcript.cpm ${label}`, {
              lesson: lesson.title,
              cpm: Math.round(cpm),
              expected: `${CHARS_PER_MIN_LOW}-${CHARS_PER_MIN_HIGH}`,
              chars: content.length,
              durationMin: Math.round(durationMin * 10) / 10,
            }),
          );
        } else {
          results.push(
            check(true, PASS, `transcript.cpm ${label}`, {
              cpm: Math.round(cpm),
            }),
          );
        }
      }

      const hasTimestamps = TRANSCRIPT_TIMESTAMP_MARKER.test(content);
      if (!hasTimestamps) {
        results.push(
          check(false, WARN, `transcript.timestamps ${label}`, {
            lesson: lesson.title,
          }),
        );
      }
    }
  }

  return results;
}

/**
 * Validate schema consistency across lessons.
 * @param {object} course
 * @returns {Array}
 */
export function checkSchema(course) {
  const results = [];
  const lessons = allLessons(course);

  for (const lesson of lessons) {
    const missing = REQUIRED_LESSON_FIELDS.filter((f) => lesson[f] === undefined);
    if (missing.length > 0) {
      results.push(
        check(false, FAIL, `schema.required M?L${lesson.position}`, {
          missing,
          title: lesson.title,
        }),
      );
    }
  }

  if (lessons.length > 1) {
    const keySets = lessons.map((l) => new Set(Object.keys(l)));
    const allKeys = new Set(lessons.flatMap((l) => Object.keys(l)));
    const inconsistent = [];

    for (const key of allKeys) {
      const presentCount = keySets.filter((ks) => ks.has(key)).length;
      if (presentCount > 0 && presentCount < lessons.length) {
        inconsistent.push({ field: key, present: presentCount, total: lessons.length });
      }
    }

    if (inconsistent.length > 0) {
      results.push(
        check(false, WARN, "schema.consistency", {
          inconsistentFields: inconsistent,
        }),
      );
    } else {
      results.push(check(true, PASS, "schema.consistency", {}));
    }
  }

  const deprecatedFields = ["resourcesDetected"];
  for (const field of deprecatedFields) {
    const count = lessons.filter((l) => l[field] !== undefined).length;
    if (count > 0) {
      results.push(
        check(false, WARN, `schema.deprecated ${field}`, {
          field,
          affectedLessons: count,
          total: lessons.length,
        }),
      );
    }
  }

  return results;
}

/**
 * Validate resource flags match filesystem state.
 * @param {object} course
 * @param {string} modulesDir
 * @returns {Array}
 */
export function checkResourceFlags(course, modulesDir) {
  const results = [];

  for (const mod of course.modules ?? []) {
    for (const lesson of mod.lessons) {
      const lessonDir = join(modulesDir, mod.slug, lessonDirName(lesson.position, lesson.title));
      const label = `M${mod.position}L${lesson.position}`;

      if (lesson.hasTranscript) {
        const exists = existsSync(join(lessonDir, "transcript.md"));
        if (!exists) {
          results.push(
            check(false, FAIL, `resources.transcript ${label}`, {
              lesson: lesson.title,
              flag: true,
              fileExists: false,
            }),
          );
        }
      }

      if (lesson.hasScreenshots) {
        const screenshotsDir = join(lessonDir, "screenshots");
        const exists = existsSync(screenshotsDir);
        const pngCount = exists
          ? readdirSync(screenshotsDir, { recursive: true }).filter((f) =>
              String(f).endsWith(".png"),
            ).length
          : 0;
        if (!exists || pngCount === 0) {
          results.push(
            check(false, FAIL, `resources.screenshots ${label}`, {
              lesson: lesson.title,
              flag: true,
              dirExists: exists,
              pngCount,
            }),
          );
        }
      }
    }
  }

  if (results.length === 0) {
    results.push(check(true, PASS, "resources.flags", { message: "all flags match filesystem" }));
  }

  return results;
}

/**
 * Compare current validation against a previous report for regressions.
 * @param {{ summary: object, checks: Array }} current
 * @param {{ summary: object, checks: Array }|null} previous
 * @returns {Array}
 */
export function checkRegression(current, previous) {
  if (!previous) return [];

  const results = [];
  const prevByName = new Map(previous.checks.map((c) => [c.message, c]));

  for (const curr of current.checks) {
    const prev = prevByName.get(curr.message);
    if (prev?.passed && !curr.passed) {
      results.push(
        check(false, curr.severity === FAIL ? FAIL : WARN, `regression: ${curr.message}`, {
          was: prev.severity,
          now: curr.severity,
        }),
      );
    }
  }

  if (previous.summary && current.summary) {
    const countDrop = previous.summary.passed - current.summary.passed;
    if (countDrop > 0) {
      results.push(
        check(false, WARN, "regression.passCountDrop", {
          previous: previous.summary.passed,
          current: current.summary.passed,
          drop: countDrop,
        }),
      );
    }
  }

  return results;
}
