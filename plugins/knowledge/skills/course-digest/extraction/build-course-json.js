/**
 * Build course.json for a Teachable course by scraping the curriculum page.
 *
 * Usage: node build-course-json.js --course-url <enrolled-url> --output-dir <path>
 *
 * Example:
 *   node build-course-json.js \
 *     --course-url "https://www.courses.example.tech/courses/enrolled/2518872" \
 *     --output-dir "<library-dir>/courses/<instructor>/<course-slug>"
 */

import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { resolveAuthStatePath } from "./lib/auth-store.js";
import { closeBrowser, launchBrowser } from "./lib/browser.js";
import { parseDuration } from "./utils.js";

const COURSE_ID_SUFFIX = /\/(\d+)$/;
const SCRAPE_REGEX_SOURCES = {
  slugPrefix: "^\\d+\\s*-\\s*",
  nonAlpha: "[^a-z0-9\\s-]",
  whitespace: "\\s+",
  lectureId: "lectures\\/(\\d+)",
  duration: "\\((\\d+:\\d+)\\)",
};
const INSTRUCTOR_CLASS_FRAGMENT = "instructor";

const { values: args } = parseArgs({
  options: {
    "course-url": { type: "string" },
    "output-dir": { type: "string" },
  },
  strict: false,
});

function scrapeCurriculumInBrowser({ sources, instructorFragment }) {
  function isSkippedModuleHeading(text, el) {
    if (text.includes("COMPLETE") || text.includes("Community")) return true;
    if (text === "Modular Monolith Architecture + Community Access") return true;
    const instructorSelector = `[class*="${instructorFragment}"]`;
    return !!(
      el.parentElement?.querySelector(instructorSelector) || el.closest(instructorSelector)
    );
  }

  const slugPrefix = new RegExp(sources.slugPrefix);
  const nonAlpha = new RegExp(sources.nonAlpha, "g");
  const whitespace = new RegExp(sources.whitespace, "g");
  const lectureIdPattern = new RegExp(sources.lectureId);
  const durationPattern = new RegExp(sources.duration);

  const allElements = Array.from(document.querySelectorAll('h2, h3, a[href*="/lectures/"]'));
  const modules = [];
  let currentModule = null;
  let modulePosition = 0;
  const headingEl = document.querySelector("h2");
  const courseTitle = headingEl?.textContent?.trim() ?? "";

  for (const el of allElements) {
    if (el.tagName === "H2") {
      const text = el.textContent.trim();
      if (isSkippedModuleHeading(text, el)) continue;

      modulePosition++;
      const slugNum = String(modulePosition).padStart(2, "0");
      const slugText = text
        .replace(slugPrefix, "")
        .toLowerCase()
        .replace(nonAlpha, "")
        .replace(whitespace, "-")
        .substring(0, 50);

      currentModule = {
        position: modulePosition,
        title: text,
        slug: `${slugNum}-${slugText}`,
        lessons: [],
      };
      modules.push(currentModule);
    } else if (el.tagName === "A" && currentModule) {
      const lectureId = el.href?.match(lectureIdPattern)?.[1];
      const h3 = el.querySelector("h3");
      if (lectureId && h3 && !currentModule.lessons.some((l) => l.lectureId === lectureId)) {
        const fullText = el.textContent.trim();
        const durationMatch = fullText.match(durationPattern);
        const rawDuration = durationMatch ? durationMatch[1] : "";
        const title = h3.textContent.trim();

        let duration = "";
        if (rawDuration) {
          const parts = rawDuration.split(":");
          duration = `${parts[0]}m ${parts[1]}s`;
        }

        const pos = currentModule.lessons.length + 1;
        currentModule.lessons.push({
          position: pos,
          title,
          duration,
          lectureId,
          slug: lectureId,
          status: "pending",
          hasTranscript: false,
          hasScreenshots: false,
          hasDownload: false,
          hasVideo: !!rawDuration,
          providerResources: {},
        });
      }
    }
  }

  return { title: courseTitle, modules };
}

function logCurriculumSummary(courseData) {
  writeStdout(`Course: ${courseData.title}`);
  writeStdout(`Modules: ${courseData.modules.length}`);
  const totalLessons = courseData.modules.reduce((sum, m) => sum + m.lessons.length, 0);
  writeStdout(`Lessons: ${totalLessons}`);

  for (const mod of courseData.modules) {
    writeStdout(`  ${mod.slug}: ${mod.title} (${mod.lessons.length} lessons)`);
  }

  return totalLessons;
}

async function main() {
  if (!args["course-url"] || !args["output-dir"]) {
    writeStderr("Usage: node build-course-json.js --course-url <url> --output-dir <path>");
    process.exit(1);
  }

  const courseUrl = args["course-url"];
  const outputDir = resolve(args["output-dir"]);
  const authStatePath = resolveAuthStatePath("teachable");

  mkdirSync(outputDir, { recursive: true });

  const { browser, context, page, authDir, cookieCount } = await launchBrowser({
    headless: false,
    storageStatePath: authStatePath,
    profilePrefix: "build-course-json",
  });
  if (cookieCount > 0) {
    writeStdout(`Injected ${cookieCount} cookies.`);
  } else {
    writeStdout("No auth state found. You may need to log in manually.");
  }
  writeStdout(`\nNavigating to: ${courseUrl}`);
  await page.goto(courseUrl, { waitUntil: "domcontentloaded", timeout: 20000 });
  await page.waitForTimeout(3000);

  writeStdout("Scraping curriculum...\n");
  const courseData = await page.evaluate(scrapeCurriculumInBrowser, {
    sources: SCRAPE_REGEX_SOURCES,
    instructorFragment: INSTRUCTOR_CLASS_FRAGMENT,
  });

  const totalLessons = logCurriculumSummary(courseData);

  const totalSeconds = courseData.modules
    .flatMap((m) => m.lessons)
    .reduce((sum, l) => sum + parseDuration(l.duration), 0);
  const hours = Math.floor(totalSeconds / 3600);
  const mins = Math.floor((totalSeconds % 3600) / 60);

  const courseId = courseUrl.match(COURSE_ID_SUFFIX)?.[1] ?? "";

  const courseJson = {
    title: courseData.title,
    slug: "modular-monolith-jovanovic",
    platform: "teachable",
    platformConfig: {
      loginUrl: "https://sso.teachable.com/secure/146684/identity/login",
      videoPlayerSelector: ".hotmart_video_player",
      referer: "https://player.hotmart.com/",
      authProvider: "teachable",
      authWarnDays: 14,
      authEnvPrefix: "TEACHABLE",
      subtitleLanguage: "eng",
      courseSlug: "modular-monolith-architecture-community",
      baseUrl: "https://www.courses.milanjovanovic.tech",
      curriculumUrl: courseUrl,
    },
    url: courseUrl,
    courseId,
    instructor: "Milan Jovanović",
    duration: `${hours}h ${mins}m`,
    totalLessons,
    extractedAt: null,
    status: "pending",
    modules: courseData.modules,
    resources: {
      githubUrl: null,
      downloadAvailable: true,
    },
    phases: {
      extract: null,
      extractFrames: null,
      processFrames: null,
      analyzeCodeRepo: null,
      validate: null,
      synthesize: null,
      analyze: null,
    },
  };

  const outputPath = join(outputDir, "course.json");
  writeFileSync(outputPath, JSON.stringify(courseJson, null, 2), "utf-8");
  writeStdout(`\n✓ course.json written to: ${outputPath}`);
  writeStdout(`  ${totalLessons} lessons, ${hours}h ${mins}m total`);

  await closeBrowser(context, authDir, browser);
}

main().catch((e) => {
  writeStderr("Fatal:", e);
  process.exit(1);
});
