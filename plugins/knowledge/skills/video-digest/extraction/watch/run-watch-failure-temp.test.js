/**
 * A watch that fails before its slice records `tempSession` in watch.json removes
 * the temp dirs it made: no slice points at them, so nothing would ever clean them.
 * Once watch.json records them, `--recover` depends on them and they stay.
 * os.tmpdir() is pointed at a sandbox dir (TMPDIR on POSIX, TEMP/TMP on Windows).
 */

import { existsSync } from "node:fs";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { createAcquisitionEnvelope, UnsupportedSourceError } from "../adapters/adapter-contract.js";
import { acquireMedia } from "../adapters/registry.js";
import { orchestrateWatching } from "../watching/orchestrate-watching.js";
import { runWatchCli } from "./run-watch.js";
import { checkTempSpace } from "./temp-space-check.js";

vi.mock("@melodic/video-digestion/shared/terminal", () => ({
  writeStderr: () => {},
  writeStdout: () => {},
}));

vi.mock("../adapters/registry.js", async (importOriginal) => {
  const actual = await importOriginal();
  return { ...actual, acquireMedia: vi.fn() };
});

vi.mock("./temp-space-check.js", () => ({ checkTempSpace: vi.fn() }));

vi.mock("../transcript/asr-transcribe.js", async (importOriginal) => {
  const actual = await importOriginal();
  return { ...actual, detectAsrCapability: vi.fn(async () => ({ available: false })) };
});

vi.mock("../watching/orchestrate-watching.js", () => ({ orchestrateWatching: vi.fn() }));

const URL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ";
const TEMP_PREFIXES = ["video-extraction-", "video-frames-", "video-sheets-"];
const ENV_KEYS = ["TMPDIR", "TEMP", "TMP"];

/** @type {string} */
let sandbox;
/** @type {string} */
let fakeTmp;
/** @type {Record<string, string|undefined>} */
let savedEnv;

async function watchTempDirs() {
  const names = await fs.readdir(fakeTmp);
  return names.filter((name) => TEMP_PREFIXES.some((prefix) => name.startsWith(prefix))).sort();
}

function acquireWritingMedia(outcome) {
  return async (_url, { workDir }) => {
    await fs.writeFile(path.join(workDir, "dQw4w9WgXcQ.mp4"), "binary");
    await fs.writeFile(path.join(workDir, "dQw4w9WgXcQ.info.json"), "{}");
    return outcome(workDir);
  };
}

describe("run-watch temp dirs on a failed watch", () => {
  beforeEach(async () => {
    sandbox = await fs.mkdtemp(path.join(os.tmpdir(), "watch-failure-temp-"));
    fakeTmp = path.join(sandbox, "tmp");
    await fs.mkdir(fakeTmp);
    savedEnv = Object.fromEntries(ENV_KEYS.map((key) => [key, process.env[key]]));
    for (const key of ENV_KEYS) process.env[key] = fakeTmp;
    process.env.YOUTUBE_WORK_ROOT = path.join(sandbox, "work");
    vi.mocked(acquireMedia).mockReset();
    vi.mocked(orchestrateWatching).mockReset();
    vi.mocked(checkTempSpace).mockResolvedValue({ state: "enough", message: "" });
  });

  afterEach(async () => {
    for (const [key, value] of Object.entries(savedEnv)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    delete process.env.YOUTUBE_WORK_ROOT;
    await fs.rm(sandbox, { recursive: true, force: true });
  });

  it("removes all three dirs, downloaded media included, when acquisition reports failure", async () => {
    vi.mocked(acquireMedia).mockImplementation(
      acquireWritingMedia(() => ({ success: false, error: "HTTP Error 429: Too Many Requests" })),
    );

    expect(await runWatchCli(["node", "run-watch.js", URL])).toBe(1);
    expect(vi.mocked(acquireMedia)).toHaveBeenCalledOnce();
    expect(await watchTempDirs()).toEqual([]);
  });

  it("exits 1 before any download, removing the dirs, when temp space is short", async () => {
    vi.mocked(checkTempSpace).mockResolvedValue({ state: "short", message: "ERROR: short" });

    expect(await runWatchCli(["node", "run-watch.js", URL])).toBe(1);
    expect(vi.mocked(checkTempSpace)).toHaveBeenCalledWith(
      expect.objectContaining({ tempDir: os.tmpdir(), timeRange: null }),
    );
    expect(vi.mocked(acquireMedia)).not.toHaveBeenCalled();
    expect(await watchTempDirs()).toEqual([]);
  });

  it("goes on to acquire when the media size is unknown", async () => {
    vi.mocked(checkTempSpace).mockResolvedValue({ state: "unknown", message: "WARN: unknown" });
    vi.mocked(acquireMedia).mockResolvedValue({ success: false, error: "stop after the check" });

    expect(await runWatchCli(["node", "run-watch.js", URL])).toBe(1);
    expect(vi.mocked(acquireMedia)).toHaveBeenCalledOnce();
  });

  it("removes all three dirs when acquisition rejects the URL as unsupported", async () => {
    vi.mocked(acquireMedia).mockRejectedValue(new UnsupportedSourceError(URL, ["youtube.com"]));

    expect(await runWatchCli(["node", "run-watch.js", URL])).toBe(1);
    expect(await watchTempDirs()).toEqual([]);
  });

  it("removes all three dirs and still rethrows when acquisition throws", async () => {
    vi.mocked(acquireMedia).mockRejectedValue(new Error("yt-dlp crashed"));

    await expect(runWatchCli(["node", "run-watch.js", URL])).rejects.toThrow("yt-dlp crashed");
    expect(await watchTempDirs()).toEqual([]);
  });

  it("keeps the dirs once watch.json records them, so --recover can resume", async () => {
    vi.mocked(acquireMedia).mockImplementation(
      acquireWritingMedia((workDir) => ({
        success: true,
        data: createAcquisitionEnvelope({
          entries: [
            {
              mediaPath: path.join(workDir, "dQw4w9WgXcQ.mp4"),
              captionPaths: [],
              metadataPath: path.join(workDir, "dQw4w9WgXcQ.info.json"),
              caption: null,
            },
          ],
          metadata: {
            id: "dQw4w9WgXcQ",
            title: "Fixture Talk",
            description: "",
            chapters: [],
            comments: [],
          },
          workDir,
        }),
      })),
    );
    vi.mocked(orchestrateWatching).mockRejectedValue(new Error("ffmpeg interrupted"));

    await expect(runWatchCli(["node", "run-watch.js", URL])).rejects.toThrow("ffmpeg interrupted");
    const remaining = await watchTempDirs();
    expect(remaining).toHaveLength(3);
    const workDir = remaining.find((name) => name.startsWith("video-extraction-"));
    expect(existsSync(path.join(fakeTmp, String(workDir), "dQw4w9WgXcQ.mp4"))).toBe(true);
  });
});
