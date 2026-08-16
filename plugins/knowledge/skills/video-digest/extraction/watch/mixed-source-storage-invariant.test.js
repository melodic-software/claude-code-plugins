import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { createAcquisitionEnvelope } from "../adapters/adapter-contract.js";
import { acquireMedia } from "../adapters/registry.js";
import { YOUTUBE_WATCH_EPIC_DIR } from "../transcript/derive-video-slug.js";
import { claimFilePath, claimRow, resolveEpicDir } from "./queue-claim.js";
import { runWatchCli } from "./run-watch.js";

const captured = vi.hoisted(() => ({
  stderr: /** @type {string[]} */ ([]),
  stdout: /** @type {string[]} */ ([]),
}));

vi.mock("@melodic/video-digestion/shared/terminal", () => ({
  writeStderr: (/** @type {unknown} */ text) => {
    captured.stderr.push(String(text));
  },
  writeStdout: (/** @type {unknown} */ text) => {
    captured.stdout.push(String(text));
  },
}));

vi.mock("../adapters/registry.js", async (importOriginal) => {
  const actual = await importOriginal();
  return { ...actual, acquireMedia: vi.fn() };
});

vi.mock("./post-bootstrap-slice.js", () => ({
  postBootstrapSlice: vi.fn(() => null),
}));

const YT_URL = "https://www.youtube.com/watch?v=7zZy1QTvokM";
const TWID = "1720000000000000000";
const X_URL = `https://x.com/someuser/status/${TWID}`;

/** @type {string} */
let workRoot;
/** @type {string} */
let fixtureDir;

/**
 * @param {string} id
 * @param {string} title
 * @param {Record<string, unknown>} [extra]
 */
function textOnlyEnvelope(id, title, extra = {}) {
  return createAcquisitionEnvelope({
    entries: [],
    metadata: { id, title, description: "", ...extra },
    workDir: fixtureDir,
  });
}

describe("storage invariant: mixed-source batches share one queue root", () => {
  beforeEach(async () => {
    workRoot = await fs.mkdtemp(path.join(os.tmpdir(), "mixed-source-root-"));
    fixtureDir = await fs.mkdtemp(path.join(os.tmpdir(), "mixed-source-fix-"));
    process.env.VIDEO_DIGEST_WORK_ROOT = workRoot;
    captured.stderr.length = 0;
    captured.stdout.length = 0;
    vi.mocked(acquireMedia).mockReset();
  });

  afterEach(async () => {
    delete process.env.VIDEO_DIGEST_WORK_ROOT;
    await fs.rm(workRoot, { recursive: true, force: true });
    await fs.rm(fixtureDir, { recursive: true, force: true });
  });

  it("X and YouTube slices land under the ONE epic dir; source is never a directory level", async () => {
    vi.mocked(acquireMedia).mockImplementation(async (url) =>
      url === YT_URL
        ? {
            success: true,
            data: textOnlyEnvelope("7zZy1QTvokM", "Fixture Video", {
              chapters: [],
              heatmap: null,
              comments: [],
            }),
          }
        : {
            success: true,
            data: textOnlyEnvelope(TWID, "Fixture Post", { "source:displayId": TWID }),
          },
    );

    expect(await runWatchCli(["node", "run-watch.js", YT_URL, "--skip-research"])).toBe(0);
    expect(await runWatchCli(["node", "run-watch.js", X_URL, "--skip-research"])).toBe(0);

    const epicDir = path.join(workRoot, ".work", YOUTUBE_WATCH_EPIC_DIR);
    const ytSlice = path.join(epicDir, "fixture-video-7zZy1QTvokM");
    const xSlice = path.join(epicDir, `fixture-post-${TWID}`);

    // Both slices resolve under the literal epic dir.
    await expect(fs.access(path.join(ytSlice, "run-state", "watch.json"))).resolves.toBeUndefined();
    await expect(fs.access(path.join(xSlice, "run-state", "watch.json"))).resolves.toBeUndefined();

    // One queue root: .work contains ONLY the epic dir — no per-source level.
    expect(await fs.readdir(path.join(workRoot, ".work"))).toEqual([YOUTUBE_WATCH_EPIC_DIR]);
    const epicEntries = await fs.readdir(epicDir);
    expect(epicEntries).toContain("fixture-video-7zZy1QTvokM");
    expect(epicEntries).toContain(`fixture-post-${TWID}`);
    expect(epicEntries).not.toContain("x");
    expect(epicEntries).not.toContain("youtube");

    // Source lives in slice metadata (watch.json sourceUrl), not in the path.
    const xState = JSON.parse(
      await fs.readFile(path.join(xSlice, "run-state", "watch.json"), "utf8"),
    );
    expect(xState.sourceUrl).toBe(X_URL);
    expect(xSlice).not.toContain("x.com");

    // Shared claims namespace: rows for both sources claim in the SAME claims dir.
    const epicFromRoot = resolveEpicDir(workRoot);
    expect(epicFromRoot).toBe(epicDir);
    claimRow(epicFromRoot, 1, { videoId: "7zZy1QTvokM", claimedBy: "test" });
    claimRow(epicFromRoot, 2, { videoId: TWID, claimedBy: "test" });
    expect(path.dirname(claimFilePath(epicFromRoot, 1))).toBe(
      path.dirname(claimFilePath(epicFromRoot, 2)),
    );
    expect((await fs.readdir(path.join(epicDir, "claims"))).sort()).toEqual([
      "1.json",
      "2.json",
    ]);
  });
});
