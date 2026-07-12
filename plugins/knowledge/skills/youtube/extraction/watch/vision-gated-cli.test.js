import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { CELL_IDS } from "../lib/watch-vision-validation.js";
import { listPromotionCandidates } from "./list-promotion-candidates.js";
import { mergeTriageJson } from "./merge-triage-json.js";
import { renderKeyFramesManifest } from "./render-key-frames-manifest.js";
import { renderQualityAudit } from "./render-quality-audit.js";
import { renderTriageLog } from "./render-triage-log.js";
import { runValidatePromotionDecisions } from "./validate-promotion-decisions.js";
import { runValidateTriageJson } from "./validate-triage-json.js";
import { visionGatedPromote } from "./vision-gated-promote.js";

const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  tempDirs.length = 0;
});

/**
 * @param {{ invalidTriage?: boolean, forbiddenDest?: boolean }} [options]
 */
function makeVisionSliceDir(options = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vision-gated-cli-"));
  const framesDir = fs.mkdtempSync(path.join(os.tmpdir(), "vision-frames-"));
  tempDirs.push(dir, framesDir);

  const sourceFile = "anchor_00000000_0001.png";
  fs.writeFileSync(path.join(framesDir, sourceFile), "fake-png");

  const selectedFrames = CELL_IDS.map((_, index) => ({
    file: `anchor_${String(index).padStart(8, "0")}_0001.png`,
    timestampSec: 60 + index * 10,
    priorityScore: index === 0 ? 8 : 1,
    textDense: index === 0,
    likelyDuplicate: false,
  }));

  for (const frame of selectedFrames) {
    if (!fs.existsSync(path.join(framesDir, frame.file))) {
      fs.writeFileSync(path.join(framesDir, frame.file), "fake-png");
    }
  }

  const inputFiles = selectedFrames.map((frame) => frame.file);
  const contactSheets = [
    {
      file: path.join(os.tmpdir(), "sheet_001.jpg"),
      path: path.join(os.tmpdir(), "sheet_001.jpg"),
      inputFiles,
    },
  ];

  const tempSession = { framesDir, contactSheetsDir: os.tmpdir() };
  const watch = { tempSession };
  const selection = {
    durationSec: 600,
    tempSession,
    selectedFrames,
    contactSheets,
    densificationWindows: [],
  };

  fs.mkdirSync(path.join(dir, "run-state"), { recursive: true });
  fs.mkdirSync(path.join(dir, "key-frames"), { recursive: true });
  fs.writeFileSync(path.join(dir, "run-state", "watch.json"), JSON.stringify(watch));
  fs.writeFileSync(path.join(dir, "key-frames", "selection.json"), JSON.stringify(selection));

  fs.mkdirSync(path.join(dir, "research"), { recursive: true });
  fs.writeFileSync(
    path.join(dir, "research", "claim-inventory.md"),
    "[0:00] intro → [10:00] session one\n",
  );

  const cells = CELL_IDS.map((cell, index) => ({
    cell,
    frame: selectedFrames[index].file,
    verdict: index === 0 ? "promote-key-frame" : "skip",
    note: "",
    ...(index === 8 ? { timestampSec: selectedFrames[8].timestampSec } : {}),
  }));

  const sheet = {
    sheetId: "sheet_001",
    reviewedAt: "2026-06-11T00:00:00.000Z",
    model: "composer-2.5",
    cells: options.invalidTriage ? cells.slice(0, 4) : cells,
  };

  const manifest = { sheetCount: 1, sheets: [sheet] };
  const batchesDir = path.join(dir, "key-frames", "triage", "batches");
  fs.mkdirSync(batchesDir, { recursive: true });
  fs.writeFileSync(path.join(batchesDir, "sheet_001.json"), JSON.stringify(sheet, null, 2));
  fs.mkdirSync(path.join(dir, "key-frames", "triage"), { recursive: true });
  fs.writeFileSync(
    path.join(dir, "key-frames", "triage", "manifest.json"),
    JSON.stringify(manifest, null, 2),
  );

  fs.writeFileSync(
    path.join(dir, "key-frames", "sheet-frame-index.json"),
    JSON.stringify(
      {
        sheets: [
          {
            sheetId: "sheet_001",
            cells: cells.map((cell) => ({ cell: cell.cell, frame: cell.frame })),
          },
        ],
      },
      null,
      2,
    ),
  );

  const destName = options.forbiddenDest ? "at-12m30s-slide.png" : "demo-slide.png";
  fs.writeFileSync(
    path.join(dir, "key-frames", "promotion-decisions.json"),
    JSON.stringify(
      {
        decisions: [
          {
            sourceFile,
            verdict: "promote",
            destName,
            gapNote: "unique diagram on slide",
            session: "session one",
          },
        ],
      },
      null,
      2,
    ),
  );

  fs.writeFileSync(
    path.join(dir, "key-frames", "key-frame-quality-audit.json"),
    JSON.stringify(
      {
        reviewedAt: "2026-06-11T00:00:00.000Z",
        files: [{ name: destName, pass: true, note: "sharp slide, legible text, no occlusion" }],
      },
      null,
      2,
    ),
  );

  return { dir, framesDir, sourceFile, destName };
}

describe("runValidateTriageJson", () => {
  it("exits 0 for a valid manifest", () => {
    const { dir } = makeVisionSliceDir();
    expect(runValidateTriageJson(dir)).toBe(0);
  });

  it("exits 1 for an invalid manifest", () => {
    const { dir } = makeVisionSliceDir({ invalidTriage: true });
    expect(runValidateTriageJson(dir)).toBe(1);
  });
});

describe("runValidatePromotionDecisions", () => {
  it("exits 0 for valid decisions", () => {
    const { dir } = makeVisionSliceDir();
    expect(runValidatePromotionDecisions(dir)).toBe(0);
  });

  it("exits 1 when decisions file is missing", () => {
    const { dir } = makeVisionSliceDir();
    fs.unlinkSync(path.join(dir, "key-frames", "promotion-decisions.json"));
    expect(runValidatePromotionDecisions(dir)).toBe(1);
  });
});

describe("visionGatedPromote", () => {
  it("dry-run returns planned promotions", async () => {
    const { dir } = makeVisionSliceDir();
    const result = await visionGatedPromote(dir, { dryRun: true });
    expect(result.promoted).toContain("frames/demo-slide.png");
  });

  it("rejects forbidden destination names", async () => {
    const { dir } = makeVisionSliceDir({ forbiddenDest: true });
    await expect(visionGatedPromote(dir, { dryRun: true })).rejects.toThrow(/forbidden/);
  });

  it("copies frames and writes promotion-map.json", async () => {
    const { dir } = makeVisionSliceDir();
    const result = await visionGatedPromote(dir);
    expect(result.promoted).toContain("demo-slide.png");
    expect(fs.existsSync(path.join(dir, "key-frames", "promotion-map.json"))).toBe(true);
    expect(fs.existsSync(path.join(dir, "key-frames", "frames", "demo-slide.png"))).toBe(true);
  });
});

describe("mergeTriageJson", () => {
  it("merges batch files into manifest.json", () => {
    const { dir } = makeVisionSliceDir();
    const batchesDir = path.join(dir, "key-frames", "triage", "batches");
    fs.mkdirSync(batchesDir, { recursive: true });
    const batchPath = path.join(batchesDir, "sheet_001.json");
    const sheet = JSON.parse(
      fs.readFileSync(path.join(dir, "key-frames", "triage", "manifest.json"), "utf8"),
    ).sheets[0];
    fs.writeFileSync(batchPath, JSON.stringify(sheet));

    const manifestPath = mergeTriageJson(dir, [batchPath]);
    expect(manifestPath).toContain("manifest.json");
    const merged = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    expect(merged.sheets).toHaveLength(1);
  });
});

describe("renderTriageLog", () => {
  it("writes frame-triage-log.md from manifest", () => {
    const { dir } = makeVisionSliceDir();
    const outPath = renderTriageLog(dir);
    expect(outPath).toContain("frame-triage-log.md");
    expect(fs.readFileSync(outPath, "utf8")).toContain("sheet_001");
  });
});

describe("renderKeyFramesManifest", () => {
  it("writes key-frames-manifest.md", () => {
    const { dir } = makeVisionSliceDir();
    const outPath = renderKeyFramesManifest(dir);
    expect(outPath).toContain("key-frames-manifest.md");
    expect(fs.readFileSync(outPath, "utf8")).toContain("demo-slide.png");
  });
});

describe("renderQualityAudit", () => {
  it("writes key-frame-quality-audit.md", () => {
    const { dir } = makeVisionSliceDir();
    const outPath = renderQualityAudit(dir);
    expect(fs.readFileSync(outPath, "utf8")).toContain("demo-slide.png");
  });
});

describe("listPromotionCandidates", () => {
  it("lists triage promote-key-frame cells", () => {
    const { dir } = makeVisionSliceDir();
    const candidates = listPromotionCandidates(dir);
    expect(candidates.length).toBeGreaterThan(0);
    expect(candidates[0].sourceFile).toMatch(/^anchor_/);
  });
});
