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

vi.mock("./temp-space-check.js", () => ({
  checkTempSpace: vi.fn(async () => ({ state: "enough", message: "" })),
}));

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
      skipCaptionWait: true,
    });
    // ASR ran on the ranged media; watching gets those cues back in media time.
    expect(vi.mocked(orchestrateWatching).mock.calls[0][0].cues).toEqual([
      { startSec: 0, endSec: 4, text: "first ranged cue" },
      { startSec: 4, endSec: 9, text: "second ranged cue" },
    ]);

    const { sliceDir, videoSlug } = JSON.parse(captured.stdout.join(""));
    // The range is in the slice key, so another range of this video gets its own slice.
    expect(videoSlug).toMatch(new RegExp(`-${VIDEO_ID}-r3600-4800$`));
    expect(path.basename(sliceDir)).toBe(videoSlug);
    const state = JSON.parse(await fs.readFile(watchStatePath(sliceDir), "utf8"));
    expect(state.videoId).toBe(VIDEO_ID);
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

  it("skips the caption wait for a captionless live-derived video and records the path", async () => {
    const mediaPath = path.join(fixtureDir, `${VIDEO_ID}.mp4`);
    const infoPath = path.join(fixtureDir, `${VIDEO_ID}.info.json`);
    await fs.writeFile(mediaPath, "binary", "utf8");
    // The stream ended an hour ago, so its caption wait is still open.
    const info = {
      id: VIDEO_ID,
      title: "Conference Stream",
      duration: 2 * 3600,
      live_status: "was_live",
      release_timestamp: Math.floor(Date.now() / 1000) - 3 * 3600,
    };
    const actual = await vi.importActual("../adapters/registry.js");
    vi.mocked(acquireMedia).mockImplementation((url, options) =>
      /** @type {typeof acquireMedia} */ (actual.acquireMedia)(url, options, {
        withThrottle: (/** @type {() => Promise<unknown>} */ fn) => fn(),
        sleep: async () => {},
        spawn: async () => ({
          success: true,
          code: 0,
          signal: null,
          stdout: "",
          stderr: "",
          timedOut: false,
        }),
        listFiles: async () => [mediaPath, infoPath],
        readFile: async () => JSON.stringify(info),
      }),
    );

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

    const output = JSON.parse(captured.stdout.join(""));
    expect(output.captionWait).toContain("caption wait skipped on a ranged run");
    const state = JSON.parse(await fs.readFile(watchStatePath(output.sliceDir), "utf8"));
    expect(state.phases.acquire.metrics.captionWait).toContain(
      "caption wait skipped on a ranged run with no captions (live_status was_live",
    );
    expect(state.phases.transcript.metrics.transcriptStrategy).toBe("asr");
    const transcript = await fs.readFile(
      path.join(output.sliceDir, "source", "transcript.txt"),
      "utf8",
    );
    expect(transcript).toMatch(/^\[60:00\] first ranged cue/);
  });

  it("keeps the caption wait under an explicit caption strategy, which never falls to ASR", async () => {
    vi.mocked(acquireMedia).mockResolvedValue({ success: false, error: "stop after acquire" });

    await runWatchCli([
      "node",
      "run-watch.js",
      YOUTUBE_URL,
      "--transcript-strategy",
      "captions",
      "--from",
      "1:00:00",
    ]);

    expect(vi.mocked(acquireMedia).mock.calls[0][1]).toMatchObject({ skipCaptionWait: false });
  });

  it("cuts caption cues to the range, in full-video time", async () => {
    const mediaPath = path.join(fixtureDir, `${VIDEO_ID}.mp4`);
    const captionPath = path.join(fixtureDir, `${VIDEO_ID}.en.vtt`);
    await fs.writeFile(mediaPath, "binary", "utf8");
    await fs.writeFile(
      captionPath,
      [
        "WEBVTT",
        "",
        "00:59:50.000 --> 00:59:55.000",
        "before the range",
        "",
        "01:00:05.000 --> 01:00:10.000",
        "inside the range",
        "",
        "01:25:00.000 --> 01:25:05.000",
        "after the range",
        "",
      ].join("\n"),
      "utf8",
    );
    vi.mocked(acquireMedia).mockResolvedValue({
      success: true,
      data: createAcquisitionEnvelope({
        entries: [
          {
            mediaPath,
            captionPaths: [captionPath],
            metadataPath: path.join(fixtureDir, `${VIDEO_ID}.info.json`),
            caption: { path: captionPath, rung: "manual-en", isAutoCaption: false },
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

    const { sliceDir } = JSON.parse(captured.stdout.join(""));
    const transcript = await fs.readFile(path.join(sliceDir, "source", "transcript.txt"), "utf8");
    expect(transcript).toMatch(/^\[60:05\] inside the range/);
    expect(transcript).not.toContain("before the range");
    expect(transcript).not.toContain("after the range");
    expect(vi.mocked(orchestrateWatching).mock.calls[0][0].cues).toEqual([
      { startSec: 5, endSec: 10, text: "inside the range" },
    ]);
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
