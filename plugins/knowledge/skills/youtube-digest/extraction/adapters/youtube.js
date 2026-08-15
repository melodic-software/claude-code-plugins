/**
 * YouTube source adapter: URL grammar, queue acceptance, error classification,
 * link harvest, and yt-dlp acquisition composed from the shared machinery in
 * `acquisition/`.
 */

import { acquireYouTubeMedia, extractVideoId } from "../acquisition/acquire.js";
import { YOUTUBE_BOT_CHALLENGE_PATTERNS } from "../acquisition/acquire-yt-dlp-auth.js";
import { findPinnedComment } from "../acquisition/video-metadata.js";
import { deduplicateHarvestedLinks, linksFromText } from "../harvesting/harvest-links.js";
import { createAcquisitionEnvelope, createSourceAdapter } from "./adapter-contract.js";

/** @typedef {import('../acquisition/video-metadata.js').VideoMetadata} VideoMetadata */
/** @typedef {import('./adapter-contract.js').SourceAdapterSpec} SourceAdapterSpec */
/** @typedef {import('./adapter-contract.js').AcquireContext} AcquireContext */
/** @typedef {import('./adapter-contract.js').AcquireOutcome} AcquireOutcome */
/** @typedef {import('./adapter-contract.js').SourceMetadata} SourceMetadata */
/** @typedef {import('./adapter-contract.js').UrlClaim} UrlClaim */
/** @typedef {import('./adapter-contract.js').EnqueueDecision} EnqueueDecision */
/** @typedef {import('../harvesting/models.js').HarvestedLink} HarvestedLink */

/**
 * stderr signatures that mean the video is permanently gone / wrong — reject,
 * do not enqueue, do not retry. Everything else (bot-check, age-gate, network,
 * unknown) is transient.
 *
 * @type {readonly RegExp[]}
 */
export const YOUTUBE_UNAVAILABLE_PATTERNS = Object.freeze([
  /Video unavailable/i,
  /Private video/i,
  /This video (?:is|has been) (?:no longer available|removed|private)/i,
  /removed by the uploader/i,
  /(?:account|channel) (?:.*)?has been terminated/i,
  /does not exist/i,
  /Incomplete YouTube ID/i,
  /is not a valid URL/i,
]);

const YOUTUBE_EXTRACTOR_ARGS = "youtube:max_comments=20,all,top;comment_sort=top";

/**
 * yt-dlp arg + spawn-classification declarations the shared acquisition
 * machinery consumes for this source.
 */
const YOUTUBE_SOURCE_ACQUISITION = Object.freeze({
  writeComments: true,
  extractorArgs: YOUTUBE_EXTRACTOR_ARGS,
  loginRequiredPatterns: YOUTUBE_BOT_CHALLENGE_PATTERNS,
  allowBrowserCookieProfileFallback: true,
});

const spec = /** @satisfies {SourceAdapterSpec} */ ({
  id: "youtube",
  hosts: ["youtube.com", "youtu.be"],
  extractorArgs: YOUTUBE_EXTRACTOR_ARGS,
  captionClass: "manual-and-auto",
  errorPatterns: {
    retryable: [],
    fatal: [...YOUTUBE_UNAVAILABLE_PATTERNS],
    loginRequired: [...YOUTUBE_BOT_CHALLENGE_PATTERNS],
  },
  transcriptStrategy: /** @type {'captions'} */ ("captions"),
  capabilities: {
    comments: true,
    browserCookieFallback: true,
  },

  /**
   * YouTube canonicalization is identity: the acquisition engine accepts every
   * claimed URL variant (watch, youtu.be, live, embed, shorts) verbatim.
   *
   * @param {string} url
   * @returns {UrlClaim|null}
   */
  matchUrl: (url) => {
    const videoId = extractVideoId(url);
    if (!videoId) return null;
    return { sliceKey: videoId, canonicalUrl: url };
  },

  /**
   * URL-authoritative slice identity: the video id captured from the URL wins;
   * metadata id is a fallback only when the URL yields none (e.g. a recovered
   * slice with a rewritten URL).
   *
   * @param {string} url
   * @param {SourceMetadata|null} metadata
   * @returns {string|null}
   */
  extractSliceKey: (url, metadata) => {
    const fromUrl = extractVideoId(url);
    if (fromUrl) return fromUrl;
    return metadata && typeof metadata.id === "string" && metadata.id ? metadata.id : null;
  },

  /**
   * @param {string} url
   * @param {AcquireContext} context
   * @returns {Promise<AcquireOutcome>}
   */
  acquire: async (url, context) => {
    const result = await acquireYouTubeMedia(
      url,
      { workDir: context.workDir, mode: context.mode, source: YOUTUBE_SOURCE_ACQUISITION },
      context.deps ?? {},
    );
    if (!result.success || !result.data) {
      return /** @type {AcquireOutcome} */ (result);
    }
    const { artifacts, metadata, caption, acquireMetrics } = result.data;
    const envelope = createAcquisitionEnvelope({
      entries: [
        {
          mediaPath: artifacts.videoPath,
          captionPaths: artifacts.captionPaths,
          metadataPath: artifacts.metadataPath,
          caption,
        },
      ],
      metadata,
      workDir: context.workDir,
      ...(acquireMetrics ? { acquireMetrics } : {}),
    });
    return { ...result, data: envelope };
  },

  /**
   * Harvest reference links from description, chapters, and pinned comment.
   *
   * @param {SourceMetadata} metadata
   * @returns {HarvestedLink[]}
   */
  harvestLinks: (metadata) => {
    const videoMetadata = /** @type {VideoMetadata} */ (metadata);
    /** @type {HarvestedLink[]} */
    const links = [];

    links.push(...linksFromText(videoMetadata.description, "description"));

    for (const chapter of videoMetadata.chapters) {
      links.push(
        ...linksFromText(chapter.title, "chapter", {
          context: chapter.title,
          timestampSec: chapter.startSec,
        }),
      );
    }

    const pinned = findPinnedComment(videoMetadata.comments);
    if (pinned) {
      links.push(...linksFromText(pinned, "pinned-comment", { context: pinned }));
    }

    return deduplicateHarvestedLinks(links);
  },

  /**
   * @param {string} url
   * @returns {EnqueueDecision}
   */
  acceptForEnqueue: (url) => {
    const videoId = extractVideoId(url);
    if (!videoId) {
      return {
        ok: false,
        note: "not a YouTube video URL",
        reason: "URL does not resolve to a YouTube video id",
      };
    }
    return { ok: true, key: videoId };
  },
});

export const adapter = createSourceAdapter(spec);
