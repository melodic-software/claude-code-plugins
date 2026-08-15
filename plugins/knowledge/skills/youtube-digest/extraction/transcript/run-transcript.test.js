import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { createAcquisitionEnvelope } from "../adapters/adapter-contract.js";
import { acquireMedia } from "../acquisition/acquire.js";
import { runTranscriptCli } from "./run-transcript.js";

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

vi.mock("../acquisition/acquire.js", async (importOriginal) => {
  const actual = await importOriginal();
  return { ...actual, acquireMedia: vi.fn() };
});

const URL = "https://www.youtube.com/watch?v=7zZy1QTvokM";
const METADATA = {
  id: "7zZy1QTvokM",
  title: "Fixture Video",
  description: "",
  chapters: [],
  heatmap: null,
  comments: [],
};
const VTT = `WEBVTT

00:00:00.000 --> 00:00:02.000
hello world

00:00:02.000 --> 00:00:04.000
second cue
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

/** @param {string} vttPath */
function captionEntry(vttPath) {
  return {
    mediaPath: "",
    captionPaths: [vttPath],
    metadataPath: path.join(fixtureDir, "info.json"),
    caption: { path: vttPath, rung: "manual-en", isAutoCaption: false },
  };
}

function sliceDir() {
  return path.join(workRoot, ".work", "youtube-watch", "fixture-video-7zZy1QTvokM");
}

describe("runTranscriptCli envelope consumption", () => {
  beforeEach(async () => {
    workRoot = await fs.mkdtemp(path.join(os.tmpdir(), "transcript-envelope-root-"));
    fixtureDir = await fs.mkdtemp(path.join(os.tmpdir(), "transcript-envelope-fix-"));
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

  it("consumes a 1-entry envelope with the historical single-transcript layout", async () => {
    const vttPath = await writeVtt("7zZy1QTvokM.en.vtt");
    vi.mocked(acquireMedia).mockResolvedValue({
      success: true,
      data: createAcquisitionEnvelope({
        entries: [captionEntry(vttPath)],
        metadata: METADATA,
        workDir: fixtureDir,
      }),
    });

    const code = await runTranscriptCli(["node", "run-transcript.js", URL]);
    expect(code).toBe(0);

    const output = JSON.parse(captured.stdout.join(""));
    expect(output.entryCount).toBe(1);
    expect(output.videoSlug).toBe("fixture-video-7zZy1QTvokM");
    expect(output.captionRung).toBe("manual-en");
    expect(output.videoDownloaded).toBe(false);
    expect(output.transcriptPath).toBe(path.join(sliceDir(), "source", "transcript.txt"));

    const transcript = await fs.readFile(output.transcriptPath, "utf8");
    expect(transcript).toContain("hello world");
    await expect(fs.readFile(path.join(sliceDir(), "README.md"), "utf8")).resolves.toContain(
      "Fixture Video",
    );
  });

  it("consumes a 0-entry envelope as a well-formed metadata-only slice", async () => {
    vi.mocked(acquireMedia).mockResolvedValue({
      success: true,
      data: createAcquisitionEnvelope({ entries: [], metadata: METADATA, workDir: fixtureDir }),
    });

    const code = await runTranscriptCli(["node", "run-transcript.js", URL]);
    expect(code).toBe(0);

    const output = JSON.parse(captured.stdout.join(""));
    expect(output.entryCount).toBe(0);
    expect(output.transcriptPath).toBeNull();
    expect(output.captionRung).toBeNull();
    expect(output.transcripts).toEqual([]);

    await expect(fs.readFile(path.join(sliceDir(), "README.md"), "utf8")).resolves.toContain(
      "Fixture Video",
    );
    await expect(
      fs.access(path.join(sliceDir(), "source", "transcript.txt")),
    ).rejects.toThrow();
  });

  it("consumes an N-entry envelope with per-entry transcripts", async () => {
    const first = await writeVtt("first.en.vtt");
    const second = await writeVtt("second.en.vtt");
    const captionless = {
      mediaPath: path.join(fixtureDir, "third.mp4"),
      captionPaths: [],
      metadataPath: "",
      caption: null,
    };
    vi.mocked(acquireMedia).mockResolvedValue({
      success: true,
      data: createAcquisitionEnvelope({
        entries: [captionEntry(first), captionEntry(second), captionless],
        metadata: METADATA,
        workDir: fixtureDir,
      }),
    });

    const code = await runTranscriptCli(["node", "run-transcript.js", URL]);
    expect(code).toBe(0);

    const output = JSON.parse(captured.stdout.join(""));
    expect(output.entryCount).toBe(3);
    // Not arity 1 — the legacy single-entry fields must not silently collapse.
    expect(output.captionRung).toBeNull();
    expect(output.transcripts.map((/** @type {{entryIndex: number}} */ t) => t.entryIndex)).toEqual([
      0, 1,
    ]);

    await expect(
      fs.readFile(path.join(sliceDir(), "source", "transcript.txt"), "utf8"),
    ).resolves.toContain("hello world");
    await expect(
      fs.readFile(path.join(sliceDir(), "source", "transcript-2.txt"), "utf8"),
    ).resolves.toContain("hello world");
    await expect(
      fs.access(path.join(sliceDir(), "source", "transcript-3.txt")),
    ).rejects.toThrow();
  });
});
