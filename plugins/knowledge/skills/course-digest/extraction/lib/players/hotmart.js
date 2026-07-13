/**
 * Hotmart HLS video player module.
 *
 * Extracts all Hotmart-specific player logic: network interception for HLS
 * master URLs and subtitle manifests, Video.js/hls.js player introspection,
 * subtitle segment fetching from cross-origin iframe context, and canvas-based
 * frame extraction.
 *
 * CRITICAL: All fetch() calls for subtitle segments MUST execute inside
 * hotmartFrame.evaluate() — Hotmart's CDN uses CORS restrictions that only
 * allow requests from the player.hotmart.com origin.
 */

import { writeStdout } from "@melodic/video-digestion/shared/terminal";
import {
  parseSubtitleManifest,
  processSubtitleSegments,
} from "@melodic/video-digestion/transcript/vtt-parser";

const VIDEO_ID_PREFIX = /^(\w+)-\d+-/;
const PNG_DATA_URL_PREFIX = /^data:image\/png;base64,/;

// ---------------------------------------------------------------------------
// Module-level state (per-session singleton)
// ---------------------------------------------------------------------------

/** @type {Map<string, { hlsMasterUrl: string|null, subtitleManifestBody: string|null }>} */
const capturedData = new Map();

/** @type {boolean} */
let interceptorsInstalled = false;

function getOrCreateEntry(pageUrl) {
  const existing = capturedData.get(pageUrl);
  if (existing) return existing;
  const entry = { hlsMasterUrl: null, subtitleManifestBody: null };
  capturedData.set(pageUrl, entry);
  return entry;
}

function findHotmartFrame(page) {
  return page.frames().find((f) => f.url().includes("player.hotmart.com"));
}

const SUBTITLE_BATCH_SIZE = 15;

async function fetchSubtitleBatch(hotmartFrame, batch) {
  return hotmartFrame.evaluate(async (urls) => {
    const responses = await Promise.allSettled(
      urls.map(async (url) => {
        const resp = await fetch(url);
        if (!resp.ok) return { ok: false, status: resp.status };
        const text = await resp.text();
        return { ok: true, text, length: text.length };
      }),
    );
    return responses.map((r) =>
      r.status === "fulfilled" ? r.value : { ok: false, error: "rejected" },
    );
  }, batch);
}

function collectSegmentBatchResults(results, segmentBodies, fetchFailedRef) {
  for (const result of results) {
    if (result.ok && result.length > 0) {
      segmentBodies.push(result.text);
    } else {
      fetchFailedRef.count++;
    }
  }
}

async function fetchSubtitleSegmentBatches(hotmartFrame, absoluteUrls) {
  const segmentBodies = [];
  const fetchFailedRef = { count: 0 };
  const batchStarts = [];
  for (let i = 0; i < absoluteUrls.length; i += SUBTITLE_BATCH_SIZE) {
    batchStarts.push(i);
  }

  await batchStarts.reduce(async (chain, start) => {
    await chain;
    const batch = absoluteUrls.slice(start, start + SUBTITLE_BATCH_SIZE);
    const results = await fetchSubtitleBatch(hotmartFrame, batch);
    collectSegmentBatchResults(results, segmentBodies, fetchFailedRef);
  }, Promise.resolve());

  return { segmentBodies, fetchFailed: fetchFailedRef.count };
}

async function captureCanvasFrame(hotmartFrame, seekTime, maxWidth) {
  return hotmartFrame
    .evaluate(
      async ({ seekTime: time, mw }) => {
        const v = document.querySelector("video");
        if (!v) return null;

        v.currentTime = time;
        await new Promise((resolve) => {
          const handler = () => {
            v.removeEventListener("seeked", handler); // spellchecker:disable-line
            resolve();
          };
          v.addEventListener("seeked", handler); // spellchecker:disable-line
          setTimeout(resolve, 3000);
        });
        await new Promise((r) => setTimeout(r, 200));

        const canvas = document.createElement("canvas");
        canvas.width = Math.min(v.videoWidth, mw);
        canvas.height = Math.round((canvas.width / v.videoWidth) * v.videoHeight);
        const ctx2d = canvas.getContext("2d");
        ctx2d.drawImage(v, 0, 0, canvas.width, canvas.height);
        return canvas.toDataURL("image/png");
      },
      { seekTime, mw: maxWidth },
    )
    .catch(() => null);
}

async function captureCanvasFrames({ hotmartFrame, timestamps, outputDir, maxWidth, fs }) {
  let success = 0;

  await timestamps.reduce(async (chain, seekTime) => {
    await chain;
    const frameData = await captureCanvasFrame(hotmartFrame, seekTime, maxWidth);
    if (frameData?.startsWith("data:image/png")) {
      const base64 = frameData.replace(PNG_DATA_URL_PREFIX, "");
      const buffer = Buffer.from(base64, "base64");
      const outFile = fs.join(outputDir, `interval_${String(success + 1).padStart(4, "0")}.png`);
      fs.writeFileSync(outFile, buffer);
      success++;
    }
  }, Promise.resolve());

  return success;
}

function mergeHlsFields(target, source) {
  for (const key of [
    "masterUrl",
    "masterUrlFull",
    "subtitlePlaylistUrl",
    "subtitlePlaylistUrlFull",
    "hasVjs",
    "hasHlsJs",
  ]) {
    if (source[key]) target[key] = source[key];
  }
}

async function readVideoSrcHls(hotmartFrame) {
  return hotmartFrame.evaluate(() => {
    const v = document.querySelector("video");
    if (!v) return { error: "no video" };
    const src = v.src || v.currentSrc;
    if (!src?.includes(".m3u8")) {
      return { src: src?.substring(0, 120), hasSrcM3u8: false };
    }
    return {
      src: src.substring(0, 120),
      hasSrcM3u8: true,
      masterUrlFull: src,
      masterUrl: src.split("?")[0],
    };
  });
}

async function readVjsHls(hotmartFrame, subtitleLang) {
  return hotmartFrame.evaluate((lang) => {
    const v = document.querySelector("video");
    const vjsEl = v?.closest(".video-js");
    const vjsPlayer = vjsEl?.__vjs_player__ ?? vjsEl?.player;
    if (!vjsPlayer) return {};

    const result = { hasVjs: true };
    try {
      const tech = vjsPlayer.tech({ IWillNotUseThisInPlugins: true });
      const vhs = tech?.vhs || tech?.hls;
      if (vhs?.playlists?.master?.uri) {
        result.masterUrlFull = vhs.playlists.master.uri;
        result.masterUrl = vhs.playlists.master.uri.split("?")[0];
      }
      const master =
        vhs?.playlists?.master || vhs?.masterPlaylistController_?.mainPlaylistLoader_?.master;
      if (master?.mediaGroups?.SUBTITLES) {
        for (const group of Object.values(master.mediaGroups.SUBTITLES)) {
          for (const [key, track] of Object.entries(group)) {
            if (key.toLowerCase().includes(lang) || track.language?.includes(lang)) {
              result.subtitlePlaylistUrlFull = track.resolvedUri || track.uri;
              result.subtitlePlaylistUrl = result.subtitlePlaylistUrlFull?.split("?")[0];
              return result;
            }
          }
        }
      }
    } catch {
      /* ignore tech access errors */
    }
    return result;
  }, subtitleLang);
}

async function readHlsJsData(hotmartFrame, subtitleLang) {
  return hotmartFrame.evaluate((lang) => {
    const v = document.querySelector("video");
    const hlsInstance = v?._hls || window.hls || window.Hls?.instances?.[0];
    if (!hlsInstance) return {};

    const result = { hasHlsJs: true };
    try {
      if (hlsInstance.url?.includes(".m3u8")) {
        result.masterUrlFull = hlsInstance.url;
        result.masterUrl = hlsInstance.url.split("?")[0];
      }
      for (const track of hlsInstance.subtitleTracks || []) {
        if (track.lang?.includes(lang) || track.name?.toLowerCase()?.includes(lang)) {
          result.subtitlePlaylistUrlFull = track.url;
          result.subtitlePlaylistUrl = track.url?.split("?")[0];
          break;
        }
      }
    } catch {
      /* ignore */
    }
    return result;
  }, subtitleLang);
}

async function scanWindowHls(hotmartFrame, subtitleLang) {
  return hotmartFrame.evaluate((lang) => {
    for (const key of Object.keys(window)) {
      try {
        const obj = window[key];
        if (!obj?.url?.includes?.(".m3u8") || typeof obj.destroy !== "function") continue;
        const result = {
          hasHlsJs: true,
          masterUrlFull: obj.url,
          masterUrl: obj.url.split("?")[0],
        };
        for (const t of obj.subtitleTracks || []) {
          if (t.lang?.includes(lang)) {
            result.subtitlePlaylistUrlFull = t.url;
            result.subtitlePlaylistUrl = t.url?.split("?")[0];
            break;
          }
        }
        return result;
      } catch {
        /* ignore property access errors */
      }
    }
    return {};
  }, subtitleLang);
}

async function readHlsDataFromFrame(hotmartFrame, subtitleLang) {
  try {
    const base = await readVideoSrcHls(hotmartFrame);
    if (base.error) return base;

    const result = {
      src: base.src,
      hasSrcM3u8: base.hasSrcM3u8,
      hasVjs: false,
      hasHlsJs: false,
      masterUrl: base.masterUrl ?? null,
      masterUrlFull: base.masterUrlFull ?? null,
      subtitlePlaylistUrl: null,
      subtitlePlaylistUrlFull: null,
    };

    mergeHlsFields(result, await readVjsHls(hotmartFrame, subtitleLang));
    mergeHlsFields(result, await readHlsJsData(hotmartFrame, subtitleLang));
    if (!result.masterUrlFull) {
      mergeHlsFields(result, await scanWindowHls(hotmartFrame, subtitleLang));
    }

    return result;
  } catch (e) {
    return { error: `evaluate failed: ${e.message}` };
  }
}

async function storeSubtitleManifest(hotmartFrame, hlsData, currentUrl) {
  if (!hlsData.subtitlePlaylistUrlFull) return null;

  const manifestBody = await hotmartFrame.evaluate(async (url) => {
    const resp = await fetch(url);
    if (!resp.ok) return null;
    return resp.text();
  }, hlsData.subtitlePlaylistUrlFull);

  if (!manifestBody) return null;

  const segCount = parseSubtitleManifest(manifestBody).length;
  writeStdout(`    ✓ Subtitle manifest fetched: ${segCount} segments`);

  const entry = getOrCreateEntry(currentUrl);
  entry.hlsMasterUrl = hlsData.masterUrlFull;
  entry.subtitleManifestBody = manifestBody;

  return segCount;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Install page.on("request") and page.on("response") interceptors for
 * HLS master URL and subtitle manifest capture.
 *
 * Safe to call multiple times — installs only once per module lifetime.
 *
 * @param {import('playwright').Page} page
 * @param {string} subtitleLang — e.g. "eng"
 */
export function installInterceptors(page, subtitleLang) {
  if (interceptorsInstalled) return;

  page.on("request", (request) => {
    const url = request.url();
    if (url.includes("master-pkg-t-") && url.includes(".m3u8")) {
      getOrCreateEntry(page.url()).hlsMasterUrl = url;
    }
  });

  page.on("response", async (response) => {
    const url = response.url();
    if (response.status() !== 200) return;

    try {
      if (url.includes("master-pkg-t-") && url.includes(".m3u8")) {
        getOrCreateEntry(page.url()).hlsMasterUrl = url;
      }

      if (url.includes(`textstream_${subtitleLang}`) && url.includes(".m3u8")) {
        const body = await response.text();
        getOrCreateEntry(page.url()).subtitleManifestBody = body;
      }
    } catch {
      // Response body may not be available for all intercepted responses
    }
  });

  interceptorsInstalled = true;
}

/**
 * Prepare a lesson page for extraction: find iframe, read HLS data from
 * Video.js/hls.js internals, fetch subtitle manifest.
 *
 * @param {import('playwright').Page} page
 * @param {string} subtitleLang — e.g. "eng"
 * @param {number} manifestTimeoutMs
 * @returns {Promise<{ hasVideo: boolean, hotmartFrame?: object, hlsMasterUrl?: string, subtitleSegments?: number, warning?: string }>}
 */
export async function preparePage(page, subtitleLang, _manifestTimeoutMs) {
  const currentUrl = page.url();

  capturedData.delete(currentUrl);

  const hasHotmart = await hasHotmartPlayer(page);

  writeStdout(`    hasHotmart: ${hasHotmart}`);

  if (!hasHotmart) {
    return { hasVideo: false, hotmartFrame: null };
  }

  const allFrames = page.frames();
  writeStdout(
    `    Frames: ${allFrames.length} — ${allFrames.map((f) => f.url().split("?")[0].substring(0, 50)).join(", ")}`,
  );
  const hotmartFrame = findHotmartFrame(page);

  if (!hotmartFrame) {
    throw new Error("Hotmart video player detected in DOM but iframe not accessible.");
  }
  writeStdout("    ✓ Hotmart iframe found.");

  await hotmartFrame.waitForTimeout(2000);

  const videoState = await hotmartFrame
    .evaluate(() => {
      const v = document.querySelector("video");
      return v ? { paused: v.paused, currentTime: v.currentTime, readyState: v.readyState } : null;
    })
    .catch(() => null);

  writeStdout(`    Video state: ${JSON.stringify(videoState)}`);

  if (!videoState) {
    throw new Error("No <video> element found in Hotmart iframe.");
  }

  const hlsData = await readHlsDataFromFrame(hotmartFrame, subtitleLang);

  writeStdout(
    `    HLS data: master=${hlsData.masterUrl ? "found" : "none"}, sub=${hlsData.subtitlePlaylistUrl ? "found" : "none"}, vjs=${hlsData.hasVjs}`,
  );

  const subtitleSegments = await storeSubtitleManifest(hotmartFrame, hlsData, currentUrl);
  if (subtitleSegments !== null) {
    return {
      hasVideo: true,
      hotmartFrame,
      hlsMasterUrl: hlsData.masterUrlFull,
      subtitleSegments,
    };
  }

  if (hlsData.masterUrlFull) {
    getOrCreateEntry(currentUrl).hlsMasterUrl = hlsData.masterUrlFull;
  }

  return {
    hasVideo: true,
    hotmartFrame,
    hlsMasterUrl: hlsData.masterUrlFull ?? null,
    subtitleSegments: 0,
    warning:
      "Could not find subtitle playlist. Video may not have captions, or HLS player structure changed.",
  };
}

/**
 * Extract transcript from captured subtitle data.
 * CRITICAL: All fetch() calls execute inside hotmartFrame.evaluate() (CORS).
 *
 * @param {import('playwright').Page} page
 * @returns {Promise<string>} — formatted transcript text
 */
export async function getTranscript(page) {
  const currentUrl = page.url();
  const captured = capturedData.get(currentUrl);

  if (!captured?.subtitleManifestBody) {
    throw new Error("No subtitle manifest captured. Ensure preparePage() ran and video played.");
  }

  const segmentUrls = parseSubtitleManifest(captured.subtitleManifestBody);
  if (segmentUrls.length === 0) {
    throw new Error("Subtitle manifest contained no WebVTT segment URLs.");
  }

  const firstSeg = segmentUrls[0] ?? "";
  const segmentsAreAbsolute = firstSeg.startsWith("http");

  let hlsBase = null;
  if (!segmentsAreAbsolute) {
    if (captured.hlsMasterUrl) {
      hlsBase = captured.hlsMasterUrl.substring(0, captured.hlsMasterUrl.lastIndexOf("/") + 1);
    } else {
      const videoIdMatch = firstSeg.match(VIDEO_ID_PREFIX);
      if (videoIdMatch) {
        hlsBase = `https://vod-akm.play.hotmart.com/video/${videoIdMatch[1]}/hls/`;
      }
    }
  }

  const hotmartFrame = findHotmartFrame(page);
  if (!hotmartFrame) {
    throw new Error("Hotmart iframe not found — cannot fetch subtitle segments.");
  }

  const absoluteUrls = segmentUrls.map((seg) => {
    if (seg.startsWith("http")) return seg;
    if (hlsBase) return `${hlsBase}${seg}`;
    return seg;
  });

  writeStdout(
    `    Segments: ${segmentUrls.length}, absolute: ${segmentsAreAbsolute}, hlsBase: ${hlsBase ? "derived" : "none"}`,
  );
  if (absoluteUrls.length > 0) {
    writeStdout(`    First URL (truncated): ${absoluteUrls[0].substring(0, 100)}...`);
  }

  const { segmentBodies, fetchFailed } = await fetchSubtitleSegmentBatches(
    hotmartFrame,
    absoluteUrls,
  );

  if (segmentBodies.length === 0) {
    throw new Error(
      `All ${absoluteUrls.length} subtitle segment fetches failed (${fetchFailed} errors). First URL pattern: ${absoluteUrls[0]?.substring(0, 80)}`,
    );
  }

  const { transcript, cueCount } = processSubtitleSegments(segmentBodies);

  if (!transcript || cueCount === 0) {
    throw new Error("Subtitle segments contained no parseable cues.");
  }

  return transcript;
}

/**
 * Get the captured HLS master URL for the current page.
 *
 * @param {import('playwright').Page} page
 * @returns {string}
 */
export function getHlsUrl(page) {
  const currentUrl = page.url();
  const captured = capturedData.get(currentUrl);

  if (!captured?.hlsMasterUrl) {
    throw new Error("No HLS master URL captured. Ensure preparePage() ran and video played.");
  }

  return captured.hlsMasterUrl;
}

/**
 * Extract video frames via canvas drawImage within the Hotmart iframe.
 *
 * Required because Hotmart HLS CDN rejects external HTTP clients
 * (session-scoped tokens make ffmpeg fail with 403).
 *
 * @param {import('playwright').Page} page
 * @param {number} duration — video duration in seconds
 * @param {string} outputDir — directory to write frame PNG files
 * @param {object} [options]
 * @param {number} [options.intervalSec=15]
 * @param {number} [options.maxWidth=1280]
 * @returns {Promise<{method: string, count: number}>}
 */
export async function extractFrames(page, duration, outputDir, options = {}) {
  const { intervalSec = 15, maxWidth = 1280 } = options;
  const { mkdirSync, writeFileSync } = await import("node:fs");
  const { join } = await import("node:path");

  mkdirSync(outputDir, { recursive: true });
  writeStdout(`    Canvas: duration=${duration}, interval=${intervalSec}, outputDir=${outputDir}`);

  const hotmartFrame = findHotmartFrame(page);
  if (!hotmartFrame) {
    throw new Error("Hotmart iframe not found for frame extraction.");
  }

  const timestamps = [];
  for (let t = intervalSec; t < duration; t += intervalSec) timestamps.push(t);

  const success = await captureCanvasFrames({
    hotmartFrame,
    timestamps,
    outputDir,
    maxWidth,
    fs: { writeFileSync, join },
  });

  return { method: "canvas-seek", count: success };
}

/**
 * Clear captured data for a specific URL.
 * @param {string} url
 */
export function clearCapturedData(url) {
  capturedData.delete(url);
}

/**
 * Check if the Hotmart video player element exists on the page.
 * @param {import('playwright').Page} page
 * @returns {Promise<boolean>}
 */
export async function hasHotmartPlayer(page) {
  return page.evaluate(() => !!document.querySelector(".hotmart_video_player")).catch(() => false);
}

// ---------------------------------------------------------------------------
// Test helpers (exported for unit tests only)
// ---------------------------------------------------------------------------

/** @returns {boolean} */
export function isInterceptorsInstalled() {
  return interceptorsInstalled;
}

/** @returns {Map} */
export function getCapturedData() {
  return capturedData;
}

/**
 * Reset module state — for tests only.
 */
export function resetState() {
  capturedData.clear();
  interceptorsInstalled = false;
}
