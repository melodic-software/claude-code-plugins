/**
 * CLI-level proof of a ranged watch (`--from` / `--to`): acquisition gets the range,
 * watching runs in media time, and the slice stores full-video time with the range
 * and the offset's error recorded. ASR and watching are stubbed.
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { parseVideoMetadata } from "../acquisition/video-metadata.js";
import { createAcquisitionEnvelope } from "../adapters/adapter-contract.js";
import { acquireMedia } from "../adapters/registry.js";
import { runWatchCli } from "./run-watch.js";
import { watchStatePath } from "./watch-state.js";

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
        { startSec: 0, endSec: 4, text: "first ranged cue" },
        { startSec: 4, endSec: 9, text: "second ranged cue" },
      ],
    })),
  };
});

const frame = {
  path: "/tmp/frames/anchor_00010000_0001.png",
  file: "anchor_00010000_0001.png",
  timestampSec: 10,
  timestampSource: "anchor",
  timestampErrorSec: 0.5,
  priorityScore: 1,
  textDense: false,
  readResolution: "1280x720",
};

vi.mock("../watching/orchestrate-watching.js", () => ({
  orchestrateWatching: vi.fn(async () => ({
    sceneFrames: [frame],
    uniqueFrames: [frame],
    selectedFrames: [frame],
    densificationWindows: [{ startSec: 5, endSec: 20, densityMultiplier: 3, reason: "demo" }],
    contactSheets: [],
    interleavedTimeline: [
      { kind: "transcript", timestampSec: 0, transcriptText: "first ranged cue" },
      { kind: "frame", timestampSec: 10, frame },
    ],
    targetMinFrames: 1,
    highVolume: false,
    overCap: false,
    candidateCount: 1,
    durationSec: 1204.5,
    probedDurationSec: 1204.5,
  })),
}));

vi.mock("./post-bootstrap-slice.js", () => ({
  postBootstrapSlice: vi.fn(() => null),
}));

import { orchestrateWatching } from "../watching/orchestrate-watching.js";

const VIDEO_ID = "7zZy1QTvokM";
const YOUTUBE_URL = `https://www.youtube.com/watch?v=${VIDEO_ID}`;

/** @type {string} */
let workRoot;
/** @type {string} */
let fixtureDir;
let previousTmpdir;

describe("run-watch time range (CLI-level)", () => {
  beforeEach(async () => {
    workRoot = await fs.mkdtemp(path.join(os.tmpdir(), "watch-range-root-"));
    fixtureDir = await fs.mkdtemp(path.join(os.tmpdir(), "watch-range-fix-"));
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

  it("acquires the range and records every stamp in full-video time", async () => {
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
        metadata: parseVideoMetadata({ id: VIDEO_ID, title: "Sample Talk", duration: 32300 }),
        workDir: fixtureDir,
      }),
    });

    const code = await runWatchCli([
      "node",
      "run-watch.js",
      YOUTUBE_URL,
      "--skip-research",
      "--from",
      "1:00:00",
      "--to",
      "1:20:00",
    ]);
    expect(code).toBe(0);

    expect(vi.mocked(acquireMedia).mock.calls[0][1]).toMatchObject({
      timeRange: { fromSec: 3600, toSec: 4800 },
    });
    // ASR ran on the ranged media; watching gets those cues back in media time.
    expect(vi.mocked(orchestrateWatching).mock.calls[0][0].cues).toEqual([
      { startSec: 0, endSec: 4, text: "first ranged cue" },
      { startSec: 4, endSec: 9, text: "second ranged cue" },
    ]);

    const { sliceDir } = JSON.parse(captured.stdout.join(""));
    const state = JSON.parse(await fs.readFile(watchStatePath(sliceDir), "utf8"));
    expect(state.timeRange).toEqual({
      fromSec: 3600,
      toSec: 4800,
      offsetSec: 3600,
      cut: "keyframe",
      offsetErrorSec: 4.5,
    });
    expect(state.durationMismatch).toBeUndefined();

    const readme = await fs.readFile(path.join(sliceDir, "README.md"), "utf8");
    expect(readme).toContain("Range: 1:00:00 to 1:20:00");

    const transcript = await fs.readFile(path.join(sliceDir, "source", "transcript.txt"), "utf8");
    expect(transcript).toMatch(/^\[60:00\] first ranged cue/);

    const selection = JSON.parse(
      await fs.readFile(path.join(sliceDir, "key-frames", "selection.json"), "utf8"),
    );
    expect(selection.selectedFrames[0]).toMatchObject({ timestampSec: 3610, timestampErrorSec: 5 });
    expect(selection.densificationWindows[0]).toMatchObject({ startSec: 3605, endSec: 3620 });
    expect(selection.interleavedTimeline.map((entry) => entry.timestampSec)).toEqual([3600, 3610]);
  });

  it("refuses a range for a source whose adapter cannot acquire one", async () => {
    const code = await runWatchCli([
      "node",
      "run-watch.js",
      "https://x.com/someuser/status/1720000000000000000",
      "--from",
      "0:10",
    ]);
    expect(code).toBe(1);
    expect(captured.stderr.join("\n")).toContain("--from/--to are not supported for x sources");
    expect(vi.mocked(acquireMedia)).not.toHaveBeenCalled();
  });

  it("rejects a range whose end is not after its start", async () => {
    const code = await runWatchCli([
      "node",
      "run-watch.js",
      YOUTUBE_URL,
      "--from",
      "1:00:00",
      "--to",
      "59:00",
    ]);
    expect(code).toBe(1);
    expect(vi.mocked(acquireMedia)).not.toHaveBeenCalled();
  });
});
