import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { deduplicateFrames } from "./dedup.js";

const silentLog = { info() {}, warn() {} };

describe("deduplicateFrames", () => {
  it("keeps each frame's time fields through deduplication", async () => {
    const frames = [
      {
        path: "/frames/scene_0001.png",
        file: "scene_0001.png",
        timestampSec: 12.5,
        timestampSource: "scene-detection",
      },
      {
        path: "/frames/interval_0003.png",
        file: "interval_0003.png",
        timestampSec: 60,
        timestampSource: "estimated",
        timestampMethod: "interval-index",
        timestampErrorSec: 15,
      },
      { path: "/frames/scene_0002.png", file: "scene_0002.png", timestampSec: null },
    ];
    const hashes = {
      "scene_0001.png": "0000",
      "interval_0003.png": "ffff",
      "scene_0002.png": "f0f0",
    };

    const result = await deduplicateFrames(
      frames,
      {},
      { hashImage: async (path) => hashes[path.split("/").pop()], log: silentLog },
    );

    assert.deepEqual(
      result.unique.map(
        ({ timestampSec, timestampSource, timestampMethod, timestampErrorSec }) => ({
          timestampSec,
          timestampSource,
          timestampMethod,
          timestampErrorSec,
        }),
      ),
      [
        {
          timestampSec: 12.5,
          timestampSource: "scene-detection",
          timestampMethod: undefined,
          timestampErrorSec: undefined,
        },
        {
          timestampSec: 60,
          timestampSource: "estimated",
          timestampMethod: "interval-index",
          timestampErrorSec: 15,
        },
        {
          timestampSec: null,
          timestampSource: undefined,
          timestampMethod: undefined,
          timestampErrorSec: undefined,
        },
      ],
    );
  });

  it("still accepts bare paths, which carry no time", async () => {
    const result = await deduplicateFrames(
      ["/frames/scene_0001.png", "/frames/scene_0002.png"],
      {},
      { hashImage: async () => "00ff", log: silentLog },
    );

    assert.equal(result.duplicates, 1);
    assert.deepEqual(
      result.frames.map((frame) => [frame.file, frame.timestampSec]),
      [
        ["scene_0001.png", null],
        ["scene_0002.png", null],
      ],
    );
  });
});
