import { describe, expect, it } from "vitest";

import { parseBoundaryLine, parseSessionsFromClaimInventory } from "./watch-slice-sessions.js";

describe("parseBoundaryLine", () => {
  it("parses transcript boundary stamps", () => {
    expect(parseBoundaryLine("[0:57] welcome → [7:58] next segment")).toEqual({
      startSec: 57,
      endSec: 478,
    });
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
});
