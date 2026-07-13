/**
 * Generate manifest.json per lesson with frame classification and transcript pairing.
 *
 * Reads dedup-report.json and course.json, classifies each frame, pairs with
 * nearest transcript segment by timestamp, and writes manifest.json per lesson.
 *
 * Usage:
 *   node generate-manifests.js --course-dir <path>
 *
 * Manifest schema (course-agnostic):
 *   - file: frame filename
 *   - timestamp: estimated video timestamp in seconds
 *   - timestampEstimated: true if linearly interpolated (scene frames),
 *     false if derived from extraction interval (interval frames at 1/15 fps)
 *   - type: classification (code/slide/talking-head)
 *   - description: one-line description (null until visual analysis)
 *   - transcriptContext: nearest transcript segment text
 *   - keep: boolean — true for unique valuable content
 *
 * Classification rules:
 *   - Scene-detected frames → "code" (all keep)
 *   - Interval frames flagged as duplicate → keep only LAST in each consecutive run
 *     (progressive bullet build-up = later frames have more content)
 *   - Interval frames with high dup rate and all interval → "talking-head" (discard)
 *   - Remaining interval frames → "slide"
 *
 * Output: screenshots/manifest.json per lesson directory
 */

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { createLogger } from "@melodic/video-digestion/shared/logger";

import {
  lessonDirName,
  loadCourseDir,
  parseCliArgs,
  parseDuration,
  resolveLogLevel,
} from "./utils.js";

const args = parseCliArgs({
  "dry-run": { type: "boolean", default: false },
});
const log = createLogger(resolveLogLevel(args));

function parseTranscript(transcriptPath) {
  if (!existsSync(transcriptPath)) return [];
  const text = readFileSync(transcriptPath, "utf-8");
  const segments = [];
  const pattern = /\[(\d+):(\d{2})\]\s*(.*?)(?=\n\n\[|\n\n$|$)/gs;
  for (let match = pattern.exec(text); match !== null; match = pattern.exec(text)) {
    const minutes = Number.parseInt(match[1], 10);
    const seconds = Number.parseInt(match[2], 10);
    segments.push({
      timestamp: minutes * 60 + seconds,
      text: match[3].trim(),
    });
  }
  return segments;
}

function nearestSegment(segments, targetTimestamp) {
  if (segments.length === 0) return null;
  let closest = segments[0];
  let minDist = Math.abs(segments[0].timestamp - targetTimestamp);
  for (const seg of segments) {
    const dist = Math.abs(seg.timestamp - targetTimestamp);
    if (dist < minDist) {
      minDist = dist;
      closest = seg;
    }
  }
  return closest;
}

function classifyLesson(dedupEntry, durationSec) {
  const { frames } = dedupEntry;
  const intervalFrames = frames.filter((f) => f.isInterval);
  const sceneFrames = frames.filter((f) => !f.isInterval);

  // Check if this is a talking-head lesson: all interval, high avg size, mostly duplicates
  const isTalkingHead =
    sceneFrames.length === 0 &&
    intervalFrames.length > 3 &&
    dedupEntry.duplicates / dedupEntry.total > 0.8;

  const classified = [];

  for (let i = 0; i < frames.length; i++) {
    const frame = frames[i];
    const isScene = !frame.isInterval;
    const isDup = !!frame.likelyDuplicate;

    // Estimate timestamp from frame position within the video duration
    const position = i / Math.max(frames.length - 1, 1);
    const estimatedTimestamp = Math.round(position * durationSec);

    let type;
    let keep;

    if (isScene) {
      // Scene-detected frames are always code/IDE content
      type = "code";
      keep = true;
    } else if (isTalkingHead) {
      type = "talking-head";
      keep = false;
    } else if (isDup) {
      // For consecutive duplicate runs, keep only the LAST frame in each run
      // (progressive bullet build-up = later frames have more content)
      const nextFrame = frames[i + 1];
      const isLastInRun = !nextFrame?.likelyDuplicate;
      type = "slide";
      keep = isLastInRun;
    } else {
      type = "slide";
      keep = true;
    }

    classified.push({
      file: frame.file,
      timestamp: estimatedTimestamp,
      timestampEstimated: !frame.isInterval,
      type,
      description: null,
      keep,
    });
  }

  return classified;
}

const { courseDir, course } = loadCourseDir(args, { logger: log });
const dedupPath = join(courseDir, "dedup-report.json");

if (!existsSync(dedupPath)) {
  log.error("  dedup-report.json not found. Run classify-frames.js --phase dedup first.");
  process.exit(1);
}

const dedup = JSON.parse(readFileSync(dedupPath, "utf-8"));

log.info(`\n  ${course.title} — Generating manifests\n`);

let totalManifests = 0;
let totalKept = 0;
let totalDiscarded = 0;

for (const module of course.modules) {
  for (const lesson of module.lessons) {
    if (!lesson.hasScreenshots) continue;

    const key = `M${module.position}L${lesson.position}`;
    const dedupEntry = dedup[key];
    if (!dedupEntry) continue;

    const durationSec = parseDuration(lesson.duration);
    const lessonDir = join(
      courseDir,
      "modules",
      module.slug,
      lessonDirName(lesson.position, lesson.title),
    );
    const screenshotsDir = join(lessonDir, "screenshots");
    const transcriptPath = join(lessonDir, "transcript.md");
    const manifestPath = join(screenshotsDir, "manifest.json");

    const classified = classifyLesson(dedupEntry, durationSec);

    // Pair each classified frame with its nearest transcript segment.
    const segments = parseTranscript(transcriptPath);
    for (const frame of classified) {
      const seg = nearestSegment(segments, frame.timestamp);
      if (seg) {
        frame.transcriptContext = seg.text.substring(0, 200);
      }
    }

    const kept = classified.filter((f) => f.keep).length;
    const discarded = classified.length - kept;
    totalKept += kept;
    totalDiscarded += discarded;

    if (!args["dry-run"]) {
      writeFileSync(manifestPath, JSON.stringify(classified, null, 2), "utf-8");
    }

    totalManifests++;
    const pct = Math.round((kept / classified.length) * 100);
    log.info(
      `  ${key} ${lesson.title.substring(0, 42).padEnd(44)} ${String(classified.length).padStart(3)} frames, ${String(kept).padStart(3)} kept (${pct}%)`,
    );
  }
}

log.info(`\n  ────────────────────────────`);
log.info(`  Manifests: ${totalManifests}`);
log.info(`  Kept:      ${totalKept} frames`);
log.info(`  Discarded: ${totalDiscarded} frames`);
log.info(
  `  ${args["dry-run"] ? "(dry run — no files written)" : `Written to: */screenshots/manifest.json`}`,
);
