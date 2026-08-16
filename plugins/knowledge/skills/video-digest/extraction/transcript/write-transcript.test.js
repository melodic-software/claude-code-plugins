import path from "node:path";

import { describe, expect, it } from "vitest";

import { createAcquisitionEnvelope } from "../adapters/adapter-contract.js";
import {
  buildTranscriptText,
  transcriptFilename,
  writeEnvelopeTranscriptArtifacts,
} from "./write-transcript.js";

const TIMESTAMP_PARAGRAPH_PATTERN = /^\[0:0\d\]/;

const SAMPLE_VTT = `WEBVTT

00:00:01.000 --> 00:00:03.000
hello

00:00:02.500 --> 00:00:04.500
hello world

00:00:05.000 --> 00:00:07.000
second sentence here.
`;

describe("buildTranscriptText", () => {
  it("cleans auto captions and formats timestamp paragraphs", () => {
    const result = buildTranscriptText(SAMPLE_VTT, true);
    expect(result.cleanedAutoCaptions).toBe(true);
    expect(result.transcript).toMatch(TIMESTAMP_PARAGRAPH_PATTERN);
    expect(result.paragraphCount).toBeGreaterThan(0);
  });

  it("parses manual captions without auto-clean pass", () => {
    const manualVtt = `WEBVTT

00:00:01.000 --> 00:00:03.000
Manual caption line.
`;
    const result = buildTranscriptText(manualVtt, false);
    expect(result.cleanedAutoCaptions).toBe(false);
    expect(result.transcript).toContain("Manual caption line.");
  });
});

describe("transcriptFilename", () => {
  it("gives the primary entry the historical transcript.txt name wherever it sits", () => {
    expect(transcriptFilename(0, 0)).toBe("transcript.txt");
    expect(transcriptFilename(1, 1)).toBe("transcript.txt");
    expect(transcriptFilename(0, 1)).toBe("transcript-1.txt");
    expect(transcriptFilename(2, 1)).toBe("transcript-3.txt");
  });
});

describe("writeEnvelopeTranscriptArtifacts", () => {
  const sliceDir = "/repo/.work/sample-abc";
  const metadata = { id: "metadataId0", title: "Sample Talk", description: "" };

  /** @param {object} [overrides] */
  function entry(overrides = {}) {
    return { mediaPath: "", captionPaths: [], metadataPath: "", caption: null, ...overrides };
  }

  /** @param {string} vttPath */
  function caption(vttPath) {
    return { path: vttPath, rung: "manual-en", isAutoCaption: false };
  }

  /** @param {import('../adapters/adapter-contract.js').AcquisitionEnvelope} envelope */
  async function writeWithFakeFs(envelope) {
    /** @type {Record<string, string>} */
    const files = {};
    const result = await writeEnvelopeTranscriptArtifacts(
      { sliceDir, envelope, sourceUrl: "https://www.youtube.com/watch?v=abc", sliceKey: "urlKey0" },
      {
        mkdir: async () => {},
        readFile: async () => SAMPLE_VTT,
        writeFile: async (filePath, content) => {
          files[String(filePath)] = String(content);
        },
      },
    );
    return { files, result };
  }

  it("records the slice key, not the metadata id, in the README", async () => {
    const { files } = await writeWithFakeFs(
      createAcquisitionEnvelope({ entries: [], metadata, workDir: "/w" }),
    );
    const readme = files[path.join(sliceDir, "README.md")];
    expect(readme).toContain("urlKey0");
    expect(readme).not.toContain("metadataId0");
  });

  it("captions+repair repairs proper nouns from the post-text lexicon", async () => {
    const corruptedVtt = `WEBVTT

00:00:01.000 --> 00:00:03.000
so I opened clawed code today
`;
    /** @type {Record<string, string>} */
    const files = {};
    const result = await writeEnvelopeTranscriptArtifacts(
      {
        sliceDir,
        envelope: createAcquisitionEnvelope({
          entries: [
            entry({
              mediaPath: "/w/a.mp4",
              captionPaths: ["/w/a.en.vtt"],
              caption: { path: "/w/a.en.vtt", rung: "platform-asr-en", isAutoCaption: true },
            }),
          ],
          metadata: { ...metadata, description: "Claude Code ships today" },
          workDir: "/w",
        }),
        sourceUrl: "https://x.com/u/status/1",
        sliceKey: "urlKey0",
        transcriptStrategy: "captions+repair",
      },
      {
        mkdir: async () => {},
        readFile: async () => corruptedVtt,
        writeFile: async (filePath, content) => {
          files[String(filePath)] = String(content);
        },
      },
    );

    expect(result.transcripts).toHaveLength(1);
    expect(result.transcripts[0].strategy).toBe("captions+repair");
    expect(result.transcripts[0].repairedTermCount).toBe(1);
    expect(result.transcriptDegradation).toBeNull();
    const transcript = files[path.join(sliceDir, "source", "transcript.txt")];
    expect(transcript).toContain("Claude Code");
    expect(transcript).not.toContain("clawed code");
  });

  it("caption-absent + ASR capability available runs the asr rung", async () => {
    /** @type {Record<string, string>} */
    const files = {};
    const runAsrMock = async (/** @type {{mediaPath: string}} */ options) => {
      expect(options.mediaPath).toBe("/w/a.mp4");
      return {
        success: true,
        cues: [{ startSec: 0, endSec: 2, text: "spoken words" }],
        words: [],
      };
    };
    const result = await writeEnvelopeTranscriptArtifacts(
      {
        sliceDir,
        envelope: createAcquisitionEnvelope({
          entries: [entry({ mediaPath: "/w/a.mp4" })],
          metadata,
          workDir: "/w",
        }),
        sourceUrl: "https://x.com/u/status/1",
        sliceKey: "urlKey0",
        transcriptStrategy: "captions+repair",
      },
      {
        mkdir: async () => {},
        readFile: async () => "",
        writeFile: async (filePath, content) => {
          files[String(filePath)] = String(content);
        },
        detectAsr: async () => ({
          available: true,
          python: "python",
          version: "1.1.0",
          detail: "test",
        }),
        runAsr: runAsrMock,
      },
    );

    expect(result.transcripts).toHaveLength(1);
    expect(result.transcripts[0].strategy).toBe("asr");
    expect(result.captionlessEntryCount).toBe(1);
    expect(result.transcriptDegradation).toBeNull();
    expect(files[path.join(sliceDir, "source", "transcript.txt")]).toContain("spoken words");
  });

  it("caption-absent + capability absent degrades explicitly in the named provenance field", async () => {
    const result = await writeEnvelopeTranscriptArtifacts(
      {
        sliceDir,
        envelope: createAcquisitionEnvelope({
          entries: [entry({ mediaPath: "/w/a.mp4" })],
          metadata,
          workDir: "/w",
        }),
        sourceUrl: "https://x.com/u/status/1",
        sliceKey: "urlKey0",
        transcriptStrategy: "captions+repair",
      },
      {
        mkdir: async () => {},
        readFile: async () => "",
        writeFile: async () => {},
        detectAsr: async () => ({
          available: false,
          python: null,
          version: null,
          detail: "not installed",
        }),
      },
    );

    expect(result.transcripts).toHaveLength(0);
    expect(result.transcriptDegradation).toContain("faster-whisper");
    expect(result.entryDegradations).toEqual([
      { entryIndex: 0, reason: expect.stringContaining("without a transcript") },
    ]);
  });

  it("an explicit pipeline override wins over the adapter default", async () => {
    const result = await writeEnvelopeTranscriptArtifacts(
      {
        sliceDir,
        envelope: createAcquisitionEnvelope({
          entries: [
            entry({
              captionPaths: ["/w/a.en.vtt"],
              caption: { path: "/w/a.en.vtt", rung: "platform-asr-en", isAutoCaption: true },
            }),
          ],
          metadata: { ...metadata, description: "Claude Code" },
          workDir: "/w",
        }),
        sourceUrl: "https://x.com/u/status/1",
        sliceKey: "urlKey0",
        transcriptStrategy: "captions+repair",
        strategyOverride: "captions",
      },
      {
        mkdir: async () => {},
        readFile: async () => SAMPLE_VTT,
        writeFile: async () => {},
      },
    );

    expect(result.transcripts[0].strategy).toBe("captions");
    expect(result.transcripts[0].repairedTermCount).toBe(0);
  });

  it("an ASR failure degrades the entry explicitly instead of failing the digest", async () => {
    const result = await writeEnvelopeTranscriptArtifacts(
      {
        sliceDir,
        envelope: createAcquisitionEnvelope({
          entries: [entry({ mediaPath: "/w/a.mp4" })],
          metadata,
          workDir: "/w",
        }),
        sourceUrl: "https://x.com/u/status/1",
        sliceKey: "urlKey0",
        transcriptStrategy: "captions+repair",
      },
      {
        mkdir: async () => {},
        readFile: async () => "",
        writeFile: async () => {},
        detectAsr: async () => ({
          available: true,
          python: "python",
          version: "1.1.0",
          detail: "test",
        }),
        runAsr: async () => ({ success: false, error: "ASR transcription failed: boom" }),
      },
    );

    expect(result.transcripts).toHaveLength(0);
    expect(result.transcriptDegradation).toContain("boom");
  });

  it("pairs transcript.txt with the primary (media-bearing) entry, not entry 0", async () => {
    const { files, result } = await writeWithFakeFs(
      createAcquisitionEnvelope({
        entries: [
          entry({ captionPaths: ["/w/a.vtt"], caption: caption("/w/a.vtt") }),
          entry({
            mediaPath: "/w/b.mp4",
            captionPaths: ["/w/b.vtt"],
            caption: caption("/w/b.vtt"),
          }),
        ],
        metadata,
        workDir: "/w",
      }),
    );

    expect(result.primaryEntryIndex).toBe(1);
    const paths = result.transcripts.map((t) => path.basename(t.transcriptPath));
    expect(paths).toEqual(["transcript-1.txt", "transcript.txt"]);
    expect(files[path.join(sliceDir, "source", "transcript.txt")]).toBeDefined();
    expect(files[path.join(sliceDir, "source", "transcript-1.txt")]).toBeDefined();
  });
});
