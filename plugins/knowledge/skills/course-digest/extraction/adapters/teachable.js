/**
 * Teachable platform adapter for course-extraction.
 *
 * Teachable uses Hotmart as its video player (cross-origin iframe at
 * player.hotmart.com). Videos stream via HLS with WebVTT subtitle segments.
 *
 * This adapter composes:
 *   - lib/players/hotmart.js — HLS interception, iframe subtitle fetch, canvas frames
 *   - lib/auth/teachable-sso.js — simple form login flow
 *
 * Key technical differences from Dometrain:
 *   - Transcript: HLS subtitle manifest intercept → fetch WebVTT from iframe context
 *   - HLS URL: intercepted via page.on("response"), not read from DOM
 *   - Resources: 6 attachment types via .lecture-attachment-type-* CSS classes
 *   - Auth: cookie-based (Teachable accounts), not Clerk
 *   - URL construction: /courses/{slug}/lectures/{id}, not baseUrl+lessonSlug
 */

import { fail, ok, timed } from "@melodic/video-digestion/shared/result";
import { writeStdout } from "@melodic/video-digestion/shared/terminal";

import { promptManualLogin } from "../lib/auth/manual-login.js";
import { login as teachableLogin } from "../lib/auth/teachable-sso.js";
import {
  extractFrames as extractHotmartFrames,
  getHlsUrl,
  getTranscript,
  installInterceptors,
  preparePage,
} from "../lib/players/hotmart.js";
import { INSTRUCTOR_HEADING_SELECTOR } from "../lib/playwright-selectors.js";

const LECTURE_ATTACHMENT_TYPE_SOURCE = "lecture-attachment-type-(\\w+)";
const CODE_LANGUAGE_SOURCE = "language-(\\w+)";
const COURSE_SLUG_PATH = /\/courses\/([^/]+)/;

// ---------------------------------------------------------------------------
// Adapter defaults (Teachable/Hotmart-specific config)
// ---------------------------------------------------------------------------

export const defaults = {
  videoPlayerSelector: ".hotmart_video_player",
  authWarnDays: 14,
  authProvider: "teachable",
  subtitleLanguage: "eng",
  resourceSelectors: {
    video: ".lecture-attachment-type-video",
    text: ".lecture-attachment-type-text",
    file: ".lecture-attachment-type-file",
    codeDisplay: ".lecture-attachment-type-code_display",
    pdfEmbed: ".lecture-attachment-type-pdf_embed",
    codeEmbed: ".lecture-attachment-type-code_embed",
  },
  frameExtraction: {
    sceneThreshold: 0.1,
    intervalFps: "1/15",
    minFramesForScene: 5,
  },
  playbackWaitMs: 5000,
  manifestTimeoutMs: 15000,
};

// ---------------------------------------------------------------------------
// Required adapter methods
// ---------------------------------------------------------------------------

/**
 * Extract transcript from Hotmart HLS subtitle stream.
 * Delegates to hotmart.getTranscript().
 */
export async function extractTranscript(page, _platformCfg) {
  return timed("extract-transcript", null, () => getTranscript(page));
}

/**
 * Extract HLS master URL from captured network interception data.
 * Delegates to hotmart.getHlsUrl().
 */
export async function extractHlsUrl(page, _platformCfg) {
  return timed("extract-hls-url", null, () => getHlsUrl(page));
}

/**
 * Detect available resources on the current Teachable lesson page.
 * Reads .lecture-attachment-type-* CSS classes from the DOM.
 */
export async function detectResources(page, platformCfg) {
  return timed("detect-resources", null, async () => {
    const selectors = {
      ...defaults.resourceSelectors,
      ...platformCfg.resourceSelectors,
    };

    return page.evaluate(
      ({ sel, attachmentTypeSource }) => {
        const has = (s) => !!document.querySelector(s);
        const attachmentTypePattern = new RegExp(attachmentTypeSource);

        return {
          hasVideo: has(".hotmart_video_player"),
          hasTranscript: false,
          hasDownload: has(sel.file),
          hasLessonNotes: false,
          hasReadThisLesson: false,
          hasCodeSnippets: has(sel.codeDisplay),
          hasArticleLinks: document.querySelectorAll(`${sel.text} a[href]`).length > 0,
          hasPdfEmbed: has(sel.pdfEmbed),
          hasCodeEmbed: has(sel.codeEmbed),
          hasTextContent: has(sel.text),
          attachmentTypes: Array.from(document.querySelectorAll(".lecture-attachment")).map(
            (a) => a.className.match(attachmentTypePattern)?.[1] ?? "unknown",
          ),
        };
      },
      { sel: selectors, attachmentTypeSource: LECTURE_ATTACHMENT_TYPE_SOURCE },
    );
  });
}

/**
 * Derive the public landing page URL from the enrolled course URL.
 */
export function deriveLandingUrl(courseUrl, platformCfg) {
  if (platformCfg.landingUrl) return platformCfg.landingUrl;
  return courseUrl.replace("/enrolled/", "/");
}

// ---------------------------------------------------------------------------
// Optional lifecycle hooks
// ---------------------------------------------------------------------------

/**
 * Install page.on("response") interceptors for HLS and subtitle data.
 * Delegates to hotmart.installInterceptors().
 */
export async function setupSession(page, platformCfg) {
  const subtitleLang = platformCfg.subtitleLanguage ?? defaults.subtitleLanguage;
  installInterceptors(page, subtitleLang);
}

/**
 * Prepare a lesson page for extraction.
 * Delegates to hotmart.preparePage().
 */
export async function prepareLessonPage(page, platformCfg, lesson) {
  return timed("prepare-lesson-page", { lesson: lesson?.title }, async () => {
    const subtitleLang = platformCfg.subtitleLanguage ?? defaults.subtitleLanguage;
    const manifestTimeout = platformCfg.manifestTimeoutMs ?? defaults.manifestTimeoutMs;

    return preparePage(page, subtitleLang, manifestTimeout);
  });
}

/**
 * Extract per-lesson resources from the Teachable DOM.
 */
async function scrapeCodeSnippets(page, codeDisplaySelector) {
  return page.evaluate(
    ({ selector, languageSource }) => {
      const languagePattern = new RegExp(languageSource);
      const snippets = [];
      for (const el of document.querySelectorAll(selector)) {
        const codeEl = el.querySelector("pre, code");
        const text = codeEl?.textContent?.trim();
        if (!text) continue;
        snippets.push({
          code: text,
          language: codeEl.className?.match(languagePattern)?.[1] ?? null,
        });
      }
      return snippets;
    },
    { selector: codeDisplaySelector, languageSource: CODE_LANGUAGE_SOURCE },
  );
}

async function scrapeDownloadLinks(page, fileSelector) {
  return page.evaluate((selector) => {
    const downloads = [];
    for (const el of document.querySelectorAll(selector)) {
      for (const link of el.querySelectorAll("a[href]")) {
        downloads.push({ label: link.textContent?.trim(), href: link.href });
      }
    }
    return downloads;
  }, fileSelector);
}

async function scrapeTextAttachments(page, textSelector) {
  return page.evaluate((selector) => {
    const articleLinks = [];
    const textContent = [];
    for (const el of document.querySelectorAll(selector)) {
      for (const link of el.querySelectorAll("a[href]")) {
        const label = link.textContent?.trim();
        const href = link.href;
        if (label && href && !href.includes("teachablecdn")) {
          articleLinks.push({ label, href });
        }
      }
      const text = el.textContent?.trim();
      if (text && text.length < 1000) textContent.push(text);
    }
    return { articleLinks, textContent };
  }, textSelector);
}

async function scrapePdfLinks(page, pdfSelector) {
  return page.evaluate((selector) => {
    const pdfLinks = [];
    for (const el of document.querySelectorAll(selector)) {
      for (const link of el.querySelectorAll("a[href]")) {
        pdfLinks.push({ label: link.textContent?.trim(), href: link.href });
      }
    }
    return pdfLinks;
  }, pdfSelector);
}

export async function extractResources(page, platformCfg) {
  return timed("extract-resources", null, async () => {
    const selectors = {
      ...defaults.resourceSelectors,
      ...platformCfg.resourceSelectors,
    };

    const [codeSnippets, downloads, textData, pdfLinks] = await Promise.all([
      scrapeCodeSnippets(page, selectors.codeDisplay),
      scrapeDownloadLinks(page, selectors.file),
      scrapeTextAttachments(page, selectors.text),
      scrapePdfLinks(page, selectors.pdfEmbed),
    ]);

    return {
      codeSnippets,
      downloads,
      articleLinks: textData.articleLinks,
      textContent: textData.textContent,
      pdfLinks,
    };
  });
}

/**
 * Extract video frames via canvas drawImage within the Hotmart iframe.
 * Delegates to hotmart.extractFrames().
 */
export async function extractFramesCanvas({ page, duration, outputDir, options = {} }) {
  return timed("extract-frames-canvas", null, () =>
    extractHotmartFrames(page, duration, outputDir, options),
  );
}

/**
 * Pre-flight check: verify Hotmart iframe loads and Teachable API responds.
 */
export async function preflight(page, _platformCfg) {
  const checks = await page.evaluate(() => {
    const hotmartEl = !!document.querySelector(".hotmart_video_player");
    const lectureContent = !!document.querySelector(".lecture-content");
    const attachments = document.querySelectorAll(".lecture-attachment").length;
    return { hotmart: hotmartEl, lectureContent, attachments };
  });

  const failures = Object.entries(checks)
    .filter(([key, val]) => key !== "attachments" && !val)
    .map(([name]) => name);

  if (failures.length > 0) {
    return fail(
      `Preflight failed — missing: ${failures.join(", ")}. Platform may have changed.`,
      "preflight",
      checks,
      0,
    );
  }

  return ok(checks, "preflight", null, 0);
}

/**
 * Authenticate with Teachable.
 * Navigation and auth detection stay here; login flow delegates to teachableSSO.
 */
/** @param {import('./auth-session.js').AuthSessionInput} input */
export async function authenticate({ context, page, course, storageStatePath, platformCfg }) {
  const videoSelector = platformCfg.videoPlayerSelector ?? defaults.videoPlayerSelector;
  const envPrefix = platformCfg.authEnvPrefix ?? "TEACHABLE";

  const firstVideoLesson = course.modules.flatMap((m) => m.lessons).find((l) => l.duration);

  if (!firstVideoLesson) {
    throw new Error("No video lessons found in course.");
  }

  const lessonUrl = buildLessonUrl(course, firstVideoLesson, platformCfg);
  await page.goto(lessonUrl, { waitUntil: "domcontentloaded", timeout: 15000 }).catch(() => {});
  await page.waitForLoadState("networkidle", { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(2000);

  const hasPlayer = await page
    .evaluate((sel) => !!document.querySelector(sel), videoSelector)
    .catch(() => false);

  if (hasPlayer) {
    writeStdout("  Already authenticated.\n");
    return;
  }

  const email = process.env[`${envPrefix}_EMAIL`];
  const password = process.env[`${envPrefix}_PASSWORD`];
  const loginUrl = platformCfg.loginUrl;

  if (email && password && loginUrl) {
    writeStdout("  Logging in automatically...");
    await teachableLogin(page, email, password, loginUrl);
    await context.storageState({ path: storageStatePath });
    writeStdout("  Logged in and saved auth state.\n");
  } else {
    await promptManualLogin(context, storageStatePath, envPrefix);
  }
}

/**
 * Extract course metadata from the landing/enrolled page.
 */
export async function extractMetadata(page, _courseUrl, _platformCfg) {
  return timed("extract-metadata", null, async () => {
    const metadata = {};

    const ogTags = await page
      .evaluate(() => {
        const tags = {};
        for (const meta of document.querySelectorAll("meta")) {
          const prop = meta.getAttribute("property") || meta.getAttribute("name");
          if (prop?.startsWith("og:") || prop?.startsWith("twitter:")) {
            tags[prop] = meta.getAttribute("content");
          }
        }
        return tags;
      })
      .catch(() => ({}));

    if (Object.keys(ogTags).length > 0) {
      metadata.ogTags = ogTags;
      if (ogTags["og:title"]) metadata.title = ogTags["og:title"];
      if (ogTags["og:description"]) metadata.description = ogTags["og:description"];
      if (ogTags["og:image"]) metadata.thumbnailUrl = ogTags["og:image"];
    }

    const instructor = await page
      .evaluate((selector) => {
        const el = document.querySelector(selector);
        return el?.textContent?.trim() ?? null;
      }, INSTRUCTOR_HEADING_SELECTOR)
      .catch(() => null);

    if (instructor) metadata.instructor = instructor;

    return metadata;
  });
}

// ---------------------------------------------------------------------------
// URL construction
// ---------------------------------------------------------------------------

export function buildLessonUrl(course, lesson, platformCfg) {
  const baseUrl = platformCfg.baseUrl ?? course.url?.split("/courses/")[0];
  const courseSlug = platformCfg.courseSlug ?? extractCourseSlug(course.url);
  return `${baseUrl}/courses/${courseSlug}/lectures/${lesson.lectureId ?? lesson.slug}`;
}

function extractCourseSlug(url) {
  const match = url?.match(COURSE_SLUG_PATH);
  return match?.[1] ?? "";
}
