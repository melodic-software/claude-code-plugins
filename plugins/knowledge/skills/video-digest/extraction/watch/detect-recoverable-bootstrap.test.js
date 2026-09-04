import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import {
  detectRecoverableBootstrap,
  formatRecoverCommand,
} from "./detect-recoverable-bootstrap.js";
import { resolveWorkArtifacts } from "./recover-watch-bootstrap.js";

/**
 * A fresh temp workDir holding the mp4/vtt/info.json trio recovery requires.
 *
 * @param {string} vttName
 * @returns {string}
 */
function makeWorkDir(vttName) {
  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), "video-extraction-"));
  fs.writeFileSync(path.join(workDir, "video.mp4"), "x");
  fs.writeFileSync(path.join(workDir, vttName), "WEBVTT\n");
  fs.writeFileSync(path.join(workDir, "meta.info.json"), "{}");
  return workDir;
}

/** Fresh temp frames + contact-sheets dirs, one surviving artifact each. */
function makeFrameAndSheetDirs() {
  const framesDir = fs.mkdtempSync(path.join(os.tmpdir(), "video-frames-"));
  const sheetsDir = fs.mkdtempSync(path.join(os.tmpdir(), "video-sheets-"));
  fs.writeFileSync(path.join(framesDir, "anchor_00010000_0001.png"), "x");
  fs.writeFileSync(path.join(sheetsDir, "sheet_001.jpg"), "x");
  return { framesDir, sheetsDir };
}

/**
 * A fresh temp slice dir whose run-state/watch.json carries the given state.
 *
 * @param {object} watchState
 * @returns {string}
 */
function makeSliceDir(watchState) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "detect-recover-"));
  fs.mkdirSync(path.join(tmp, "run-state"));
  fs.writeFileSync(path.join(tmp, "run-state", "watch.json"), JSON.stringify(watchState));
  return tmp;
}

describe("detectRecoverableBootstrap", () => {
  it("returns not recoverable when watching complete", () => {
    const tmp = makeSliceDir({
      phases: { watching: { completedAt: "2026-01-01T00:00:00.000Z" } },
      tempSession: {},
    });
    fs.mkdirSync(path.join(tmp, "key-frames"));
    fs.writeFileSync(path.join(tmp, "key-frames", "selection.json"), "{}");
    const result = detectRecoverableBootstrap(tmp);
    expect(result.recoverable).toBe(false);
    expect(result.watchingComplete).toBe(true);
  });

  it("detects recoverable temp artifacts", () => {
    const { framesDir, sheetsDir } = makeFrameAndSheetDirs();
    const tmp = makeSliceDir({
      phases: {},
      tempSession: { workDir: makeWorkDir("captions.vtt"), framesDir, contactSheetsDir: sheetsDir },
    });

    const result = detectRecoverableBootstrap(tmp);
    expect(result.recoverable).toBe(true);
    expect(formatRecoverCommand(tmp)).toContain("recover-watch-bootstrap.js");
    expect(formatRecoverCommand(tmp)).toContain("skills/video-digest/extraction/run.mjs");
    expect(formatRecoverCommand(tmp)).not.toContain("youtube-digest");
  });

  it("accepts an auto-caption-only workDir (*-orig.vtt)", () => {
    const { framesDir, sheetsDir } = makeFrameAndSheetDirs();
    const tmp = makeSliceDir({
      phases: {},
      tempSession: {
        workDir: makeWorkDir("captions.en-orig.vtt"),
        framesDir,
        contactSheetsDir: sheetsDir,
      },
    });

    expect(detectRecoverableBootstrap(tmp).recoverable).toBe(true);
  });

  it("is not recoverable when workDir is gone even if frames+sheets survive", () => {
    const { framesDir, sheetsDir } = makeFrameAndSheetDirs();
    const tmp = makeSliceDir({
      phases: {},
      tempSession: {
        workDir: path.join(os.tmpdir(), "video-extraction-gone-9999"),
        framesDir,
        contactSheetsDir: sheetsDir,
      },
    });

    const result = detectRecoverableBootstrap(tmp);
    expect(result.recoverable).toBe(false);
    expect(formatRecoverCommand(tmp)).toBe("");
  });
});

describe("resolveWorkArtifacts", () => {
  it("resolves an auto-caption-only workDir via the *-orig.vtt fallback", () => {
    const artifacts = resolveWorkArtifacts(makeWorkDir("captions.en-orig.vtt"));
    expect(artifacts.vttPath.endsWith("captions.en-orig.vtt")).toBe(true);
  });

  it("prefers a cleaned .vtt over the -orig auto-caption when both exist", () => {
    const workDir = makeWorkDir("captions.en-orig.vtt");
    fs.writeFileSync(path.join(workDir, "captions.en.vtt"), "WEBVTT\n");

    expect(resolveWorkArtifacts(workDir).vttPath.endsWith("captions.en.vtt")).toBe(true);
  });
});
