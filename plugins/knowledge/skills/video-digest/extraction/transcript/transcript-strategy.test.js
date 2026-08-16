import { describe, expect, it } from "vitest";

import {
  isTranscriptStrategy,
  parseTranscriptStrategyOverride,
  resolveTranscriptStrategy,
} from "./transcript-strategy.js";

/**
 * @param {Partial<Parameters<typeof resolveTranscriptStrategy>[0]>} overrides
 */
function resolve(overrides = {}) {
  return resolveTranscriptStrategy({
    adapterDefault: "captions",
    override: null,
    captionPresent: true,
    mediaAvailable: true,
    asrAvailable: false,
    ...overrides,
  });
}

describe("resolveTranscriptStrategy", () => {
  it("uses the per-source adapter default when captions are present", () => {
    expect(resolve({ adapterDefault: "captions" })).toEqual({
      strategy: "captions",
      degradation: null,
    });
    expect(resolve({ adapterDefault: "captions+repair" })).toEqual({
      strategy: "captions+repair",
      degradation: null,
    });
  });

  it("lets an explicit pipeline override win over the adapter default", () => {
    expect(resolve({ adapterDefault: "captions+repair", override: "captions" })).toEqual({
      strategy: "captions",
      degradation: null,
    });
    expect(
      resolve({ adapterDefault: "captions", override: "asr", asrAvailable: true }),
    ).toEqual({ strategy: "asr", degradation: null });
  });

  it("selects asr for caption-absent entries whenever the capability is available", () => {
    expect(
      resolve({
        adapterDefault: "captions+repair",
        captionPresent: false,
        asrAvailable: true,
      }),
    ).toEqual({ strategy: "asr", degradation: null });
  });

  it("degrades explicitly (no transcript, named reason) when the capability is absent", () => {
    const plan = resolve({
      adapterDefault: "captions+repair",
      captionPresent: false,
      asrAvailable: false,
    });
    expect(plan.strategy).toBeNull();
    expect(plan.degradation).toContain("faster-whisper");
    expect(plan.degradation).toContain("without a transcript");
  });

  it("degrades explicitly when asr is available but the media file was not downloaded", () => {
    const plan = resolve({
      adapterDefault: "captions+repair",
      captionPresent: false,
      asrAvailable: true,
      mediaAvailable: false,
    });
    expect(plan.strategy).toBeNull();
    expect(plan.degradation).toContain("media file");
  });

  it("honors an explicit caption-based override on a caption-absent entry as degradation, never silent asr escalation", () => {
    const plan = resolve({
      adapterDefault: "captions+repair",
      override: "captions+repair",
      captionPresent: false,
      asrAvailable: true,
    });
    expect(plan.strategy).toBeNull();
    expect(plan.degradation).toContain('"captions+repair"');
  });

  it("falls back from an unrunnable asr override to the caption strategy, explicitly", () => {
    const plan = resolve({
      adapterDefault: "captions+repair",
      override: "asr",
      captionPresent: true,
      asrAvailable: false,
    });
    expect(plan.strategy).toBe("captions+repair");
    expect(plan.degradation).toContain('"asr" could not run');
  });

  it("rejects unknown strategy values loudly", () => {
    expect(() =>
      resolveTranscriptStrategy({
        adapterDefault: /** @type {never} */ ("telepathy"),
        captionPresent: true,
        mediaAvailable: true,
        asrAvailable: false,
      }),
    ).toThrow(/adapterDefault/);
    expect(() => resolve({ override: /** @type {never} */ ("telepathy") })).toThrow(
      /override/,
    );
  });
});

describe("isTranscriptStrategy", () => {
  it("accepts exactly the contract vocabulary", () => {
    expect(isTranscriptStrategy("captions")).toBe(true);
    expect(isTranscriptStrategy("captions+repair")).toBe(true);
    expect(isTranscriptStrategy("asr")).toBe(true);
    expect(isTranscriptStrategy("telepathy")).toBe(false);
    expect(isTranscriptStrategy(null)).toBe(false);
  });
});

describe("parseTranscriptStrategyOverride", () => {
  it("returns null when the flag is absent", () => {
    expect(parseTranscriptStrategyOverride(["node", "run.js", "https://x.com/u/status/1"]))
      .toEqual({ ok: true, override: null });
  });

  it("parses a valid override", () => {
    expect(
      parseTranscriptStrategyOverride([
        "node",
        "run.js",
        "https://x.com/u/status/1",
        "--transcript-strategy",
        "asr",
      ]),
    ).toEqual({ ok: true, override: "asr" });
  });

  it("rejects a missing or unknown value", () => {
    const missing = parseTranscriptStrategyOverride(["node", "run.js", "--transcript-strategy"]);
    expect(missing.ok).toBe(false);
    const unknown = parseTranscriptStrategyOverride([
      "node",
      "run.js",
      "--transcript-strategy",
      "telepathy",
    ]);
    expect(unknown.ok).toBe(false);
    if (!unknown.ok) {
      expect(unknown.error).toContain("captions, captions+repair, asr");
    }
  });
});
