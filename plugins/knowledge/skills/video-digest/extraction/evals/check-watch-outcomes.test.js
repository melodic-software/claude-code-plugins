import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it, onTestFinished } from "vitest";

import { parseBoundaryLine } from "../lib/watch-slice-sessions.js";
import {
  checkWatchOutcomes,
  countTriageSheetsLogged,
  densificationCoverage,
  outcomeFloors,
  parseMinuteTimestamp,
  parsePromotedTimestampsSec,
} from "./check-watch-outcomes.js";

describe("parseMinuteTimestamp", () => {
  it("parses minute markers", () => {
    expect(parseMinuteTimestamp("~35m")).toBe(2100);
    expect(parseMinuteTimestamp("452m")).toBe(27120);
  });
});

describe("parseBoundaryLine", () => {
  it("parses transcript boundary stamps", () => {
    expect(parseBoundaryLine("[0:57] welcome → [7:58] Diane welcome")).toEqual({
      startSec: 57,
      endSec: 478,
    });
  });
});

describe("outcomeFloors", () => {
  it("requires higher floors for long conferences", () => {
    const floors = outcomeFloors("conference-multi-session", 8 * 3600, 11);
    expect(floors.minSynthesisFrames).toBeGreaterThanOrEqual(44);
    expect(floors.minPerHour).toBe(5);
    expect(floors.minPerSession).toBe(3);
    expect(floors.minSheetTriageRatio).toBe(0.75);
  });
});

describe("countTriageSheetsLogged", () => {
  it("counts sheet sections", () => {
    const body = "## sheet_001\n\n## sheet_002\n";
    expect(countTriageSheetsLogged(body)).toBe(2);
  });
});

describe("densificationCoverage", () => {
  it("counts promoted frames inside windows", () => {
    const result = densificationCoverage({
      windows: [{ startSec: 100, endSec: 200 }],
      promotedTimestampsSec: [150],
      visualGapsBody: "",
    });
    expect(result).toEqual({ covered: 1, total: 1 });
  });

  it("credits a gap row only for its own region, so ~15m never covers region 5", () => {
    const result = densificationCoverage({
      windows: [{ startSec: 300, endSec: 312 }],
      promotedTimestampsSec: [],
      visualGapsBody: "| ~15m (900.0-912.0s) | slide | No synthesis frame in window; transcript-only |",
    });
    expect(result).toEqual({ covered: 0, total: 1 });
  });

  it("credits a gap row with exact bounds for its region", () => {
    const result = densificationCoverage({
      windows: [{ startSec: 300, endSec: 312.4 }],
      promotedTimestampsSec: [],
      visualGapsBody: "| ~5m (300.0-312.4s) | slide | No synthesis frame in window; transcript-only |",
    });
    expect(result).toEqual({ covered: 1, total: 1 });
  });
});

describe("parsePromotedTimestampsSec", () => {
  it("extracts timestamps from visual-frames table", () => {
    const body = "| ~35m | `frames/foo.png` | x |\n| ~82m | bar | y |";
    expect(parsePromotedTimestampsSec(body)).toEqual([2100, 4920]);
  });
});

describe("checkWatchOutcomes warn-only count floors", () => {
  it("assigns warn severity to synthesis count checks", () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "watch-outcomes-"));
    onTestFinished(() => fs.rmSync(tmp, { recursive: true, force: true }));
    fs.mkdirSync(path.join(tmp, "run-state"), { recursive: true });
    fs.writeFileSync(
      path.join(tmp, "run-state", "watch.json"),
      JSON.stringify({ artifactPaths: { contactSheetCount: 0 } }),
    );
    const result = checkWatchOutcomes(tmp);
    const countFloor = result.checks.find((c) => c.id === "synthesis-count-floor");
    const perHour = result.checks.find((c) => c.id === "synthesis-per-hour");
    expect(countFloor?.severity).toBe("warn");
    expect(perHour?.severity).toBe("warn");
  });

  it("does not block overall pass when only count floors fail", () => {
    const checks = [
      { pass: false, severity: "warn", id: "synthesis-count-floor" },
      { pass: false, severity: "warn", id: "synthesis-per-hour" },
      { pass: true, severity: "fail", id: "vision-plan" },
      { pass: true, severity: "fail", id: "quality-audit" },
    ];
    expect(checks.every((c) => c.pass || c.severity === "warn")).toBe(true);
    const withBlocking = [
      ...checks,
      { pass: false, severity: "fail", id: "sheet-triage-coverage" },
    ];
    expect(withBlocking.every((c) => c.pass || c.severity === "warn")).toBe(false);
  });
});

/**
 * A slice with one promoted synthesis frame at 30 s of a 600 s video and the
 * given claim inventory.
 *
 * @param {string} claimInventory
 * @returns {string}
 */
function makeSessionSlice(claimInventory) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "watch-outcomes-sessions-"));
  onTestFinished(() => fs.rmSync(tmp, { recursive: true, force: true }));
  for (const dir of ["run-state", "research", "key-frames/frames"]) {
    fs.mkdirSync(path.join(tmp, dir), { recursive: true });
  }
  fs.writeFileSync(path.join(tmp, "run-state", "watch.json"), JSON.stringify({}));
  fs.writeFileSync(
    path.join(tmp, "key-frames", "selection.json"),
    JSON.stringify({
      durationSec: 600,
      selectedFrames: [{ file: "scene_0001.png", timestampSec: 30 }],
    }),
  );
  fs.writeFileSync(path.join(tmp, "key-frames", "frames", "0001.png"), "");
  fs.writeFileSync(path.join(tmp, "research", "claim-inventory.md"), claimInventory);
  return tmp;
}

/**
 * @param {string} sliceDir
 * @param {string} id
 */
function sessionCheck(sliceDir, id) {
  return checkWatchOutcomes(sliceDir).checks.find((c) => c.id === id);
}

describe("checkWatchOutcomes session gates", () => {
  it("fails both session gates when a table-form inventory parses to no session", () => {
    const slice = makeSessionSlice(
      [
        "# Claim inventory",
        "",
        "## Session segments",
        "",
        "| ID | Window | Topic |",
        "| --- | --- | --- |",
        "| S1 | 0:04-1:33 | Opening |",
        "| S2 | 1:33-9:10 | Main talk |",
        "",
      ].join("\n"),
    );
    for (const id of ["session-visual-coverage", "session-synthesis-depth"]) {
      const check = sessionCheck(slice, id);
      expect(check?.pass).toBe(false);
      expect(check?.severity).toBe("fail");
      expect(check?.actual).toContain("no session parsed");
      expect(check?.actual).toContain("**Boundary:**");
    }
  });

  it("passes when every heading-form session holds a promoted frame", () => {
    const slice = makeSessionSlice("## 1. Opening\n\n**Boundary:** [0:00] start → [5:00] main\n");
    expect(sessionCheck(slice, "session-visual-coverage")?.pass).toBe(true);
    expect(sessionCheck(slice, "session-synthesis-depth")?.pass).toBe(true);
  });

  it("names a heading-form session that holds no promoted frame", () => {
    const slice = makeSessionSlice(
      [
        "## 1. Opening",
        "**Boundary:** [0:00] start → [5:00] main",
        "",
        "## 2. Closing",
        "**Boundary:** [5:00] main → [10:00] end",
        "",
      ].join("\n"),
    );
    const check = sessionCheck(slice, "session-visual-coverage");
    expect(check?.pass).toBe(false);
    expect(check?.actual).toBe("missing: Closing");
  });
});
