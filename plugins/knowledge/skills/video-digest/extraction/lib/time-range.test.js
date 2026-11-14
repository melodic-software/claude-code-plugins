import { describe, expect, it } from "vitest";

import {
  cuesInMediaTime,
  cuesInVideoTime,
  describeTimeRange,
  downloadSectionSpec,
  keyframeOffsetErrorSec,
  parseClock,
  parseTimeRangeArgs,
  watchingInVideoTime,
} from "./time-range.js";

describe("parseClock", () => {
  it("reads h:mm:ss, m:ss and plain seconds", () => {
    expect(parseClock("1:00:00")).toBe(3600);
    expect(parseClock("75:30")).toBe(4530);
    expect(parseClock("90")).toBe(90);
  });

  it("rejects malformed times", () => {
    for (const value of ["", "1:60", "1:00:60", "1:2:3:4", "-5", "1.5", "abc", undefined]) {
      expect(parseClock(value)).toBeNull();
    }
  });
});

describe("parseTimeRangeArgs", () => {
  it("returns no range without either flag", () => {
    expect(parseTimeRangeArgs(["node", "x", "url"])).toEqual({ ok: true, range: null });
  });

  it("allows either bound alone", () => {
    expect(parseTimeRangeArgs(["--from", "1:00:00"])).toEqual({
      ok: true,
      range: { fromSec: 3600, toSec: null },
    });
    expect(parseTimeRangeArgs(["--to", "20:00"])).toEqual({
      ok: true,
      range: { fromSec: 0, toSec: 1200 },
    });
  });

  it("rejects a malformed bound or an end not after the start", () => {
    expect(parseTimeRangeArgs(["--from"]).ok).toBe(false);
    expect(parseTimeRangeArgs(["--from", "soon"]).ok).toBe(false);
    expect(parseTimeRangeArgs(["--from", "10:00", "--to", "10:00"]).ok).toBe(false);
    expect(parseTimeRangeArgs(["--to", "0"]).ok).toBe(false);
  });
});

describe("downloadSectionSpec / describeTimeRange", () => {
  it("formats a closed and an open range", () => {
    expect(downloadSectionSpec({ fromSec: 3600, toSec: 4800 })).toBe("*1:00:00-1:20:00");
    expect(downloadSectionSpec({ fromSec: 3600, toSec: null })).toBe("*1:00:00-inf");
    expect(describeTimeRange({ fromSec: 0, toSec: 1200 })).toBe("0:00:00 to 0:20:00");
    expect(describeTimeRange({ fromSec: 3600, toSec: null })).toBe("1:00:00 to the end");
  });
});

describe("keyframeOffsetErrorSec", () => {
  it("is the media's length beyond the range", () => {
    const range = { fromSec: 3600, toSec: 4800 };
    const errorFor = (/** @type {number} */ probedDurationSec) =>
      keyframeOffsetErrorSec(range, { probedDurationSec, videoDurationSec: 32300 });
    expect(errorFor(1207.25)).toBe(7.25);
    expect(errorFor(1199)).toBe(0);
  });

  it("uses the video duration for an open end", () => {
    expect(
      keyframeOffsetErrorSec(
        { fromSec: 3600, toSec: null },
        { probedDurationSec: 1203, videoDurationSec: 4800 },
      ),
    ).toBe(3);
  });

  it("caps a --to past the video's end at the video duration", () => {
    expect(
      keyframeOffsetErrorSec(
        { fromSec: 3600, toSec: 32400 },
        { probedDurationSec: 28705, videoDurationSec: 32300 },
      ),
    ).toBe(5);
    expect(
      keyframeOffsetErrorSec(
        { fromSec: 3600, toSec: 32400 },
        { probedDurationSec: 28705, videoDurationSec: null },
      ),
    ).toBe(0);
  });

  it("is zero from the start and null when a duration is unknown", () => {
    expect(
      keyframeOffsetErrorSec(
        { fromSec: 0, toSec: 600 },
        { probedDurationSec: null, videoDurationSec: null },
      ),
    ).toBe(0);
    expect(
      keyframeOffsetErrorSec(
        { fromSec: 60, toSec: null },
        { probedDurationSec: 500, videoDurationSec: null },
      ),
    ).toBeNull();
  });
});

describe("cue time moves", () => {
  const cues = [
    { startSec: 3590, endSec: 3602, text: "straddles start" },
    { startSec: 3700, endSec: 3705, text: "inside" },
    { startSec: 4795, endSec: 4810, text: "straddles end" },
    { startSec: 4900, endSec: 4905, text: "after" },
  ];

  it("keeps the cues overlapping the range, in media time", () => {
    expect(cuesInMediaTime(cues, { fromSec: 3600, toSec: 4800 })).toEqual([
      { startSec: 0, endSec: 2, text: "straddles start" },
      { startSec: 100, endSec: 105, text: "inside" },
      { startSec: 1195, endSec: 1200, text: "straddles end" },
    ]);
  });

  it("adds the offset back for media-time cues", () => {
    expect(cuesInVideoTime([{ startSec: 1, endSec: 2, text: "a" }], 3600)).toEqual([
      { startSec: 3601, endSec: 3602, text: "a" },
    ]);
  });
});

describe("watchingInVideoTime", () => {
  const timed = { path: "/f/a.png", file: "a.png", timestampSec: 10, timestampErrorSec: 1 };
  const untimed = { path: "/f/b.png", file: "b.png", timestampSec: null };
  const watching = /** @type {any} */ ({
    sceneFrames: [timed, untimed],
    uniqueFrames: [timed],
    selectedFrames: [timed, untimed],
    densificationWindows: [{ startSec: 5, endSec: 20, densityMultiplier: 3, reason: "demo" }],
    contactSheets: [],
    interleavedTimeline: [
      { kind: "transcript", timestampSec: 0, transcriptText: "hi" },
      { kind: "frame", timestampSec: 10, frame: timed },
      { kind: "frame", timestampSec: null, frame: untimed },
    ],
    durationSec: 1200,
    overCap: false,
    candidateCount: 1,
  });

  it("shifts every stamp and widens timed frames' error by the offset error", () => {
    const shifted = watchingInVideoTime(watching, { offsetSec: 3600, offsetErrorSec: 2 });
    expect(shifted.selectedFrames).toEqual([
      { ...timed, timestampSec: 3610, timestampErrorSec: 3 },
      untimed,
    ]);
    expect(shifted.sceneFrames[0].timestampSec).toBe(3610);
    expect(shifted.densificationWindows[0]).toMatchObject({ startSec: 3605, endSec: 3620 });
    expect(shifted.interleavedTimeline.map((entry) => entry.timestampSec)).toEqual([
      3600,
      3610,
      null,
    ]);
    expect(shifted.interleavedTimeline[1].frame?.timestampSec).toBe(3610);
    expect(shifted.durationSec).toBe(1200);
    expect(watching.selectedFrames[0].timestampSec).toBe(10);
  });

  it("leaves frame errors alone when the offset is exact", () => {
    const shifted = watchingInVideoTime(watching, { offsetSec: 60, offsetErrorSec: 0 });
    expect(shifted.selectedFrames[0]).toEqual({ ...timed, timestampSec: 70 });
  });
});
