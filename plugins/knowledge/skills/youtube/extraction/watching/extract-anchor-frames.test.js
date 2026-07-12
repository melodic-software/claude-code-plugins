import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it, vi } from "vitest";

import {
  anchorFrameFileName,
  extractAnchorFrames,
  formatElapsedMinutes,
} from "./extract-anchor-frames.js";

describe("formatElapsedMinutes", () => {
  it("formats minutes and seconds", () => {
    expect(formatElapsedMinutes(125)).toBe("2m05s");
  });
});

describe("anchorFrameFileName", () => {
  it("encodes timestamp in filename", () => {
    expect(anchorFrameFileName(1, 42.5)).toBe("anchor_00042500_0001.png");
  });
});

describe("extractAnchorFrames heartbeat", () => {
  it("logs progress at interval", async () => {
    const log = { info: vi.fn(), warn: vi.fn() };
    const spawn = vi.fn(async () => ({ success: true }));
    const timestamps = [1, 2, 3, 4, 5];

    const outputDir = fs.mkdtempSync(path.join(os.tmpdir(), "anchor-frames-"));
    await extractAnchorFrames("video.mp4", outputDir, timestamps, {
      spawn,
      heartbeatInterval: 2,
      staleSilenceMs: 0,
      log,
    });

    expect(log.info).toHaveBeenCalled();
    expect(log.info.mock.calls.some((c) => String(c[0]).includes("anchor 1/5"))).toBe(true);
    expect(log.info.mock.calls.some((c) => String(c[0]).includes("anchor 5/5"))).toBe(true);
  });
});
