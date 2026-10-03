import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { renderTriageLog } from "./render-triage-log.js";

/** @type {string[]} */
const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

function makeSliceWithTriageManifest() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "render-triage-log-"));
  tempDirs.push(dir);
  const triageDir = lanePath(dir, LANES.keyFrames, "triage");
  fs.mkdirSync(triageDir, { recursive: true });
  const manifest = {
    sheetCount: 1,
    sheets: [
      {
        sheetId: "sheet_001",
        cells: [
          {
            cell: "R1C1",
            frame: "frame_001.png",
            verdict: "promote-key-frame",
            note: "clear architecture diagram",
          },
        ],
      },
    ],
  };
  fs.writeFileSync(path.join(triageDir, "manifest.json"), JSON.stringify(manifest, null, 2));
  return dir;
}

/**
 * @param {number|null} timestampSec
 * @param {string} [timestampSource]
 */
function midCell(timestampSec, timestampSource) {
  return {
    cell: "R3C2",
    frame: "scene_0001.png",
    verdict: "skip",
    timestampSec,
    ...(timestampSource ? { timestampSource } : {}),
  };
}

describe("renderTriageLog", () => {
  it("populates the Notes column from the canonical `note` field", () => {
    const dir = makeSliceWithTriageManifest();
    const outPath = renderTriageLog(dir);
    const log = fs.readFileSync(outPath, "utf8");
    expect(log).toContain("clear architecture diagram");
  });

  it("labels each sheet by its middle frame: time 0, estimated, and untimed", () => {
    const dir = makeSliceWithTriageManifest();
    fs.writeFileSync(
      lanePath(dir, LANES.keyFrames, "triage", "manifest.json"),
      JSON.stringify({
        sheets: [
          { sheetId: "sheet_001", cells: [midCell(0, "scene-detection")] },
          { sheetId: "sheet_002", cells: [midCell(300, "estimated")] },
          { sheetId: "sheet_003", cells: [midCell(null)] },
        ],
      }),
    );

    const log = fs.readFileSync(renderTriageLog(dir), "utf8");

    expect(log).toContain("## sheet_001 (~0m)\n");
    expect(log).toContain("## sheet_002 (~5m, estimated)\n");
    expect(log).toContain("## sheet_003 (untimed)\n");
  });
});
