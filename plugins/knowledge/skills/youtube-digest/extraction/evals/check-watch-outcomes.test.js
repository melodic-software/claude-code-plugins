import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

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
      durationSec: 3600,
      windows: [{ startSec: 100, endSec: 200 }],
      promotedTimestampsSec: [150],
      visualGapsBody: "",
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
