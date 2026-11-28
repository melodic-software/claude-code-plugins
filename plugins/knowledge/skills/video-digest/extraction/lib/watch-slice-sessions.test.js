import { describe, expect, it } from "vitest";

import {
  parseBoundaryLine,
  parseSessionsFromClaimInventory,
  sessionsInTimeRange,
} from "./watch-slice-sessions.js";

describe("parseBoundaryLine", () => {
  it("parses transcript boundary stamps", () => {
    expect(parseBoundaryLine("[0:57] welcome → [7:58] next segment")).toEqual({
      startSec: 57,
      endSec: 478,
    });
  });

  it("parses h:mm:ss stamps, as written from YouTube chapter times", () => {
    expect(parseBoundaryLine("[59:00] a → [1:05:30] b")).toEqual({
      startSec: 3540,
      endSec: 3930,
    });
  });

  it("keeps minutes unbounded in m:ss stamps, as transcripts write them", () => {
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

  it("rejects the whole inventory when one numbered session cannot be parsed", () => {
    const body = `## 1. Opening

**Boundary:** [0:00] start → [10:00] break

## 2. Main talk

**Boundary:** 10:00 → 40:00
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

describe("sessionsInTimeRange", () => {
  const sessions = [
    { name: "Before", startSec: 0, endSec: 3600 },
    { name: "Straddles start", startSec: 3000, endSec: 3900 },
    { name: "Inside", startSec: 3900, endSec: 4500 },
    { name: "After", startSec: 4800, endSec: 6000 },
    { name: "Open end", startSec: 6000, endSec: null },
  ];

  it("keeps every session when the slice has no range", () => {
    expect(sessionsInTimeRange(sessions, undefined)).toEqual(sessions);
  });

  it("keeps the sessions that overlap the range and drops the ones that only touch it", () => {
    const kept = sessionsInTimeRange(sessions, { fromSec: 3600, toSec: 4800 });
    expect(kept.map((s) => s.name)).toEqual(["Straddles start", "Inside"]);
  });

  it("runs an open-ended range and an open-ended session to the end of the video", () => {
    const kept = sessionsInTimeRange(sessions, { fromSec: 5000, toSec: null });
    expect(kept.map((s) => s.name)).toEqual(["After", "Open end"]);
  });
});
