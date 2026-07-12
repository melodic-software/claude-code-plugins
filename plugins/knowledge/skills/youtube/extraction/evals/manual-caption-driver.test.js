import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { buildTranscriptText } from "../transcript/write-transcript.js";
import { checkTranscriptGoldens } from "./check-transcript-goldens.js";
import { analyzeTranscriptReadability } from "./check-transcript-readability.js";

const FIXTURES = path.dirname(fileURLToPath(import.meta.url));
const DRIVER_VTT = path.join(FIXTURES, "fixtures", "driver-manual-en-snippet.vtt");
const CLEAN_VTT = path.join(FIXTURES, "fixtures", "clean-manual-course-snippet.vtt");
const ROLLING_DUPLICATE_RE = /I just listened I just listened/;

const GOLDENS = path.join(FIXTURES, "../../evals/fixtures/driver-video-goldens.json");

describe("driver manual-en progressive clean", () => {
  it("collapses rolling duplication in fixture VTT", () => {
    const vtt = fs.readFileSync(DRIVER_VTT, "utf8");
    const built = buildTranscriptText(vtt, false);
    expect(built.cleanedManualCaptions).toBe(true);
    expect(built.transcript).not.toMatch(ROLLING_DUPLICATE_RE);
    expect(built.transcript).toContain("50 m away");
    const { maxRepeats } = analyzeTranscriptReadability(built.transcript);
    expect(maxRepeats).toBeLessThanOrEqual(2);
  });

  it("does not over-merge clean course manual VTT", () => {
    const vtt = fs.readFileSync(CLEAN_VTT, "utf8");
    const built = buildTranscriptText(vtt, false);
    expect(built.cueCount).toBe(3);
    expect(built.transcript).toContain("dependency injection");
  });
});

describe("driver transcript goldens on cleaned snippet", () => {
  it("car-wash golden still matches cleaned driver snippet", async () => {
    const vtt = fs.readFileSync(DRIVER_VTT, "utf8");
    const built = buildTranscriptText(vtt, false);
    const tmpPath = path.join(FIXTURES, "fixtures", ".tmp-driver-snippet-transcript.txt");
    fs.writeFileSync(tmpPath, built.transcript, "utf8");
    try {
      const result = await checkTranscriptGoldens(tmpPath, GOLDENS);
      const carWash = result.failed.find((f) => f.id === "car-wash-distance");
      expect(carWash).toBeUndefined();
    } finally {
      fs.unlinkSync(tmpPath);
    }
  });
});
