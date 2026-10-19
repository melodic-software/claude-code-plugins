import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { writeSliceReadme } from "../transcript/write-transcript.js";
import {
  appendDurationMismatchToReadme,
  DURATION_MISMATCH_HEADING,
  detectDurationMismatch,
  formatClock,
  recordDurationMismatch,
} from "./duration-mismatch.js";
import { createWatchState } from "./watch-state.js";

describe("detectDurationMismatch", () => {
  it("reports both durations for the observed post-live stream (10446 s vs 3995 s)", () => {
    const mismatch = detectDurationMismatch(10446, 3995);
    expect(mismatch).toMatchObject({
      metadataDurationSec: 10446,
      probedDurationSec: 3995,
      deltaSec: 6451,
    });
  });

  it("reports nothing when the durations agree within the threshold", () => {
    expect(detectDurationMismatch(600, 600)).toBeNull();
    expect(detectDurationMismatch(600, 603.4)).toBeNull();
    expect(detectDurationMismatch(60, 64)).toBeNull();
    // 1% of a 10000 s stream is 100 s: a 90 s gap is within tolerance.
    expect(detectDurationMismatch(10000, 9910)).toBeNull();
  });

  it("reports a gap just past the threshold, in either direction", () => {
    expect(detectDurationMismatch(600, 607)).not.toBeNull();
    expect(detectDurationMismatch(607, 600)).not.toBeNull();
    expect(detectDurationMismatch(10000, 9890)).not.toBeNull();
  });

  it("reports nothing when either duration is missing or unusable", () => {
    expect(detectDurationMismatch(null, 3995)).toBeNull();
    expect(detectDurationMismatch(10446, null)).toBeNull();
    expect(detectDurationMismatch(undefined, undefined)).toBeNull();
    expect(detectDurationMismatch(0, 3995)).toBeNull();
    expect(detectDurationMismatch(10446, Number.NaN)).toBeNull();
  });
});

describe("formatClock", () => {
  it("formats seconds as H:MM:SS", () => {
    expect(formatClock(10446)).toBe("2:54:06");
    expect(formatClock(3995)).toBe("1:06:35");
  });
});

describe("recording a mismatch", () => {
  /** @type {string} */
  let sliceDir;

  beforeEach(async () => {
    sliceDir = await fs.mkdtemp(path.join(os.tmpdir(), "duration-mismatch-"));
    await writeSliceReadme({
      sliceDir,
      videoTitle: "Post-live stream",
      videoId: "abc123",
      sourceUrl: "https://example.test/watch?v=abc123",
    });
  });

  afterEach(async () => {
    await fs.rm(sliceDir, { recursive: true, force: true });
  });

  const newState = () =>
    createWatchState({
      videoId: "abc123",
      videoSlug: "post-live-stream",
      sourceUrl: "https://example.test/watch?v=abc123",
      title: "Post-live stream",
    });

  it("records both durations in watch state and states the mismatch in the README", async () => {
    const state = await recordDurationMismatch(newState(), sliceDir, {
      metadataDurationSec: 10446,
      probedDurationSec: 3995,
    });

    expect(state.durationMismatch).toMatchObject({
      metadataDurationSec: 10446,
      probedDurationSec: 3995,
    });
    const readme = await fs.readFile(path.join(sliceDir, "README.md"), "utf8");
    expect(readme).toContain(DURATION_MISMATCH_HEADING);
    expect(readme).toContain("2:54:06");
    expect(readme).toContain("1:06:35");
  });

  it("records nothing extra when the durations agree", async () => {
    const before = await fs.readFile(path.join(sliceDir, "README.md"), "utf8");
    const initial = newState();

    const state = await recordDurationMismatch(initial, sliceDir, {
      metadataDurationSec: 3995,
      probedDurationSec: 3995.6,
    });

    expect(state).toBe(initial);
    expect(state).not.toHaveProperty("durationMismatch");
    expect(await fs.readFile(path.join(sliceDir, "README.md"), "utf8")).toBe(before);
  });

  it("does not duplicate the README section on a second append", async () => {
    const mismatch = detectDurationMismatch(10446, 3995);
    expect(await appendDurationMismatchToReadme(sliceDir, mismatch)).toBe(true);
    expect(await appendDurationMismatchToReadme(sliceDir, mismatch)).toBe(false);
    const readme = await fs.readFile(path.join(sliceDir, "README.md"), "utf8");
    expect(readme.split(DURATION_MISMATCH_HEADING)).toHaveLength(2);
  });
});
