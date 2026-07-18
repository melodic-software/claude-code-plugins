import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import {
  detectRecoverableBootstrap,
  formatRecoverCommand,
} from "./detect-recoverable-bootstrap.js";
import { resolveWorkArtifacts } from "./recover-watch-bootstrap.js";

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

  it("accepts an auto-caption-only workDir (*-orig.vtt)", () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "detect-recover-"));
    const workDir = fs.mkdtempSync(path.join(os.tmpdir(), "youtube-extraction-"));
    const framesDir = fs.mkdtempSync(path.join(os.tmpdir(), "youtube-frames-"));
    const sheetsDir = fs.mkdtempSync(path.join(os.tmpdir(), "youtube-sheets-"));

    fs.writeFileSync(path.join(workDir, "video.mp4"), "x");
    fs.writeFileSync(path.join(workDir, "captions.en-orig.vtt"), "WEBVTT\n");
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

    expect(detectRecoverableBootstrap(tmp).recoverable).toBe(true);
  });

  it("is not recoverable when workDir is gone even if frames+sheets survive", () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "detect-recover-"));
    const framesDir = fs.mkdtempSync(path.join(os.tmpdir(), "youtube-frames-"));
    const sheetsDir = fs.mkdtempSync(path.join(os.tmpdir(), "youtube-sheets-"));

    fs.writeFileSync(path.join(framesDir, "anchor_00010000_0001.png"), "x");
    fs.writeFileSync(path.join(sheetsDir, "sheet_001.jpg"), "x");

    fs.mkdirSync(path.join(tmp, "run-state"));
    fs.writeFileSync(
      path.join(tmp, "run-state", "watch.json"),
      JSON.stringify({
        phases: {},
        tempSession: {
          workDir: path.join(os.tmpdir(), "youtube-extraction-gone-9999"),
          framesDir,
          contactSheetsDir: sheetsDir,
        },
      }),
    );

    const result = detectRecoverableBootstrap(tmp);
    expect(result.recoverable).toBe(false);
    expect(formatRecoverCommand(tmp)).toBe("");
  });
});

describe("resolveWorkArtifacts", () => {
  it("resolves an auto-caption-only workDir via the *-orig.vtt fallback", () => {
    const workDir = fs.mkdtempSync(path.join(os.tmpdir(), "youtube-extraction-"));
    fs.writeFileSync(path.join(workDir, "video.mp4"), "x");
    fs.writeFileSync(path.join(workDir, "captions.en-orig.vtt"), "WEBVTT\n");
    fs.writeFileSync(path.join(workDir, "meta.info.json"), "{}");

    const artifacts = resolveWorkArtifacts(workDir);
    expect(artifacts.vttPath.endsWith("captions.en-orig.vtt")).toBe(true);
  });

  it("prefers a cleaned .vtt over the -orig auto-caption when both exist", () => {
    const workDir = fs.mkdtempSync(path.join(os.tmpdir(), "youtube-extraction-"));
    fs.writeFileSync(path.join(workDir, "video.mp4"), "x");
    fs.writeFileSync(path.join(workDir, "captions.en-orig.vtt"), "WEBVTT\n");
    fs.writeFileSync(path.join(workDir, "captions.en.vtt"), "WEBVTT\n");
    fs.writeFileSync(path.join(workDir, "meta.info.json"), "{}");

    expect(resolveWorkArtifacts(workDir).vttPath.endsWith("captions.en.vtt")).toBe(true);
  });
});
