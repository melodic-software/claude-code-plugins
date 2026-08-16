import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { dedupeSynthesisDir } from "./dedupe-synthesis-dir.js";

const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  tempDirs.length = 0;
});

describe("dedupeSynthesisDir", () => {
  it("keeps semantic name when bytes match", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "syn-dedupe-"));
    tempDirs.push(dir);
    const bytes = Buffer.from("same-image-bytes");
    fs.writeFileSync(path.join(dir, "0012.png"), bytes);
    fs.writeFileSync(path.join(dir, "network-diagram.png"), bytes);

    const { kept, removed } = dedupeSynthesisDir(dir);
    expect(kept).toEqual(["network-diagram.png"]);
    expect(removed).toEqual(["0012.png"]);
    expect(fs.existsSync(path.join(dir, "network-diagram.png"))).toBe(true);
    expect(fs.existsSync(path.join(dir, "0012.png"))).toBe(false);
  });
});
