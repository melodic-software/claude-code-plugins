/**
 * Provider-agnostic utilities for course-extraction scripts.
 *
 * Platform-specific code (transcript extraction, resource detection,
 * HLS URL capture, landing URL derivation) lives in adapters/{platform}.js.
 */

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";

import { createLogger } from "@melodic/video-digestion/shared/logger";
import { writeStdout } from "@melodic/video-digestion/shared/terminal";

const DURATION_PATTERN = /(\d+)m\s*(\d+)?s?/;

export function lessonDirName(position, title) {
  const padded = String(position).padStart(2, "0");
  const slug = title
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "")
    .substring(0, 60);
  return `${padded}-${slug}`;
}

export function parseDuration(durationStr) {
  if (!durationStr) return 0;
  const parts = durationStr.match(DURATION_PATTERN);
  if (!parts) return 0;
  return (Number.parseInt(parts[1], 10) || 0) * 60 + (Number.parseInt(parts[2], 10) || 0);
}

export function walkPngs(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const f of readdirSync(dir).sort()) {
    const fp = join(dir, f);
    if (statSync(fp).isDirectory()) walkPngs(fp, out);
    else if (f.endsWith(".png")) out.push(fp);
  }
  return out;
}

export function courseBaseUrl(courseUrl) {
  return courseUrl.substring(0, courseUrl.lastIndexOf("/", courseUrl.length - 2) + 1);
}

// Workaround: storageState doesn't reliably inject cookies
// on launchPersistentContext (Playwright #14949, #35466, #36139).
export async function injectSavedCookies(context, storageStatePath) {
  if (!existsSync(storageStatePath)) return 0;
  try {
    const state = JSON.parse(readFileSync(storageStatePath, "utf-8"));
    if (state.cookies?.length > 0) {
      await context.addCookies(state.cookies);
      return state.cookies.length;
    }
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    writeStdout(`  Warning: could not load auth state: ${message}`);
  }
  return 0;
}

export function formatTranscriptMd(lesson, module, transcript) {
  return [
    `# ${lesson.title}`,
    "",
    `**Duration:** ${lesson.duration}`,
    `**Module:** ${module.title}`,
    "",
    "## Transcript",
    "",
    transcript,
    "",
  ].join("\n");
}

export function resolveLogLevel(args) {
  if (args.verbose) return "debug";
  if (args.quiet) return "warn";
  return "info";
}

/**
 * @param {Record<string, unknown>} args
 * @param {{ logger?: ReturnType<typeof createLogger> }} [options]
 */
export function loadCourseDir(args, { logger } = {}) {
  const log = logger ?? createLogger("info");

  if (!args["course-dir"]) {
    log.error("  --course-dir is required");
    process.exit(1);
  }

  const courseDir = resolve(args["course-dir"]);
  const courseJsonPath = join(courseDir, "course.json");

  if (!existsSync(courseJsonPath)) {
    log.error(`  course.json not found at: ${courseJsonPath}`);
    process.exit(1);
  }

  const course = JSON.parse(readFileSync(courseJsonPath, "utf-8"));
  return { courseDir, courseJsonPath, course };
}

/** @type {import('node:util').ParseArgsOptionsConfig} */
export const baseCliOptions = {
  "course-dir": { type: "string" },
  verbose: { type: "boolean", short: "v", default: false },
  quiet: { type: "boolean", short: "q", default: false },
};

export function parseCliArgs(scriptOptions = {}) {
  const { values } = parseArgs({
    options: { ...baseCliOptions, ...scriptOptions },
    strict: false,
  });
  return values;
}

export function findFirstVideoLesson(modules) {
  for (const mod of modules) {
    for (const lesson of mod.lessons) {
      if (lesson.duration && lesson.title !== "Rate this course") {
        return lesson;
      }
    }
  }
  return null;
}

export function detectFrameMethod(frames) {
  const hasScene = frames.some((f) =>
    typeof f === "string" ? f.includes("scene_") : !f.isInterval,
  );
  const hasInterval = frames.some((f) =>
    typeof f === "string" ? f.includes("interval_") : f.isInterval,
  );
  if (hasScene && hasInterval) return "hybrid";
  if (hasScene) return "scene";
  return "interval";
}
