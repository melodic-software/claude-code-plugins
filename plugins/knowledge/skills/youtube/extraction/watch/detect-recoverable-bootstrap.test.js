import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import {
  detectRecoverableBootstrap,
  formatRecoverCommand,
} from "./detect-recoverable-bootstrap.js";

describe("detectRecoverableBootstrap", () => {
  it("returns not recoverable when watching complete", () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "detect-recover-"));
    fs.mkdirSync(path.join(tmp, "key-frames"));
    fs.mkdirSync(path.join(tmp, "run-state"));
    fs.writeFileSync(
      path.join(tmp, "run-state", "watch.json"),
      JSON.stringify({
        phases: { watching: { completedAt: "2026-01-01T00:00:00.000Z" } },
        tempSession: {},
      }),
    );
    fs.writeFileSync(path.join(tmp, "key-frames", "selection.json"), "{}");
    const result = detectRecoverableBootstrap(tmp);
    expect(result.recoverable).toBe(false);
    expect(result.watchingComplete).toBe(true);
  });

  it("detects recoverable temp artifacts", () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "detect-recover-"));
    const workDir = fs.mkdtempSync(path.join(os.tmpdir(), "youtube-extraction-"));
    const framesDir = fs.mkdtempSync(path.join(os.tmpdir(), "youtube-frames-"));
    const sheetsDir = fs.mkdtempSync(path.join(os.tmpdir(), "youtube-sheets-"));

    fs.writeFileSync(path.join(workDir, "video.mp4"), "x");
    fs.writeFileSync(path.join(workDir, "captions.vtt"), "WEBVTT\n");
    fs.writeFileSync(path.join(workDir, "meta.info.json"), "{}");
    fs.writeFileSync(path.join(framesDir, "anchor_00010000_0001.png"), "x");
    fs.writeFileSync(path.join(sheetsDir, "sheet_001.jpg"), "x");

    fs.mkdirSync(path.join(tmp, "run-state"));
    fs.writeFileSync(
      path.join(tmp, "run-state", "watch.json"),
      JSON.stringify({
        phases: {},
        tempSession: { workDir, framesDir, contactSheetsDir: sheetsDir },
      }),
    );

    const result = detectRecoverableBootstrap(tmp);
    expect(result.recoverable).toBe(true);
    expect(formatRecoverCommand(tmp)).toContain("recover-watch-bootstrap.js");
  });
});
