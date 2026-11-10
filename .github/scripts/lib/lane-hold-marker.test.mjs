import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { markLaneHold } from "./lane-hold-marker.mjs";
import { markLaneHold as reportOutcomeMark } from "../work-resolve-issue/report-outcome.mjs";

// report-outcome.mjs keeps its own copy, so both are held to the same contract.
for (const [name, mark] of [["lane-hold-marker.mjs", markLaneHold], ["report-outcome.mjs", reportOutcomeMark]]) {
  test(`${name}: a hold job's marker names its lane and run`, () => {
    const dir = mkdtempSync(join(tmpdir(), "lane-hold-"));
    try {
      const path = join(dir, "lane-hold", "work-unblock");
      assert.equal(mark({ LANE_HOLD_MARKER: path, GITHUB_RUN_ID: "123" }), true);
      assert.equal(readFileSync(path, "utf8"), "work-unblock 123\n", "the body is the lane and the run id");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test(`${name}: a job that is no hold job writes no marker`, () => {
    const dir = mkdtempSync(join(tmpdir(), "lane-hold-"));
    try {
      assert.equal(mark({ GITHUB_RUN_ID: "123" }), false);
      assert.equal(existsSync(join(dir, "lane-hold")), false, "nothing written without LANE_HOLD_MARKER");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test(`${name}: a marker that cannot be written leaves the hold to its notice`, () => {
    const dir = mkdtempSync(join(tmpdir(), "lane-hold-"));
    try {
      const path = join(dir, "lane-hold", "work-unblock");
      assert.equal(mark({ LANE_HOLD_MARKER: path, GITHUB_RUN_ID: "1" }), true);
      assert.equal(mark({ LANE_HOLD_MARKER: join(path, "under-a-file"), GITHUB_RUN_ID: "2" }), false, "a path under a file is no directory; no throw");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
}
