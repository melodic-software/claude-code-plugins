import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { formatTranscriptMd, lessonDirName, parseDuration } from "./utils.js";

function saveLessonResources(lessonDir, res) {
  if (res.codeSnippets?.length > 0) {
    const snippetsMd = res.codeSnippets
      .map(
        (s, i) =>
          `### Snippet ${i + 1}${s.language ? ` (${s.language})` : ""}\n\n\`\`\`${s.language ?? ""}\n${s.code}\n\`\`\``,
      )
      .join("\n\n");
    writeFileSync(join(lessonDir, "code-snippets.md"), `${snippetsMd}\n`, "utf-8");
  }

  const resourceData = {};
  if (res.downloads?.length > 0) resourceData.downloads = res.downloads;
  if (res.articleLinks?.length > 0) resourceData.articleLinks = res.articleLinks;
  if (res.pdfLinks?.length > 0) resourceData.pdfLinks = res.pdfLinks;
  if (res.textContent?.length > 0) resourceData.textContent = res.textContent;

  if (Object.keys(resourceData).length > 0) {
    writeFileSync(
      join(lessonDir, "resources.json"),
      JSON.stringify(resourceData, null, 2),
      "utf-8",
    );
  }
}

async function extractLessonFrames({ ctx, lesson, lessonDir, url, durationSec }) {
  const { adapter, page, platformCfg, frameConfig, log, ffmpegReferer, extractFramesFn, stats } =
    ctx;
  const screenshotsDir = join(lessonDir, "screenshots");

  log.info(`    FRAMES ${lesson.position}. ${lesson.title} — extracting...`);

  if (adapter.extractFramesCanvas) {
    const canvasResult = await adapter.extractFramesCanvas({
      page,
      duration: durationSec,
      outputDir: screenshotsDir,
      options: frameConfig,
    });
    log.logResult(canvasResult);

    if (canvasResult.success && canvasResult.data.count > 0) {
      lesson.hasScreenshots = true;
      stats.framesExtracted += canvasResult.data.count;
      log.info(`      ${canvasResult.data.count} frames (${canvasResult.data.method})`);
    } else {
      log.warn("      No frames extracted via canvas.");
    }
    return;
  }

  if (!adapter.setupSession) {
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 15000 }).catch(() => {});
    await page.waitForLoadState("networkidle", { timeout: 15000 }).catch(() => {});
  }

  const hlsResult = await adapter.extractHlsUrl(page, platformCfg);
  log.logResult(hlsResult);

  if (!hlsResult.success) {
    log.warn(`    SKIP-FRAMES ${lesson.position}. ${lesson.title} (${hlsResult.error})`);
    return;
  }

  const sceneDir = join(screenshotsDir, "scene-01");
  const result = await extractFramesFn(hlsResult.data, sceneDir, ffmpegReferer, frameConfig);
  if (result.count > 0) {
    lesson.hasScreenshots = true;
    stats.framesExtracted += result.count;
    log.info(`      ${result.count} frames (${result.method})`);
  } else {
    log.warn("      No frames extracted.");
  }
}

async function detectLessonResources(lesson, ctx) {
  const { adapter, page, platformCfg, log } = ctx;
  if (lesson.hasDownload !== undefined) return;

  const resourceResult = await adapter.detectResources(page, platformCfg);
  log.logResult(resourceResult);
  if (!resourceResult.success) return;

  const resources = resourceResult.data;
  lesson.hasDownload = resources.hasDownload;
  lesson.hasVideo = resources.hasVideo;
  lesson.providerResources = {
    lessonNotes: resources.hasLessonNotes ?? false,
    readThisLesson: resources.hasReadThisLesson ?? false,
    codeSnippets: resources.hasCodeSnippets ?? false,
    articleLinks: resources.hasArticleLinks ?? false,
    pdfEmbed: resources.hasPdfEmbed ?? false,
  };
}

async function extractLessonTranscript({
  module,
  lesson,
  lessonDir,
  transcriptPath,
  ctx,
  lessonStart,
}) {
  const { adapter, page, platformCfg, log, stats, tracker } = ctx;
  const transcriptResult = await adapter.extractTranscript(page, platformCfg);
  log.logResult(transcriptResult);

  if (!transcriptResult.success) {
    stats.failed++;
    tracker.item(stats.lessonIndex, lesson.title, {
      success: false,
      error: transcriptResult.error,
      durationMs: performance.now() - lessonStart,
    });
    return false;
  }

  mkdirSync(lessonDir, { recursive: true });
  writeFileSync(transcriptPath, formatTranscriptMd(lesson, module, transcriptResult.data), "utf-8");

  lesson.status = "extracted";
  lesson.hasTranscript = true;
  stats.extracted++;
  tracker.item(stats.lessonIndex, lesson.title, {
    success: true,
    chars: transcriptResult.data.length,
    durationMs: performance.now() - lessonStart,
  });
  return true;
}

async function processLesson(module, lesson, ctx) {
  const {
    args,
    adapter,
    course,
    courseJson,
    log,
    modulesDir,
    navigateWithFallback,
    page,
    platformCfg,
    skipTitles,
    stats,
    tracker,
  } = ctx;

  const lessonDir = join(modulesDir, module.slug, lessonDirName(lesson.position, lesson.title));
  const transcriptPath = join(lessonDir, "transcript.md");

  if (skipTitles.has(lesson.title)) {
    stats.skipped++;
    return;
  }

  const skipTranscript =
    args.skipTranscripts || lesson.status === "extracted" || existsSync(transcriptPath);
  const needsTranscript = !skipTranscript;
  const durationSec = parseDuration(lesson.duration);
  const shouldExtractFrames = args.extractFrames && durationSec > 0 && !lesson.hasScreenshots;
  const isNonVideoLesson = !lesson.duration;
  const needsWork =
    needsTranscript || shouldExtractFrames || (isNonVideoLesson && adapter.extractResources);

  if (!needsWork) {
    stats.skipped++;
    return;
  }

  stats.lessonIndex++;
  const lessonStart = performance.now();
  const url = adapter.buildLessonUrl(course, lesson, platformCfg);

  if (!(await navigateWithFallback(page, url))) {
    stats.failed++;
    tracker.item(stats.lessonIndex, lesson.title, {
      success: false,
      error: "nav error",
      durationMs: performance.now() - lessonStart,
    });
    return;
  }
  await page.waitForTimeout(1500);

  if (adapter.prepareLessonPage) {
    const prepResult = await adapter.prepareLessonPage(page, platformCfg, lesson);
    log.logResult(prepResult);
    if (!prepResult.success) {
      log.warn(`    PREP-WARN ${lesson.position}. ${lesson.title}: ${prepResult.error}`);
    } else if (prepResult.data?.warning) {
      log.warn(`    ${prepResult.data.warning}`);
    }
  }

  await detectLessonResources(lesson, ctx);

  if (needsTranscript && !isNonVideoLesson) {
    const ok = await extractLessonTranscript({
      module,
      lesson,
      lessonDir,
      transcriptPath,
      ctx,
      lessonStart,
    });
    if (!ok) return;
  }

  if (shouldExtractFrames && !isNonVideoLesson) {
    await extractLessonFrames({ ctx, lesson, lessonDir, url, durationSec });
  }

  if (adapter.extractResources) {
    const resResult = await adapter.extractResources(page, platformCfg);
    log.logResult(resResult);
    if (resResult.success && resResult.data) {
      mkdirSync(lessonDir, { recursive: true });
      saveLessonResources(lessonDir, resResult.data);
    }
  }

  writeFileSync(courseJson, JSON.stringify(course, null, 2), "utf-8");
}

export async function runLessonExtraction(ctx) {
  const { course, log, modulesDir } = ctx;

  await course.modules.reduce(async (moduleChain, module) => {
    await moduleChain;
    log.info(`  Module ${module.position}: ${module.title}`);
    const lessons = module.lessons.map((lesson) => ({ module, lesson }));
    await lessons.reduce(async (lessonChain, entry) => {
      await lessonChain;
      await processLesson(entry.module, entry.lesson, ctx);
    }, Promise.resolve());
  }, Promise.resolve());

  return { modulesDir };
}

export function createRunStats() {
  return {
    extracted: 0,
    skipped: 0,
    failed: 0,
    framesExtracted: 0,
    lessonIndex: 0,
  };
}
