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
