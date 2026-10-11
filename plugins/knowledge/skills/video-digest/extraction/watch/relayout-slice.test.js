import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import { checkLayoutLinks, inlineLinks, relayoutSlice } from "./relayout-slice.js";

/** @type {string[]} */
const scratch = [];

function makeDir(prefix) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  scratch.push(dir);
  return dir;
}

/** @param {string} root @param {Record<string, string>} files */
function writeTree(root, files) {
  for (const [rel, body] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
    fs.writeFileSync(path.join(root, rel), body);
  }
}

/** @param {string} root @param {string} rel */
function read(root, rel) {
  return fs.readFileSync(path.join(root, rel), "utf8");
}

const VIDEO_ID = "abc123XYZ_0";

/**
 * A small closed slice plus its temp session (media, caption tracks, info JSON
 * and two extracted frames).
 *
 * @param {{ status?: string, withMedia?: boolean, extraFiles?: Record<string, string> }} [options]
 */
function makeFixture({ status = "complete", withMedia = true, extraFiles = {} } = {}) {
  const parent = makeDir("relayout-slice-");
  const sliceDir = path.join(parent, "sample-talk-abc123XYZ_0");
  const workDir = makeDir("relayout-work-");
  const framesDir = makeDir("relayout-frames-");
  if (withMedia) {
    writeTree(workDir, {
      [`${VIDEO_ID}.mp4`]: "video-bytes",
      [`${VIDEO_ID}.en.vtt`]: "WEBVTT\n",
      [`${VIDEO_ID}.en-orig.vtt`]: "WEBVTT\n",
      [`${VIDEO_ID}.info.json`]: JSON.stringify({
        id: VIDEO_ID,
        title: "Sample Talk",
        formats: [{}],
        requested_formats: [{}],
        thumbnails: [{}],
        automatic_captions: {},
        subtitles: {},
        heatmap: [],
        http_headers: {},
        requested_subtitles: {},
        _format_sort_fields: [],
        requested_downloads: [{}],
        _filename: "/tmp/video-extraction-x/abc123XYZ_0.mp4",
        filename: "/tmp/video-extraction-x/abc123XYZ_0.mp4",
        __files_to_move: {},
        comments: Array.from({ length: 25 }, (_, index) => ({ id: `c${index}` })),
      }),
    });
    writeTree(framesDir, {
      "scene_0001.png": "png",
      "anchor_00012000_0001.png": "png",
      "frame-times.json": JSON.stringify({ "scene_0001.png": { timestampSec: 1 } }),
    });
  } else {
    fs.rmSync(workDir, { recursive: true, force: true });
    fs.rmSync(framesDir, { recursive: true, force: true });
  }
  writeTree(sliceDir, {
    "run-state/watch.json": JSON.stringify({
      videoId: VIDEO_ID,
      videoSlug: "sample-talk-abc123XYZ_0",
      sourceUrl: `https://www.youtube.com/watch?v=${VIDEO_ID}`,
      title: "Sample Talk",
      status,
      phases: { transcript: { metrics: { transcriptStrategy: "captions" } } },
      tempSession: { workDir, framesDir, acquiredAt: "2026-10-10T12:00:00.000Z" },
    }),
    "README.md": "# Sample Talk journey\n",
    "RESEARCH.md": "Clusters from `research/claim-inventory.md`; shards in `research/findings/`.\n",
    "source/transcript.txt": "[0:01] hello\n",
    "source/harvested-links.json": "[]",
    "key-frames/frames/title-slide.png": "png",
    "key-frames/visual-frames.md":
      "| `frames/title-slide.png` | `scene_0001.png` |\n\nTiers: [manifest](key-frames-manifest.md)\n",
    "key-frames/key-frames-manifest.md": "| title-slide.png |\n",
    "key-frames/key-frame-quality-audit.md": "| title-slide.png | yes |\n",
    "key-frames/frame-triage-log.md": "| sheet_001 | promote |\n",
    "key-frames/selection.json": "{}",
    "source/companion-sources.md": "Companion: [digest](companion-digest/README.md).\n",
    "source/companion-digest/README.md": "Brief: `source/companion-sources.md`.\n",
    "research/claim-inventory.md": "Transcript: `source/transcript.txt`.\n",
    "research/findings/topic.md":
      "Quote at `SLICE/source/transcript.txt:3`; see [agenda](../claim-inventory.md#sessions).\n",
    "recommendations/menu.md": [
      "Evidence: `source/transcript.txt` and ![slide](../key-frames/frames/title-slide.png).",
      "Detail: `research/findings/topic.md`, the hub [README](README.md), the [journey](../README.md).",
      "Target file: `plugins/knowledge/skills/video-digest/SKILL.md`.",
      "Run state: `run-state/watch.json`, [selection](../key-frames/selection.json).",
      "Upstream: `research/deepening/html-report.md:92` in mattpocock/skills.",
      "",
    ].join("\n"),
    "recommendations/README.md": "# Hub\n",
    ...extraFiles,
  });
  return { sliceDir, workDir, framesDir, targetDir: path.join(makeDir("relayout-target-"), "out") };
}

afterEach(() => {
  for (const dir of scratch.splice(0)) fs.rmSync(dir, { recursive: true, force: true });
});

describe("relayoutSlice", () => {
  it("copies a closed slice into the corpus layout", async () => {
    const { sliceDir, targetDir } = makeFixture();

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    for (const rel of [
      "transcript/transcript.txt",
      "transcript/en.vtt",
      "transcript/en-orig.vtt",
      "metadata/info.json",
      "metadata/harvested-links.json",
      "frames/all/scene_0001.png",
      "frames/all/anchor_00012000_0001.png",
      "frames/all/frame-times.json",
      "frames/key/title-slide.png",
      "frames/visual-frames.md",
      "frames/key-frames-manifest.md",
      "frames/key-frame-quality-audit.md",
      "frames/frame-triage-log.md",
      "metadata/companion-sources.md",
      "analysis/companion-digest/README.md",
      `media/${VIDEO_ID}.mp4`,
      "analysis/RESEARCH.md",
      "analysis/research/claim-inventory.md",
      "analysis/research/findings/topic.md",
      "analysis/recommendations/menu.md",
      "analysis/recommendations/README.md",
      "README.md",
    ]) {
      expect(fs.existsSync(path.join(targetDir, rel)), rel).toBe(true);
    }
    expect(fs.existsSync(path.join(targetDir, "key-frames"))).toBe(false);
    expect(fs.existsSync(path.join(targetDir, "run-state"))).toBe(false);
    expect(fs.readdirSync(targetDir).filter((name) => name.startsWith("."))).toEqual([]);
  });

  it("trims info.json to the corpus copy", async () => {
    const { sliceDir, targetDir } = makeFixture();

    await relayoutSlice({ sliceDir, targetDir });

    const info = JSON.parse(read(targetDir, "metadata/info.json"));
    expect(Object.keys(info).sort()).toEqual(["comments", "id", "title"]);
    expect(info.comments).toHaveLength(20);
  });

  it("rewrites slice-internal references relative to each file's new location", async () => {
    const { sliceDir, targetDir } = makeFixture();

    await relayoutSlice({ sliceDir, targetDir });

    expect(read(targetDir, "analysis/recommendations/menu.md")).toBe(
      [
        "Evidence: `../../transcript/transcript.txt` and ![slide](../../frames/key/title-slide.png).",
        "Detail: `../research/findings/topic.md`, the hub [README](README.md), the journey (README.md, not retained in this copy).",
        "Target file: `plugins/knowledge/skills/video-digest/SKILL.md`.",
        "Run state: run-state/watch.json (not retained in this copy), selection (key-frames/selection.json, not retained in this copy).",
        "Upstream: `research/deepening/html-report.md:92` in mattpocock/skills.",
        "",
      ].join("\n"),
    );
    expect(read(targetDir, "metadata/companion-sources.md")).toBe(
      "Companion: [digest](../analysis/companion-digest/README.md).\n",
    );
    expect(read(targetDir, "analysis/companion-digest/README.md")).toBe(
      "Brief: `../../metadata/companion-sources.md`.\n",
    );
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      "| `key/title-slide.png` | `all/scene_0001.png` |\n\nTiers: [manifest](key-frames-manifest.md)\n",
    );
    expect(read(targetDir, "analysis/research/findings/topic.md")).toBe(
      "Quote at `../../../transcript/transcript.txt:3`; see [agenda](../claim-inventory.md#sessions).\n",
    );
    expect(read(targetDir, "analysis/research/claim-inventory.md")).toBe(
      "Transcript: `../../transcript/transcript.txt`.\n",
    );
    expect(read(targetDir, "analysis/RESEARCH.md")).toBe(
      "Clusters from `research/claim-inventory.md`; shards in `research/findings/`.\n",
    );
  });

  it("replaces an existing target with --replace, keeping its README", async () => {
    const { sliceDir, targetDir } = makeFixture();
    writeTree(targetDir, { "README.md": "# Curated\n", "stale.md": "old\n" });

    const result = await relayoutSlice({ sliceDir, targetDir, replace: true });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "README.md")).toBe("# Curated\n");
    expect(fs.existsSync(path.join(targetDir, "stale.md"))).toBe(false);
    expect(fs.readdirSync(path.dirname(targetDir))).toEqual(["out"]);
  });

  it("refuses an existing target without --replace and leaves it untouched", async () => {
    const { sliceDir, targetDir } = makeFixture();
    writeTree(targetDir, { "stale.md": "old\n" });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.readdirSync(targetDir)).toEqual(["stale.md"]);
  });

  it("leaves the target untouched and no staging behind when a copy fails midway", async () => {
    const { sliceDir, targetDir } = makeFixture();
    writeTree(targetDir, { "README.md": "# Curated\n", "stale.md": "old\n" });
    let calls = 0;

    const result = await relayoutSlice({
      sliceDir,
      targetDir,
      replace: true,
      copyFile: (from, to) => {
        calls += 1;
        if (calls === 3) throw new Error("disk full");
        fs.copyFileSync(from, to);
      },
    });

    expect(result.exitCode).toBe(1);
    expect(calls).toBe(3);
    expect(fs.readdirSync(targetDir).sort()).toEqual(["README.md", "stale.md"]);
    expect(read(targetDir, "stale.md")).toBe("old\n");
    expect(fs.readdirSync(path.dirname(targetDir))).toEqual(["out"]);
  });

  it("takes nothing from a temp session that still exists under --no-media", async () => {
    const { sliceDir, targetDir } = makeFixture();

    const result = await relayoutSlice({ sliceDir, targetDir, noMedia: true });

    expect(result.exitCode).toBe(0);
    for (const rel of ["media", "frames/all", "transcript/en.vtt", "metadata/info.json"]) {
      expect(fs.existsSync(path.join(targetDir, rel)), rel).toBe(false);
    }
    expect(read(targetDir, "transcript/transcript.txt")).toBe("[0:01] hello\n");
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      "| `key/title-slide.png` | scene_0001.png (not retained in this copy) |\n\nTiers: [manifest](key-frames-manifest.md)\n",
    );
  });

  it("copies decks, attachments and the vision logs, rewriting their references", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "source/decks/session-1/slides.pdf": "pdf",
        "source/attachments/pdf/notes.pdf": "pdf",
        "source/deck-inventory.md": "Fetched: `decks/session-1/slides.pdf`.\n",
        "research/sources.md": "Notes: [pdf](../source/attachments/pdf/notes.pdf).\n",
        "key-frames/vision-plan.md": "# Vision plan\n",
        "key-frames/visual-gaps.md": "# Visual gaps\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "metadata/decks/session-1/slides.pdf")).toBe("pdf");
    expect(read(targetDir, "metadata/attachments/pdf/notes.pdf")).toBe("pdf");
    expect(read(targetDir, "metadata/deck-inventory.md")).toBe(
      "Fetched: `decks/session-1/slides.pdf`.\n",
    );
    expect(read(targetDir, "analysis/research/sources.md")).toBe(
      "Notes: [pdf](../../metadata/attachments/pdf/notes.pdf).\n",
    );
    expect(read(targetDir, "frames/vision-plan.md")).toBe("# Vision plan\n");
    expect(read(targetDir, "frames/visual-gaps.md")).toBe("# Visual gaps\n");
  });

  it("names where a split directory's files went instead of a single new path", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "recommendations/questions.md": "Inputs: `source/`.\n" },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "analysis/recommendations/questions.md")).toBe(
      "Inputs: source (split across analysis/, metadata/, transcript/ in this copy).\n",
    );
  });

  it("fails the link check on a frame name the temp session does not hold", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "key-frames/visual-frames.md": "Rejected: `scene_0099.png`.\n" },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([{ file: "frames/visual-frames.md", ref: "scene_0099.png" }]);
  });

  it("warns about leftover staging dirs and leaves them alone", async () => {
    const { sliceDir, targetDir } = makeFixture();
    const leftover = path.join(path.dirname(targetDir), ".out.relayout-abc123");
    writeTree(leftover, { "README.md": "# From a killed run\n" });
    const stderr = vi.spyOn(process.stderr, "write").mockImplementation(() => true);

    const result = await relayoutSlice({ sliceDir, targetDir });
    const message = stderr.mock.calls.map(([chunk]) => String(chunk)).join("");
    stderr.mockRestore();

    expect(result.exitCode).toBe(0);
    expect(message).toContain(leftover);
    expect(read(leftover, "README.md")).toBe("# From a killed run\n");
    expect(read(targetDir, "README.md")).not.toBe("# From a killed run\n");
  });

  it.skipIf(process.platform === "win32")(
    "installs over an empty target directory created during the run (it holds no data)",
    async () => {
      const { sliceDir, targetDir } = makeFixture();
      let calls = 0;

      const result = await relayoutSlice({
        sliceDir,
        targetDir,
        copyFile: (from, to) => {
          calls += 1;
          if (calls === 1) fs.mkdirSync(targetDir);
          fs.copyFileSync(from, to);
        },
      });

      expect(result.exitCode).toBe(0);
      expect(fs.existsSync(path.join(targetDir, "analysis/RESEARCH.md"))).toBe(true);
    },
  );

  it.skipIf(process.platform === "win32" || process.getuid?.() === 0)(
    "refuses, without throwing, when the backup restore fails",
    async () => {
      const { sliceDir, targetDir } = makeFixture();
      writeTree(`${targetDir}.relayout-backup`, { "README.md": "# Curated\n" });
      const parent = path.dirname(targetDir);
      fs.chmodSync(parent, 0o555);
      try {
        const result = await relayoutSlice({ sliceDir, targetDir, replace: true });

        expect(result.exitCode).toBe(1);
        expect(read(`${targetDir}.relayout-backup`, "README.md")).toBe("# Curated\n");
      } finally {
        fs.chmodSync(parent, 0o755);
      }
    },
  );

  it("refuses, without --replace, a target that appears after the early check", async () => {
    const { sliceDir, targetDir } = makeFixture();
    let calls = 0;

    const result = await relayoutSlice({
      sliceDir,
      targetDir,
      copyFile: (from, to) => {
        calls += 1;
        // Another run installs its layout while this one is staging.
        if (calls === 1) writeTree(targetDir, { "theirs.md": "theirs\n" });
        fs.copyFileSync(from, to);
      },
    });

    expect(result.exitCode).toBe(1);
    expect(fs.readdirSync(targetDir)).toEqual(["theirs.md"]);
    expect(fs.readdirSync(path.dirname(targetDir))).toEqual(["out"]);
  });

  it("fails the link check on a missing file under a slice directory", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "recommendations/questions.md": "Slide: `key-frames/frames/deleted.png`.\n" },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([
      { file: "analysis/recommendations/questions.md", ref: "../../frames/key/deleted.png" },
    ]);
    expect(fs.readdirSync(path.dirname(targetDir))).toEqual([]);
  });

  it("re-lays out an unclosed slice, media included, when its outcome checks pass", async () => {
    const { sliceDir, targetDir } = makeFixture({ status: "synthesizing" });
    /** @type {string[]} */
    const verified = [];

    const result = await relayoutSlice({
      sliceDir,
      targetDir,
      verifyOutcomes: (dir) => {
        verified.push(dir);
        return 0;
      },
    });

    expect(result.exitCode).toBe(0);
    expect(verified).toEqual([path.resolve(sliceDir)]);
    expect(fs.existsSync(path.join(targetDir, `media/${VIDEO_ID}.mp4`))).toBe(true);
  });

  it("refuses an unclosed slice whose outcome checks fail", async () => {
    const { sliceDir, targetDir } = makeFixture({ status: "synthesizing" });

    const result = await relayoutSlice({ sliceDir, targetDir, verifyOutcomes: () => 1 });

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  it("refuses an unclosed slice that fails the real outcome checks", async () => {
    const { sliceDir, targetDir } = makeFixture({ status: "synthesizing" });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  it("skips the outcome checks for a closed slice", async () => {
    const { sliceDir, targetDir } = makeFixture();

    const result = await relayoutSlice({ sliceDir, targetDir, verifyOutcomes: () => 1 });

    expect(result.exitCode).toBe(0);
  });

  it("refuses when the temp session's media is gone, unless --no-media", async () => {
    const { sliceDir, targetDir } = makeFixture({ withMedia: false });

    const refused = await relayoutSlice({ sliceDir, targetDir });
    expect(refused.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);

    const result = await relayoutSlice({ sliceDir, targetDir, noMedia: true });
    expect(result.exitCode).toBe(0);
    expect(fs.existsSync(path.join(targetDir, "media"))).toBe(false);
    expect(fs.existsSync(path.join(targetDir, "analysis/recommendations/menu.md"))).toBe(true);
  });

  it.each([
    ["the slice itself", (/** @type {string} */ slice) => slice],
    ["an ancestor of the slice", (/** @type {string} */ slice) => path.dirname(slice)],
    ["a directory inside the slice", (/** @type {string} */ slice) => path.join(slice, "out")],
  ])("refuses a target that is %s, even with --replace", async (_label, toTarget) => {
    const { sliceDir } = makeFixture();
    const targetDir = toTarget(sliceDir);
    const before = fs.readdirSync(sliceDir).sort();

    const result = await relayoutSlice({ sliceDir, targetDir, replace: true });

    expect(result.exitCode).toBe(1);
    expect(fs.readdirSync(sliceDir).sort()).toEqual(before);
    expect(fs.existsSync(path.join(sliceDir, "out"))).toBe(false);
  });

  it("restores the target from the backup an interrupted --replace left", async () => {
    const { sliceDir, targetDir } = makeFixture();
    // Killed between the two renames: the old target sits at the backup name.
    writeTree(`${targetDir}.relayout-backup`, { "README.md": "# Curated\n" });

    const result = await relayoutSlice({ sliceDir, targetDir, replace: true });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "README.md")).toBe("# Curated\n");
    expect(fs.readdirSync(path.dirname(targetDir))).toEqual(["out"]);
  });

  it("refuses when both the target and a leftover backup exist", async () => {
    const { sliceDir, targetDir } = makeFixture();
    writeTree(targetDir, { "README.md": "# New\n" });
    writeTree(`${targetDir}.relayout-backup`, { "README.md": "# Old\n" });

    const result = await relayoutSlice({ sliceDir, targetDir, replace: true });

    expect(result.exitCode).toBe(1);
    expect(read(targetDir, "README.md")).toBe("# New\n");
    expect(read(`${targetDir}.relayout-backup`, "README.md")).toBe("# Old\n");
  });

  it("refuses a temp session whose frames are gone though the video survives", async () => {
    const { sliceDir, targetDir, framesDir } = makeFixture();
    fs.rmSync(framesDir, { recursive: true, force: true });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  it("refuses a temp session holding several videos, since the primary is not recorded", async () => {
    const { sliceDir, targetDir, workDir } = makeFixture();
    // An X post with two videos: yt-dlp writes each as `<media id>.<ext>`.
    writeTree(workDir, {
      "1800000000000000002.mp4": "video-2",
      "1800000000000000002.info.json": "{}",
      "1800000000000000002.en.vtt": "WEBVTT\n",
    });
    const stderr = vi.spyOn(process.stderr, "write").mockImplementation(() => true);

    const result = await relayoutSlice({ sliceDir, targetDir });
    const message = stderr.mock.calls.map(([chunk]) => String(chunk)).join("");
    stderr.mockRestore();

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
    expect(message).toContain("1800000000000000002.mp4");
    expect(message).toContain(`${VIDEO_ID}.mp4`);
  });

  it("refuses a temp session whose info JSON is gone though the video survives", async () => {
    const { sliceDir, targetDir, workDir } = makeFixture();
    fs.rmSync(path.join(workDir, `${VIDEO_ID}.info.json`));

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  it.each([
    [
      "is the backup path",
      (/** @type {string} */ parent) => path.join(parent, "out.relayout-backup"),
    ],
    [
      "sits inside the backup path",
      (/** @type {string} */ parent) => path.join(parent, "out.relayout-backup", "slice"),
    ],
    [
      "sits inside a staging dir",
      (/** @type {string} */ parent) => path.join(parent, ".out.relayout-abc123", "slice"),
    ],
  ])("refuses when the slice %s of the target", async (_label, toSlice) => {
    const { sliceDir: original } = makeFixture();
    const parent = makeDir("relayout-overlap-");
    const sliceDir = toSlice(parent);
    fs.mkdirSync(path.dirname(sliceDir), { recursive: true });
    fs.renameSync(original, sliceDir);
    const before = fs.readdirSync(sliceDir).sort();

    const result = await relayoutSlice({
      sliceDir,
      targetDir: path.join(parent, "out"),
      replace: true,
    });

    expect(result.exitCode).toBe(1);
    expect(fs.readdirSync(sliceDir).sort()).toEqual(before);
    expect(fs.existsSync(path.join(parent, "out"))).toBe(false);
  });

  it("refuses a slice holding a symlink, which a copy would follow", async () => {
    const { sliceDir, targetDir } = makeFixture();
    const outside = path.join(makeDir("relayout-secret-"), "secret.md");
    fs.writeFileSync(outside, "secret\n");
    fs.symlinkSync(outside, path.join(sliceDir, "research", "leak.md"));

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  it.each([
    ["outside the OS temp dir", () => path.join(path.parse(os.tmpdir()).root, "relayout-not-tmp")],
    ["the slice itself", (/** @type {string} */ slice) => slice],
  ])("refuses a recorded temp dir %s", async (_label, toWorkDir) => {
    const { sliceDir, targetDir } = makeFixture();
    const statePath = path.join(sliceDir, "run-state", "watch.json");
    const state = JSON.parse(read(sliceDir, "run-state/watch.json"));
    state.tempSession.workDir = toWorkDir(sliceDir);
    fs.writeFileSync(statePath, JSON.stringify(state));

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  it.each([
    [
      "frame-times.json is gone",
      (/** @type {string} */ dir) => fs.rmSync(path.join(dir, "frame-times.json")),
    ],
    [
      "a frame frame-times.json lists is gone",
      (/** @type {string} */ dir) => fs.rmSync(path.join(dir, "scene_0001.png")),
    ],
    [
      "a scene frame has no frame-times.json entry",
      (/** @type {string} */ dir) => fs.writeFileSync(path.join(dir, "scene_0002.png"), "png"),
    ],
    [
      "an interval frame has no frame-times.json entry",
      (/** @type {string} */ dir) => fs.writeFileSync(path.join(dir, "interval_0001.png"), "png"),
    ],
    [
      "frame-times.json holds null",
      (/** @type {string} */ dir) => fs.writeFileSync(path.join(dir, "frame-times.json"), "null"),
    ],
    [
      "frame-times.json holds an array",
      (/** @type {string} */ dir) =>
        fs.writeFileSync(path.join(dir, "frame-times.json"), '["scene_0001.png"]'),
    ],
    [
      "a frame-times.json record is not an object",
      (/** @type {string} */ dir) =>
        fs.writeFileSync(path.join(dir, "frame-times.json"), '{"scene_0001.png": 1}'),
    ],
    [
      "a frame-times.json record has no timestampSec",
      (/** @type {string} */ dir) =>
        fs.writeFileSync(
          path.join(dir, "frame-times.json"),
          '{"scene_0001.png": {"timestampSource": "scene-detection"}}',
        ),
    ],
    [
      "a frame-times.json record has a non-numeric timestampSec",
      (/** @type {string} */ dir) =>
        fs.writeFileSync(
          path.join(dir, "frame-times.json"),
          '{"scene_0001.png": {"timestampSec": "1.5"}}',
        ),
    ],
    [
      "only the sidecar is left",
      (/** @type {string} */ dir) => {
        for (const name of fs.readdirSync(dir).filter((file) => file.endsWith(".png"))) {
          fs.rmSync(path.join(dir, name));
        }
      },
    ],
  ])("refuses a temp session where %s", async (_label, damage) => {
    const { sliceDir, targetDir, framesDir } = makeFixture();
    damage(framesDir);

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  it("refuses a temp session holding a symlink, which a copy would follow", async () => {
    const { sliceDir, targetDir, framesDir } = makeFixture();
    const outside = path.join(makeDir("relayout-secret-"), "secret.png");
    fs.writeFileSync(outside, "secret");
    fs.symlinkSync(outside, path.join(framesDir, "anchor_00030000_0002.png"));

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  it("refuses, without throwing, a target whose parent is a file", async () => {
    const { sliceDir } = makeFixture();
    const blocker = path.join(makeDir("relayout-blocker-"), "file");
    fs.writeFileSync(blocker, "");

    const result = await relayoutSlice({ sliceDir, targetDir: path.join(blocker, "out") });

    expect(result.exitCode).toBe(1);
  });

  it.each([
    [
      "inside the recorded workDir",
      (/** @type {Record<string, string>} */ dirs) => path.join(dirs.workDir, "out"),
    ],
    [
      "the recorded framesDir itself",
      (/** @type {Record<string, string>} */ dirs) => dirs.framesDir,
    ],
    [
      "holding a recorded contactSheetsDir",
      (/** @type {Record<string, string>} */ dirs) => path.dirname(dirs.contactSheetsDir),
    ],
    [
      "inside a recorded contactSheetsDir that no longer exists",
      (/** @type {Record<string, string>} */ dirs) => path.join(dirs.contactSheetsDir, "out"),
    ],
  ])("refuses, even under --no-media, a target %s", async (_label, toTarget) => {
    const { sliceDir, workDir, framesDir } = makeFixture();
    // `close` already removed this one; its parent holds nothing else.
    const contactSheetsDir = path.join(makeDir("relayout-holder-"), "sheets");
    const statePath = path.join(sliceDir, "run-state", "watch.json");
    const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
    state.tempSession.contactSheetsDir = contactSheetsDir;
    fs.writeFileSync(statePath, JSON.stringify(state));
    const targetDir = toTarget({ workDir, framesDir, contactSheetsDir });
    const before = fs.readdirSync(framesDir).sort();

    const result = await relayoutSlice({ sliceDir, targetDir, noMedia: true, replace: true });

    expect(result.exitCode).toBe(1);
    expect(fs.readdirSync(framesDir).sort()).toEqual(before);
    expect(fs.existsSync(path.join(workDir, "out"))).toBe(false);
    expect(fs.existsSync(contactSheetsDir)).toBe(false);
  });

  it("refuses an empty video file", async () => {
    const { sliceDir, targetDir, workDir } = makeFixture();
    fs.writeFileSync(path.join(workDir, `${VIDEO_ID}.mp4`), "");

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  it("refuses a captioned temp session whose caption tracks are gone", async () => {
    const { sliceDir, targetDir, workDir } = makeFixture();
    for (const name of fs.readdirSync(workDir).filter((file) => file.endsWith(".vtt"))) {
      fs.rmSync(path.join(workDir, name));
    }

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  /**
   * @param {string} sliceDir
   * @param {Record<string, unknown>} transcriptMetrics
   * @param {string} workDir
   */
  function withTranscriptMetricsAndNoCaptions(sliceDir, transcriptMetrics, workDir) {
    const statePath = path.join(sliceDir, "run-state", "watch.json");
    const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
    // What recover-watch-bootstrap.js writes: acquire and transcript carry only `recovered`.
    state.phases = {
      acquire: { metrics: { videoDownloaded: true, recovered: true } },
      transcript: { metrics: transcriptMetrics },
    };
    fs.writeFileSync(statePath, JSON.stringify(state));
    for (const name of fs.readdirSync(workDir).filter((file) => file.endsWith(".vtt"))) {
      fs.rmSync(path.join(workDir, name));
    }
  }

  it("refuses a bootstrap-recovered session whose caption tracks are gone", async () => {
    const { sliceDir, targetDir, workDir } = makeFixture();
    withTranscriptMetricsAndNoCaptions(sliceDir, { recovered: true }, workDir);

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  it("still requires caption tracks when a caption transcript records a degradation", async () => {
    const { sliceDir, targetDir, workDir } = makeFixture();
    // write-transcript.js sets transcriptDegradation to the caption's
    // provenanceNote even when that caption produced the transcript.
    withTranscriptMetricsAndNoCaptions(
      sliceDir,
      { transcriptStrategy: "captions", transcriptDegradation: "auto captions only" },
      workDir,
    );

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  it("needs no caption tracks when no entry produced a transcript", async () => {
    const { sliceDir, targetDir, workDir } = makeFixture();
    withTranscriptMetricsAndNoCaptions(
      sliceDir,
      { skipped: true, reason: "no transcript-bearing entries" },
      workDir,
    );

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
  });

  it("needs no caption tracks when the transcript came from ASR", async () => {
    const { sliceDir, targetDir, workDir } = makeFixture();
    withTranscriptMetricsAndNoCaptions(sliceDir, { transcriptStrategy: "asr" }, workDir);

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(fs.existsSync(path.join(targetDir, "transcript/en.vtt"))).toBe(false);
  });
});

describe("relayoutSlice input shapes and reference forms (adversarial sweep)", () => {
  /** @param {string} sliceDir @param {(state: Record<string, any>) => unknown} edit */
  function editState(sliceDir, edit) {
    const statePath = path.join(sliceDir, "run-state", "watch.json");
    const next = edit(JSON.parse(fs.readFileSync(statePath, "utf8")));
    fs.writeFileSync(statePath, JSON.stringify(next));
  }

  it.each([
    ["a videoId that is a path", (/** @type {any} */ s) => ({ ...s, videoId: "../../escaped" })],
    ["no title", (/** @type {any} */ s) => ({ ...s, title: undefined })],
    ["no sourceUrl", (/** @type {any} */ s) => ({ ...s, sourceUrl: "" })],
    ["null instead of an object", () => null],
    [
      "a temp dir that is not a string",
      (/** @type {any} */ s) => ({ ...s, tempSession: { ...s.tempSession, workDir: 123 } }),
    ],
  ])("refuses, without throwing, a watch.json with %s", async (_label, edit) => {
    const { sliceDir, targetDir } = makeFixture();
    editState(sliceDir, edit);

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.readdirSync(path.dirname(targetDir))).toEqual([]);
  });

  it("rewrites reference-style definitions, HTML src, encoded, spaced and backslash paths", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "research/findings/my notes.md": "notes\n",
        "key-frames/visual-frames.md": [
          '[defined][1] and <img src="frames/title-slide.png">',
          "[spaced](<../research/findings/my notes.md>) [encoded](../research/findings/my%20notes.md)",
          "Windows: `frames\\title-slide.png`.",
          "",
          "[1]: ../source/transcript.txt",
          "",
        ].join("\n"),
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      [
        '[defined][1] and <img src="key/title-slide.png">',
        "[spaced](<../analysis/research/findings/my notes.md>) [encoded](../analysis/research/findings/my%20notes.md)",
        "Windows: `key/title-slide.png`.",
        "",
        "[1]: ../transcript/transcript.txt",
        "",
      ].join("\n"),
    );
  });

  it("rewrites link destinations holding balanced or escaped parentheses", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "source/decks/session-1/slides_(final).pdf": "pdf",
        "key-frames/visual-frames.md": [
          "[balanced](../source/decks/session-1/slides_(final).pdf)",
          '[escaped](../source/decks/session-1/slides_\\(final\\).pdf "Deck")',
          "",
        ].join("\n"),
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      [
        "[balanced](../metadata/decks/session-1/slides_(final).pdf)",
        '[escaped](../metadata/decks/session-1/slides_\\(final\\).pdf "Deck")',
        "",
      ].join("\n"),
    );
  });

  it("flags a missing destination with parentheses rather than a truncated one", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, { "metadata/deck-inventory.md": "[deck](decks/slides_(v2).pdf)\n" });

    expect(checkLayoutLinks(root)).toEqual([
      { file: "metadata/deck-inventory.md", ref: "decks/slides_(v2).pdf" },
    ]);
  });

  it("skips backslash-escaped delimiters inside quoted and parenthesized titles", () => {
    expect(
      inlineLinks(
        '[a](a.md "say \\"hi\\"") [b](b.md \'it\\\'s\') [c](c.md (one \\) two)) [d](d.md)',
      ).map(({ dest }) => dest),
    ).toEqual(["a.md", "b.md", "c.md", "d.md"]);
  });

  it("reads a link with a parenthesized title and rewrites its destination", async () => {
    expect(inlineLinks("[x](a.md (Title)) and [y](b.md)").map(({ dest }) => dest)).toEqual([
      "a.md",
      "b.md",
    ]);
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "key-frames/visual-frames.md": "[t](../source/transcript.txt (The transcript))\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      "[t](../transcript/transcript.txt (The transcript))\n",
    );
  });

  it("reads a title on the next line after the destination", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "key-frames/visual-frames.md": '[t](../source/transcript.txt\n  "The transcript")\n',
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      '[t](../transcript/transcript.txt\n  "The transcript")\n',
    );
  });

  it("keeps a nested image's rewrite when the outer link names a dropped file", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "key-frames/visual-frames.md":
          "[![slide](frames/title-slide.png)](../run-state/watch.json)\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      "![slide](key/title-slide.png) (run-state/watch.json, not retained in this copy)\n",
    );
  });

  it("reads an image nested in a link as two links with the right labels", () => {
    expect(
      inlineLinks("[![alt](a.png)](b.md)").map(({ dest, label }) => ({ dest, label })),
    ).toEqual([
      { dest: "a.png", label: "alt" },
      { dest: "b.md", label: "![alt](a.png)" },
    ]);
  });

  it("rewrites single-quoted and unquoted HTML src and href", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "key-frames/visual-frames.md":
          "<img src='frames/title-slide.png'> <a href=../source/transcript.txt>t</a>\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      "<img src='key/title-slide.png'> <a href=../transcript/transcript.txt>t</a>\n",
    );
  });

  it("rewrites percent-encoded #, ? and space in path segments, keeping the encoding", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "research/findings/notes#1.md": "n\n",
        "research/findings/what?.md": "w\n",
        "key-frames/visual-frames.md":
          "[a](../research/findings/notes%231.md) [b](../research/findings/what%3F.md#top)\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      "[a](../analysis/research/findings/notes%231.md) [b](../analysis/research/findings/what%3F.md#top)\n",
    );
  });

  it("rewrites and checks upper-case HTML attribute names", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "key-frames/visual-frames.md": '<IMG SRC="frames/title-slide.png">\n' },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe('<IMG SRC="key/title-slide.png">\n');
    const root = makeDir("relayout-check-");
    writeTree(root, { "frames/visual-frames.md": "<A HREF='key/gone.png'>x</A>\n" });
    expect(checkLayoutLinks(root)).toEqual([
      { file: "frames/visual-frames.md", ref: "key/gone.png" },
    ]);
  });

  it("flags a single-quoted HTML src that does not resolve", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, { "frames/visual-frames.md": "<img src='key/gone.png'>\n" });

    expect(checkLayoutLinks(root)).toEqual([
      { file: "frames/visual-frames.md", ref: "key/gone.png" },
    ]);
  });

  it.each([
    ["null", "null"],
    ["an array", "[]"],
    ["corrupt JSON", "{"],
  ])("refuses, before staging, an info JSON holding %s", async (_label, body) => {
    const { sliceDir, targetDir, workDir } = makeFixture();
    fs.writeFileSync(path.join(workDir, `${VIDEO_ID}.info.json`), body);

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.readdirSync(path.dirname(targetDir))).toEqual([]);
  });

  it("flags a reference-style definition to a path that does not exist", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "research/claim-inventory.md": "[gone][g]\n\n[g]: findings/gone.md\n" },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([
      { file: "analysis/research/claim-inventory.md", ref: "findings/gone.md" },
    ]);
  });

  it("treats an outside path whose directory shares the slice's name as outside", async () => {
    const { sliceDir, targetDir } = makeFixture();
    const slug = path.basename(sliceDir);
    const outsideRef = `../../repos/${slug}/source/transcript.txt`;
    fs.writeFileSync(path.join(sliceDir, "research", "claim-inventory.md"), `[x](${outsideRef})\n`);
    const pointedAt = path.resolve(sliceDir, "research", outsideRef);

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    const link = /\]\(([^)]+)\)/.exec(read(targetDir, "analysis/research/claim-inventory.md"))?.[1];
    expect(path.resolve(targetDir, "analysis/research", String(link))).toBe(pointedAt);
  });

  it("accepts an untimed frame-times.json record (timestampSec null, as the writer emits)", async () => {
    const { sliceDir, targetDir, framesDir } = makeFixture();
    fs.writeFileSync(
      path.join(framesDir, "frame-times.json"),
      JSON.stringify({ "scene_0001.png": { timestampSec: null, timestampSource: null } }),
    );

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
  });

  it.each([
    [
      "../<slice>/ from the slice root",
      "RESEARCH.md",
      (/** @type {string} */ slug) => `../${slug}/`,
    ],
    ["../ from a lane file", "research/claim-inventory.md", () => "../"],
  ])(
    "rewrites a reference to the slice dir itself (%s) as split text",
    async (_label, file, ref) => {
      const { sliceDir, targetDir } = makeFixture();
      const slug = path.basename(sliceDir);
      fs.writeFileSync(path.join(sliceDir, file), `Whole slice: [slice](${ref(slug)}).\n`);

      const result = await relayoutSlice({ sliceDir, targetDir });

      expect(result.exitCode).toBe(0);
      const target = file === "RESEARCH.md" ? "analysis/RESEARCH.md" : `analysis/${file}`;
      expect(read(targetDir, target)).toBe(
        `Whole slice: slice (${slug}, split across analysis/, frames/, metadata/, transcript/ in this copy).\n`,
      );
    },
  );

  it("reads a path that leaves and re-enters the slice as the slice's", async () => {
    const { sliceDir, targetDir } = makeFixture();
    const slug = path.basename(sliceDir);
    fs.writeFileSync(path.join(sliceDir, "RESEARCH.md"), `[t](../${slug}/source/transcript.txt)\n`);

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "analysis/RESEARCH.md")).toBe("[t](../transcript/transcript.txt)\n");
  });

  it("reads the .work/<epic>/<slug> form only with the slice's own work path", async () => {
    const { sliceDir: original, targetDir } = makeFixture();
    const slug = path.basename(original);
    const sliceDir = path.join(makeDir("relayout-root-"), ".work", "youtube-watch", slug);
    fs.mkdirSync(path.dirname(sliceDir), { recursive: true });
    fs.renameSync(original, sliceDir);
    fs.writeFileSync(
      path.join(sliceDir, "recommendations", "questions.md"),
      [
        `Own: \`.work/youtube-watch/${slug}/source/transcript.txt\`.`,
        `Other epic: \`.work/other-epic/${slug}/source/transcript.txt\`.`,
        "",
      ].join("\n"),
    );

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "analysis/recommendations/questions.md")).toBe(
      [
        "Own: `../../transcript/transcript.txt`.",
        `Other epic: \`.work/other-epic/${slug}/source/transcript.txt\`.`,
        "",
      ].join("\n"),
    );
  });

  it("keeps a link that leaves the slice pointing at the same file from its deeper location", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "research/claim-inventory.md": "[other](../../other-slice/RESEARCH.md)\n" },
    });
    const sibling = path.join(path.dirname(sliceDir), "other-slice", "RESEARCH.md");

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    const link = /\]\(([^)]+)\)/.exec(read(targetDir, "analysis/research/claim-inventory.md"))?.[1];
    expect(path.resolve(targetDir, "analysis/research", String(link))).toBe(sibling);
  });

  it("leaves another repo's lane-named path in RESEARCH.md alone", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "RESEARCH.md": "Upstream: `research/deepening/html-report.md:92` in mattpocock/skills.\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
  });

  it.each([
    [
      "an empty caption track",
      (/** @type {Record<string, string>} */ d) =>
        fs.writeFileSync(path.join(d.workDir, `${VIDEO_ID}.en.vtt`), ""),
    ],
    [
      "an empty frame image",
      (/** @type {Record<string, string>} */ d) =>
        fs.writeFileSync(path.join(d.framesDir, "anchor_00012000_0001.png"), ""),
    ],
  ])("refuses a temp session with %s", async (_label, damage) => {
    const { sliceDir, targetDir, workDir, framesDir } = makeFixture();
    damage({ workDir, framesDir });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
  });
});

describe("checkLayoutLinks", () => {
  it("stays quiet on URLs, placeholders, other-repository paths and resolvable paths", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "transcript/transcript.txt": "",
      "analysis/RESEARCH.md": [
        "[docs](https://code.claude.com/docs/en/hooks) and <https://example.com/a/b>.",
        "Paths: `plugins/knowledge/SKILL.md`, `docs/adr/0001.md`, `templates/x.md`, `.claude/rules/a.md`.",
        "Links: [skill](plugins/knowledge/SKILL.md), [adr](docs/adr/0001.md), [rules](AGENTS.md).",
        "[agents](../../../AGENTS.md), `AGENTS.md`, `mattpocock/skills`, `/code-review`.",
        "Temp: `{tmp}/video-frames-x/scene_0001.png`, `<tmpdir>/report-<ts>.html`.",
        "Outside the slice: `../../other-repo/README.md`. Inside: `../transcript/transcript.txt`.",
        "[anchor](#verdicts)",
        "",
      ].join("\n"),
    });

    expect(checkLayoutLinks(root)).toEqual([]);
  });

  it("flags an unresolved path under a slice lane whose directory the slice had", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "recommendations/questions.md":
          "Typo: `source/missing.txt`. Upstream: `research/deepening/html-report.md:92`.\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([
      { file: "analysis/recommendations/questions.md", ref: "source/missing.txt" },
    ]);
  });

  it("says so when prose names a lane folder this slice never produced", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "key-frames/vision-plan.md": "No deck in the `source/decks/` lane.\n" },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/vision-plan.md")).toBe(
      "No deck in the source/decks (none in this slice) lane.\n",
    );
  });

  it("treats any lane-named path as the slice's when no slice directories are given", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, { "analysis/RESEARCH.md": "See `run-state/watch.json`.\n" });

    expect(checkLayoutLinks(root)).toEqual([
      { file: "analysis/RESEARCH.md", ref: "run-state/watch.json" },
    ]);
  });

  it("flags a bare extracted-frame name but not other bare file names", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "frames/all/scene_0001.png": "png",
      "frames/visual-frames.md":
        "Kept: `all/scene_0001.png`. Dangling: `anchor_00012000_0003.png`. Prose: `SKILL.md`, `README.md`.\n",
    });

    expect(checkLayoutLinks(root)).toEqual([
      { file: "frames/visual-frames.md", ref: "anchor_00012000_0003.png" },
    ]);
  });
});
