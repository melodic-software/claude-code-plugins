/**
 * Course extraction orchestrator.
 *
 * Delegates all platform-specific work to the adapter pattern:
 *   adapters/{platform}.js  — transcript, HLS, resources, metadata, auth
 *   lib/browser.js          — shared Playwright infrastructure
 *   lib/config.js            — platformConfig validation, adapter resolution
 *   @melodic/video-digestion/shared/result — Result type, structured logging
 *
 * Frame extraction (ffmpeg) stays here — it's provider-agnostic.
 *
 * Usage:
 *   node extract-course.js --course-dir <path> [options]
 *
 * Options:
 *   --course-dir       Path to directory containing course.json (required)
 *   --extract-frames   Also capture HLS URLs and extract video frames via ffmpeg
 *   --metadata-only    Only extract course metadata from the landing page, then exit
 *   --skip-transcripts Skip transcript extraction (useful when re-running for frames only)
 *   --no-headless      Show the browser window (default: headless)
 */

import { spawnSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { join } from "node:path";

import { extractSceneFrames } from "@melodic/video-digestion/frames/scene-detect";
import { createLogger } from "@melodic/video-digestion/shared/logger";
import { createTracker } from "@melodic/video-digestion/shared/progress";

import { createAdapter } from "./adapters/adapter-contract.js";
import { createRunStats, runLessonExtraction } from "./extract-course-run.js";
import { resolveAuthStatePath } from "./lib/auth-store.js";
import { checkAuthAge, closeBrowser, launchBrowser } from "./lib/browser.js";
import { courseBaseUrl, loadCourseDir, parseCliArgs, resolveLogLevel } from "./utils.js";

const args = parseCliArgs({
  "extract-frames": { type: "boolean", default: false },
  "metadata-only": { type: "boolean", default: false },
  "skip-transcripts": { type: "boolean", default: false },
  headless: { type: "boolean", default: true },
  "show-browser": { type: "boolean", default: false },
});
const log = createLogger(resolveLogLevel(args));

async function navigateWithFallback(page, url) {
  try {
    await page.goto(url, { waitUntil: "networkidle", timeout: 15000 });
    return true;
  } catch {
    try {
      await page.goto(url, { waitUntil: "domcontentloaded", timeout: 15000 });
      return true;
    } catch {
      return false;
    }
  }
}

async function extractFrames(hlsUrl, outputDir, referer, frameConfig = {}) {
  const result = await extractSceneFrames(
    hlsUrl,
    outputDir,
    {
      sceneThreshold: frameConfig.sceneThreshold,
      intervalFps: frameConfig.intervalFps,
      minFramesForScene: frameConfig.minFramesForScene,
      referer,
    },
    { log },
  );

  return {
    method: result.method,
    sceneCount: result.sceneCount,
    intervalCount: result.intervalCount,
    count: result.count,
  };
}

function ensureFfmpegAvailable() {
  if (!args["extract-frames"]) return;
  const ffCheck = spawnSync("ffmpeg", ["-version"], { stdio: "pipe" });
  if (ffCheck.status !== 0) {
    log.error("  ffmpeg not found on PATH. Required for --extract-frames.");
    process.exit(1);
  }
  log.info("  ffmpeg: available");
}

async function runPreflight({ adapter, page, platformCfg, context, authDir, browser }) {
  if (!adapter.preflight) return 0;

  const pfStart = performance.now();
  const preflightResult = await adapter.preflight(page, platformCfg);
  const preflightDurationMs = Math.round(performance.now() - pfStart);
  log.logResult(preflightResult);

  if (!preflightResult.success) {
    log.error(`\n  ✗ ${preflightResult.error}`);
    log.error("  Aborting — fix the adapter selectors before extracting.\n");
    await closeBrowser(context, authDir, browser);
    process.exit(1);
  }

  const checks = preflightResult.data;
  log.info(
    `  Preflight: video=${checks.videoPlayer ? "✓" : "✗"} transcript-btn=${checks.transcriptButton ? "✓" : "✗"} transcript-panel=${checks.transcriptPanel ? "✓" : "✗"}`,
  );
  return preflightDurationMs;
}

async function runMetadataPhase({
  adapter,
  page,
  course,
  courseJson,
  platformCfg,
  context,
  authDir,
  browser,
}) {
  if (!args["metadata-only"] && course.metadata) return 0;

  log.info("\n  Extracting course metadata...");
  const metaStart = performance.now();
  const metaResult = await adapter.extractMetadata(page, course.url, platformCfg);
  const metadataDurationMs = Math.round(performance.now() - metaStart);
  log.logResult(metaResult);

  if (metaResult.success && Object.keys(metaResult.data).length > 0) {
    course.metadata = metaResult.data;
    writeFileSync(courseJson, JSON.stringify(course, null, 2), "utf-8");
    log.info(`  Metadata found: ${Object.keys(metaResult.data).join(", ")}`);
  } else {
    log.info("  No metadata found on course landing page.");
  }

  if (args["metadata-only"]) {
    await closeBrowser(context, authDir, browser);
    log.info("\n  Done (metadata only).");
    process.exit(0);
  }

  return metadataDurationMs;
}

async function main() {
  const { courseDir, courseJsonPath: courseJson, course } = loadCourseDir(args, { logger: log });
  const modulesDir = join(courseDir, "modules");
  const platformCfg = course.platformConfig ?? {};

  if (!course.platform) {
    log.error(
      "  course.json missing required 'platform' field. Set to 'dometrain', 'teachable', etc.",
    );
    process.exit(1);
  }
  const platformName = course.platform;
  const storageStatePath = resolveAuthStatePath(platformName);

  log.info(`\n  ${course.title} — ${course.totalLessons} lessons`);
  log.info(`  Platform: ${platformName}`);
  log.debug(`  Node: ${process.version} | OS: ${process.platform}`);
  log.debug(
    `  Options: extractFrames=${args["extract-frames"]} skipTranscripts=${args["skip-transcripts"]} metadataOnly=${args["metadata-only"]} headless=${args.headless}`,
  );

  const adapterResult = await createAdapter(platformName, platformCfg);
  if (!adapterResult.success) {
    log.error(`  ${adapterResult.error}`);
    process.exit(1);
  }
  const adapter = adapterResult.data;
  log.debug(`  Adapter: ${platformName} (resolved)`);

  const ffmpegReferer = platformCfg.referer ?? "";
  const frameConfig = {
    ...adapter.defaults?.frameExtraction,
    ...platformCfg.frameExtraction,
  };

  checkAuthAge(storageStatePath, platformCfg);
  ensureFfmpegAvailable();

  const headless = !args["show-browser"] && args.headless;
  log.info("  Launching Playwright Chromium...");
  log.info(`  Browser headless: ${headless} (show-browser=${args["show-browser"]})`);
  const { browser, context, page, authDir, cookieCount } = await launchBrowser({
    headless,
    storageStatePath,
  });
  if (cookieCount > 0) log.info(`  Injected ${cookieCount} saved cookies.`);

  const authStart = performance.now();
  const authResult = await adapter.authenticate({
    context,
    page,
    course,
    storageStatePath,
    platformCfg,
  });
  const authDurationMs = Math.round(performance.now() - authStart);
  const baseUrl = authResult?.baseUrl ?? courseBaseUrl(course.url);
  log.info(`  Base: ${baseUrl}`);
  log.debug(`  Auth: ${authDurationMs}ms`);

  const preflightDurationMs = await runPreflight({
    adapter,
    page,
    platformCfg,
    context,
    authDir,
    browser,
  });
  const metadataDurationMs = await runMetadataPhase({
    adapter,
    page,
    course,
    courseJson,
    platformCfg,
    context,
    authDir,
    browser,
  });

  if (adapter.setupSession) {
    await adapter.setupSession(page, platformCfg);
    log.debug("  Adapter session setup complete.");
  }

  log.info("\n  ----------------------------------------\n");

  const skipTitles = new Set(platformCfg.skipLessonTitles ?? ["Rate this course"]);
  const processable = course.modules
    .flatMap((m) => m.lessons)
    .filter((l) => l.duration && !skipTitles.has(l.title));
  const tracker = createTracker(processable.length, { logger: log });
  tracker.start();

  const stats = createRunStats();
  const extractionStart = performance.now();
  const saveProgress = () => {
    writeFileSync(courseJson, JSON.stringify(course, null, 2), "utf-8");
    const report = tracker.finish();
    writeFileSync(join(courseDir, "run-report.json"), JSON.stringify(report, null, 2), "utf-8");
    log.info("\n  Progress saved (interrupted).");
  };
  process.on("SIGINT", () => {
    saveProgress();
    process.exit(0);
  });

  await runLessonExtraction({
    args: {
      skipTranscripts: args["skip-transcripts"],
      extractFrames: args["extract-frames"],
    },
    adapter,
    course,
    courseJson,
    extractFramesFn: extractFrames,
    ffmpegReferer,
    frameConfig,
    log,
    modulesDir,
    navigateWithFallback,
    page,
    platformCfg,
    skipTitles,
    stats,
    tracker,
  });

  await closeBrowser(context, authDir, browser);
  const extractionDurationMs = Math.round(performance.now() - extractionStart);

  const report = tracker.finish({
    environment: {
      nodeVersion: process.version,
      platform: process.platform,
      adapter: platformName,
      options: {
        extractFrames: args["extract-frames"],
        skipTranscripts: args["skip-transcripts"],
        metadataOnly: args["metadata-only"],
        verbose: args.verbose,
        quiet: args.quiet,
      },
    },
    phases: {
      authMs: authDurationMs,
      preflightMs: preflightDurationMs,
      metadataMs: metadataDurationMs,
      extractionMs: extractionDurationMs,
    },
  });
  writeFileSync(join(courseDir, "run-report.json"), JSON.stringify(report, null, 2), "utf-8");

  log.info("\n  ----------------------------------------");
  log.info(
    `  Transcripts — Extracted: ${stats.extracted} | Skipped: ${stats.skipped} | Failed: ${stats.failed}`,
  );
  if (args["extract-frames"]) {
    log.info(`  Frames — Total extracted: ${stats.framesExtracted}`);
  }
  log.info(
    `  Total lessons processed: ${stats.extracted + stats.skipped + stats.failed}/${course.totalLessons}`,
  );
  log.info(`  Run report: ${join(courseDir, "run-report.json")}`);
}

main().catch((e) => {
  log.error("Fatal error:", e);
  process.exit(1);
});
