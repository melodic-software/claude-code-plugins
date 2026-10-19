import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { afterEach, describe, expect, it } from "vitest";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { listPromotionCandidates } from "./list-promotion-candidates.js";

/** @type {string[]} */
const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

/**
 * @param {string} sliceDir
 * @param {string} lane
 * @param {string} name
 * @param {string} body
 */
function writeLaneFile(sliceDir, lane, name, body) {
  const filePath = lanePath(sliceDir, lane, name);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, body);
}

function makeSlice() {
  const sliceDir = fs.mkdtempSync(path.join(os.tmpdir(), "promotion-candidates-"));
  tempDirs.push(sliceDir);

  writeLaneFile(
    sliceDir,
    LANES.research,
    "claim-inventory.md",
    [
      "# Claims",
      "",
      "## 1. Intro",
      "**Boundary:** [0:00] intro → [1:00] main",
      "",
      "## 2. Main",
      "**Boundary:** [1:00] main → [3:00] end",
      "",
    ].join("\n"),
  );
  writeLaneFile(
    sliceDir,
    LANES.keyFrames,
    "selection.json",
    JSON.stringify({
      durationSec: 180,
      selectedFrames: [
        { file: "scene_0001.png", timestampSec: 20, priorityScore: 1 },
        { file: "scene_0002.png", timestampSec: 90, priorityScore: 1 },
        { file: "scene_0003.png", timestampSec: null, priorityScore: 1 },
        { file: "scene_0004.png", timestampSec: 30, priorityScore: 1 },
        { file: "interval_0001.png", timestampSec: null, priorityScore: 9 },
      ],
    }),
  );
  writeLaneFile(
    sliceDir,
    LANES.keyFrames,
    "triage/manifest.json",
    JSON.stringify({
      sheets: [
        {
          sheetId: "sheet_001",
          cells: [
            { cell: "R1C1", frame: "scene_0002.png", verdict: "promote-key-frame" },
            { cell: "R1C2", frame: "scene_0003.png", verdict: "promote-key-frame" },
            { cell: "R1C3", frame: "scene_0001.png", verdict: "keep-detail" },
          ],
        },
      ],
    }),
  );
  return sliceDir;
}

describe("listPromotionCandidates", () => {
  it("orders candidates by real time with untimed frames last, never as time 0", () => {
    const candidates = listPromotionCandidates(makeSlice());

    expect(candidates.map((c) => [c.sourceFile, c.timestampSec, c.session])).toEqual([
      ["scene_0001.png", 20, "Intro"],
      ["scene_0004.png", 30, "Intro"],
      ["scene_0002.png", 90, "Main"],
      ["scene_0003.png", null, "unknown"],
    ]);
  });

  it("throws naming the session format when the inventory parses to no session", () => {
    const sliceDir = makeSlice();
    writeLaneFile(
      sliceDir,
      LANES.research,
      "claim-inventory.md",
      "## Session segments\n\n| ID | Window |\n| --- | --- |\n| S1 | 0:00-1:00 |\n",
    );
    expect(() => listPromotionCandidates(sliceDir)).toThrow(/no session parsed.*\*\*Boundary:\*\*/s);
  });
});

describe("list-promotion-candidates CLI", () => {
  const script = fileURLToPath(new URL("./list-promotion-candidates.js", import.meta.url));

  /** @param {string} sliceDir */
  function runCli(sliceDir) {
    return spawnSync(process.execPath, [script, sliceDir], { encoding: "utf8" });
  }

  it("prints the message and format hint without a stack trace and exits 1 on a zero-session inventory", () => {
    const sliceDir = makeSlice();
    writeLaneFile(
      sliceDir,
      LANES.research,
      "claim-inventory.md",
      "## Session segments\n\n| ID | Window |\n| --- | --- |\n| S1 | 0:00-1:00 |\n",
    );

    const result = runCli(sliceDir);

    expect(result.status).toBe(1);
    expect(result.stderr).toMatch(/no session parsed.*\*\*Boundary:\*\*/s);
    expect(result.stderr).not.toMatch(/\n\s+at /);
    expect(result.stderr).not.toContain("node:internal");
    expect(result.stderr.trim().split("\n")).toHaveLength(1);
    expect(result.stdout).toBe("");
  });

  it("exits 1 without a stack trace when the claim inventory is missing", () => {
    const sliceDir = makeSlice();
    fs.rmSync(lanePath(sliceDir, LANES.research, "claim-inventory.md"));

    const result = runCli(sliceDir);

    expect(result.status).toBe(1);
    expect(result.stderr).toContain("claim-inventory.md");
    expect(result.stderr).not.toMatch(/\n\s+at /);
    expect(result.stderr).not.toContain("node:internal");
  });
});
