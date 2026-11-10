import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { cleanAutoCaptions, dropCarriedCaptionLines } from "./auto-caption-clean.js";

describe("dropCarriedCaptionLines", () => {
  it("keeps the lines after a carried first line and drops a cue with none", () => {
    const cues = dropCarriedCaptionLines([
      { startSec: 0, endSec: 2, text: "we load the data okay.", lines: ["we load the data", "okay."] },
      { startSec: 2, endSec: 2.01, text: "okay.", lines: ["okay."] },
      { startSec: 2.01, endSec: 4, text: "okay. then", lines: ["okay.", "then"] },
    ]);
    assert.deepEqual(cues, [
      { startSec: 0, endSec: 2, text: "we load the data okay." },
      { startSec: 2.01, endSec: 4, text: "then", carriedLineDropped: true },
    ]);
  });

  it("never matches two single-line cues", () => {
    const cues = dropCarriedCaptionLines([
      { startSec: 0, endSec: 2, text: "Thank you.", lines: ["Thank you."] },
      { startSec: 3, endSec: 5, text: "Thank you.", lines: ["Thank you."] },
    ]);
    assert.deepEqual(cues, [
      { startSec: 0, endSec: 2, text: "Thank you." },
      { startSec: 3, endSec: 5, text: "Thank you." },
    ]);
  });
});

describe("cleanAutoCaptions", () => {
  it("returns cues without their lines, marking each trimmed one", () => {
    const { cues } = cleanAutoCaptions(`WEBVTT

00:00:01.000 --> 00:00:03.000
we said
right

00:00:03.000 --> 00:00:03.010
right

00:00:03.010 --> 00:00:05.000
right
right again.
`);
    assert.deepEqual(cues, [
      { startSec: 1, endSec: 3, text: "we said right" },
      { startSec: 3, endSec: 5, text: "right again.", carriedLineDropped: true },
    ]);
  });
});
