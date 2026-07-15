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

  it("handles a long unterminated tag in linear traversal", () => {
    expect(stripVttInlineTags(`<${"<".repeat(100_000)}payload`)).toBe("");
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
});
