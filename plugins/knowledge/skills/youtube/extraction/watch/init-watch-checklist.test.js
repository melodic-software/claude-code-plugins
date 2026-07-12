import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { buildSheetCheckboxes, formatSheetId, initWatchChecklist } from "./init-watch-checklist.js";

const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  tempDirs.length = 0;
});

function makeSliceDir(overrides = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "watch-checklist-"));
  tempDirs.push(dir);

  const watch = {
    phases: { watching: { metrics: { durationSec: 8 * 3600, highVolume: true } } },
    artifactPaths: { contactSheetCount: 3 },
    ...overrides.watch,
  };
  fs.mkdirSync(path.join(dir, "run-state"), { recursive: true });
  fs.writeFileSync(path.join(dir, "run-state", "watch.json"), JSON.stringify(watch));

  const selection = {
    durationSec: 8 * 3600,
    contactSheets: [{ id: "1" }, { id: "2" }, { id: "3" }],
    densificationWindows: [
      { startSec: 0, endSec: 60 },
      { startSec: 100, endSec: 200 },
    ],
    frameSelection: { highVolume: true },
    ...overrides.selection,
  };
  fs.mkdirSync(path.join(dir, "key-frames"), { recursive: true });
  fs.writeFileSync(path.join(dir, "key-frames", "selection.json"), JSON.stringify(selection));

  if (overrides.visionPlan) {
    fs.writeFileSync(path.join(dir, "key-frames", "vision-plan.md"), overrides.visionPlan);
  }

  return dir;
}

describe("formatSheetId", () => {
  it("zero-pads sheet ids", () => {
    expect(formatSheetId(1)).toBe("001");
    expect(formatSheetId(48)).toBe("048");
  });
});

describe("buildSheetCheckboxes", () => {
  it("emits one row per sheet", () => {
    const body = buildSheetCheckboxes(2);
    expect(body).toContain("sheet_001");
    expect(body).toContain("sheet_002");
    expect(body.split("\n")).toHaveLength(2);
  });
});

describe("initWatchChecklist", () => {
  it("writes checklist with floors and per-sheet rows", () => {
    const sliceDir = makeSliceDir({
      visionPlan: "# Plan\n\nClass: `conference-multi-session`\n".padEnd(120, "x"),
    });
    const outPath = initWatchChecklist(sliceDir, { force: true });
    const body = fs.readFileSync(outPath, "utf8");

    expect(body).toContain(path.basename(sliceDir));
    expect(body).toContain("conference-multi-session");
    expect(body).toContain("sheet_001");
    expect(body).toContain("sheet_003");
    expect(body).toContain("key-frames/triage/batches/sheet_001.json");
    expect(body).toContain("≥40 synthesis frames");
    expect(body).toContain("highVolume=true");
  });

  it("defers the floors/class header when vision-plan.md is absent", () => {
    const sliceDir = makeSliceDir();
    const outPath = initWatchChecklist(sliceDir, { force: true });
    const body = fs.readFileSync(outPath, "utf8");

    // Post-bootstrap, vision-plan.md does not exist yet: do not leak the literal
    // "TBD — set in vision-plan.md" placeholder into the content-class span, and do
    // not emit fabricated numeric floors. Defer with a clear pending note instead.
    expect(body).not.toContain("TBD — set in vision-plan.md");
    expect(body).toContain("pending `key-frames/vision-plan.md`");
    // Per-sheet rows + signals still materialize (they come from watch.json, not vision-plan).
    expect(body).toContain("sheet_001");
    expect(body).toContain("highVolume=true");
  });

  it("fills the floors/class header once vision-plan.md exists", () => {
    const sliceDir = makeSliceDir({
      visionPlan: "# Plan\n\nClass: `conference-multi-session`\n".padEnd(120, "x"),
    });
    const outPath = initWatchChecklist(sliceDir, { force: true });
    const body = fs.readFileSync(outPath, "utf8");

    expect(body).toContain("conference-multi-session");
    expect(body).toContain("≥40 synthesis frames");
    expect(body).not.toContain("pending `key-frames/vision-plan.md`");
  });

  it("skips when checklist exists without force", () => {
    const sliceDir = makeSliceDir();
    initWatchChecklist(sliceDir, { force: true });
    fs.writeFileSync(path.join(sliceDir, "run-state", "watch-checklist.md"), "stale");
    initWatchChecklist(sliceDir);
    expect(fs.readFileSync(path.join(sliceDir, "run-state", "watch-checklist.md"), "utf8")).toBe(
      "stale",
    );
  });
});
