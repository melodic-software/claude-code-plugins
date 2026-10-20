/**
 * CLI-level proof that a caption-less run whose transcript came from the
 * optional ASR rung feeds those ASR cues to watching, so frame densification
 * has cues to work from. ASR detection and transcription are stubbed: no real
 * Whisper model runs.
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

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
    detectAsrCapability: vi.fn(async () => ({ available: true, python: "python3" })),
    runAsrTranscription: vi.fn(async () => ({
      success: true,
      cues: [
        { startSec: 0, endSec: 4, text: "first asr cue" },
        { startSec: 4, endSec: 9, text: "second asr cue" },
      ],
    })),
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

import { orchestrateWatching } from "../watching/orchestrate-watching.js";

const TWID = "1720000000000000000";
const X_URL = `https://x.com/someuser/status/${TWID}`;
const MEDIA_ID = String(BigInt(TWID) - (60_000n << 22n));

/** @type {string} */
let workRoot;
/** @type {string} */
let fixtureDir;
let previousTmpdir;

describe("run-watch ASR cues reach watching (CLI-level)", () => {
  beforeEach(async () => {
    workRoot = await fs.mkdtemp(path.join(os.tmpdir(), "watch-asr-cues-root-"));
    fixtureDir = await fs.mkdtemp(path.join(os.tmpdir(), "watch-asr-cues-fix-"));
    previousTmpdir = process.env.TMPDIR;
    process.env.TMPDIR = fixtureDir;
    process.env.VIDEO_DIGEST_WORK_ROOT = workRoot;
    captured.stderr.length = 0;
    captured.stdout.length = 0;
    vi.mocked(acquireMedia).mockReset();
    vi.mocked(orchestrateWatching).mockClear();
  });

  afterEach(async () => {
    if (previousTmpdir === undefined) delete process.env.TMPDIR;
    else process.env.TMPDIR = previousTmpdir;
    delete process.env.VIDEO_DIGEST_WORK_ROOT;
    await fs.rm(workRoot, { recursive: true, force: true });
    await fs.rm(fixtureDir, { recursive: true, force: true });
  });

  it("passes the ASR cues to orchestrateWatching when there is no caption VTT", async () => {
    const mediaPath = path.join(fixtureDir, `${MEDIA_ID}.mp4`);
    await fs.writeFile(mediaPath, "binary", "utf8");
    vi.mocked(acquireMedia).mockResolvedValue({
      success: true,
      data: createAcquisitionEnvelope({
        entries: [
          { mediaPath, captionPaths: [], metadataPath: path.join(fixtureDir, "info.json"), caption: null },
        ],
        metadata: {
          id: MEDIA_ID,
          title: "Fixture Post",
          description: "",
          "source:displayId": TWID,
        },
        workDir: fixtureDir,
      }),
    });

    const code = await runWatchCli(["node", "run-watch.js", X_URL, "--skip-research"]);
    expect(code).toBe(0);

    expect(vi.mocked(orchestrateWatching)).toHaveBeenCalledOnce();
    const { cues } = vi.mocked(orchestrateWatching).mock.calls[0][0];
    expect(cues).toEqual([
      { startSec: 0, endSec: 4, text: "first asr cue" },
      { startSec: 4, endSec: 9, text: "second asr cue" },
    ]);
  });
});
