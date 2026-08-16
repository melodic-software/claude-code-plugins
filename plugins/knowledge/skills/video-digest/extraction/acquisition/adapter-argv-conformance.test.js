/**
 * End-to-end argv conformance: each adapter's declarations flow through
 * `adapterSourceDeclarations` into the real arg builders, and the built argv
 * carries EXACTLY the flags that adapter declared. The load-bearing negative:
 * YouTube declares no extractor allow-list and no mediaOptional, so no YouTube
 * invocation — acquisition in any mode, or queue preflight — may ever carry
 * `--use-extractors` or `--ignore-no-formats-error`.
 */

import { describe, expect, it } from "vitest";

import { adapter as x } from "../adapters/x.js";
import { adapter as youtube } from "../adapters/youtube.js";
import { adapterSourceDeclarations } from "./acquire.js";
import { buildYtDlpArgs } from "./build-yt-dlp-args.js";
import { buildPreflightArgs } from "./preflight-metadata.js";

const YOUTUBE_URL = "https://www.youtube.com/watch?v=7zZy1QTvokM";
const X_URL = "https://x.com/i/web/status/1720000000000000000";

/** @type {import('./build-yt-dlp-args.js').AcquisitionMode[]} */
const MODES = ["full", "video-only", "transcript", "captions-only"];

/** @param {typeof youtube} adapter @param {string} url */
function buildAllArgv(adapter, url) {
  const source = adapterSourceDeclarations(adapter);
  // Empty env: local cookie/js-runtime settings must not leak into the assertions.
  const env = {};
  return [
    ...MODES.map((mode) => ({
      label: `acquisition ${mode}`,
      args: buildYtDlpArgs(url, { mode, outputTemplate: "/w/%(id)s.%(ext)s", workDir: "/w", env, source }),
    })),
    { label: "preflight", args: buildPreflightArgs(url, { env, source }) },
  ];
}

describe("YouTube argv never carries the X-declared flags", () => {
  it("lacks --use-extractors and --ignore-no-formats-error in every acquisition mode and preflight", () => {
    for (const { label, args } of buildAllArgv(youtube, YOUTUBE_URL)) {
      expect(args, label).not.toContain("--use-extractors");
      expect(args, label).not.toContain("--ignore-no-formats-error");
    }
  });
});

describe("X argv carries its declared allow-list and mediaOptional flag everywhere", () => {
  it("pushes --use-extractors twitter.* and --ignore-no-formats-error in every acquisition mode and preflight", () => {
    for (const { label, args } of buildAllArgv(x, X_URL)) {
      const allowListIndex = args.indexOf("--use-extractors");
      expect(allowListIndex, label).toBeGreaterThan(-1);
      expect(args[allowListIndex + 1], label).toBe("twitter.*");
      expect(args, label).toContain("--ignore-no-formats-error");
      // Comments capability is false — never push the comment download.
      expect(args, label).not.toContain("--write-comments");
    }
  });
});
