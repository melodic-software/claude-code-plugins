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

describe("renderTriageLog", () => {
  it("populates the Notes column from the canonical `note` field", () => {
    const dir = makeSliceWithTriageManifest();
    const outPath = renderTriageLog(dir);
    const log = fs.readFileSync(outPath, "utf8");
    expect(log).toContain("clear architecture diagram");
  });
});
