import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { acquireYouTubeMedia } from "./acquire.js";

vi.mock("./acquire-retry-policy.js", async (importOriginal) => ({
  ...(await importOriginal()),
  computeAcquireBackoffMs: () => 0,
}));

// Shape of probe 5 (#6812): "Me at the zoo" has manual `en` and `de` tracks; the
// translated `en-de` track 429s after `en.vtt` is already on disk.
const VIDEO_ID = "jNQXAC9IVRw";
const URL = `https://www.youtube.com/watch?v=${VIDEO_ID}`;
const TRANSLATED_429 =
  "ERROR: Unable to download video subtitles for 'en-de': HTTP Error 429: Too Many Requests";
const INFO_JSON = JSON.stringify({
  id: VIDEO_ID,
  title: "Me at the zoo",
  subtitles: { en: [], de: [] },
  automatic_captions: {},
});
const NO_THROTTLE = {
  withThrottle: (/** @type {() => Promise<unknown>} */ fn) => fn(),
  sleep: async () => {},
};

/** @param {string} stderr */
const failed = (stderr) => ({
  success: false,
  code: 1,
  signal: null,
  stdout: "",
  stderr,
  timedOut: false,
});
const succeeded = { success: true, code: 0, signal: null, stdout: "", stderr: "", timedOut: false };

/** @type {string} */
let workDir;

beforeEach(async () => {
  workDir = await fs.mkdtemp(path.join(os.tmpdir(), "vd-partial-captions-"));
});

afterEach(async () => {
  await fs.rm(workDir, { recursive: true, force: true });
});

/** @param {Record<string, string>} files */
async function writeFixture(files) {
  for (const [name, content] of Object.entries(files)) {
    await fs.writeFile(path.join(workDir, name), content, "utf8");
  }
}

const EN_VTT = "WEBVTT\nKind: captions\nLanguage: en\n\n00:00:01.200 --> 00:00:03.360\nAll right\n";

describe("acquireYouTubeMedia keeps a caption already on disk when another track fails", () => {
  it("full mode: a 429 on a translated track does not discard the downloaded en.vtt", async () => {
    await writeFixture({ [`${VIDEO_ID}.mp4`]: "", [`${VIDEO_ID}.info.json`]: INFO_JSON });
    const result = await acquireYouTubeMedia(
      URL,
      { workDir, mode: "full", videoId: VIDEO_ID },
      {
        ...NO_THROTTLE,
        spawn: async (_cmd, args) => {
          if (!args.includes("--skip-download")) return succeeded;
          // yt-dlp writes en.vtt, then aborts its subtitle loop on the en-de 429.
          await writeFixture({ [`${VIDEO_ID}.en.vtt`]: EN_VTT });
          return failed(`WARNING: something\n${TRANSLATED_429}`);
        },
      },
    );

    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(path.basename(result.data.caption.path)).toBe(`${VIDEO_ID}.en.vtt`);
    expect(result.data.caption.rung).toBe("manual-en");
    expect(result.data.caption.provenanceNote).toContain(TRANSLATED_429);
    expect(result.data.caption.provenanceNote).not.toContain("WARNING");
    expect(result.data.acquireMetrics?.captionDownloadErrors).toEqual([TRANSLATED_429]);
  });

  it("transcript mode: a non-zero exit with a usable caption and info.json still succeeds", async () => {
    const result = await acquireYouTubeMedia(
      URL,
      { workDir, mode: "transcript", videoId: VIDEO_ID },
      {
        ...NO_THROTTLE,
        spawn: async () => {
          await writeFixture({
            [`${VIDEO_ID}.info.json`]: INFO_JSON,
            [`${VIDEO_ID}.en.vtt`]: EN_VTT,
          });
          return failed(TRANSLATED_429);
        },
      },
    );

    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(path.basename(result.data.caption.path)).toBe(`${VIDEO_ID}.en.vtt`);
    expect(result.data.caption.provenanceNote).toContain("HTTP Error 429");
  });

  it("transcript mode: a non-zero exit with no caption on disk still reports the yt-dlp error", async () => {
    const result = await acquireYouTubeMedia(
      URL,
      { workDir, mode: "transcript", videoId: VIDEO_ID },
      {
        ...NO_THROTTLE,
        spawn: async () => {
          await writeFixture({ [`${VIDEO_ID}.info.json`]: INFO_JSON });
          return failed(
            "ERROR: Unable to download video subtitles for 'en': HTTP Error 429: Too Many Requests",
          );
        },
      },
    );

    expect(result.success).toBe(false);
    expect(result.error).toContain("HTTP Error 429");
    expect(result.error).not.toContain("ladder exhausted");
  });

  it("requests translated tracks only on the retry after the ladder finds no English", async () => {
    /** @type {string[]} */
    const captionExtractorArgs = [];
    const result = await acquireYouTubeMedia(
      URL,
      {
        workDir,
        mode: "full",
        videoId: VIDEO_ID,
        source: { extractorArgs: "youtube:comment_sort=top;skip=translated_subs" },
      },
      {
        ...NO_THROTTLE,
        spawn: async (_cmd, args) => {
          if (!args.includes("--skip-download")) {
            await writeFixture({
              [`${VIDEO_ID}.mp4`]: "",
              [`${VIDEO_ID}.info.json`]: JSON.stringify({ id: VIDEO_ID, subtitles: { de: [] } }),
            });
            return succeeded;
          }
          const value = args[args.indexOf("--extractor-args") + 1];
          captionExtractorArgs.push(value);
          if (!value.includes("skip=translated_subs")) {
            // Only a video's non-English manual track exists; its English translation is the rung left.
            await writeFixture({ [`${VIDEO_ID}.en-de.vtt`]: EN_VTT });
          }
          return succeeded;
        },
      },
    );

    expect(captionExtractorArgs).toEqual([
      "youtube:comment_sort=top;skip=translated_subs",
      "youtube:comment_sort=top",
    ]);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(path.basename(result.data.caption.path)).toBe(`${VIDEO_ID}.en-de.vtt`);
    expect(result.data.caption.rung).toBe("auto-translate-en");
  });
});
