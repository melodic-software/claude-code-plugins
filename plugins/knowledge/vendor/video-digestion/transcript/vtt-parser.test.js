import { describe, expect, it } from "vitest";

import { parseVttSegment, stripVttInlineTags } from "./vtt-parser.js";

describe("stripVttInlineTags", () => {
  it("removes normal WebVTT formatting tags", () => {
    expect(stripVttInlineTags("<c>Hello</c> <b>world</b>")).toBe("Hello world");
  });

  it("does not create a tag when nested malformed markup is removed", () => {
    expect(stripVttInlineTags("before <scr<script>ipt> after")).toBe(
      "before ipt> after",
    );
  });

  it.each(["if (x < y)", "count < limit"])(
    "preserves an unmatched less-than tail: %s",
    (caption) => {
      expect(stripVttInlineTags(caption)).toBe(caption);
    },
  );

  it("preserves an unmatched less-than tail after a complete tag", () => {
    expect(stripVttInlineTags("<c>count</c> < limit")).toBe("count < limit");
  });

  it("preserves a long unterminated candidate in linear traversal", () => {
    const caption = `<${"<".repeat(100_000)}payload`;
    expect(stripVttInlineTags(caption)).toBe(caption);
  });
});

describe("parseVttSegment", () => {
  it("uses the linear tag stripper for cue text", () => {
    const cues = parseVttSegment(`WEBVTT

00:00:01.000 --> 00:00:03.000
<c>Hello</c> <b>world</b>`);
    expect(cues).toHaveLength(1);
    expect(cues[0].text).toBe("Hello world");
  });

  it("preserves literal less-than text in a parsed cue", () => {
    const cues = parseVttSegment(`WEBVTT

00:00:01.000 --> 00:00:03.000
if (x < y)`);
    expect(cues).toHaveLength(1);
    expect(cues[0].text).toBe("if (x < y)");
  });
});
