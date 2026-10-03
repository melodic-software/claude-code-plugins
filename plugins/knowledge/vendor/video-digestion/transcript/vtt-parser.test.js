import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  formatTranscript,
  overlapWordCount,
  parseVttSegment,
  stripVttInlineTags,
} from "./vtt-parser.js";

describe("formatTranscript", () => {
  it("does not start a paragraph with the previous paragraph's tail", () => {
    const transcript = formatTranscript([
      { startSec: 0, endSec: 2, text: "so let us cut through" },
      {
        startSec: 2,
        endSec: 4,
        text: "cut through the hype and answer what is Jev really.",
      },
      {
        startSec: 4,
        endSec: 6,
        text: "answer what is Jev really. And today we build",
      },
    ]);
    const paragraphs = transcript.split("\n\n");
    assert.equal(paragraphs.length, 2);
    assert.equal(paragraphs[1], "[0:04] And today we build");
  });

  it("keeps a shifted-window phrase once across touching cues", () => {
    const phrase = "By now you have heard of Jev.";
    const transcript = formatTranscript([
      { startSec: 0, endSec: 2, text: "welcome back to the channel" },
      { startSec: 2, endSec: 4, text: `agents in this video. ${phrase}` },
      { startSec: 4, endSec: 6, text: `${phrase} And today we build agents` },
    ]);
    assert.equal(transcript.split(phrase).length - 1, 1);
  });

  it("drops a cue that only repeats the previous paragraph's tail", () => {
    const transcript = formatTranscript([
      { startSec: 0, endSec: 2, text: "we ship the agent today" },
      { startSec: 2, endSec: 4, text: "and it answers what is Jev really." },
      { startSec: 4, endSec: 5, text: "what is Jev really." },
      { startSec: 5, endSec: 7, text: "Next we test it" },
    ]);
    assert.deepEqual(transcript.split("\n\n"), [
      "[0:00] we ship the agent today and it answers what is Jev really.",
      "[0:05] Next we test it",
    ]);
  });
});

describe("overlapWordCount", () => {
  it("counts the shared suffix/prefix word run, case-insensitively", () => {
    assert.equal(
      overlapWordCount(
        "cut through the hype and answer what is Jev really.",
        "Answer what is Jev really. And today we build",
      ),
      5,
    );
  });

  it("ignores a run shorter than three words", () => {
    assert.equal(overlapWordCount("so let us cut through", "cut through the hype"), 0);
  });
});

describe("stripVttInlineTags", () => {
  it("removes normal WebVTT formatting tags", () => {
    assert.equal(
      stripVttInlineTags("<c>Hello</c> <b>world</b>"),
      "Hello world",
    );
  });

  it("does not create a tag when nested malformed markup is removed", () => {
    assert.equal(
      stripVttInlineTags("before <scr<script>ipt> after"),
      "before ipt> after",
    );
  });

  for (const caption of ["if (x < y)", "count < limit"]) {
    it(`preserves an unmatched less-than tail: ${caption}`, () => {
      assert.equal(stripVttInlineTags(caption), caption);
    });
  }

  it("preserves an unmatched less-than tail after a complete tag", () => {
    assert.equal(stripVttInlineTags("<c>count</c> < limit"), "count < limit");
  });

  it("preserves a long unterminated candidate in linear traversal", () => {
    const caption = `<${"<".repeat(100_000)}payload`;
    assert.equal(stripVttInlineTags(caption), caption);
  });
});

describe("parseVttSegment", () => {
  it("uses the linear tag stripper for cue text", () => {
    const cues = parseVttSegment(`WEBVTT

00:00:01.000 --> 00:00:03.000
<c>Hello</c> <b>world</b>`);
    assert.equal(cues.length, 1);
    assert.equal(cues[0].text, "Hello world");
  });

  it("preserves literal less-than text in a parsed cue", () => {
    const cues = parseVttSegment(`WEBVTT

00:00:01.000 --> 00:00:03.000
if (x < y)`);
    assert.equal(cues.length, 1);
    assert.equal(cues[0].text, "if (x < y)");
  });
});
