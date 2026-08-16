import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { describe, expect, it, vi } from "vitest";

import { adapterSourceDeclarations } from "../acquisition/acquire.js";
import { PREFLIGHT_FIELD_SEP, preflightVideo } from "../acquisition/preflight-metadata.js";
import { spawnYtDlpWithAuthFallback } from "../acquisition/spawn-yt-dlp-with-auth-fallback.js";
import { harvestMetadataLinks } from "../harvesting/harvest-links.js";
import { writeEnvelopeTranscriptArtifacts } from "../transcript/write-transcript.js";
import { classifyErrorDetail } from "./adapter-contract.js";
import { acquireMedia } from "./registry.js";
import { describeSourceAdapterContract } from "./shared-adapter-suite.js";
import {
  acquireXMedia,
  adapter,
  canonicalXStatusUrl,
  convertSrtToVtt,
  detectSnowflakeAliasing,
  detectSyndicationDegradation,
  parseDelegationRefusal,
  parseXStatusUrl,
  snowflakeTimestampMs,
  X_ALLOWED_EXTRACTORS,
  X_SYNDICATION_DEGRADATION_WARNING,
} from "./x.js";

const REFUSED_URL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ";
const REFUSAL_STDERR = `ERROR: No suitable extractor found for URL ${REFUSED_URL}`;

const TWID = "1720000000000000000";
const STATUS_URL = `https://x.com/someuser/status/${TWID}`;
// Media ids are snowflakes too: minted 60 s before the post (normal composition
// lag) vs 3 days before (quote/retweet aliasing).
const MEDIA_ID = String(BigInt(TWID) - (60_000n << 22n));
const OLD_MEDIA_ID = String(BigInt(TWID) - (259_200_000n << 22n));
const RETWEET_MEDIA_ID = String(BigInt(TWID) - (604_800_000n << 22n));
const SECOND_MEDIA_ID = String(BigInt(MEDIA_ID) + (5_000n << 22n));

const CLEAN_VTT = `WEBVTT

00:00:00.000 --> 00:00:02.000
hello from x
`;

// Real live tag shape (probed 2026-08-15): one tag per cue wrapping the text,
// with per-word ms durations and inclusive character ranges as attributes.
const TAGGED_VTT = `WEBVTT

00:00:00.000 --> 00:00:02.000
<X-word-ms ms=380,319,260 index=1 character_ranges=0-4,6-9,11-11>hello from x</X-word-ms>
`;

const CLEANUP_SRT = `1
00:00:00,000 --> 00:00:02,000
hello from x
`;

/**
 * @param {object} [overrides]
 */
function twitterInfoJson(overrides = {}) {
  return JSON.stringify({
    extractor: "twitter",
    extractor_key: "Twitter",
    id: MEDIA_ID,
    display_id: TWID,
    title: "Fixture Post",
    description: "Read https://example.com/paper for details",
    like_count: 12,
    repost_count: 3,
    comment_count: 4,
    view_count: 900,
    formats: [{ format_id: "http-2176" }],
    ...overrides,
  });
}

/**
 * In-memory acquisition fixture: each spawn call applies the next pass's
 * stderr + files, listFiles/readFile/writeFile/removeFile all resolve against
 * the same map.
 *
 * @param {string} workDir
 * @param {Array<{stderr?: string, success?: boolean, addFiles?: Record<string, string>}>} passes
 */
function createFixtureDeps(workDir, passes) {
  /** @type {Map<string, string>} */
  const files = new Map();
  const spawn = vi.fn(async () => {
    const pass = passes[spawn.mock.calls.length - 1] ?? {};
    for (const [name, content] of Object.entries(pass.addFiles ?? {})) {
      files.set(path.join(workDir, name), content);
    }
    const success = pass.success !== false;
    return {
      success,
      code: success ? 0 : 1,
      signal: null,
      stdout: "",
      stderr: pass.stderr ?? "",
      timedOut: false,
    };
  });
  return {
    files,
    spawn,
    deps: {
      spawn,
      listFiles: async () => [...files.keys()],
      readFile: async (/** @type {string} */ filePath) => {
        const content = files.get(filePath);
        if (content === undefined) throw new Error(`missing fixture file: ${filePath}`);
        return content;
      },
      writeFile: async (/** @type {string} */ filePath, /** @type {string} */ content) => {
        files.set(filePath, content);
      },
      removeFile: async (/** @type {string} */ filePath) => {
        files.delete(filePath);
      },
      sleep: async () => {},
      withThrottle: (/** @type {() => Promise<unknown>} */ fn) => fn(),
    },
  };
}

describeSourceAdapterContract(adapter, {
  claimedUrls: [
    { url: STATUS_URL, sliceKey: TWID },
    { url: `https://twitter.com/SomeUser/status/${TWID}?s=20&t=tracking`, sliceKey: TWID },
    { url: `https://mobile.twitter.com/someuser/status/${TWID}`, sliceKey: TWID },
    { url: `https://x.com/someuser/status/${TWID}/video/2`, sliceKey: TWID },
    { url: `https://x.com/i/web/status/${TWID}`, sliceKey: TWID },
    { url: `https://twitter.com/statuses/${TWID}`, sliceKey: TWID },
  ],
  unclaimedUrls: [
    "https://x.com/someuser",
    "https://x.com/i/spaces/1YqKDqWqdPLxV",
    "https://x.com/someuser/status/not-a-status-id",
    // Bounded grammar: a 26-digit "status id" exceeds any snowflake and is refused.
    `https://x.com/someuser/status/${"9".repeat(26)}`,
    `https://x.com/someuser/status/${TWID}/video/1000`,
    "https://example.com/someuser/status/1720000000000000000",
    "https://notx.com/someuser/status/1720000000000000000",
    "https://x.com.evil.example/someuser/status/1720000000000000000",
    "not a url",
  ],
  harvestMetadata: {
    id: MEDIA_ID,
    title: "Fixture Post",
    description: "Read https://example.com/paper and https://example.com/paper again",
    "source:displayId": TWID,
    "source:blockedDelegations": [{ url: REFUSED_URL, extractor: "refused-before-fetch" }],
  },
});

describe("x adapter declarations", () => {
  it("declares hosts, null extractor args, platform-ASR caption class, and repair strategy", () => {
    expect(adapter.id).toBe("x");
    expect([...adapter.hosts]).toEqual(["x.com", "twitter.com"]);
    expect(adapter.extractorArgs).toBeNull();
    expect(adapter.captionClass).toBe("platform-asr");
    expect(adapter.transcriptStrategy).toBe("captions+repair");
  });

  it("declares the twitter-family extractor allow-list (SSRF guard) consumed by shared machinery", () => {
    expect(adapter.allowedExtractors).toBe("twitter.*");
    expect(adapterSourceDeclarations(adapter).allowedExtractors).toBe("twitter.*");
  });

  it("declares comments and browser-cookie-fallback OFF (cookies file is the only auth route)", () => {
    expect(adapter.capabilities.comments).toBe(false);
    expect(adapter.capabilities.browserCookieFallback).toBe(false);
    const declarations = adapterSourceDeclarations(adapter);
    expect(declarations.writeComments).toBe(false);
    expect(declarations.allowBrowserCookieProfileFallback).toBe(false);
    expect(declarations.extractorArgs).toBeNull();
  });

  it("declares mediaOptional: 0-media posts are well-formed for every yt-dlp consumer", () => {
    expect(adapter.capabilities.mediaOptional).toBe(true);
    expect(adapterSourceDeclarations(adapter).ignoreNoFormatsError).toBe(true);
  });
});

describe("x canonicalization (adapter-level, T10 (ii))", () => {
  it("re-derives the canonical status URL: pinned host, lowercased handle, no tracking params", () => {
    expect(adapter.matchUrl(`https://twitter.com/SomeUser/status/${TWID}?s=20&t=abc#m`)).toEqual({
      sliceKey: TWID,
      canonicalUrl: STATUS_URL,
    });
    expect(adapter.matchUrl(`https://mobile.twitter.com/someuser/status/${TWID}/`)).toEqual({
      sliceKey: TWID,
      canonicalUrl: STATUS_URL,
    });
  });

  it("preserves the pinned media index and normalizes /photo/<n> to /video/<n>", () => {
    expect(adapter.matchUrl(`${STATUS_URL}/video/2`)?.canonicalUrl).toBe(`${STATUS_URL}/video/2`);
    expect(adapter.matchUrl(`${STATUS_URL}/photo/2`)?.canonicalUrl).toBe(`${STATUS_URL}/video/2`);
    // Index 0 is falsy but pinned — it must survive canonicalization.
    expect(adapter.matchUrl(`${STATUS_URL}/video/0`)?.canonicalUrl).toBe(`${STATUS_URL}/video/0`);
  });

  it("canonicalizes handle-less forms to i/web", () => {
    expect(adapter.matchUrl(`https://twitter.com/statuses/${TWID}`)?.canonicalUrl).toBe(
      `https://x.com/i/web/status/${TWID}`,
    );
    expect(adapter.matchUrl(`https://x.com/i/status/${TWID}`)?.canonicalUrl).toBe(
      `https://x.com/i/web/status/${TWID}`,
    );
    expect(adapter.matchUrl(`https://x.com/i/web/status/${TWID}`)?.canonicalUrl).toBe(
      `https://x.com/i/web/status/${TWID}`,
    );
  });

  it("parses parts and rebuilds them", () => {
    const parts = parseXStatusUrl(`https://twitter.com/SomeUser/status/${TWID}/photo/3`);
    expect(parts).toEqual({ statusId: TWID, handle: "someuser", mediaIndex: 3 });
    expect(canonicalXStatusUrl(/** @type {NonNullable<typeof parts>} */ (parts))).toBe(
      `${STATUS_URL}/video/3`,
    );
  });
});

describe("x slice identity (display_id canonical, id as media discriminator)", () => {
  it("resolves the same slice key for every URL form and any metadata (same pair -> same slice)", () => {
    const urls = [
      STATUS_URL,
      `${STATUS_URL}/video/2`,
      `https://twitter.com/someuser/status/${TWID}?s=20`,
      `https://x.com/i/web/status/${TWID}`,
    ];
    for (const url of urls) {
      expect(adapter.extractSliceKey(url, null)).toBe(TWID);
      expect(
        adapter.extractSliceKey(url, { id: MEDIA_ID, title: "", description: "" }),
      ).toBe(TWID);
    }
  });

  it("falls back to metadata display id, then id, only when the URL yields none", () => {
    const noStatusUrl = "https://x.com/someuser";
    expect(
      adapter.extractSliceKey(noStatusUrl, {
        id: MEDIA_ID,
        title: "",
        description: "",
        "source:displayId": TWID,
      }),
    ).toBe(TWID);
    expect(
      adapter.extractSliceKey(noStatusUrl, { id: MEDIA_ID, title: "", description: "" }),
    ).toBe(MEDIA_ID);
    expect(adapter.extractSliceKey(noStatusUrl, null)).toBeNull();
    // A non-path-safe fallback is refused, never returned.
    expect(
      adapter.extractSliceKey(noStatusUrl, { id: "../evil", title: "", description: "" }),
    ).toBeNull();
  });
});

describe("snowflake timestamps and quote/retweet aliasing", () => {
  it("decodes the snowflake timestamp", () => {
    const expected = Number((BigInt(TWID) >> 22n) + 1288834974657n);
    expect(snowflakeTimestampMs(TWID)).toBe(expected);
    expect(snowflakeTimestampMs("not-digits")).toBeNull();
    expect(snowflakeTimestampMs("12345")).toBeNull();
  });

  it("does not flag an original post (small composition lag) or the link-post id === twid branch", () => {
    expect(detectSnowflakeAliasing(TWID, TWID)).toBeNull();
    const original = detectSnowflakeAliasing(TWID, MEDIA_ID);
    expect(original?.aliasSuspected).toBe(false);
    expect(original?.deltaMs).toBe(60_000);
  });

  it("flags media minted far before the URL's status id (quote/retweet aliasing)", () => {
    const aliased = detectSnowflakeAliasing(TWID, OLD_MEDIA_ID);
    expect(aliased?.aliasSuspected).toBe(true);
    expect(aliased?.deltaMs).toBe(259_200_000);
    expect(aliased?.urlStatusId).toBe(TWID);
    expect(aliased?.resultId).toBe(OLD_MEDIA_ID);
  });
});

describe("x error-pattern taxonomy", () => {
  it("maps the observed X post-content failures to fatal-source", () => {
    for (const detail of [
      `ERROR: [twitter] ${TWID}: No video could be found in this tweet`,
      `ERROR: [twitter] ${TWID}: No video formats found!`,
      "ERROR: Unsupported URL: https://example.com/article",
      `ERROR: [twitter] ${TWID}: Media #2 is not a video`,
      `ERROR: [twitter] ${TWID}: Video #5 is unavailable`,
    ]) {
      expect(classifyErrorDetail(adapter.errorPatterns, detail)).toBe("fatal");
    }
  });

  it("classifies EXACTLY the three documented login-required cases", () => {
    for (const detail of [
      `ERROR: [twitter] ${TWID}: NSFW tweet requires authentication. Use --cookies-from-browser or --cookies for the authentication.`,
      `ERROR: [twitter] ${TWID}: You are not authorized to view this protected tweet. Use --cookies-from-browser or --cookies for the authentication.`,
      `ERROR: [twitter] ${TWID}: Sorry, you are not authorized to see this status. Use --cookies-from-browser or --cookies for the authentication.`,
    ]) {
      expect(classifyErrorDetail(adapter.errorPatterns, detail)).toBe("login-required");
    }
  });

  it("never applies YouTube semantics or the bare cookie hint to X failures", () => {
    for (const detail of [
      "ERROR: Sign in to confirm you're not a bot",
      "Incomplete YouTube ID",
      "Use --cookies-from-browser or --cookies for the authentication.",
    ]) {
      expect(classifyErrorDetail(adapter.errorPatterns, detail)).toBeNull();
    }
  });

  it("an attacker-influenced URL echoed on stderr can never classify as login-required", () => {
    // The refusal/unsupported line carries a URL the post author chose; the
    // login-required patterns are anchored to [twitter]-tagged ERROR lines, so
    // these classify fatal (the Unsupported URL pattern), never login-required.
    for (const detail of [
      "ERROR: [generic] Unsupported URL: https://evil.example/not-authorized-content",
      "ERROR: Unsupported URL: https://evil.example/NSFW%20tweet%20requires%20authentication",
    ]) {
      expect(classifyErrorDetail(adapter.errorPatterns, detail)).toBe("fatal");
    }
  });

  it("classifies the source's syndication warning as retryable (and ONLY source signatures)", () => {
    expect(
      classifyErrorDetail(
        adapter.errorPatterns,
        `WARNING: [twitter] ${TWID}: ${X_SYNDICATION_DEGRADATION_WARNING}`,
      ),
    ).toBe("retryable");
    // The table describes the source's stderr, never this adapter's own
    // emitted failure messages.
    expect(
      classifyErrorDetail(adapter.errorPatterns, "X acquisition degraded (rate-limited …)"),
    ).toBeNull();
  });

  it("cookie fallback gating: a login-required X failure never iterates browser profiles", async () => {
    const spawn = vi.fn(async () => ({
      success: false,
      code: 1,
      signal: null,
      stdout: "",
      stderr: `ERROR: [twitter] ${TWID}: NSFW tweet requires authentication. Use --cookies for the authentication.`,
      timedOut: false,
    }));
    const result = await spawnYtDlpWithAuthFallback(spawn, () => ["--version"], {
      env: {},
      source: adapterSourceDeclarations(adapter),
    });
    expect(result.success).toBe(false);
    expect(spawn).toHaveBeenCalledTimes(1);
  });
});

describe("compound 429 silent-degradation detector", () => {
  const countsPresent = { repost_count: 3, comment_count: 4 };

  it("positive: warning + missing counts flags degradation", () => {
    const degradation = detectSyndicationDegradation({
      stderr: `WARNING: [twitter] ${TWID}: ${X_SYNDICATION_DEGRADATION_WARNING}`,
      postInfo: { like_count: 10 },
      entryCount: 1,
    });
    expect(degradation).toMatchObject({
      warningSeen: true,
      countsMissing: true,
      possibleMultiMediaCollapse: true,
    });
  });

  it("negative: a legitimate single-video post with counts and no warning must NOT flag", () => {
    expect(
      detectSyndicationDegradation({ stderr: "", postInfo: countsPresent, entryCount: 1 }),
    ).toBeNull();
  });

  it("boundary: counts present but warning seen still flags (syndication response is partial)", () => {
    const degradation = detectSyndicationDegradation({
      stderr: `WARNING: [twitter] ${TWID}: ${X_SYNDICATION_DEGRADATION_WARNING}`,
      postInfo: countsPresent,
      entryCount: 2,
    });
    expect(degradation).toMatchObject({
      warningSeen: true,
      countsMissing: false,
      possibleMultiMediaCollapse: false,
    });
  });

  it("counts are only judged when a twitter post payload exists", () => {
    expect(detectSyndicationDegradation({ stderr: "", postInfo: null, entryCount: 0 })).toBeNull();
  });
});

describe("convertSrtToVtt", () => {
  it("produces a WEBVTT document with dot decimals and no cue counters", () => {
    const vtt = convertSrtToVtt(CLEANUP_SRT);
    expect(vtt.startsWith("WEBVTT\n\n")).toBe(true);
    expect(vtt).toContain("00:00:00.000 --> 00:00:02.000");
    expect(vtt).toContain("hello from x");
    expect(vtt).not.toMatch(/^\d+$/m);
  });
});

describe("acquireXMedia (fixture-driven, offline)", () => {
  const workDir = path.join("/fixture", "x-work");

  it("single video (full): 1 -> single-entry collection, never a bare object", async () => {
    const { deps, spawn } = createFixtureDeps(workDir, [
      { addFiles: { [`${MEDIA_ID}.info.json`]: twitterInfoJson(), [`${MEDIA_ID}.en.vtt`]: CLEAN_VTT } },
      { addFiles: { [`${MEDIA_ID}.mp4`]: "binary" } },
    ]);
    const result = await acquireXMedia(STATUS_URL, { workDir, mode: "full", deps });

    expect(result.success).toBe(true);
    const envelope = result.data;
    expect(Array.isArray(envelope.entries)).toBe(true);
    expect(envelope.entries).toHaveLength(1);
    expect(envelope.entries[0].mediaPath).toBe(path.join(workDir, `${MEDIA_ID}.mp4`));
    expect(envelope.entries[0].captionPaths).toEqual([path.join(workDir, `${MEDIA_ID}.en.vtt`)]);
    expect(envelope.entries[0].caption?.path).toBe(path.join(workDir, `${MEDIA_ID}.en.vtt`));
    expect(envelope.metadata.id).toBe(MEDIA_ID);
    expect(envelope.metadata["source:displayId"]).toBe(TWID);
    expect(envelope.metadata["source:snowflakeAliasing"]).toBeUndefined();

    // Probe pass first (never media), media pass second; both on the canonical URL.
    expect(spawn).toHaveBeenCalledTimes(2);
    const probeArgs = spawn.mock.calls[0][1];
    const mediaArgs = spawn.mock.calls[1][1];
    expect(probeArgs).toContain("--skip-download");
    expect(probeArgs).toContain("--ignore-no-formats-error");
    expect(probeArgs).toContain("--no-playlist");
    expect(probeArgs).toContain("--write-subs");
    expect(probeArgs).not.toContain("--write-auto-subs");
    expect(probeArgs[probeArgs.indexOf("--sub-langs") + 1]).toBe("en.*,und,-live_chat");
    expect(probeArgs[probeArgs.indexOf("--use-extractors") + 1]).toBe(X_ALLOWED_EXTRACTORS);
    expect(probeArgs.at(-1)).toBe(STATUS_URL);
    expect(mediaArgs).toContain("-f");
    expect(mediaArgs).not.toContain("--skip-download");
    expect(mediaArgs[mediaArgs.indexOf("--use-extractors") + 1]).toBe(X_ALLOWED_EXTRACTORS);
    expect(mediaArgs.at(-1)).toBe(STATUS_URL);
  });

  it("transcript mode: single probe pass, no media download", async () => {
    const { deps, spawn } = createFixtureDeps(workDir, [
      { addFiles: { [`${MEDIA_ID}.info.json`]: twitterInfoJson(), [`${MEDIA_ID}.en.vtt`]: CLEAN_VTT } },
    ]);
    const result = await acquireXMedia(STATUS_URL, { workDir, mode: "transcript", deps });

    expect(result.success).toBe(true);
    expect(spawn).toHaveBeenCalledTimes(1);
    expect(result.data.entries).toHaveLength(1);
    expect(result.data.entries[0].mediaPath).toBe("");
    expect(result.data.entries[0].caption?.path).toBe(path.join(workDir, `${MEDIA_ID}.en.vtt`));
  });

  it("N videos: playlist declaration order wins; every entry matches its own artifacts", async () => {
    const playlist = JSON.stringify({
      extractor: "twitter",
      _type: "playlist",
      id: TWID,
      display_id: TWID,
      title: "Fixture Post",
      description: "two clips",
      repost_count: 1,
      comment_count: 1,
      entries: [{ id: SECOND_MEDIA_ID }, { id: MEDIA_ID }],
    });
    const { deps } = createFixtureDeps(workDir, [
      {
        addFiles: {
          [`${TWID}.info.json`]: playlist,
          [`${MEDIA_ID}.info.json`]: twitterInfoJson({ title: "Fixture Post #2" }),
          [`${SECOND_MEDIA_ID}.info.json`]: twitterInfoJson({
            id: SECOND_MEDIA_ID,
            title: "Fixture Post #1",
          }),
          [`${MEDIA_ID}.en.vtt`]: CLEAN_VTT,
        },
      },
      {
        addFiles: {
          [`${MEDIA_ID}.mp4`]: "binary-1",
          [`${SECOND_MEDIA_ID}.mp4`]: "binary-2",
        },
      },
    ]);
    const result = await acquireXMedia(STATUS_URL, { workDir, mode: "full", deps });

    expect(result.success).toBe(true);
    const envelope = result.data;
    expect(envelope.entries).toHaveLength(2);
    expect(envelope.entries[0].mediaPath).toBe(path.join(workDir, `${SECOND_MEDIA_ID}.mp4`));
    expect(envelope.entries[1].mediaPath).toBe(path.join(workDir, `${MEDIA_ID}.mp4`));
    expect(envelope.entries[1].captionPaths).toEqual([path.join(workDir, `${MEDIA_ID}.en.vtt`)]);
    expect(envelope.entries[0].captionPaths).toEqual([]);
    expect(envelope.metadata.title).toBe("Fixture Post");
  });

  it("honors the URL-pinned /video/<n> index (canonical URL + --no-playlist select it)", async () => {
    const pinnedUrl = `${STATUS_URL}/video/2`;
    const { deps, spawn } = createFixtureDeps(workDir, [
      { addFiles: { [`${MEDIA_ID}.info.json`]: twitterInfoJson({ title: "Fixture Post #2" }) } },
      { addFiles: { [`${MEDIA_ID}.mp4`]: "binary" } },
    ]);
    const result = await acquireXMedia(pinnedUrl, { workDir, mode: "full", deps });

    expect(result.success).toBe(true);
    expect(result.data.entries).toHaveLength(1);
    const probeArgs = spawn.mock.calls[0][1];
    expect(probeArgs).toContain("--no-playlist");
    expect(probeArgs.at(-1)).toBe(pinnedUrl);
  });

  it("link post: the allow-list refuses the delegated URL unfetched; post resolves as a 0-result", async () => {
    const { deps, spawn } = createFixtureDeps(workDir, [
      { success: false, stderr: REFUSAL_STDERR },
    ]);
    const result = await acquireXMedia(STATUS_URL, { workDir, mode: "full", deps });

    // Well-formed 0-video result — the refusal blocks the foreign fetch, it
    // does not error the post; the media pass never runs.
    expect(result.success).toBe(true);
    expect(spawn).toHaveBeenCalledTimes(1);
    const envelope = result.data;
    expect(envelope.entries).toHaveLength(0);
    expect(envelope.metadata.id).toBe(TWID);
    expect(envelope.metadata["source:blockedDelegations"]).toEqual([
      { url: REFUSED_URL, extractor: "refused-before-fetch" },
    ]);

    // Blocked link lands in harvested links (provenance).
    const links = harvestMetadataLinks(envelope.metadata, adapter);
    expect(links.map((link) => link.url)).toContain(REFUSED_URL);
  });

  it("a refusal of an X status URL itself is never treated as a link post", async () => {
    expect(parseDelegationRefusal(REFUSAL_STDERR)).toBe(REFUSED_URL);
    expect(
      parseDelegationRefusal(`ERROR: No suitable extractor found for URL ${STATUS_URL}`),
    ).toBeNull();
    const { deps } = createFixtureDeps(workDir, [
      { success: false, stderr: `ERROR: No suitable extractor found for URL ${STATUS_URL}` },
    ]);
    const result = await acquireXMedia(STATUS_URL, { workDir, mode: "full", deps });
    expect(result.success).toBe(false);
  });

  it("defense-in-depth provenance guard: a foreign info JSON fails the acquisition, never digested", async () => {
    const { deps, spawn } = createFixtureDeps(workDir, [
      {
        addFiles: {
          "dQw4w9WgXcQ.info.json": JSON.stringify({
            extractor: "youtube",
            extractor_key: "Youtube",
            id: "dQw4w9WgXcQ",
            webpage_url: REFUSED_URL,
            formats: [{ format_id: "22" }],
          }),
        },
      },
    ]);
    const result = await acquireXMedia(STATUS_URL, { workDir, mode: "full", deps });

    expect(result.success).toBe(false);
    expect(spawn).toHaveBeenCalledTimes(1);
    expect(result.error).toContain("Provenance violation");
    expect(result.error).toContain(REFUSED_URL);
  });

  it("a successful spawn that wrote no info JSON is a hard failure, never a durable 0-result", async () => {
    const { deps } = createFixtureDeps(workDir, [{}]);
    const result = await acquireXMedia(STATUS_URL, { workDir, mode: "full", deps });
    expect(result.success).toBe(false);
    expect(result.error).toContain("no info JSON");
  });

  it("0 videos, no link: well-formed metadata-only result", async () => {
    const { deps, spawn } = createFixtureDeps(workDir, [
      {
        addFiles: {
          [`${TWID}.info.json`]: twitterInfoJson({ id: TWID, formats: [] }),
        },
      },
    ]);
    const result = await acquireXMedia(STATUS_URL, { workDir, mode: "full", deps });

    expect(result.success).toBe(true);
    expect(spawn).toHaveBeenCalledTimes(1);
    expect(result.data.entries).toHaveLength(0);
    expect(result.data.metadata.title).toBe("Fixture Post");
    expect(result.data.metadata["source:snowflakeAliasing"]).toBeUndefined();
  });

  it("both 0-cases produce a text-only digest with populated provenance (T6 D-A)", async () => {
    const cases = [
      {
        name: "blocked-delegation",
        pass: { success: false, stderr: REFUSAL_STDERR },
        expectedLink: REFUSED_URL,
      },
      {
        name: "no-link",
        pass: { addFiles: { [`${TWID}.info.json`]: twitterInfoJson({ id: TWID, formats: [] }) } },
        expectedLink: "https://example.com/paper",
      },
    ];
    for (const testCase of cases) {
      const { deps } = createFixtureDeps(workDir, [testCase.pass]);
      const result = await acquireXMedia(STATUS_URL, { workDir, mode: "full", deps });
      expect(result.success, testCase.name).toBe(true);

      const sliceDir = await fs.mkdtemp(path.join(os.tmpdir(), "x-zero-case-"));
      try {
        const written = await writeEnvelopeTranscriptArtifacts({
          sliceDir,
          envelope: result.data,
          sourceUrl: STATUS_URL,
          sliceKey: TWID,
        });
        expect(written.entryCount, testCase.name).toBe(0);
        const readme = await fs.readFile(path.join(sliceDir, "README.md"), "utf8");
        expect(readme, testCase.name).toContain(TWID);
        expect(readme, testCase.name).toContain(STATUS_URL);
        const links = harvestMetadataLinks(result.data.metadata, adapter);
        expect(links.map((link) => link.url), testCase.name).toContain(testCase.expectedLink);
      } finally {
        await fs.rm(sliceDir, { recursive: true, force: true });
      }
    }
  });

  // The four named identity fixtures: original post and link post (id === twid)
  // are covered above; quote tweet and retweet are the two DISTINCT aliasing
  // cases — media minted days before the URL's status id, at different scales.
  for (const identityCase of [
    { name: "quote tweet", mediaId: OLD_MEDIA_ID, expectedDeltaMs: 259_200_000 },
    { name: "retweet", mediaId: RETWEET_MEDIA_ID, expectedDeltaMs: 604_800_000 },
  ]) {
    it(`records ${identityCase.name} aliasing in slice metadata`, async () => {
      const { deps } = createFixtureDeps(workDir, [
        {
          addFiles: {
            [`${identityCase.mediaId}.info.json`]: twitterInfoJson({ id: identityCase.mediaId }),
            [`${identityCase.mediaId}.en.vtt`]: CLEAN_VTT,
          },
        },
        { addFiles: { [`${identityCase.mediaId}.mp4`]: "binary" } },
      ]);
      const result = await acquireXMedia(STATUS_URL, { workDir, mode: "full", deps });

      expect(result.success).toBe(true);
      const aliasing = result.data.metadata["source:snowflakeAliasing"];
      expect(aliasing).toMatchObject({
        urlStatusId: TWID,
        resultId: identityCase.mediaId,
        deltaMs: identityCase.expectedDeltaMs,
        aliasSuspected: true,
      });
      // The slice key stays the URL's status id — aliasing never moves the slice.
      expect(adapter.extractSliceKey(STATUS_URL, result.data.metadata)).toBe(TWID);
    });
  }

  it("degraded 429 syndication acquisition fails retryable, never success, before any media pass", async () => {
    const { deps, spawn } = createFixtureDeps(workDir, [
      {
        stderr: `WARNING: [twitter] ${TWID}: ${X_SYNDICATION_DEGRADATION_WARNING}`,
        addFiles: {
          [`${MEDIA_ID}.info.json`]: twitterInfoJson({
            repost_count: undefined,
            comment_count: undefined,
          }),
        },
      },
    ]);
    const result = await acquireXMedia(STATUS_URL, { workDir, mode: "full", deps });

    expect(result.success).toBe(false);
    expect(spawn).toHaveBeenCalledTimes(1);
    expect(result.error).toContain("X acquisition degraded");
    expect(result.error).toContain("retry later");
  });

  it("cleans X word-timing caption tags via a --convert-subs srt pass", async () => {
    const { deps, spawn, files } = createFixtureDeps(workDir, [
      {
        addFiles: {
          [`${MEDIA_ID}.info.json`]: twitterInfoJson(),
          [`${MEDIA_ID}.en.vtt`]: TAGGED_VTT,
        },
      },
      { addFiles: { [`${MEDIA_ID}.en.srt`]: CLEANUP_SRT } },
      { addFiles: { [`${MEDIA_ID}.mp4`]: "binary" } },
    ]);
    const result = await acquireXMedia(STATUS_URL, { workDir, mode: "full", deps });

    expect(result.success).toBe(true);
    expect(spawn).toHaveBeenCalledTimes(3);
    const cleanupArgs = spawn.mock.calls[1][1];
    expect(cleanupArgs).toContain("--convert-subs");
    expect(cleanupArgs[cleanupArgs.indexOf("--convert-subs") + 1]).toBe("srt");
    expect(cleanupArgs).toContain("--skip-download");

    const vttPath = path.join(workDir, `${MEDIA_ID}.en.vtt`);
    expect(result.data.entries[0].captionPaths).toContain(vttPath);
    const rebuilt = files.get(vttPath);
    expect(rebuilt).toContain("WEBVTT");
    expect(rebuilt).toContain("hello from x");
    expect(rebuilt).not.toContain("<X-word-ms");
    expect(result.data.acquireMetrics?.captionCleanup).toBe("converted");
  });

  it("a cleanup pass that SUCCEEDS but produces no .srt fails the acquisition too", async () => {
    const { deps, files } = createFixtureDeps(workDir, [
      {
        addFiles: {
          [`${MEDIA_ID}.info.json`]: twitterInfoJson(),
          [`${MEDIA_ID}.en.vtt`]: TAGGED_VTT,
        },
      },
      // Exit 0, but yt-dlp wrote nothing for the post's media — a silent
      // no-op cleanup must fail loud, never continue with lost captions.
      { addFiles: {} },
    ]);
    const result = await acquireXMedia(STATUS_URL, { workDir, mode: "full", deps });

    expect(result.success).toBe(false);
    expect(result.error).toContain("Caption cleanup failed");
    expect(result.error).toContain("produced no .srt output");
    // The tagged original survives as a backup for the no-output branch too.
    expect(files.get(path.join(workDir, `${MEDIA_ID}.en.vtt.tagged-original`))).toBe(TAGGED_VTT);
  });

  it("a PARTIAL cleanup conversion on a multi-video post fails the acquisition with every backup intact", async () => {
    const { deps, files } = createFixtureDeps(workDir, [
      {
        addFiles: {
          [`${MEDIA_ID}.info.json`]: twitterInfoJson(),
          [`${SECOND_MEDIA_ID}.info.json`]: twitterInfoJson({ id: SECOND_MEDIA_ID }),
          [`${MEDIA_ID}.en.vtt`]: TAGGED_VTT,
          [`${SECOND_MEDIA_ID}.en.vtt`]: TAGGED_VTT,
        },
      },
      // Cleanup exits 0 but converts only the FIRST entry's captions — one
      // matching .srt must never license deleting the other entry's backup.
      { addFiles: { [`${MEDIA_ID}.en.srt`]: CLEANUP_SRT } },
    ]);
    const result = await acquireXMedia(STATUS_URL, { workDir, mode: "full", deps });

    expect(result.success).toBe(false);
    expect(result.error).toContain("Caption cleanup failed");
    expect(result.error).toContain(`${SECOND_MEDIA_ID}.en.vtt`);
    // BOTH tagged originals survive as backups — including the converted entry's.
    expect(files.get(path.join(workDir, `${MEDIA_ID}.en.vtt.tagged-original`))).toBe(TAGGED_VTT);
    expect(files.get(path.join(workDir, `${SECOND_MEDIA_ID}.en.vtt.tagged-original`))).toBe(
      TAGGED_VTT,
    );
  });

  it("a multi-video cleanup that converts EVERY tagged caption succeeds and clears the backups", async () => {
    const { deps, files } = createFixtureDeps(workDir, [
      {
        addFiles: {
          [`${MEDIA_ID}.info.json`]: twitterInfoJson(),
          [`${SECOND_MEDIA_ID}.info.json`]: twitterInfoJson({ id: SECOND_MEDIA_ID }),
          [`${MEDIA_ID}.en.vtt`]: TAGGED_VTT,
          [`${SECOND_MEDIA_ID}.en.vtt`]: TAGGED_VTT,
        },
      },
      {
        addFiles: {
          [`${MEDIA_ID}.en.srt`]: CLEANUP_SRT,
          [`${SECOND_MEDIA_ID}.en.srt`]: CLEANUP_SRT,
        },
      },
    ]);
    const result = await acquireXMedia(STATUS_URL, { workDir, mode: "transcript", deps });

    expect(result.success).toBe(true);
    expect(result.data.acquireMetrics?.captionCleanup).toBe("converted");
    for (const mediaId of [MEDIA_ID, SECOND_MEDIA_ID]) {
      const rebuilt = files.get(path.join(workDir, `${mediaId}.en.vtt`));
      expect(rebuilt).toContain("WEBVTT");
      expect(rebuilt).not.toContain("<X-word-ms");
      expect(files.get(path.join(workDir, `${mediaId}.en.vtt.tagged-original`))).toBeUndefined();
    }
  });

  it("a failed caption cleanup pass fails the acquisition — captions are never silently lost", async () => {
    const { deps, files } = createFixtureDeps(workDir, [
      {
        addFiles: {
          [`${MEDIA_ID}.info.json`]: twitterInfoJson(),
          [`${MEDIA_ID}.en.vtt`]: TAGGED_VTT,
        },
      },
      { success: false, stderr: "ERROR: network" },
    ]);
    const result = await acquireXMedia(STATUS_URL, { workDir, mode: "full", deps });

    expect(result.success).toBe(false);
    expect(result.error).toContain("Caption cleanup failed");
    // The tagged original survives as a backup until cleanup succeeds.
    expect(files.get(path.join(workDir, `${MEDIA_ID}.en.vtt.tagged-original`))).toBe(TAGGED_VTT);
  });
});

describe("harvestLinks blocked-delegation scheme gate", () => {
  it("drops non-http(s) and malformed blocked-delegation URLs (javascript: never harvested)", () => {
    const links = adapter.harvestLinks({
      id: MEDIA_ID,
      title: "Fixture Post",
      description: "",
      "source:blockedDelegations": [
        { url: "javascript:alert(1)", extractor: "refused-before-fetch" },
        { url: "file:///etc/passwd", extractor: "refused-before-fetch" },
        { url: "not a url", extractor: "refused-before-fetch" },
        { url: 42, extractor: "refused-before-fetch" },
        { url: "https://ok.example.com/paper", extractor: "refused-before-fetch" },
      ],
    });
    expect(links.map((link) => link.url)).toEqual(["https://ok.example.com/paper"]);
  });
});

describe("canonicalization reaches every entry path by construction", () => {
  const RAW_URL = `https://mobile.twitter.com/SomeUser/status/${TWID}?s=20`;
  const workDir = path.join("/fixture", "x-canon");

  it("transcript entry: acquireMedia dispatches the adapter's canonical URL", async () => {
    const { deps, spawn } = createFixtureDeps(workDir, [
      { addFiles: { [`${MEDIA_ID}.info.json`]: twitterInfoJson(), [`${MEDIA_ID}.en.vtt`]: CLEAN_VTT } },
    ]);
    const result = await acquireMedia(RAW_URL, { workDir, mode: "transcript" }, deps);
    expect(result.success).toBe(true);
    expect(spawn.mock.calls[0][1].at(-1)).toBe(STATUS_URL);
  });

  it("watch entry: acquireMedia (full) probes and downloads against the canonical URL", async () => {
    const { deps, spawn } = createFixtureDeps(workDir, [
      { addFiles: { [`${MEDIA_ID}.info.json`]: twitterInfoJson(), [`${MEDIA_ID}.en.vtt`]: CLEAN_VTT } },
      { addFiles: { [`${MEDIA_ID}.mp4`]: "binary" } },
    ]);
    const result = await acquireMedia(RAW_URL, { workDir, mode: "full" }, deps);
    expect(result.success).toBe(true);
    for (const call of spawn.mock.calls) {
      expect(call[1].at(-1)).toBe(STATUS_URL);
    }
  });

  it("queue entry: preflight probes the canonical URL and keys the row by status id", async () => {
    const spawn = vi.fn(async () => ({
      success: true,
      code: 0,
      signal: null,
      stdout: `${[TWID, "Fixture Post", "Some User", "@someuser"].join(PREFLIGHT_FIELD_SEP)}\n`,
      stderr: "",
      timedOut: false,
    }));
    const result = await preflightVideo(RAW_URL, { spawn, env: {} });

    expect(result.ok).toBe(true);
    expect(result.videoId).toBe(TWID);
    const args = spawn.mock.calls[0][1];
    expect(args.at(-1)).toBe(STATUS_URL);
    expect(args[args.indexOf("--use-extractors") + 1]).toBe(X_ALLOWED_EXTRACTORS);
    // mediaOptional: a valid 0-video X post survives the queue probe as
    // metadata-only and enqueues (T6 D-A text-only digest downstream).
    expect(args).toContain("--ignore-no-formats-error");
    expect(result.title).toBe("Fixture Post");
  });

  it("queue entry: a non-status X URL is rejected by the adapter gate", async () => {
    const spawn = vi.fn();
    const result = await preflightVideo("https://x.com/someuser", { spawn, env: {} });
    expect(result.ok).toBe(false);
    expect(result.status).toBe("invalid-url");
    expect(spawn).not.toHaveBeenCalled();
  });

  it("queue entry: stderr-derived note/reason are markdown-escaped (no table injection)", async () => {
    const spawn = vi.fn(async () => ({
      success: false,
      code: 1,
      signal: null,
      stdout: "",
      stderr: "ERROR: transient thing | with pipes | in it",
      timedOut: false,
    }));
    const result = await preflightVideo(RAW_URL, { spawn, env: {} });

    expect(result.ok).toBe(false);
    expect(result.status).toBe("transient");
    expect(result.note).toContain("\\|");
    expect(result.reason).toContain("\\|");
    expect(result.note).not.toMatch(/[^\\]\|/);
  });
});
