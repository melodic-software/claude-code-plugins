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

  it("renders no unsubstituted {{ tokens, with or without vision-plan.md", () => {
    const withoutPlan = fs.readFileSync(initWatchChecklist(makeSliceDir(), { force: true }), "utf8");
    expect(withoutPlan).not.toContain("{{");
    expect(withoutPlan).toContain("≥ the deferred floor before phase 6 complete");

    const withPlan = fs.readFileSync(
      initWatchChecklist(
        makeSliceDir({
          visionPlan: "# Plan\n\nClass: `conference-multi-session`\n".padEnd(120, "x"),
        }),
        { force: true },
      ),
      "utf8",
    );
    expect(withPlan).not.toContain("{{");
    expect(withPlan).toContain("≥ 75% before phase 6 complete");
    expect(withPlan).not.toContain("the deferred floor");
  });

  it("--force keeps ticks and Resume notes while refreshing floors and sheet rows", () => {
    const sliceDir = makeSliceDir();
    const outPath = initWatchChecklist(sliceDir, { force: true });
    const ticked = fs
      .readFileSync(outPath, "utf8")
      .replace("- [ ] **0.1**", "- [x] **0.1**")
      .replace("- [ ] **1.6**", "- [x] **1.6**")
      .replace("- [ ] **sheet_002**", "- [x] **sheet_002**")
      .replace(
        "(paste verification evidence as you tick)",
        "0.1 setup-deps exit 0; 1.6 watch.json phases complete",
      );
    fs.writeFileSync(outPath, ticked);

    // The vision plan lands and a fourth sheet appears; the operator re-runs with --force.
    fs.writeFileSync(
      path.join(sliceDir, "key-frames", "vision-plan.md"),
      "# Plan\n\nClass: `conference-multi-session`\n".padEnd(120, "x"),
    );
    fs.writeFileSync(
      path.join(sliceDir, "key-frames", "selection.json"),
      JSON.stringify({
        durationSec: 8 * 3600,
        contactSheets: [{ id: "1" }, { id: "2" }, { id: "3" }, { id: "4" }],
        densificationWindows: [],
        frameSelection: { highVolume: true },
      }),
    );
    const body = fs.readFileSync(initWatchChecklist(sliceDir, { force: true }), "utf8");

    expect(body).toContain("- [x] **0.1**");
    expect(body).toContain("- [x] **1.6**");
    expect(body).toContain("- [x] **sheet_002**");
    expect(body).toContain("- [ ] **0.2**");
    expect(body).toContain("- [ ] **sheet_004**");
    expect(body).toContain("0.1 setup-deps exit 0; 1.6 watch.json phases complete");
    expect(body).not.toContain("(paste verification evidence as you tick)");
    expect(body).toContain("≥40 synthesis frames");
    expect(body).not.toContain("pending `key-frames/vision-plan.md`");
  });

  it("--force keeps indented evidence lines under a ticked row, and only under it", () => {
    const sliceDir = makeSliceDir();
    const outPath = initWatchChecklist(sliceDir, { force: true });
    const withEvidence = fs
      .readFileSync(outPath, "utf8")
      .split("\n")
      .flatMap((line) => {
        if (line.startsWith("- [ ] **0.1**")) {
          return [line.replace("- [ ]", "- [x]"), "  - evidence: setup-deps exit 0"];
        }
        if (line.startsWith("- [ ] **0.2**")) return [line, "  - draft note on an unticked row"];
        return [line];
      })
      .join("\n");
    fs.writeFileSync(outPath, withEvidence);

    const lines = fs.readFileSync(initWatchChecklist(sliceDir, { force: true }), "utf8").split("\n");
    const row = lines.findIndex((line) => line.startsWith("- [x] **0.1**"));

    expect(row).toBeGreaterThan(-1);
    expect(lines[row + 1]).toBe("  - evidence: setup-deps exit 0");
    expect(lines.filter((line) => line === "  - evidence: setup-deps exit 0")).toHaveLength(1);
    expect(lines).not.toContain("  - draft note on an unticked row");
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
