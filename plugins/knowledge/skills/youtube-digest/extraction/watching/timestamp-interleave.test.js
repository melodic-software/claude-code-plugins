import { describe, expect, it } from "vitest";

import {
  batchFramesForContactSheets,
  interleaveTranscriptAndFrames,
} from "./timestamp-interleave.js";

const FRAMES = [
  {
    path: "/f1.png",
    file: "f1.png",
    timestampSec: 30,
    priorityScore: 1,
    textDense: false,
    readResolution: /** @type {'1280x720'} */ ("1280x720"),
  },
  {
    path: "/f2.png",
    file: "f2.png",
    timestampSec: 10,
    priorityScore: 1,
    textDense: false,
    readResolution: /** @type {'1280x720'} */ ("1280x720"),
  },
];

describe("interleaveTranscriptAndFrames", () => {
  it("sorts transcript and frame items by timestamp", () => {
    const timeline = interleaveTranscriptAndFrames(
      [
        { startSec: 0, endSec: 5, text: "Intro" },
        { startSec: 25, endSec: 35, text: "Middle" },
      ],
      FRAMES,
    );

    expect(timeline.map((item) => item.timestampSec)).toEqual([0, 10, 25, 30]);
    expect(timeline.filter((item) => item.kind === "transcript")).toHaveLength(2);
    expect(timeline.filter((item) => item.kind === "frame")).toHaveLength(2);
  });
});

describe("batchFramesForContactSheets", () => {
  it("splits frames into 16-frame batches", () => {
    const frames = Array.from({ length: 20 }, (_, i) => ({
      path: `/f${i}.png`,
      file: `f${i}.png`,
      timestampSec: i,
      priorityScore: 1,
      textDense: false,
      readResolution: /** @type {'1280x720'} */ ("1280x720"),
    }));
    const batches = batchFramesForContactSheets(frames, 16);
    expect(batches).toHaveLength(2);
    expect(batches[0]).toHaveLength(16);
    expect(batches[1]).toHaveLength(4);
  });
});
