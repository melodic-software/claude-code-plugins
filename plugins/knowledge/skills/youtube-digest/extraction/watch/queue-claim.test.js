import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import {
  claimFilePath,
  claimRow,
  defaultClaimedBy,
  isStaleClaim,
  listClaims,
  readClaimFile,
  reclaimStaleClaims,
  releaseRow,
} from "./queue-claim.js";

const tempDirs = [];

afterEach(() => {
  for (const dir of tempDirs) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  tempDirs.length = 0;
});

function makeEpicDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "watch-queue-"));
  tempDirs.push(dir);
  return dir;
}

describe("claimRow", () => {
  it("creates exclusive claim file", () => {
    const epicDir = makeEpicDir();
    const claim = claimRow(epicDir, 3, { videoId: "AAA", claimedBy: "test-a" });

    expect(claim.row).toBe(3);
    expect(claim.videoId).toBe("AAA");
    expect(claim.claimedBy).toBe("test-a");

    const filePath = claimFilePath(epicDir, 3);
    expect(fs.existsSync(filePath)).toBe(true);
    expect(readClaimFile(filePath).row).toBe(3);
  });

  it("rejects double claim on same row", () => {
    const epicDir = makeEpicDir();
    claimRow(epicDir, 2, { claimedBy: "first" });

    expect(() => claimRow(epicDir, 2, { claimedBy: "second" })).toThrow(/already claimed/);
  });

  it("allows parallel claims on different rows", () => {
    const epicDir = makeEpicDir();
    claimRow(epicDir, 2, { claimedBy: "term-a" });
    claimRow(epicDir, 4, { claimedBy: "term-b" });

    expect(listClaims(epicDir).map((c) => c.row)).toEqual([2, 4]);
  });
});

describe("releaseRow", () => {
  it("removes claim file", () => {
    const epicDir = makeEpicDir();
    claimRow(epicDir, 1);
    expect(releaseRow(epicDir, 1)).toBe(true);
    expect(fs.existsSync(claimFilePath(epicDir, 1))).toBe(false);
    expect(releaseRow(epicDir, 1)).toBe(false);
  });
});

describe("isStaleClaim", () => {
  it("flags old claims", () => {
    const old = {
      row: 1,
      videoId: null,
      claimedAt: new Date(Date.now() - 8 * 24 * 60 * 60 * 1000).toISOString(),
      claimedBy: defaultClaimedBy(),
    };
    expect(isStaleClaim(old, 7)).toBe(true);
  });

  it("accepts fresh claims", () => {
    const fresh = {
      row: 1,
      videoId: null,
      claimedAt: new Date().toISOString(),
      claimedBy: defaultClaimedBy(),
    };
    expect(isStaleClaim(fresh, 7)).toBe(false);
  });
});

describe("reclaimStaleClaims", () => {
  it("releases only stale rows", () => {
    const epicDir = makeEpicDir();
    claimRow(epicDir, 1, { claimedBy: "fresh" });

    const stalePath = claimFilePath(epicDir, 2);
    fs.mkdirSync(path.dirname(stalePath), { recursive: true });
    fs.writeFileSync(
      stalePath,
      JSON.stringify({
        row: 2,
        videoId: null,
        claimedAt: new Date(Date.now() - 10 * 24 * 60 * 60 * 1000).toISOString(),
        claimedBy: "stale",
      }),
      "utf8",
    );

    const result = reclaimStaleClaims(epicDir, 7);
    expect(result.released).toEqual([2]);
    expect(fs.existsSync(claimFilePath(epicDir, 1))).toBe(true);
    expect(fs.existsSync(stalePath)).toBe(false);
  });
});
