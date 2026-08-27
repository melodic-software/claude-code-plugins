import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  downsampleSelectedFrames,
  RECOVER_USAGE,
  recoverWatchBootstrapCli,
  resolveRecoverySourceUrl,
} from "./recover-watch-bootstrap.js";
import { createWatchState, writeWatchState } from "./watch-state.js";

const captured = vi.hoisted(() => ({ stderr: /** @type {string[]} */ ([]) }));

vi.mock("@melodic/video-digestion/shared/terminal", () => ({
  writeStderr: (/** @type {unknown} */ text) => {
    captured.stderr.push(String(text));
  },
  writeStdout: () => {},
}));

/** @type {string} */
let sliceDir;

describe("recovery source-URL resolution", () => {
  beforeEach(async () => {
    sliceDir = await fs.mkdtemp(path.join(os.tmpdir(), "recover-source-"));
    captured.stderr.length = 0;
  });

  afterEach(async () => {
    await fs.rm(sliceDir, { recursive: true, force: true });
  });

  it("reads sourceUrl from the slice's persisted watch.json — never synthesized", async () => {
    // A non-YouTube sourceUrl proves recovery honors what the original run
    // recorded instead of re-deriving a YouTube-shaped URL from metadata.
    const sourceUrl = "https://x.com/someone/status/1234567890";
    await writeWatchState(
      sliceDir,
      createWatchState({ videoId: "1234567890", videoSlug: "slug", sourceUrl, title: "T" }),
    );

    await expect(resolveRecoverySourceUrl(sliceDir)).resolves.toBe(sourceUrl);
  });

  it("returns null when the slice has no persisted state", async () => {
    await expect(resolveRecoverySourceUrl(sliceDir)).resolves.toBeNull();
  });

  it("recovery CLI fails closed before touching artifacts when sourceUrl is missing", async () => {
    const code = await recoverWatchBootstrapCli([
      "node",
      "recover-watch-bootstrap.js",
      sliceDir,
      path.join(sliceDir, "work"),
      path.join(sliceDir, "frames"),
      path.join(sliceDir, "sheets"),
    ]);

    expect(code).toBe(1);
    expect(captured.stderr.join("\n")).toContain("no sourceUrl");
  });
});

describe("recovery CLI argument validation", () => {
  beforeEach(() => {
    captured.stderr.length = 0;
  });

  // Regression (#3365): `path.resolve(argv[2..5])` ran BEFORE the presence
  // check, so a missing argument threw `TypeError` and the usage branch was
  // unreachable. A bad invocation must print the usage line and return 1.
  it.each([
    ["no arguments", []],
    ["only slice-dir", ["slice"]],
    ["only slice-dir and workDir", ["slice", "work"]],
    ["missing contactSheetsDir", ["slice", "work", "frames"]],
    ["empty contactSheetsDir", ["slice", "work", "frames", ""]],
  ])("prints usage and returns 1 with %s", async (_label, args) => {
    const code = await recoverWatchBootstrapCli(["node", "recover-watch-bootstrap.js", ...args]);

    expect(code).toBe(1);
    expect(captured.stderr.join("\n")).toContain(RECOVER_USAGE);
  });
});

describe("stratified downsample reporting", () => {
  // Regression (#3365): the WARN interpolated `selection.selected.length`
  // AFTER `selection` was reassigned to the downsampled array, so it printed
  // "N → N" and hid every dropped frame.
  it("reports the pre-downsample count, not the post-downsample count", () => {
    const selected = Array.from({ length: 50 }, (_, i) => ({ path: `f${i}.png` }));

    const result = downsampleSelectedFrames(selected, 16);

    expect(result.selected).toHaveLength(16);
    expect(result.droppedCount).toBe(34);
    expect(result.warning).toContain("downsampled 50 → 16 frames");
    expect(result.warning).not.toContain("16 → 16");
  });

  it("keeps the selection and stays silent when it already fits", () => {
    const selected = Array.from({ length: 12 }, (_, i) => ({ path: `f${i}.png` }));

    const result = downsampleSelectedFrames(selected, 16);

    expect(result.selected).toBe(selected);
    expect(result.droppedCount).toBe(0);
    expect(result.warning).toBeNull();
  });

  it("samples across the whole selection rather than truncating the tail", () => {
    const selected = Array.from({ length: 8 }, (_, i) => ({ path: `f${i}.png` }));

    const result = downsampleSelectedFrames(selected, 4);

    expect(result.selected.map((f) => f.path)).toEqual([
      "f0.png",
      "f2.png",
      "f4.png",
      "f6.png",
    ]);
  });
});
