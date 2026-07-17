import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { LANES, lanePath } from "../lib/slice-lanes.js";
import { renderQualityAudit } from "./render-quality-audit.js";

/** @type {string[]} */
const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

function makeSliceWithQualityAudit() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "render-quality-audit-"));
  tempDirs.push(dir);
  const keyFramesDir = lanePath(dir, LANES.keyFrames);
  fs.mkdirSync(keyFramesDir, { recursive: true });
  const audit = {
    reviewedAt: "2026-06-17T00:00:00.000Z",
    files: [{ name: "demo-slide.png", pass: true, note: "sharp slide, no occlusion" }],
  };
  fs.writeFileSync(
    path.join(keyFramesDir, "key-frame-quality-audit.json"),
    JSON.stringify(audit, null, 2),
  );
  return dir;
}

describe("renderQualityAudit", () => {
  it("populates the Notes column from the canonical `note` field", () => {
    const dir = makeSliceWithQualityAudit();
    const outPath = renderQualityAudit(dir);
    const md = fs.readFileSync(outPath, "utf8");
    expect(md).toContain("sharp slide, no occlusion");
  });
});
