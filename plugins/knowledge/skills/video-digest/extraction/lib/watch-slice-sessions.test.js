import { describe, expect, it } from "vitest";

import { parseBoundaryLine, parseSessionsFromClaimInventory } from "./watch-slice-sessions.js";

describe("parseBoundaryLine", () => {
  it("parses transcript boundary stamps", () => {
    expect(parseBoundaryLine("[0:57] welcome → [7:58] next segment")).toEqual({
      startSec: 57,
      endSec: 478,
    });
  });

  it("parses h:mm:ss stamps, as written from YouTube chapter times", () => {
    // 59:00 = 3540 s; 1:05:30 = 3600 + 300 + 30 = 3930 s
    expect(parseBoundaryLine("[59:00] a → [1:05:30] b")).toEqual({
      startSec: 3540,
      endSec: 3930,
    });
  });

  it("keeps minutes unbounded in m:ss stamps, as transcripts write them", () => {
    // 75:30 = 4500 + 30 = 4530 s
    expect(parseBoundaryLine("[75:30] a")).toEqual({ startSec: 4530, endSec: null });
  });
});

describe("parseSessionsFromClaimInventory", () => {
  it("extracts session segments from claim inventory markdown", () => {
    const body = `## 1. Opening segment

**Boundary:** [0:00] start → [10:00] break

| ID | Claim | Timestamp |
| --- | --- | --- |
`;
    const sessions = parseSessionsFromClaimInventory(body);
    expect(sessions).toHaveLength(1);
    expect(sessions[0].name).toBe("Opening segment");
    expect(sessions[0].startSec).toBe(0);
    expect(sessions[0].endSec).toBe(600);
  });

  it("parses no session from a table-form inventory", () => {
    const body = `## Session segments

| ID | Window | Topic |
| --- | --- | --- |
| S1 | 0:04-1:33 | Opening |
| S2 | 1:33-9:10 | Main talk |
`;
    expect(parseSessionsFromClaimInventory(body)).toEqual([]);
  });

  it("parses no session from a heading whose boundary has no bracketed stamp", () => {
    const body = `## 1. Opening

**Boundary:** 0:04 → 1:33
`;
    expect(parseSessionsFromClaimInventory(body)).toEqual([]);
  });
});
