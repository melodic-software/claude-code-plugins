import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { checkWatchOutcomes } from "./check-watch-outcomes.js";

const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  tempDirs.length = 0;
});

/**
 * Build a synthetic slice in the 6-lane layout, writing each artifact through the
 * lane registry so the fixture's directory shape is exactly what the writers produce.
 * Proves the lane-layout contract (writers + the outcome gate agree on lane paths)
 * network-free — Phase 5's live watch is then confirmation, not the sole proof.
 *
 * @returns {string} slice dir
 */
function makeSixLaneSlice() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "six-lane-"));
  tempDirs.push(dir);

  const write = (lane, file, body) => {
    const target = lanePath(dir, lane, file);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, body);
  };

  // run-state lane
  write(
    LANES.runState,
    "watch.json",
    JSON.stringify({ status: "complete", artifactPaths: { contactSheetCount: 1 } }),
  );
  // source lane
  write(LANES.source, "transcript.txt", "[0:00] intro\n");
  // research lane
  write(LANES.research, "claim-inventory.md", "[0:00] intro → [10:00] session one\n");
  // key-frames lane
  write(LANES.keyFrames, "vision-plan.md", "Class: `single-talk`\n".padEnd(120, "x"));
  write(
    LANES.keyFrames,
    "selection.json",
    JSON.stringify({
      durationSec: 600,
      selectedFrames: [],
      contactSheets: [{}],
      densificationWindows: [],
    }),
  );
  // recommendations lane
  write(LANES.recommendations, "README.md", "# hub\n");

  return dir;
}

describe("check-watch-outcomes 6-lane layout contract", () => {
  it("reads every artifact from its concern lane (no context/ watching/ .bootstrap/)", () => {
    const dir = makeSixLaneSlice();
    const result = checkWatchOutcomes(dir);

    // The gate found watch.json in run-state/. A gate still reading the OLD root/`context/`
    // location would null the slice and emit a single `watch-json: missing` FAIL — so its
    // ABSENCE proves the run-state lane read works (non-vacuous: it goes present→absent).
    const watchJsonFail = result.checks.find((c) => c.id === "watch-json");
    expect(watchJsonFail).toBeUndefined();

    // Vision-plan was read from key-frames/ — content class detected, not the unknown fallback.
    const visionPlan = result.checks.find((c) => c.id === "vision-plan");
    expect(visionPlan?.pass).toBe(true);

    // Claim-inventory was read from research/ (gate populated its check from the new lane).
    const claimInventory = result.checks.find((c) => c.id === "claim-inventory");
    expect(claimInventory?.pass).toBe(true);

    // No legacy lane directories were created by the layout.
    expect(fs.existsSync(path.join(dir, "context"))).toBe(false);
    expect(fs.existsSync(path.join(dir, "watching"))).toBe(false);
    expect(fs.existsSync(path.join(dir, ".bootstrap"))).toBe(false);
    expect(fs.existsSync(path.join(dir, "media"))).toBe(false);
  });
});
