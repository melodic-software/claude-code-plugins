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

vi.mock("../watching/orchestrate-watching.js", async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    orchestrateWatching: vi.fn(async () => ({
      selectedFrames: [],
      targetMinFrames: 0,
      highVolume: false,
      densificationWindows: [],
      candidateCount: 0,
    })),
  };
});

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

const URL = "https://www.youtube.com/watch?v=7zZy1QTvokM";
const METADATA = {
  id: "7zZy1QTvokM",
  title: "Fixture Video",
  description: "See https://example.com/docs",
  chapters: [],
  heatmap: null,
  comments: [],
};
const VTT = `WEBVTT

00:00:00.000 --> 00:00:02.000
hello world
`;

/** @type {string} */
let workRoot;
/** @type {string} */
let fixtureDir;

/** @param {string} name */
async function writeVtt(name) {
  const vttPath = path.join(fixtureDir, name);
  await fs.writeFile(vttPath, VTT, "utf8");
  return vttPath;
}

/** @param {string} vttPath @param {object} [overrides] */
function mediaEntry(vttPath, overrides = {}) {
  return {
    mediaPath: path.join(fixtureDir, "video.mp4"),
    captionPaths: [vttPath],
    metadataPath: path.join(fixtureDir, "info.json"),
    caption: { path: vttPath, rung: "manual-en", isAutoCaption: false },
    ...overrides,
  };
}

function sliceDir() {
  return path.join(workRoot, ".work", "youtube-watch", "fixture-video-7zZy1QTvokM");
}

async function readWatchJson() {
  const raw = await fs.readFile(path.join(sliceDir(), "run-state", "watch.json"), "utf8");
  return JSON.parse(raw);
}

describe("runWatchCli envelope consumption", () => {
  beforeEach(async () => {
    workRoot = await fs.mkdtemp(path.join(os.tmpdir(), "watch-envelope-root-"));
    fixtureDir = await fs.mkdtemp(path.join(os.tmpdir(), "watch-envelope-fix-"));
    process.env.VIDEO_DIGEST_WORK_ROOT = workRoot;
    captured.stderr.length = 0;
    captured.stdout.length = 0;
    vi.mocked(acquireMedia).mockReset();
    vi.mocked(orchestrateWatching).mockClear();
    vi.mocked(orchestrateWatching).mockResolvedValue({
      selectedFrames: [],
      targetMinFrames: 0,
      highVolume: false,
      densificationWindows: [],
      candidateCount: 0,
    });
  });

  afterEach(async () => {
    delete process.env.VIDEO_DIGEST_WORK_ROOT;
    await fs.rm(workRoot, { recursive: true, force: true });
    await fs.rm(fixtureDir, { recursive: true, force: true });
  });

  it("consumes a 1-entry envelope through the full watch bootstrap", async () => {
    const vttPath = await writeVtt("7zZy1QTvokM.en.vtt");
    vi.mocked(acquireMedia).mockResolvedValue({
      success: true,
      data: createAcquisitionEnvelope({
        entries: [mediaEntry(vttPath)],
        metadata: METADATA,
        workDir: fixtureDir,
      }),
    });

    const code = await runWatchCli(["node", "run-watch.js", URL, "--skip-research"]);
    expect(code).toBe(0);

    const output = JSON.parse(captured.stdout.join(""));
    expect(output.entryCount).toBe(1);
    expect(output.videoSlug).toBe("fixture-video-7zZy1QTvokM");
    expect(output.status).toBe("vision");
    expect(vi.mocked(orchestrateWatching)).toHaveBeenCalledOnce();

    const state = await readWatchJson();
    expect(state.phases.acquire.metrics.entryCount).toBe(1);
    expect(state.phases.transcript.metrics.cueCount).toBe(1);
    expect(state.phases.watching).not.toBeNull();
    expect(state.phases.harvest.metrics.linkCount).toBe(1);
    expect(state.phases.research.metrics.skipped).toBe(true);

    await expect(
      fs.readFile(path.join(sliceDir(), "source", "transcript.txt"), "utf8"),
    ).resolves.toContain("hello world");
  });

  it("consumes a 0-entry envelope as a well-formed text-only slice", async () => {
    vi.mocked(acquireMedia).mockResolvedValue({
      success: true,
      data: createAcquisitionEnvelope({ entries: [], metadata: METADATA, workDir: fixtureDir }),
    });

    const code = await runWatchCli(["node", "run-watch.js", URL]);
    expect(code).toBe(0);

    const output = JSON.parse(captured.stdout.join(""));
    expect(output.entryCount).toBe(0);
    expect(output.textOnly).toBe(true);
    expect(vi.mocked(orchestrateWatching)).not.toHaveBeenCalled();

    const state = await readWatchJson();
    expect(state.phases.acquire.metrics.entryCount).toBe(0);
    expect(state.phases.transcript.metrics.skipped).toBe(true);
    expect(state.phases.watching.metrics.skipped).toBe(true);
    expect(state.phases.vision.metrics.skipped).toBe(true);
    expect(state.phases.harvest).not.toBeNull();

    await expect(
      fs.readFile(path.join(sliceDir(), "source", "harvested-links.json"), "utf8"),
    ).resolves.toContain("https://example.com/docs");
    await expect(fs.readFile(path.join(sliceDir(), "README.md"), "utf8")).resolves.toContain(
      "Fixture Video",
    );
  });

  it("consumes an N-entry envelope: primary watched, arity recorded, every caption transcribed", async () => {
    const first = await writeVtt("first.en.vtt");
    const second = await writeVtt("second.en.vtt");
    vi.mocked(acquireMedia).mockResolvedValue({
      success: true,
      data: createAcquisitionEnvelope({
        entries: [
          mediaEntry(first),
          mediaEntry(second, { mediaPath: path.join(fixtureDir, "video-2.mp4") }),
        ],
        metadata: METADATA,
        workDir: fixtureDir,
      }),
    });

    const code = await runWatchCli(["node", "run-watch.js", URL]);
    expect(code).toBe(0);

    const output = JSON.parse(captured.stdout.join(""));
    expect(output.entryCount).toBe(2);
    expect(vi.mocked(orchestrateWatching)).toHaveBeenCalledOnce();
    expect(vi.mocked(orchestrateWatching).mock.calls[0][0].videoPath).toBe(
      path.join(fixtureDir, "video.mp4"),
    );

    const state = await readWatchJson();
    expect(state.phases.acquire.metrics.entryCount).toBe(2);
    expect(state.phases.transcript.metrics.transcriptCount).toBe(2);

    await expect(
      fs.readFile(path.join(sliceDir(), "source", "transcript.txt"), "utf8"),
    ).resolves.toContain("hello world");
    await expect(
      fs.readFile(path.join(sliceDir(), "source", "transcript-2.txt"), "utf8"),
    ).resolves.toContain("hello world");
  });

  it("pairs watching and transcript.txt on the media-bearing entry when entry 0 is medialess", async () => {
    const captionOnly = await writeVtt("caption-only.en.vtt");
    const withMedia = await writeVtt("with-media.en.vtt");
    vi.mocked(acquireMedia).mockResolvedValue({
      success: true,
      data: createAcquisitionEnvelope({
        entries: [
          mediaEntry(captionOnly, { mediaPath: "" }),
          mediaEntry(withMedia, { mediaPath: path.join(fixtureDir, "video-2.mp4") }),
        ],
        metadata: METADATA,
        workDir: fixtureDir,
      }),
    });

    const code = await runWatchCli(["node", "run-watch.js", URL]);
    expect(code).toBe(0);

    // Watch orchestration covers the media-bearing entry…
    expect(vi.mocked(orchestrateWatching)).toHaveBeenCalledOnce();
    expect(vi.mocked(orchestrateWatching).mock.calls[0][0].videoPath).toBe(
      path.join(fixtureDir, "video-2.mp4"),
    );

    // …and transcript.txt names THAT entry's transcript, so downstream
    // consumers that assume transcript.txt is THE transcript stay correct.
    const state = await readWatchJson();
    expect(state.phases.acquire.metrics.entryCount).toBe(2);
    await expect(
      fs.readFile(path.join(sliceDir(), "source", "transcript.txt"), "utf8"),
    ).resolves.toContain("hello world");
    await expect(
      fs.readFile(path.join(sliceDir(), "source", "transcript-1.txt"), "utf8"),
    ).resolves.toContain("hello world");
    await expect(
      fs.access(path.join(sliceDir(), "source", "transcript-2.txt")),
    ).rejects.toThrow();
  });
});
