/**
 * Frame classification pipeline for course-digest.
 *
 * Phases:
 *   contact-sheets  — Generate labeled thumbnail grids per lesson (shared contact-sheet stage)
 *   dedup           — Perceptual-hash near-duplicate detection for interval frames
 *   summary         — Print frame inventory table
 *
 * Usage:
 *   node classify-frames.js --course-dir <path> --phase contact-sheets
 *   node classify-frames.js --course-dir <path> --phase dedup
 *   node classify-frames.js --course-dir <path> --phase summary
 *
 * Requires: ImageMagick 7 on PATH for contact-sheet generation
 */

import { existsSync, mkdirSync, statSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";

import { createContactSheet } from "@melodic/video-digestion/frames/contact-sheet";
import { deduplicateFrames } from "@melodic/video-digestion/frames/dedup";
import { createLogger } from "@melodic/video-digestion/shared/logger";

import {
  detectFrameMethod,
  lessonDirName,
  loadCourseDir,
  parseCliArgs,
  resolveLogLevel,
  walkPngs,
} from "./utils.js";

const args = parseCliArgs({
  phase: { type: "string", default: "contact-sheets" },
});

const log = createLogger(resolveLogLevel(args));

function forEachLesson(courseDir, course, fn) {
  const modulesDir = join(courseDir, "modules");
  for (const module of course.modules) {
    for (const lesson of module.lessons) {
      if (!lesson.hasScreenshots) continue;
      const lDir = join(
        modulesDir,
        module.slug,
        lessonDirName(lesson.position, lesson.title),
        "screenshots",
      );
      const pngs = walkPngs(lDir);
      if (pngs.length === 0) continue;
      fn(module, lesson, pngs);
    }
  }
}

async function generateContactSheets(courseDir, course) {
  const outDir = join(courseDir, "contact-sheets");
  mkdirSync(outDir, { recursive: true });

  let generated = 0;

  for (const entry of collectLessons(courseDir, course)) {
    const { module, lesson, pngs } = entry;
    const label = `M${module.position}L${lesson.position}`;
    const outFile = join(outDir, `${label}-${lessonDirName(lesson.position, lesson.title)}.jpg`);

    if (existsSync(outFile)) {
      log.debug(`  SKIP ${label} ${lesson.title.substring(0, 40)} (exists)`);
      continue;
    }

    // biome-ignore lint/performance/noAwaitInLoops: contact sheets are built sequentially to cap ImageMagick memory
    const sheet = await createContactSheet(pngs, outFile, {}, { log });
    if (sheet) {
      const sizeKB = Math.round(statSync(outFile).size / 1024);
      log.info(
        `  OK  ${label} ${lesson.title.substring(0, 40).padEnd(42)} ${String(pngs.length).padStart(3)} frames → ${sizeKB}KB`,
      );
      generated++;
    }
  }

  log.info(`\n  Generated: ${generated} contact sheets → ${outDir}`);
}

function collectLessons(courseDir, course) {
  /** @type {{ module: object, lesson: object, pngs: string[] }[]} */
  const lessons = [];
  forEachLesson(courseDir, course, (module, lesson, pngs) => {
    lessons.push({ module, lesson, pngs });
  });
  return lessons;
}

async function computeDedup(courseDir, course) {
  let totalFrames = 0;
  let totalDups = 0;
  const results = {};

  for (const { module, lesson, pngs } of collectLessons(courseDir, course)) {
    const key = `M${module.position}L${lesson.position}`;
    // biome-ignore lint/performance/noAwaitInLoops: lesson dedup runs sequentially to cap memory on large courses
    const frameSet = await deduplicateFrames(pngs, {}, { log });

    totalFrames += frameSet.total;
    totalDups += frameSet.duplicates;

    results[key] = {
      title: lesson.title,
      duration: lesson.duration,
      total: frameSet.total,
      duplicates: frameSet.duplicates,
      unique: frameSet.unique.length,
      method: detectFrameMethod(frameSet.frames),
      frames: frameSet.frames.map((frame) => ({
        file: frame.file,
        isInterval: frame.isInterval,
        likelyDuplicate: frame.likelyDuplicate,
        phash: frame.phash,
      })),
    };

    if (frameSet.duplicates > 0) {
      const pct = Math.round((frameSet.duplicates / frameSet.total) * 100);
      log.info(
        `  ${key} ${lesson.title.substring(0, 42).padEnd(44)} ${String(frameSet.total).padStart(3)} frames, ${String(frameSet.duplicates).padStart(2)} dups (${pct}%)`,
      );
    }
  }

  const pct = totalFrames > 0 ? Math.round((totalDups / totalFrames) * 100) : 0;
  log.info(`\n  Total: ${totalFrames} frames, ${totalDups} likely duplicates (${pct}%)`);
  log.info(`  Estimated unique: ~${totalFrames - totalDups} frames`);

  const reportPath = join(courseDir, "dedup-report.json");
  writeFileSync(reportPath, JSON.stringify(results, null, 2), "utf-8");
  log.info(`  Report: ${reportPath}`);
}

function printSummary(courseDir, course) {
  log.info("  Mod  Lesson                                       Frames  Method     AvgKB");
  log.info(`  ${"-".repeat(78)}`);

  let grandTotal = 0;

  forEachLesson(courseDir, course, (module, lesson, pngs) => {
    const sizes = pngs.map((p) => statSync(p).size);
    const avgKB = Math.round(sizes.reduce((a, b) => a + b, 0) / sizes.length / 1024);
    const method = detectFrameMethod(pngs.map((p) => basename(p)));

    log.info(
      `  M${module.position}L${String(lesson.position).padStart(2)}  ${lesson.title.substring(0, 44).padEnd(46)} ${String(pngs.length).padStart(4)}  ${method.padEnd(10)} ${String(avgKB).padStart(4)}`,
    );
    grandTotal += pngs.length;
  });

  log.info(`  ${"-".repeat(78)}`);
  log.info(`  Grand total: ${grandTotal} frames`);
}

const { courseDir, course } = loadCourseDir(args, { logger: log });

log.info(`\n  ${course.title} — Phase: ${args.phase}\n`);

switch (args.phase) {
  // biome-ignore lint/suspicious/noUnnecessaryConditions: args.phase is runtime CLI argv (parseArgs strict:false); reachable via --phase. Biome narrows it to the literal default "contact-sheets".
  case "contact-sheets":
    await generateContactSheets(courseDir, course);
    break;
  // biome-ignore lint/suspicious/noUnnecessaryConditions: args.phase is runtime CLI argv; reachable via --phase dedup. Biome's literal-narrowing to the default is wrong across the argv boundary.
  case "dedup":
    await computeDedup(courseDir, course);
    break;
  // biome-ignore lint/suspicious/noUnnecessaryConditions: args.phase is runtime CLI argv; reachable via --phase summary. Biome's literal-narrowing to the default is wrong across the argv boundary.
  case "summary":
    printSummary(courseDir, course);
    break;
  default:
    log.error(`  Unknown phase: ${args.phase}`);
    process.exit(1);
}
