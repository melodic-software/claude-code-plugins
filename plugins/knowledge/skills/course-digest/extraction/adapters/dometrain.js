/**
 * Dometrain platform adapter for course-extraction.
 *
 * This adapter composes:
 *   - lib/players/mux.js — HLS URL from Mux player DOM element
 *   - lib/auth/clerk.js — two-step Clerk login flow
 *
 * All Dometrain-specific DOM interaction, URL patterns, and orchestration
 * live here. The orchestrator delegates to these methods via the adapter
 * contract — zero platform-specific code in extract-course.js.
 */

import { fail, ok, timed } from "@melodic/video-digestion/shared/result";
import { writeStdout } from "@melodic/video-digestion/shared/terminal";

import { login as clerkLogin } from "../lib/auth/clerk.js";
import { promptManualLogin } from "../lib/auth/manual-login.js";
import { getHlsUrl } from "../lib/players/mux.js";
import {
  DESCRIPTION_META_SELECTOR,
  TRANSCRIPT_PANEL_SELECTOR,
} from "../lib/playwright-selectors.js";
import { courseBaseUrl } from "../utils.js";

const LOADING_TRANSCRIPT_PREFIX = /^Loading transcript\s*/m;
const NO_TRANSCRIPT_SUFFIX = /No transcript available for this lesson\.\s*$/m;
const TRANSCRIPT_TIMESTAMP_LINE = /^\d+:\d{2}$/;
const TRAILING_LESSON_SLUG = /\/[^/]+\/$/;
const TRAILING_COURSE_ID_SUFFIX = /-\d+\/$/;
const DATE_LAST_UPDATED = /last\s+updated[:\s]+(\w+\s+\d{1,2},?\s+\d{4})/i;
const DATE_UPDATED = /updated[:\s]+(\w+\s+\d{1,2},?\s+\d{4})/i;
const DATE_PUBLISHED = /published[:\s]+(\w+\s+\d{1,2},?\s+\d{4})/i;
const DATE_RELEASED = /released[:\s]+(\w+\s+\d{1,2},?\s+\d{4})/i;
const VISIBLE_DATE_PATTERNS = [DATE_LAST_UPDATED, DATE_UPDATED, DATE_PUBLISHED, DATE_RELEASED];

// ---------------------------------------------------------------------------
// Adapter defaults (Dometrain-specific config)
// ---------------------------------------------------------------------------

export const defaults = {
  videoPlayerSelector: "mux-player",
  authWarnDays: 6,
  authProvider: "clerk",
  resourceButtons: {
    download: "Download course files",
    lessonNotes: "Show lesson notes",
    readThisLesson: "Read this lesson",
    transcript: "Transcript",
  },
  frameExtraction: {
    sceneThreshold: 0.1,
    intervalFps: "1/15",
    minFramesForScene: 5,
  },
};

// ---------------------------------------------------------------------------
// Required adapter methods
// ---------------------------------------------------------------------------

/**
 * Extract transcript from the Dometrain transcript panel.
 * Clicks "Transcript" button, reads the panel, formats as [M:SS] segments.
 */
export async function extractTranscript(page, _platformCfg) {
  return timed("extract-transcript", null, async () => {
    const btn = page.locator("button", { hasText: "Transcript" }).first();
    if (await btn.isVisible().catch(() => false)) {
      await btn.click();
      await page.waitForTimeout(2000);
    }

    const transcriptEl = page.locator(TRANSCRIPT_PANEL_SELECTOR).first();
    if (!(await transcriptEl.isVisible({ timeout: 5000 }).catch(() => false))) {
      throw new Error("Transcript panel not visible");
    }

    const raw = await transcriptEl.innerText();
    const cleaned = raw
      .replace(LOADING_TRANSCRIPT_PREFIX, "")
      .replace(NO_TRANSCRIPT_SUFFIX, "")
      .trim();

    if (!cleaned || cleaned === "Loading transcript") {
      throw new Error("No transcript content available");
    }

    const lines = cleaned.split("\n");
    const segments = [];
    let current = "";

    for (const line of lines) {
      const trimmed = line.trim();
      if (TRANSCRIPT_TIMESTAMP_LINE.test(trimmed)) {
        if (current) segments.push(current.trim());
        current = `[${trimmed}] `;
      } else if (trimmed) {
        current += `${trimmed} `;
      }
    }
    if (current) segments.push(current.trim());

    return segments.join("\n\n");
  });
}

/**
 * Extract HLS URL from the Mux player element.
 * Delegates to mux.getHlsUrl().
 */
export async function extractHlsUrl(page, platformCfg) {
  return timed("extract-hls-url", null, async () => {
    await page.waitForTimeout(2000);
    const selector = platformCfg.videoPlayerSelector ?? defaults.videoPlayerSelector;
    return getHlsUrl(page, selector);
  });
}

/**
 * Detect which resource buttons are visible on the current lesson page.
 */
export async function detectResources(page, platformCfg) {
  return timed("detect-resources", null, async () => {
    const labels = {
      ...defaults.resourceButtons,
      ...platformCfg.resourceButtons,
    };
    const videoSelector = platformCfg.videoPlayerSelector ?? defaults.videoPlayerSelector;

    return page.evaluate(
      ({ labels: l, videoSel }) => {
        const buttons = Array.from(document.querySelectorAll("button"));
        const check = (label) => {
          const btn = buttons.find((b) => b.textContent.trim().startsWith(label));
          if (!btn) return false;
          const style = window.getComputedStyle(btn);
          return style.display !== "none" && style.visibility !== "hidden";
        };

        return {
          hasDownload: check(l.download),
          hasLessonNotes: check(l.lessonNotes),
          hasReadThisLesson: check(l.readThisLesson),
          hasTranscript: check(l.transcript),
          hasVideo: !!document.querySelector(`${videoSel}, video`),
        };
      },
      { labels, videoSel: videoSelector },
    );
  });
}

/**
 * Pre-flight check: verify critical DOM selectors exist on the current page.
 * Call on the first lesson page (already loaded during auth) before iterating
 * all lessons. Catches platform UI changes early — saves 45+ wasted navigations.
 */
export async function preflight(page, platformCfg) {
  const videoSel = platformCfg.videoPlayerSelector ?? defaults.videoPlayerSelector;

  const checks = await page.evaluate(
    ({ videoSel: vs, panelSelector }) => {
      const videoPlayer = !!document.querySelector(`${vs}, video`);
      const transcriptButton = Array.from(document.querySelectorAll("button")).some(
        (b) => b.textContent.trim() === "Transcript",
      );
      const transcriptPanel = !!document.querySelector(panelSelector);
      return { videoPlayer, transcriptButton, transcriptPanel };
    },
    { videoSel, panelSelector: TRANSCRIPT_PANEL_SELECTOR },
  );

  const failures = Object.entries(checks)
    .filter(([, passed]) => !passed)
    .map(([name]) => name);

  if (failures.length > 0) {
    return fail(
      `Preflight failed — missing: ${failures.join(", ")}. Platform may have changed their DOM structure.`,
      "preflight",
      checks,
      0,
    );
  }

  return ok(checks, "preflight", null, 0);
}

/**
 * Derive the public landing page URL from the lesson player URL.
 * Strips "/take/" prefix, trailing lesson slug, and numeric courseId suffix.
 */
export function deriveLandingUrl(courseUrl, platformCfg) {
  const landingPattern = platformCfg.landingUrlPattern ?? "";
  if (!landingPattern.includes(" -> ")) return courseUrl;

  const [from, to] = landingPattern.split(" -> ");
  let url = courseUrl.replace(from, to);
  url = url.replace(TRAILING_LESSON_SLUG, "/");
  url = url.replace(TRAILING_COURSE_ID_SUFFIX, "/");
  return url;
}

/**
 * Build a full lesson URL for Dometrain.
 * Pattern: {baseUrl}{lesson.slug}/
 */
export function buildLessonUrl(course, lesson, _platformCfg) {
  const baseUrl = courseBaseUrl(course.url);
  return `${baseUrl}${lesson.slug}/`;
}

// ---------------------------------------------------------------------------
// Optional adapter methods
// ---------------------------------------------------------------------------

function applyJsonLdMetadata(metadata, jsonLd) {
  if (!jsonLd) return;
  metadata.structuredData = jsonLd;
  if (jsonLd.name) metadata.title = jsonLd.name;
  if (jsonLd.description) metadata.description = jsonLd.description;
  if (jsonLd.dateCreated) metadata.dateCreated = jsonLd.dateCreated;
  if (jsonLd.dateModified) metadata.dateModified = jsonLd.dateModified;
  if (jsonLd.datePublished) metadata.datePublished = jsonLd.datePublished;
  if (jsonLd.aggregateRating) {
    metadata.rating = {
      value: jsonLd.aggregateRating.ratingValue,
      count: jsonLd.aggregateRating.ratingCount,
      best: jsonLd.aggregateRating.bestRating,
    };
  }
  if (jsonLd.author) {
    const authors = Array.isArray(jsonLd.author) ? jsonLd.author : [jsonLd.author];
    metadata.authors = authors.map((a) => a.name ?? a).filter(Boolean);
  }
}

function applyOgMetadata(metadata, ogTags) {
  if (Object.keys(ogTags).length === 0) return;
  metadata.ogTags = ogTags;
  if (ogTags["og:image"]) metadata.thumbnailUrl = ogTags["og:image"];
  if (!metadata.description && ogTags["og:description"]) {
    metadata.description = ogTags["og:description"];
  }
  if (ogTags["article:modified_time"]) metadata.dateModified = ogTags["article:modified_time"];
  if (ogTags["article:published_time"]) metadata.datePublished = ogTags["article:published_time"];
}

function findVisibleDate(pageText) {
  for (const pattern of VISIBLE_DATE_PATTERNS) {
    const match = pageText.match(pattern);
    if (match) return match[0];
  }
  return null;
}

async function fetchJsonLd(page) {
  return page
    .evaluate(() => {
      const isCourse = (node) => node["@type"] === "Course" || node["@type"]?.includes?.("Course");
      const scripts = document.querySelectorAll('script[type="application/ld+json"]');
      for (const script of scripts) {
        try {
          const data = JSON.parse(script.textContent);
          if (isCourse(data)) return data;
          if (Array.isArray(data["@graph"])) {
            const course = data["@graph"].find(isCourse);
            if (course) return course;
          }
        } catch {
          /* ignore parse errors */
        }
      }
      return null;
    })
    .catch(() => null);
}

async function fetchOgTags(page) {
  return page
    .evaluate(() => {
      const tags = {};
      for (const meta of document.querySelectorAll("meta")) {
        const prop = meta.getAttribute("property") || meta.getAttribute("name");
        if (
          prop?.startsWith("og:") ||
          prop?.startsWith("twitter:") ||
          prop?.includes("date") ||
          prop?.includes("time") ||
          prop?.includes("modified") ||
          prop?.includes("published")
        ) {
          tags[prop] = meta.getAttribute("content");
        }
      }
      return tags;
    })
    .catch(() => ({}));
}

async function fetchDescriptionMeta(page) {
  return page
    .evaluate((selector) => {
      const meta = document.querySelector(selector);
      return meta?.getAttribute("content") || null;
    }, DESCRIPTION_META_SELECTOR)
    .catch(() => null);
}

/**
 * Extract course metadata from the landing page (JSON-LD, OG tags, visible text).
 */
export async function extractMetadata(page, courseUrl, platformCfg) {
  return timed("extract-metadata", null, async () => {
    const metadata = {};
    const landingUrl = deriveLandingUrl(courseUrl, platformCfg);

    await page.goto(landingUrl, {
      waitUntil: "domcontentloaded",
      timeout: 15000,
    });
    await page.waitForTimeout(2000);

    applyJsonLdMetadata(metadata, await fetchJsonLd(page));
    applyOgMetadata(metadata, await fetchOgTags(page));

    const pageText = await page.innerText("body").catch(() => "");
    const visibleDate = findVisibleDate(pageText);
    if (visibleDate) metadata.visibleDate = visibleDate;

    if (!metadata.description) {
      const desc = await fetchDescriptionMeta(page);
      if (desc) metadata.description = desc;
    }

    metadata.landingUrl = landingUrl;
    return metadata;
  });
}

/**
 * Authenticate with Dometrain via Clerk login flow.
 */
/** @param {import('./auth-session.js').AuthSessionInput} input */
export async function authenticate({ context, page, course, storageStatePath, platformCfg }) {
  const baseUrl = courseBaseUrl(course.url);
  const firstLesson = course.modules[0].lessons[0];
  const videoSelector = platformCfg.videoPlayerSelector ?? defaults.videoPlayerSelector;
  const envPrefix = platformCfg.authEnvPrefix ?? "COURSE";
  const loginUrl = platformCfg.loginUrl;

  await page
    .goto(`${baseUrl}${firstLesson.slug}/`, {
      waitUntil: "domcontentloaded",
      timeout: 15000,
    })
    .catch(() => {});
  await page.waitForLoadState("networkidle", { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(2000);

  const hasPlayer = await page
    .evaluate((sel) => !!document.querySelector(sel), videoSelector)
    .catch(() => false);

  if (hasPlayer) {
    writeStdout("  Already authenticated.\n");
    return { baseUrl };
  }

  const email = process.env[`${envPrefix}_EMAIL`];
  const password = process.env[`${envPrefix}_PASSWORD`];

  if (email && password && loginUrl) {
    writeStdout("  Logging in automatically...");
    await clerkLogin(page, email, password, loginUrl);
    await context.storageState({ path: storageStatePath });
    writeStdout("  Logged in and saved auth state.\n");
  } else {
    await promptManualLogin(context, storageStatePath, envPrefix);
  }

  return { baseUrl };
}
