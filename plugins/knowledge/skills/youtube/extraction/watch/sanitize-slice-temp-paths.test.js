import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { sanitizeSliceTempPaths } from "./sanitize-slice-temp-paths.js";

describe("sanitizeSliceTempPaths", () => {
  let sliceDir;
  const absFrames = join(tmpdir(), "youtube-frames-xyz");
  const absSheets = join(tmpdir(), "youtube-sheets-xyz");
  const absWork = join(tmpdir(), "youtube-extraction-xyz");

  beforeEach(() => {
    sliceDir = mkdtempSync(join(tmpdir(), "slice-"));
    mkdirSync(join(sliceDir, "run-state"), { recursive: true });
    mkdirSync(join(sliceDir, "key-frames", "contact-sheets"), { recursive: true });

    writeFileSync(
      join(sliceDir, "run-state", "watch.json"),
      `${JSON.stringify({ tempSession: { workDir: absWork, framesDir: absFrames, contactSheetsDir: absSheets } }, null, 2)}\n`,
      "utf8",
    );
    writeFileSync(
      join(sliceDir, "key-frames", "selection.json"),
      `${JSON.stringify(
        {
          tempSession: { framesDir: absFrames, contactSheetsDir: absSheets },
          selectedFrames: [{ path: join(absFrames, "scene_0001.png"), file: "scene_0001.png" }],
          interleavedTimeline: [
            { kind: "frame", frame: { path: join(absFrames, "interval_0001.png"), file: "x" } },
            { kind: "transcript", transcriptText: "hi" },
          ],
        },
        null,
        2,
      )}\n`,
      "utf8",
    );
    writeFileSync(
      join(sliceDir, "key-frames", "contact-sheets", "snapshot-meta.json"),
      `${JSON.stringify({ sheetCount: 2, sourceDir: absSheets }, null, 2)}\n`,
      "utf8",
    );
    writeFileSync(
      join(sliceDir, "run-state", "continuation-prompt.md"),
      [
        "## Temp session",
        "",
        `- Frames temp: \`${absFrames}\``,
        `- Contact sheets temp: \`${absSheets}\``,
        "- Re-run `run-watch.js` if temp paths are missing.",
        "",
        "## Vision pipeline",
        "",
        "- Triage: one subagent per sheet → `key-frames/triage/batches/sheet_NNN.json`",
        "",
      ].join("\n"),
      "utf8",
    );
  });

  afterEach(() => {
    rmSync(sliceDir, { recursive: true, force: true });
  });

  it("tokenizes all four leak shapes (watch.json, selection.json, snapshot-meta.json, continuation-prompt.md)", () => {
    const touched = sanitizeSliceTempPaths(sliceDir);
    expect(touched).toEqual(
      expect.arrayContaining([
        "run-state/watch.json",
        "key-frames/selection.json",
        "key-frames/contact-sheets/snapshot-meta.json",
        "continuation-prompt.md",
      ]),
    );

    // Leak 1 — watch.json tempSession
    const watch = JSON.parse(readFileSync(join(sliceDir, "run-state", "watch.json"), "utf8"));
    expect(watch.tempSession.framesDir).toBe("{tmp}/youtube-frames-xyz");

    // Leak 2 — selection.json interleaved + selected frame paths stripped
    const selection = JSON.parse(
      readFileSync(join(sliceDir, "key-frames", "selection.json"), "utf8"),
    );
    expect(selection.tempSession.framesDir).toBe("{tmp}/youtube-frames-xyz");
    expect(selection.selectedFrames[0].path).toBeUndefined();
    expect(selection.interleavedTimeline[0].frame.path).toBeUndefined();

    // Leak 3 — snapshot-meta.json sourceDir
    const meta = JSON.parse(
      readFileSync(join(sliceDir, "key-frames", "contact-sheets", "snapshot-meta.json"), "utf8"),
    );
    expect(meta.sourceDir).toBe("{tmp}/youtube-sheets-xyz");

    // Leak 4 — continuation-prompt.md temp block, non-temp backtick lines untouched
    const prompt = readFileSync(join(sliceDir, "run-state", "continuation-prompt.md"), "utf8");
    expect(prompt).toContain("- Frames temp: `{tmp}/youtube-frames-xyz`");
    expect(prompt).toContain("- Contact sheets temp: `{tmp}/youtube-sheets-xyz`");
    expect(prompt).not.toContain(absFrames);
    expect(prompt).not.toContain(absSheets);
    expect(prompt).toContain("`key-frames/triage/batches/sheet_NNN.json`");
    expect(prompt).toContain("`run-watch.js`");
  });
});
