import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { forbiddenSynthesisFileNameReason } from "./synthesis-filename.js";
import {
  validatePromotionDecisions,
  validateQualityAudit,
  validateTriageBatchFiles,
  validateTriageSheet,
} from "./watch-vision-validation.js";

const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  tempDirs.length = 0;
});

describe("forbiddenSynthesisFileNameReason", () => {
  it("rejects automated filename patterns", () => {
    expect(forbiddenSynthesisFileNameReason("at-12m30s-anchor.png")).toBeTruthy();
    expect(forbiddenSynthesisFileNameReason("densification-code-0.png")).toBeTruthy();
    expect(forbiddenSynthesisFileNameReason("dens-code-m478.png")).toBeTruthy();
    expect(forbiddenSynthesisFileNameReason("code-code-28134.png")).toBeTruthy();
    expect(forbiddenSynthesisFileNameReason("benchmark-curve-slide-metrics.png")).toBeNull();
  });
});

describe("validateTriageSheet", () => {
  it("requires 16 cells with valid verdicts", () => {
    const sheet = {
      sheetId: "sheet_001",
      reviewedAt: "2026-06-11T00:00:00.000Z",
      cells: Array.from({ length: 16 }, (_, i) => {
        const row = Math.floor(i / 4) + 1;
        const col = (i % 4) + 1;
        return {
          cell: `R${row}C${col}`,
          frame: `anchor_${String(i).padStart(8, "0")}_0001.png`,
          verdict: "skip",
        };
      }),
    };
    expect(validateTriageSheet(sheet)).toEqual([]);
  });
});

describe("validateTriageBatchFiles", () => {
  it("requires a batch JSON file per manifest sheet", () => {
    const sliceDir = fs.mkdtempSync(path.join(os.tmpdir(), "triage-batches-"));
    tempDirs.push(sliceDir);
    const batchesDir = path.join(sliceDir, "key-frames", "triage", "batches");
    fs.mkdirSync(batchesDir, { recursive: true });
    fs.writeFileSync(
      path.join(batchesDir, "sheet_001.json"),
      JSON.stringify({ sheetId: "sheet_001", cells: [] }),
    );
    const manifest = { sheets: [{ sheetId: "sheet_001" }, { sheetId: "sheet_002" }] };
    const errors = validateTriageBatchFiles(sliceDir, manifest);
    expect(errors.some((e) => e.includes("sheet_002"))).toBe(true);
  });
});

describe("validatePromotionDecisions", () => {
  it("requires destName and gapNote for promote", () => {
    const errors = validatePromotionDecisions({
      decisions: [{ sourceFile: "a.png", verdict: "promote" }],
    });
    expect(errors.some((e) => e.includes("destName"))).toBe(true);
    expect(errors.some((e) => e.includes("gapNote"))).toBe(true);
  });

  it("accepts valid promote row", () => {
    const errors = validatePromotionDecisions({
      decisions: [
        {
          sourceFile: "anchor_00010000_0001.png",
          verdict: "promote",
          destName: "demo-ui-slide.png",
          gapNote: "On-screen metrics not in transcript",
          session: "opening",
        },
      ],
    });
    expect(errors).toEqual([]);
  });
});

describe("validateQualityAudit note enforcement", () => {
  const reviewedAt = "2026-01-01T00:00:00.000Z";

  it("rejects a passing row with the note omitted", () => {
    const errors = validateQualityAudit({
      reviewedAt,
      files: [{ name: "demo.png", pass: true }],
    });
    expect(errors).toContain("files[0].note must be substantive (min 20 chars, not stub token)");
  });

  it("rejects a passing row with a stub note", () => {
    const errors = validateQualityAudit({
      reviewedAt,
      files: [{ name: "demo.png", pass: true, note: "ok" }],
    });
    expect(errors).toContain("files[0].note must be substantive (min 20 chars, not stub token)");
  });

  it("accepts a passing row with a substantive note", () => {
    const errors = validateQualityAudit({
      reviewedAt,
      files: [{ name: "demo.png", pass: true, note: "Sharp architecture diagram with legible labels" }],
    });
    expect(errors).toEqual([]);
  });

  it("does not require a note on a failing row", () => {
    const errors = validateQualityAudit({
      reviewedAt,
      files: [{ name: "demo.png", pass: false }],
    });
    expect(errors).toEqual([]);
  });
});
