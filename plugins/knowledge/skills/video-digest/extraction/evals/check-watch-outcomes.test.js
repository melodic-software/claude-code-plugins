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

describe("checkWatchOutcomes research gate", () => {
  /**
   * A slice with watch.json and a research lane whose one agenda row has the given status.
   *
   * @param {{ skipResearch?: boolean, agendaStatus: string, findings?: number }} options
   */
  function sliceWithResearch({ skipResearch, agendaStatus, findings = 0 }) {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "watch-outcomes-research-"));
    onTestFinished(() => fs.rmSync(tmp, { recursive: true, force: true }));
    fs.mkdirSync(path.join(tmp, "run-state"), { recursive: true });
    fs.writeFileSync(
      path.join(tmp, "run-state", "watch.json"),
      JSON.stringify(skipResearch === undefined ? {} : { skipResearch }),
    );
    fs.mkdirSync(path.join(tmp, "research", "findings"), { recursive: true });
    fs.writeFileSync(path.join(tmp, "RESEARCH.md"), "R".repeat(250));
    fs.writeFileSync(path.join(tmp, "research", "claim-inventory.md"), "# claims\n");
    fs.writeFileSync(
      path.join(tmp, "research", "research-agenda.md"),
      `| claim | T1 | ${agendaStatus} |\n`,
    );
    for (let i = 0; i < findings; i++) {
      fs.writeFileSync(path.join(tmp, "research", "findings", `finding-${i}.md`), "# f\n");
    }
    return tmp;
  }

  /** @param {string} sliceDir */
  const researchCheck = (sliceDir) =>
    checkWatchOutcomes(sliceDir).checks.find((c) => c.id === "research-complete");

  it("fails as blocking when an agenda row is still pending", () => {
    const check = researchCheck(sliceWithResearch({ agendaStatus: "pending" }));
    expect(check?.pass).toBe(false);
    expect(check?.severity).toBe("fail");
    expect(check?.actual).toContain("1 research-agenda rows still pending");
  });

  it("fails when a done row has no research/findings file", () => {
    const check = researchCheck(sliceWithResearch({ agendaStatus: "done" }));
    expect(check?.pass).toBe(false);
    expect(check?.actual).toContain("research-findings count (0) < done agenda rows (1)");
  });

  it("names a missing research file relative to the slice", () => {
    const sliceDir = sliceWithResearch({ agendaStatus: "done", findings: 1 });
    fs.rmSync(path.join(sliceDir, "research", "research-agenda.md"));
    expect(researchCheck(sliceDir)?.actual).toBe(
      `missing ${path.join("research", "research-agenda.md")}`,
    );
  });

  it("passes when every row is resolved and backed by a finding", () => {
    const check = researchCheck(sliceWithResearch({ agendaStatus: "done", findings: 1 }));
    expect(check?.pass).toBe(true);
  });

  it("does not block a watch that ran with --skip-research", () => {
    const check = researchCheck(sliceWithResearch({ skipResearch: true, agendaStatus: "pending" }));
    expect(check?.pass).toBe(true);
    expect(check?.actual).toBe("skipped (--skip-research)");
  });
});
