/**
 * CLI-level architecture proof for the capability-absent ASR degradation: a
 * caption-less X acquisition on a machine WITHOUT the optional faster-whisper
 * capability still exits 0, and the reason travels in the named
 * `transcriptDegradation` provenance field (stdout JSON + watch.json) — the
 * digest degrades explicitly, it never fails and never degrades silently.
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

// The machine-under-test has no faster-whisper: capability detection reports
// absent, and the transcription rung must never be reached.
vi.mock("../transcript/asr-transcribe.js", async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    detectAsrCapability: vi.fn(async () => ({ available: false })),
    runAsrTranscription: vi.fn(async () => {
      throw new Error("ASR must never run when the capability is absent");
    }),
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

import { runAsrTranscription } from "../transcript/asr-transcribe.js";
import { orchestrateWatching } from "../watching/orchestrate-watching.js";

const TWID = "1720000000000000000";
const X_URL = `https://x.com/someuser/status/${TWID}`;
const MEDIA_ID = String(BigInt(TWID) - (60_000n << 22n));

/** @type {string} */
let workRoot;
/** @type {string} */
let fixtureDir;

describe("run-watch capability-absent ASR degradation (CLI-level)", () => {
  beforeEach(async () => {
    workRoot = await fs.mkdtemp(path.join(os.tmpdir(), "watch-degradation-root-"));
    fixtureDir = await fs.mkdtemp(path.join(os.tmpdir(), "watch-degradation-fix-"));
    process.env.YOUTUBE_WORK_ROOT = workRoot;
    captured.stderr.length = 0;
    captured.stdout.length = 0;
    vi.mocked(acquireMedia).mockReset();
  });

  afterEach(async () => {
    delete process.env.YOUTUBE_WORK_ROOT;
    await fs.rm(workRoot, { recursive: true, force: true });
    await fs.rm(fixtureDir, { recursive: true, force: true });
  });

  it("exits 0 with transcriptDegradation recorded in stdout JSON and watch.json", async () => {
    const mediaPath = path.join(fixtureDir, `${MEDIA_ID}.mp4`);
    await fs.writeFile(mediaPath, "binary", "utf8");
    vi.mocked(acquireMedia).mockResolvedValue({
      success: true,
      data: createAcquisitionEnvelope({
        entries: [
          // Caption-less X media entry: no captions were published for the post.
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

    const output = JSON.parse(captured.stdout.join(""));
    // The named provenance field carries the capability-absent reason —
    // explicitly, never silently, and never as a failure.
    expect(output.transcriptDegradation).toContain("faster-whisper");
    expect(output.transcriptDegradation).toContain("without a transcript");
    expect(output.transcriptStrategy).toBeNull();
    // The X slice key is the URL's status id, and the digest continues into
    // the visual lane (media exists even though no transcript does).
    expect(output.videoSlug.endsWith(TWID)).toBe(true);
    expect(vi.mocked(orchestrateWatching)).toHaveBeenCalledOnce();
    expect(vi.mocked(runAsrTranscription)).not.toHaveBeenCalled();

    const stateRaw = await fs.readFile(
      path.join(output.sliceDir, "run-state", "watch.json"),
      "utf8",
    );
    const state = JSON.parse(stateRaw);
    expect(state.phases.transcript.metrics.transcriptDegradation).toContain("faster-whisper");
    expect(state.phases.transcript.metrics.skipped).toBe(true);
    // source:* provenance persists into watch state alongside the degradation.
    expect(state.sourceMetadata["source:displayId"]).toBe(TWID);
  });
});
