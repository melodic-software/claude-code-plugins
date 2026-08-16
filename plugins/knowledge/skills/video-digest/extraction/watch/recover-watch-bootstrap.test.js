import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { recoverWatchBootstrapCli, resolveRecoverySourceUrl } from "./recover-watch-bootstrap.js";
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
