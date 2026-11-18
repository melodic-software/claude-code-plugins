import { describe, expect, it, vi } from "vitest";

import { YT_DLP_VIDEO_FORMAT } from "../acquisition/build-yt-dlp-args.js";
import { adapter as youtubeAdapter } from "../adapters/youtube.js";
import {
  buildSizeProbeArgs,
  checkTempSpace,
  estimateStagingBytes,
  formatBytes,
  parseSizeProbe,
  probeMediaSize,
} from "./temp-space-check.js";

const URL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ";
const SEP = String.fromCharCode(0x1f);
const GIB = 1024 ** 3;
const TEMP = "/tmp-under-test";

/**
 * @param {object} overrides
 * @returns {import('@melodic/video-digestion/shared/process').SpawnResult}
 */
function spawnResult(overrides) {
  return { success: false, code: 1, signal: null, stdout: "", stderr: "", timedOut: false, ...overrides };
}

/** @param {{ bytes: number|null, durationSec?: number|null, error?: string }} size */
const probeReturning = (size) => vi.fn(async () => ({ durationSec: null, ...size }));

describe("buildSizeProbeArgs", () => {
  it("selects the watch's own formats without downloading, the URL after the sentinel", () => {
    const args = buildSizeProbeArgs(URL, { env: { VIDEO_DIGEST_YT_DLP_JS_RUNTIMES: "off" } });
    expect(args).toContain("--skip-download");
    expect(args[args.indexOf("-f") + 1]).toBe(YT_DLP_VIDEO_FORMAT);
    expect(args.slice(-2)).toEqual(["--", URL]);
  });
});

describe("parseSizeProbe", () => {
  it("reads the size and duration", () => {
    expect(parseSizeProbe(`\n1054000000${SEP}3000\n`)).toEqual({
      bytes: 1054000000,
      durationSec: 3000,
    });
  });

  it("reads yt-dlp's NA as unknown", () => {
    expect(parseSizeProbe(`NA${SEP}NA`)).toEqual({ bytes: null, durationSec: null });
  });

  it("sums one line per media entry, unknown when any entry has no size", () => {
    expect(parseSizeProbe(`100${SEP}10\n200${SEP}20\n`)).toEqual({ bytes: 300, durationSec: null });
    expect(parseSizeProbe(`100${SEP}10\nNA${SEP}20\n`).bytes).toBeNull();
  });
});

describe("probeMediaSize", () => {
  it("parses a successful probe", async () => {
    const spawn = vi.fn(async () => spawnResult({ success: true, code: 0, stdout: `2048${SEP}60` }));
    expect(await probeMediaSize(URL, youtubeAdapter, { spawn, env: {} })).toEqual({
      bytes: 2048,
      durationSec: 60,
    });
  });

  it("reports a failed probe's first error line", async () => {
    const spawn = vi.fn(async () => spawnResult({ stderr: "ERROR: Video unavailable\nmore" }));
    const size = await probeMediaSize(URL, youtubeAdapter, { spawn, env: {} });
    expect(size).toMatchObject({ bytes: null, error: "ERROR: Video unavailable" });
  });
});

describe("estimateStagingBytes", () => {
  it("doubles the selected formats' size", () => {
    expect(estimateStagingBytes({ bytes: 1000, durationSec: 3000 }, null)).toBe(2000);
  });

  it("scales a ranged run to the range's share of the video", () => {
    const range = { fromSec: 600, toSec: 1200 };
    expect(estimateStagingBytes({ bytes: 1000, durationSec: 3000 }, range)).toBeCloseTo(400);
  });

  it("is unknown without a size, or for a ranged run without a duration", () => {
    expect(estimateStagingBytes({ bytes: null, durationSec: 3000 }, null)).toBeNull();
    expect(estimateStagingBytes({ bytes: GIB, durationSec: null }, { fromSec: 0, toSec: 60 })).toBeNull();
  });
});

describe("formatBytes", () => {
  it("uses binary units", () => {
    expect(formatBytes(512)).toBe("512 B");
    expect(formatBytes(1.5 * GIB)).toBe("1.5 GiB");
  });
});

describe("checkTempSpace", () => {
  const options = { url: URL, adapter: youtubeAdapter, tempDir: TEMP, timeRange: null };

  it("fails naming the temp dir, the space needed and free, and the TMPDIR workaround", async () => {
    const result = await checkTempSpace(options, {
      probe: probeReturning({ bytes: GIB }),
      freeBytes: async () => 1.8 * GIB,
    });
    expect(result.state).toBe("short");
    expect(result.message).toContain(TEMP);
    expect(result.message).toContain("needs about 2.0 GiB");
    expect(result.message).toContain("1.8 GiB free");
    expect(result.message).toContain("TMPDIR");
    expect(result.message).toContain("every later run.mjs call");
  });

  it("passes when the free space covers the estimate", async () => {
    const result = await checkTempSpace(options, {
      probe: probeReturning({ bytes: GIB }),
      freeBytes: async () => 3 * GIB,
    });
    expect(result).toEqual({ state: "enough", message: "" });
  });

  it("warns naming the temp dir when no size is known, without reading free space", async () => {
    const freeBytes = vi.fn(async () => 0);
    const result = await checkTempSpace(options, {
      probe: probeReturning({ bytes: null }),
      freeBytes,
    });
    expect(result.state).toBe("unknown");
    expect(result.message).toMatch(/^WARN: /);
    expect(result.message).toContain(TEMP);
    expect(freeBytes).not.toHaveBeenCalled();
  });

  it("warns when the probe fails or free space cannot be read", async () => {
    const failed = await checkTempSpace(options, {
      probe: probeReturning({ bytes: null, error: "ERROR: Video unavailable" }),
      freeBytes: async () => 0,
    });
    expect(failed.message).toContain("size probe failed: ERROR: Video unavailable");

    const unreadable = await checkTempSpace(options, {
      probe: probeReturning({ bytes: GIB }),
      freeBytes: async () => {
        throw new Error("ENOSYS");
      },
    });
    expect(unreadable).toMatchObject({ state: "unknown" });
    expect(unreadable.message).toContain("free space unreadable: ENOSYS");
  });

  it("probes the adapter's canonical URL", async () => {
    const probe = probeReturning({ bytes: 1 });
    await checkTempSpace(options, { probe, freeBytes: async () => GIB });
    expect(probe).toHaveBeenCalledWith(URL, youtubeAdapter);
  });

  it.each([
    "https://www.youtube.com/playlist?list=PLabcdefghijklmnop",
    "https://www.youtube.com/@somechannel",
  ])("never probes a URL the adapter declines (%s), leaving the refusal to acquisition", async (url) => {
    const probe = probeReturning({ bytes: GIB });
    const freeBytes = vi.fn(async () => 0);
    const result = await checkTempSpace({ ...options, url }, { probe, freeBytes });
    expect(result).toEqual({ state: "enough", message: "" });
    expect(probe).not.toHaveBeenCalled();
    expect(freeBytes).not.toHaveBeenCalled();
  });
});
