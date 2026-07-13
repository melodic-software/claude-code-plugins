/**
 * Resource discovery tool for course-digest.
 *
 * Navigates lesson pages and reports available resource types per lesson.
 * Does NOT extract content — discovery and reporting only.
 * Uses the adapter pattern for platform-specific resource detection.
 *
 * Usage:
 *   node discover-resources.js --course-dir <path> [options]
 *
 * Options:
 *   --course-dir       Path to directory containing course.json (required)
 *   --sample           Check a representative sample per module (default: all lessons)
 *   --no-headless      Show the browser window (default: headless)
 */

import { writeFileSync } from "node:fs";
import { join } from "node:path";

import { createLogger } from "@melodic/video-digestion/shared/logger";

import { createAdapter } from "./adapters/adapter-contract.js";
import { resolveAuthStatePath } from "./lib/auth-store.js";
import { checkAuthAge, closeBrowser, launchBrowser } from "./lib/browser.js";
import { findFirstVideoLesson, loadCourseDir, parseCliArgs, resolveLogLevel } from "./utils.js";

const args = parseCliArgs({
  sample: { type: "boolean", default: false },
  headless: { type: "boolean", default: true },
});
const log = createLogger(resolveLogLevel(args));

/**
 * Select a representative sample of lessons from each module.
 * Picks: first lesson, last lesson, and one from the middle.
 */
function selectSample(modules) {
  const sampled = [];
  for (const mod of modules) {
    const lessons = mod.lessons;
    if (lessons.length === 0) continue;

    const indices = new Set([0, lessons.length - 1]);
    if (lessons.length > 2) indices.add(Math.floor(lessons.length / 2));

    for (const i of indices) {
      sampled.push({ module: mod, lesson: lessons[i] });
    }
  }
  return sampled;
}

function formatLessonLabel(mod, lesson) {
  return `M${mod.position}L${lesson.position}`;
}

function recordNonVideoLesson(mod, lesson, report) {
  report.push({
    module: mod.position,
    lesson: lesson.position,
    title: lesson.title,
    type: "non-video",
    hasVideo: false,
    hasTranscript: false,
    hasDownload: false,
    hasLessonNotes: false,
    hasReadThisLesson: false,
  });
}

async function navigateToLesson(page, url) {
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 15000 });
  await page.waitForLoadState("networkidle", { timeout: 10000 }).catch(() => {});
  await page.waitForTimeout(1500);
}

async function inspectLesson({ module: mod, lesson }, ctx) {
  const label = formatLessonLabel(mod, lesson);

  if (!lesson.duration || lesson.title === "Rate this course") {
    recordNonVideoLesson(mod, lesson, ctx.report);
    log.info(
      `  ${label.padEnd(7)}${lesson.title.substring(0, 46).padEnd(48)}(non-video — skipped)`,
    );
    return;
  }

  const url = ctx.adapter.buildLessonUrl(ctx.course, lesson, ctx.platformCfg);
  try {
    await navigateToLesson(ctx.page, url);
  } catch {
    log.warn(`  ${label.padEnd(7)}${lesson.title.substring(0, 46).padEnd(48)}FAILED (nav error)`);
    return;
  }

  const resourceResult = await ctx.adapter.detectResources(ctx.page, ctx.platformCfg);
  if (!resourceResult.success) {
    log.warn(
      `  ${label.padEnd(7)}${lesson.title.substring(0, 46).padEnd(48)}FAILED (detect error)`,
    );
    return;
  }

  ctx.checked++;
  const resources = resourceResult.data;
  ctx.report.push({
    module: mod.position,
    lesson: lesson.position,
    title: lesson.title,
    slug: lesson.slug,
    ...resources,
  });

  const flag = (val) => (val ? "✓" : "·");
  log.info(
    "  " +
      label.padEnd(7) +
      lesson.title.substring(0, 46).padEnd(48) +
      flag(resources.hasVideo).padEnd(7) +
      flag(resources.hasTranscript).padEnd(6) +
      flag(resources.hasDownload).padEnd(5) +
      flag(resources.hasLessonNotes).padEnd(7) +
      flag(resources.hasReadThisLesson),
  );
}

async function inspectAllLessons(lessonList, ctx) {
  await lessonList.reduce(async (chain, entry) => {
    await chain;
    await inspectLesson(entry, ctx);
  }, Promise.resolve());
}

async function main() {
  const { courseDir, course } = loadCourseDir(args, { logger: log });
  const platformCfg = course.platformConfig ?? {};

  log.info(`\n  ${course.title} — Resource Discovery`);
  log.info(`  Platform: ${course.platform ?? "unknown"}`);
  log.debug(`  Node: ${process.version} | OS: ${process.platform}`);

  if (!course.platform) {
    log.error(
      "  course.json missing required 'platform' field. Set to 'dometrain', 'teachable', etc.",
    );
    process.exit(1);
  }
  const storageStatePath = resolveAuthStatePath(course.platform);
  const adapterResult = await createAdapter(course.platform, platformCfg);
  if (!adapterResult.success) {
    log.error(`  ${adapterResult.error}`);
    process.exit(1);
  }
  const adapter = adapterResult.data;

  checkAuthAge(storageStatePath, platformCfg);

  const lessonList = args.sample
    ? selectSample(course.modules)
    : course.modules.flatMap((mod) => mod.lessons.map((lesson) => ({ module: mod, lesson })));

  const modeLabel = args.sample
    ? `sample (${lessonList.length} lessons from ${course.modules.length} modules)`
    : `full (${lessonList.length} lessons)`;
  log.info(`  Mode: ${modeLabel}`);

  log.info("  Launching Playwright Chromium...\n");
  const { browser, context, page, authDir, cookieCount } = await launchBrowser({
    headless: args.headless,
    storageStatePath,
    profilePrefix: "discover-resources",
  });
  if (cookieCount > 0) log.info(`  Injected ${cookieCount} saved cookies.`);

  const videoSelector = platformCfg.videoPlayerSelector ?? "video";

  // Verify auth against the first video lesson to avoid false "not authenticated" errors
  // when course.modules[0].lessons[0] is a non-video intro or announcement with no player.
  const firstVideoLesson = findFirstVideoLesson(course.modules);
  if (!firstVideoLesson) {
    log.error("  ✗ No video lessons found in course.json. Cannot verify authentication.");
    await closeBrowser(context, authDir, browser);
    process.exit(1);
  }
  const authCheckUrl = adapter.buildLessonUrl(course, firstVideoLesson, platformCfg);
  await page.goto(authCheckUrl, { waitUntil: "domcontentloaded", timeout: 15000 }).catch(() => {});
  await page.waitForLoadState("networkidle", { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(2000);

  const hasPlayer = await page
    .evaluate((sel) => !!document.querySelector(sel), videoSelector)
    .catch(() => false);

  if (!hasPlayer) {
    log.error(
      "  ✗ Not authenticated. Run extract-course.js first to establish the auth session.",
    );
    await closeBrowser(context, authDir, browser);
    process.exit(1);
  }
  log.info("  ✓ Authenticated\n");

  log.info(
    "  " +
      "Mod".padEnd(7) +
      "Lesson".padEnd(48) +
      "Video".padEnd(7) +
      "Txpt".padEnd(6) +
      "DL".padEnd(5) +
      "Notes".padEnd(7) +
      "Read",
  );
  log.info(`  ${"-".repeat(80)}`);

  const report = [];
  const discoveryCtx = {
    adapter,
    course,
    page,
    platformCfg,
    report,
    checked: 0,
  };
  await inspectAllLessons(lessonList, discoveryCtx);
  const checked = discoveryCtx.checked;

  await closeBrowser(context, authDir, browser);

  const withDownload = report.filter((r) => r.hasDownload).length;
  const withNotes = report.filter((r) => r.hasLessonNotes).length;
  const withRead = report.filter((r) => r.hasReadThisLesson).length;
  const withVideo = report.filter((r) => r.hasVideo).length;

  log.info(`\n  ----------------------------------------`);
  log.info(`  Checked: ${checked} lessons`);
  log.info(
    `  Video: ${withVideo} | Download: ${withDownload} | Notes: ${withNotes} | Read: ${withRead}`,
  );

  const reportPath = join(courseDir, "discovery-report.json");
  writeFileSync(
    reportPath,
    JSON.stringify(
      {
        course: course.title,
        platform: course.platform,
        discoveredAt: new Date().toISOString(),
        mode: args.sample ? "sample" : "full",
        summary: {
          totalLessons: lessonList.length,
          checked,
          withVideo,
          withDownload,
          withNotes,
          withReadThisLesson: withRead,
        },
        lessons: report,
      },
      null,
      2,
    ),
    "utf-8",
  );
  log.info(`  Report: ${reportPath}\n`);
}

main().catch((e) => {
  log.error("Fatal error:", e);
  process.exit(1);
});
