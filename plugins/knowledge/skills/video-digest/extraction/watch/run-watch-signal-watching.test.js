/**
 * A signal that lands while frame extraction runs stops the watch before it writes
 * anything from the killed work: no watching manifest, and the run reports failure.
 * The signal handler is invoked in-process, with process.exit stubbed.
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { createAcquisitionEnvelope } from "../adapters/adapter-contract.js";
import { acquireMedia } from "../adapters/registry.js";
import { orchestrateWatching } from "../watching/orchestrate-watching.js";
import { writeWatchingManifest } from "../watching/write-watching-manifest.js";
import { runWatchCli } from "./run-watch.js";

vi.mock("@melodic/video-digestion/shared/terminal", () => ({
  writeStderr: () => {},
  writeStdout: () => {},
}));

vi.mock("../adapters/registry.js", async (importOriginal) => {
  const actual = await importOriginal();
  return { ...actual, acquireMedia: vi.fn() };
});

vi.mock("../transcript/asr-transcribe.js", async (importOriginal) => {
  const actual = await importOriginal();
  return { ...actual, detectAsrCapability: vi.fn(async () => ({ available: false })) };
});

vi.mock("../watching/orchestrate-watching.js", () => ({ orchestrateWatching: vi.fn() }));

vi.mock("../watching/write-watching-manifest.js", () => ({
  writeWatchingManifest: vi.fn(async () => ({
    selectionPath: "selection.json",
    coveragePlanPath: "coverage-plan.json",
    frameCount: 0,
    contactSheetCount: 0,
  })),
}));

const URL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ";
const ENV_KEYS = ["TMPDIR", "TEMP", "TMP"];

/** @type {string} */
let sandbox;
/** @type {Record<string, string|undefined>} */
let savedEnv;

describe("run-watch interrupted during frame extraction", () => {
  beforeEach(async () => {
    sandbox = await fs.mkdtemp(path.join(os.tmpdir(), "watch-signal-watching-"));
    const fakeTmp = path.join(sandbox, "tmp");
    await fs.mkdir(fakeTmp);
    savedEnv = Object.fromEntries(ENV_KEYS.map((key) => [key, process.env[key]]));
    for (const key of ENV_KEYS) process.env[key] = fakeTmp;
    process.env.YOUTUBE_WORK_ROOT = path.join(sandbox, "work");
    vi.mocked(acquireMedia).mockReset();
    vi.mocked(orchestrateWatching).mockReset();
    vi.mocked(writeWatchingManifest).mockClear();
    vi.spyOn(process, "exit").mockImplementation(/** @type {any} */ (() => undefined));
  });

  afterEach(async () => {
    vi.restoreAllMocks();
    for (const [key, value] of Object.entries(savedEnv)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    delete process.env.YOUTUBE_WORK_ROOT;
    await fs.rm(sandbox, { recursive: true, force: true });
  });

  it("writes no watching manifest and returns 1 when SIGTERM lands mid-extraction", async () => {
    vi.mocked(acquireMedia).mockImplementation(async (_url, { workDir }) => {
      const mediaPath = path.join(workDir, "dQw4w9WgXcQ.mp4");
      const metadataPath = path.join(workDir, "dQw4w9WgXcQ.info.json");
      await fs.writeFile(mediaPath, "binary");
      await fs.writeFile(metadataPath, "{}");
      return {
        success: true,
        data: createAcquisitionEnvelope({
          entries: [{ mediaPath, captionPaths: [], metadataPath, caption: null }],
          metadata: { id: "dQw4w9WgXcQ", title: "Fixture Talk", description: "", chapters: [], comments: [] },
          workDir,
        }),
      };
    });
    vi.mocked(orchestrateWatching).mockImplementation(async () => {
      const handler = /** @type {() => void} */ (process.listeners("SIGTERM").at(-1));
      handler();
      // A killed ffmpeg leaves a degraded result rather than a rejection.
      return /** @type {any} */ ({
        selectedFrames: [],
        targetMinFrames: 0,
        highVolume: false,
        candidateCount: 0,
        probedDurationSec: null,
        densificationWindows: [],
      });
    });

    expect(await runWatchCli(["node", "run-watch.js", URL])).toBe(1);
    expect(vi.mocked(orchestrateWatching)).toHaveBeenCalledOnce();
    expect(vi.mocked(writeWatchingManifest)).not.toHaveBeenCalled();
  });
});
