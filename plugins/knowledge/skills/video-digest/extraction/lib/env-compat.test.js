import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { resetLegacyEnvWarnings, resolveEnvWithLegacy } from "./env-compat.js";

describe("resolveEnvWithLegacy", () => {
  /** @type {import('vitest').MockInstance} */
  let stderrSpy;

  beforeEach(() => {
    resetLegacyEnvWarnings();
    stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
  });

  afterEach(() => {
    stderrSpy.mockRestore();
  });

  it("returns the new name's value without warning", () => {
    const env = { VIDEO_DIGEST_WORK_ROOT: "/new" };
    expect(resolveEnvWithLegacy("VIDEO_DIGEST_WORK_ROOT", "YOUTUBE_WORK_ROOT", env)).toBe("/new");
    expect(stderrSpy).not.toHaveBeenCalled();
  });

  it("falls back to the legacy name and warns", () => {
    const env = { YOUTUBE_WORK_ROOT: "/old" };
    expect(resolveEnvWithLegacy("VIDEO_DIGEST_WORK_ROOT", "YOUTUBE_WORK_ROOT", env)).toBe("/old");
    expect(stderrSpy).toHaveBeenCalledTimes(1);
    expect(String(stderrSpy.mock.calls[0][0])).toContain("YOUTUBE_WORK_ROOT is deprecated");
    expect(String(stderrSpy.mock.calls[0][0])).toContain("VIDEO_DIGEST_WORK_ROOT");
  });

  it("warns once per process per legacy variable", () => {
    const env = {
      YOUTUBE_WORK_ROOT: "/old",
      YOUTUBE_MAX_CONCURRENT_ACQUIRES: "2",
    };
    resolveEnvWithLegacy("VIDEO_DIGEST_WORK_ROOT", "YOUTUBE_WORK_ROOT", env);
    resolveEnvWithLegacy("VIDEO_DIGEST_WORK_ROOT", "YOUTUBE_WORK_ROOT", env);
    expect(stderrSpy).toHaveBeenCalledTimes(1);
    resolveEnvWithLegacy(
      "VIDEO_DIGEST_MAX_CONCURRENT_ACQUIRES",
      "YOUTUBE_MAX_CONCURRENT_ACQUIRES",
      env,
    );
    expect(stderrSpy).toHaveBeenCalledTimes(2);
  });

  it("prefers the new name when both are set, without warning", () => {
    const env = { VIDEO_DIGEST_WORK_ROOT: "/new", YOUTUBE_WORK_ROOT: "/old" };
    expect(resolveEnvWithLegacy("VIDEO_DIGEST_WORK_ROOT", "YOUTUBE_WORK_ROOT", env)).toBe("/new");
    expect(stderrSpy).not.toHaveBeenCalled();
  });

  it("returns undefined when neither is set (empty counts as unset)", () => {
    expect(resolveEnvWithLegacy("VIDEO_DIGEST_WORK_ROOT", "YOUTUBE_WORK_ROOT", {})).toBeUndefined();
    expect(
      resolveEnvWithLegacy("VIDEO_DIGEST_WORK_ROOT", "YOUTUBE_WORK_ROOT", {
        VIDEO_DIGEST_WORK_ROOT: "",
        YOUTUBE_WORK_ROOT: "",
      }),
    ).toBeUndefined();
    expect(stderrSpy).not.toHaveBeenCalled();
  });

  it("falls through an empty new value to a set legacy value", () => {
    const env = { VIDEO_DIGEST_WORK_ROOT: "", YOUTUBE_WORK_ROOT: "/old" };
    expect(resolveEnvWithLegacy("VIDEO_DIGEST_WORK_ROOT", "YOUTUBE_WORK_ROOT", env)).toBe("/old");
  });
});
