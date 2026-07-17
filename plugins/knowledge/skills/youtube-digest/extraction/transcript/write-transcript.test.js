import path from "node:path";

import { describe, expect, it } from "vitest";

import { buildTranscriptText, writeTranscriptArtifacts } from "./write-transcript.js";

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

describe("writeTranscriptArtifacts", () => {
  it("writes transcript.txt and README stub via injected fs", async () => {
    /** @type {Record<string, string>} */
    const files = {};

    const sliceDir = "/repo/.work/sample-abc";
    const result = await writeTranscriptArtifacts(
      {
        sliceDir,
        vttText: SAMPLE_VTT,
        isAutoCaption: true,
        videoTitle: "Sample Talk",
        videoId: "abc",
        sourceUrl: "https://www.youtube.com/watch?v=abc",
      },
      {
        mkdir: async () => {},
        writeFile: async (filePath, content) => {
          files[filePath] = String(content);
        },
      },
    );

    expect(files[result.transcriptPath]).toContain("[");
    expect(files[path.join(sliceDir, "README.md")]).toContain("Sample Talk");
    expect(result.transcriptPath.endsWith("transcript.txt")).toBe(true);
  });
});
