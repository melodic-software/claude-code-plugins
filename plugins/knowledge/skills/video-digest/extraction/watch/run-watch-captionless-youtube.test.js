/**
 * CLI-level proof for a caption-less YouTube watch (caption ladder exhausted,
 * video downloaded): the run exits 0, selects `asr` when the capability is
 * detected, and otherwise completes with a recorded `transcriptDegradation`.
 * `detectAsrCapability` and `runAsrTranscription` are stubbed; no real Whisper
 * model runs.
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { parseVideoMetadata } from "../acquisition/video-metadata.js";
import { createAcquisitionEnvelope } from "../adapters/adapter-contract.js";
import { acquireMedia } from "../adapters/registry.js";
import { runWatchCli } from "./run-watch.js";

const captured = vi.hoisted(() => ({
  stderr: /** @type {string[]} */ ([]),
  stdout: /** @type {string[]} */ ([]),
}));

vi.mock("@melodic/video-digestion/shared/terminal", () => ({
  writeStderr: (/** @type {unknown} */ text) => {
    captured.stderr.push(String(text));
  },
  writeStdout: (/** @type {unknown} */ text) => {
    captured.stdout.push(String(text));
  },
}));

vi.mock("../adapters/registry.js", async (importOriginal) => {
  const actual = await importOriginal();
  return { ...actual, acquireMedia: vi.fn() };
});

vi.mock("../transcript/asr-transcribe.js", async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    detectAsrCapability: vi.fn(),
    runAsrTranscription: vi.fn(),
  };
});

vi.mock("../watching/orchestrate-watching.js", () => ({
  orchestrateWatching: vi.fn(async () => ({
    selectedFrames: [],
    targetMinFrames: 0,
    highVolume: false,
    densificationWindows: [],
    candidateCount: 0,
  })),
}));

vi.mock("../watching/write-watching-manifest.js", () => ({
  writeWatchingManifest: vi.fn(async () => ({
    selectionPath: "",
    coveragePlanPath: "",
    frameCount: 0,
    contactSheetCount: 0,
  })),
}));

vi.mock("./post-bootstrap-slice.js", () => ({
  postBootstrapSlice: vi.fn(() => null),
}));

import { detectAsrCapability, runAsrTranscription } from "../transcript/asr-transcribe.js";

const VIDEO_ID = "7zZy1QTvokM";
const YOUTUBE_URL = `https://www.youtube.com/watch?v=${VIDEO_ID}`;

/** @type {string} */
let workRoot;
/** @type {string} */
let fixtureDir;
let previousTmpdir;

/** Mock acquisition as the YouTube adapter returns it for a caption-less full run. */
async function mockCaptionlessAcquisition() {
  const mediaPath = path.join(fixtureDir, `${VIDEO_ID}.mp4`);
  await fs.writeFile(mediaPath, "binary", "utf8");
  vi.mocked(acquireMedia).mockResolvedValue({
    success: true,
    data: createAcquisitionEnvelope({
      entries: [
        {
          mediaPath,
          captionPaths: [],
          metadataPath: path.join(fixtureDir, `${VIDEO_ID}.info.json`),
          caption: null,
        },
      ],
      metadata: parseVideoMetadata({ id: VIDEO_ID, title: "Caption-less Fixture" }),
      workDir: fixtureDir,
    }),
  });
}

describe("run-watch caption-less YouTube video (CLI-level)", () => {
  beforeEach(async () => {
    workRoot = await fs.mkdtemp(path.join(os.tmpdir(), "watch-captionless-root-"));
    fixtureDir = await fs.mkdtemp(path.join(os.tmpdir(), "watch-captionless-fix-"));
    previousTmpdir = process.env.TMPDIR;
    process.env.TMPDIR = fixtureDir;
    process.env.YOUTUBE_WORK_ROOT = workRoot;
    captured.stderr.length = 0;
    captured.stdout.length = 0;
    vi.mocked(acquireMedia).mockReset();
    vi.mocked(detectAsrCapability).mockReset();
    vi.mocked(runAsrTranscription).mockReset();
  });

  afterEach(async () => {
    if (previousTmpdir === undefined) delete process.env.TMPDIR;
    else process.env.TMPDIR = previousTmpdir;
    delete process.env.YOUTUBE_WORK_ROOT;
    await fs.rm(workRoot, { recursive: true, force: true });
    await fs.rm(fixtureDir, { recursive: true, force: true });
  });

  it("selects asr when the capability is detected", async () => {
    await mockCaptionlessAcquisition();
    vi.mocked(detectAsrCapability).mockResolvedValue({ available: true, python: "python3" });
    vi.mocked(runAsrTranscription).mockResolvedValue({
      success: true,
      cues: [{ startSec: 0, endSec: 2, text: "spoken words" }],
    });

    const code = await runWatchCli(["node", "run-watch.js", YOUTUBE_URL, "--skip-research"]);
    expect(code).toBe(0);

    const output = JSON.parse(captured.stdout.join(""));
    expect(output.transcriptStrategy).toBe("asr");
    expect(output.transcriptDegradation ?? null).toBeNull();
    expect(vi.mocked(runAsrTranscription)).toHaveBeenCalledOnce();
  });

  it("completes with a recorded transcriptDegradation when asr is absent", async () => {
    await mockCaptionlessAcquisition();
    vi.mocked(detectAsrCapability).mockResolvedValue({ available: false });

    const code = await runWatchCli(["node", "run-watch.js", YOUTUBE_URL, "--skip-research"]);
    expect(code).toBe(0);

    const output = JSON.parse(captured.stdout.join(""));
    expect(output.transcriptStrategy).toBeNull();
    expect(output.transcriptDegradation).toContain("faster-whisper");
    expect(vi.mocked(runAsrTranscription)).not.toHaveBeenCalled();
  });
});
