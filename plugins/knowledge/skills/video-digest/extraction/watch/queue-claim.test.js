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
  readQueueRows,
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

describe("reclaimStaleClaims queue state", () => {
  const queue = [
    "# Queue",
    "",
    "| # | URL | video-id | title | channel | slug | status | notes |",
    "| --- | --- | --- | --- | --- | --- | --- | --- |",
    "| 1 | https://example.com/a | AAA | A \\| B | Chan | a | in_progress | |",
    "| 2 | https://example.com/b | BBB | B | Chan | b | in_progress | |",
    "| 3 | https://example.com/c | CCC | C | Chan | c | complete | |",
    "",
  ].join("\n");

  function writeStale(epicDir, row) {
    const filePath = claimFilePath(epicDir, row);
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(
      filePath,
      JSON.stringify({
        row,
        videoId: null,
        claimedAt: new Date(Date.now() - 10 * 24 * 60 * 60 * 1000).toISOString(),
        claimedBy: "stale",
      }),
      "utf8",
    );
  }

  it("resets a stale row to pending and reports stub-less in_progress rows", () => {
    const epicDir = makeEpicDir();
    fs.writeFileSync(path.join(epicDir, "QUEUE.md"), queue, "utf8");
    writeStale(epicDir, 1);

    const result = reclaimStaleClaims(epicDir, 7);

    expect(result.released).toEqual([1]);
    expect(result.reset).toEqual([1]);
    expect(result.orphaned).toEqual([2]);
    expect(readQueueRows(epicDir)).toEqual([
      { row: 1, status: "pending" },
      { row: 2, status: "in_progress" },
      { row: 3, status: "complete" },
    ]);
    expect(fs.readFileSync(path.join(epicDir, "QUEUE.md"), "utf8")).toContain("A \\| B");
  });

  it("does not reset a row that is no longer in_progress", () => {
    const epicDir = makeEpicDir();
    fs.writeFileSync(path.join(epicDir, "QUEUE.md"), queue, "utf8");
    writeStale(epicDir, 3);

    const result = reclaimStaleClaims(epicDir, 7);

    expect(result.released).toEqual([3]);
    expect(result.reset).toEqual([]);
    expect(readQueueRows(epicDir)?.[2]).toEqual({ row: 3, status: "complete" });
  });

  it("returns null rows when QUEUE.md is absent", () => {
    expect(readQueueRows(makeEpicDir())).toBeNull();
  });
});
