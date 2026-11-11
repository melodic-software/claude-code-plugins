import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import {
  AWAITING_CAPTIONS,
  captionWaitNotes,
  claimableRows,
  claimFilePath,
  claimRow,
  defaultClaimedBy,
  holdRowForCaptions,
  isStaleClaim,
  listClaims,
  parseCaptionWaitNotes,
  readClaimFile,
  readQueueRows,
  reclaimStaleClaims,
  releaseRow,
  resumeRowFromCaptionWait,
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

describe("awaiting_captions rows", () => {
  const NOW = Date.parse("2026-11-11T12:00:00.000Z");
  const due = { nextCheckAt: "2026-11-11T11:30:00.000Z", deadline: "2026-11-12T00:00:00.000Z" };
  const notDue = { nextCheckAt: "2026-11-11T12:30:00.000Z", deadline: "2026-11-12T00:00:00.000Z" };

  /** @param {string} epicDir */
  function writeQueue(epicDir) {
    const queue = [
      "| # | URL | video-id | title | channel | slug | status | notes |",
      "| --- | --- | --- | --- | --- | --- | --- | --- |",
      `| 1 | https://example.com/a | AAA | A | Chan | a | ${AWAITING_CAPTIONS} | ${captionWaitNotes(notDue)} |`,
      "| 2 | https://example.com/b | BBB | B | Chan | b | pending | |",
      `| 3 | https://example.com/c | CCC | C | Chan | c | ${AWAITING_CAPTIONS} | ${captionWaitNotes(due)} |`,
      "| 4 | https://example.com/d | DDD | D | Chan | d | in_progress | |",
      "",
    ].join("\n");
    fs.writeFileSync(path.join(epicDir, "QUEUE.md"), queue, "utf8");
  }

  /** @param {string} epicDir @param {number} row */
  function notesOf(epicDir, row) {
    const line = fs
      .readFileSync(path.join(epicDir, "QUEUE.md"), "utf8")
      .split("\n")
      .find((l) => l.startsWith(`| ${row} |`));
    return line?.split(" | ").at(-1)?.replace(/ \|$/, "") ?? "";
  }

  it("holds an in_progress row with its next check time and deadline", () => {
    const epicDir = makeEpicDir();
    writeQueue(epicDir);

    expect(holdRowForCaptions(epicDir, 4, notDue)).toBe(true);

    expect(readQueueRows(epicDir)?.[3]).toEqual({ row: 4, status: AWAITING_CAPTIONS });
    expect(parseCaptionWaitNotes(notesOf(epicDir, 4))).toEqual(notDue);
  });

  it("re-holds a held row with a new next check time, and holds no other status", () => {
    const epicDir = makeEpicDir();
    writeQueue(epicDir);
    const later = { ...due, nextCheckAt: "2026-11-11T13:00:00.000Z" };

    expect(holdRowForCaptions(epicDir, 3, later)).toBe(true);
    expect(parseCaptionWaitNotes(notesOf(epicDir, 3))).toEqual(later);
    expect(holdRowForCaptions(epicDir, 2, later)).toBe(false);
    expect(readQueueRows(epicDir)?.[1]).toEqual({ row: 2, status: "pending" });
  });

  it("returns a held row to pending once captions appear", () => {
    const epicDir = makeEpicDir();
    writeQueue(epicDir);

    expect(resumeRowFromCaptionWait(epicDir, 3)).toBe(true);

    expect(readQueueRows(epicDir)?.[2]).toEqual({ row: 3, status: "pending" });
    expect(notesOf(epicDir, 3)).toBe("");
    expect(resumeRowFromCaptionWait(epicDir, 2)).toBe(false);
  });

  it("keeps the deadline in notes when the wait ended, so the watch run falls through", () => {
    const epicDir = makeEpicDir();
    writeQueue(epicDir);
    const note = `caption wait ended at deadline ${due.deadline} with no captions (live_status post_live); falls through to ASR or transcriptDegradation`;

    expect(resumeRowFromCaptionWait(epicDir, 3, note)).toBe(true);

    expect(notesOf(epicDir, 3)).toBe(note);
    expect(claimableRows(epicDir, NOW).find((e) => e.row === 3)).toEqual({
      row: 3,
      status: "pending",
      recheck: false,
      captionWaitDeadline: due.deadline,
    });
  });

  it("FIFO watch skips a held row until its next check time", () => {
    const epicDir = makeEpicDir();
    writeQueue(epicDir);

    expect(claimableRows(epicDir, NOW)).toEqual([
      { row: 2, status: "pending", recheck: false, captionWaitDeadline: null },
      { row: 3, status: AWAITING_CAPTIONS, recheck: true, captionWaitDeadline: due.deadline },
    ]);
    expect(claimableRows(epicDir, Date.parse(notDue.nextCheckAt)).map((e) => e.row)).toEqual([
      1, 2, 3,
    ]);
  });

  it("FIFO watch skips a claimed row", () => {
    const epicDir = makeEpicDir();
    writeQueue(epicDir);
    claimRow(epicDir, 2, { claimedBy: "other" });

    expect(claimableRows(epicDir, NOW).map((e) => e.row)).toEqual([3]);
  });

  it("stale-check neither resets nor orphans a held row, and reports a due re-check", () => {
    const epicDir = makeEpicDir();
    writeQueue(epicDir);
    const stale = claimFilePath(epicDir, 1);
    fs.mkdirSync(path.dirname(stale), { recursive: true });
    fs.writeFileSync(
      stale,
      JSON.stringify({
        row: 1,
        videoId: null,
        claimedAt: new Date(NOW - 10 * 24 * 60 * 60 * 1000).toISOString(),
        claimedBy: "stale",
      }),
      "utf8",
    );

    const result = reclaimStaleClaims(epicDir, 7, NOW);

    expect(result.released).toEqual([1]);
    expect(result.reset).toEqual([]);
    expect(result.orphaned).toEqual([4]);
    expect(result.captionRecheckDue).toEqual([3]);
    expect(readQueueRows(epicDir)?.[0]).toEqual({ row: 1, status: AWAITING_CAPTIONS });
    expect(readQueueRows(epicDir)?.[2]).toEqual({ row: 3, status: AWAITING_CAPTIONS });
  });
});
