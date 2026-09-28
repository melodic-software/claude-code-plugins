import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { parseVttSegment, stripVttInlineTags } from "./vtt-parser.js";

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
