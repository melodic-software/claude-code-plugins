import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterAll, describe, expect, it, vi } from "vitest";

import {
  detectRecoverableBootstrap,
  formatRecoverCommand,
} from "./detect-recoverable-bootstrap.js";
import { resolveWorkArtifacts } from "./recover-watch-bootstrap.js";

const tmpDirs = [];
afterAll(() => {
  for (const dir of tmpDirs) fs.rmSync(dir, { recursive: true, force: true });
});

function mkTmp(prefix) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  tmpDirs.push(dir);
  return dir;
}

/**
 * A fresh temp workDir holding the mp4/vtt/info.json trio recovery requires.
 *
 * @param {string} vttName
 * @returns {string}
 */
function makeWorkDir(vttName) {
  const workDir = mkTmp("video-extraction-");
  fs.writeFileSync(path.join(workDir, "video.mp4"), "x");
  fs.writeFileSync(path.join(workDir, vttName), "WEBVTT\n");
  fs.writeFileSync(path.join(workDir, "meta.info.json"), "{}");
  return workDir;
}

/** Fresh temp frames + contact-sheets dirs, one surviving artifact each. */
function makeFrameAndSheetDirs() {
  const framesDir = mkTmp("video-frames-");
  const sheetsDir = mkTmp("video-sheets-");
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
  const tmp = mkTmp("detect-recover-");
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

  it("names the launcher by absolute path and passes the plugin's own data dir", () => {
    const { framesDir, sheetsDir } = makeFrameAndSheetDirs();
    const tmp = makeSliceDir({
      phases: {},
      tempSession: { workDir: makeWorkDir("captions.vtt"), framesDir, contactSheetsDir: sheetsDir },
    });
    const knowledgeData = "/home/u/.claude/plugins/data/knowledge-melodic-software";

    vi.stubEnv("CLAUDE_PLUGIN_DATA", knowledgeData);
    try {
      const match = /^node "([^"]+)" --data-dir "([^"]+)" watch\/recover-watch-bootstrap\.js /.exec(
        formatRecoverCommand(tmp),
      );
      expect(match).not.toBeNull();
      const [, launcher, dataDir] = /** @type {RegExpExecArray} */ (match);
      expect(path.isAbsolute(launcher)).toBe(true);
      expect(launcher.endsWith("/skills/video-digest/extraction/run.mjs")).toBe(true);
      expect(fs.existsSync(launcher)).toBe(true);
      expect(dataDir).toBe(knowledgeData);
      vi.stubEnv("CLAUDE_PLUGIN_DATA", "/home/u/.claude/plugins/data/codex-openai-codex");
      expect(formatRecoverCommand(tmp)).not.toContain("--data-dir");
      expect(formatRecoverCommand(tmp)).not.toContain("codex-openai-codex");
    } finally {
      vi.unstubAllEnvs();
    }
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

describe("run.mjs hands its child only the resolved data dir", () => {
  const launcher = path.join(import.meta.dirname, "..", "run.mjs");
  const codex = "/home/u/.claude/plugins/data/codex-openai-codex";

  /** The recover command the CLI prints when run through the launcher with these args. */
  function recoverCommandVia(launcherArgs) {
    const { framesDir, sheetsDir } = makeFrameAndSheetDirs();
    const slice = makeSliceDir({
      phases: {},
      tempSession: { workDir: makeWorkDir("captions.vtt"), framesDir, contactSheetsDir: sheetsDir },
    });
    const result = spawnSync(
      process.execPath,
      [launcher, ...launcherArgs, "watch/detect-recoverable-bootstrap.js", slice, "--json"],
      { encoding: "utf8", timeout: 20000, env: { ...process.env, CLAUDE_PLUGIN_DATA: codex } },
    );
    expect(result.status, result.stderr).toBe(0);
    return JSON.parse(result.stdout).recoverCommand;
  }

  it("replaces an inherited value naming another plugin with the --data-dir value", () => {
    const knowledge = "/home/u/.claude/plugins/data/knowledge-melodic-software";
    const command = recoverCommandVia(["--data-dir", knowledge]);
    expect(command).toContain(`--data-dir "${knowledge}"`);
    expect(command).not.toContain("codex-openai-codex");
  });

  it("never passes on an inherited value naming another plugin when no flag is given", () => {
    const command = recoverCommandVia([]);
    expect(command).not.toContain("--data-dir");
    expect(command).not.toContain("codex-openai-codex");
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
