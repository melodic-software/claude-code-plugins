import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { repairSynthesisPromotions } from "./repair-synthesis-promotions.js";

const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  tempDirs.length = 0;
});

describe("repairSynthesisPromotions", () => {
  it("rejects forbidden names with pipeline placeholder gap notes", () => {
    const sliceDir = fs.mkdtempSync(path.join(os.tmpdir(), "repair-promo-"));
    tempDirs.push(sliceDir);
    fs.mkdirSync(path.join(sliceDir, "key-frames", "frames"), { recursive: true });
    fs.mkdirSync(path.join(sliceDir, "run-state"), { recursive: true });
    fs.writeFileSync(
      path.join(sliceDir, "key-frames", "promotion-decisions.json"),
      `${JSON.stringify({
        decisions: [
          {
            sourceFile: "anchor_0001.png",
            verdict: "promote",
            destName: "code-code-99.png",
            gapNote: "Frame in code densification window.",
            session: "densification-topup",
          },
        ],
      })}\n`,
    );
    fs.writeFileSync(
      path.join(sliceDir, "run-state", "watch.json"),
      JSON.stringify({ tempSession: {}, artifactPaths: {} }),
    );
    fs.writeFileSync(
      path.join(sliceDir, "key-frames", "selection.json"),
      JSON.stringify({ selectedFrames: [], tempSession: {} }),
    );

    const result = repairSynthesisPromotions(sliceDir);
    expect(result.rejected).toBe(1);
    const doc = JSON.parse(
      fs.readFileSync(path.join(sliceDir, "key-frames", "promotion-decisions.json"), "utf8"),
    );
    expect(doc.decisions[0].verdict).toBe("reject");
  });
});
