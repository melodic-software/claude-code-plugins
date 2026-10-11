import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  checkLayoutLinks,
  encodeDestination,
  inlineLinks,
  relayoutSlice,
} from "./relayout-slice.js";

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
  it("writes an upstream title with Markdown syntax as plain text in the README", async () => {
    const { sliceDir, targetDir } = makeFixture();
    const watchPath = path.join(sliceDir, "run-state/watch.json");
    const watch = JSON.parse(fs.readFileSync(watchPath, "utf8"));
    fs.writeFileSync(watchPath, JSON.stringify({ ...watch, title: "[Episode](trailer.md)\n#1" }));

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    const readme = fs.readFileSync(path.join(targetDir, "README.md"), "utf8");
    expect(readme.split("\n")[0]).toBe("# \\[Episode\\]\\(trailer\\.md\\) \\#1");
  });

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

  /**
   * Rename the temp session's video, info JSON and caption tracks to another
   * yt-dlp id, optionally writing an info JSON with `display_id`.
   *
   * @param {string} workDir
   * @param {string} id
   * @param {Record<string, unknown>} [info]
   */
  function renameMedia(workDir, id, info) {
    for (const name of fs.readdirSync(workDir)) {
      fs.renameSync(path.join(workDir, name), path.join(workDir, name.replace(VIDEO_ID, id)));
    }
    if (info) fs.writeFileSync(path.join(workDir, `${id}.info.json`), JSON.stringify(info));
  }

  it("refuses a temp session whose video is another id, naming both", async () => {
    const { sliceDir, targetDir, workDir } = makeFixture();
    renameMedia(workDir, "otherVideo1", { id: "otherVideo1", display_id: "otherVideo1" });
    const stderr = vi.spyOn(process.stderr, "write").mockImplementation(() => true);

    const result = await relayoutSlice({ sliceDir, targetDir });
    const message = stderr.mock.calls.map(([chunk]) => String(chunk)).join("");
    stderr.mockRestore();

    expect(result.exitCode).toBe(1);
    expect(message).toContain("otherVideo1");
    expect(message).toContain(VIDEO_ID);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  it("accepts an X media id whose info JSON names this slice's post as display_id", async () => {
    const { sliceDir, targetDir, workDir } = makeFixture();
    renameMedia(workDir, "1800000000000000001", {
      id: "1800000000000000001",
      display_id: VIDEO_ID,
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(fs.existsSync(path.join(targetDir, `media/${VIDEO_ID}.mp4`))).toBe(true);
  });

  it.each([false, true])(
    "refuses a recorded contact-sheets dir outside the OS temp dir (noMedia: %s)",
    async (noMedia) => {
      const { sliceDir, targetDir } = makeFixture();
      const statePath = path.join(sliceDir, "run-state", "watch.json");
      const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
      state.tempSession.contactSheetsDir = path.join(
        path.parse(os.tmpdir()).root,
        "relayout-sheets",
      );
      fs.writeFileSync(statePath, JSON.stringify(state));

      const result = await relayoutSlice({ sliceDir, targetDir, noMedia });

      expect(result.exitCode).toBe(1);
      expect(fs.existsSync(targetDir)).toBe(false);
    },
  );

  it.each([false, true])(
    "refuses a recorded contact-sheets dir that overlaps the slice (noMedia: %s)",
    async (noMedia) => {
      const { sliceDir, targetDir } = makeFixture();
      const statePath = path.join(sliceDir, "run-state", "watch.json");
      const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
      state.tempSession.contactSheetsDir = path.join(sliceDir, "key-frames");
      fs.writeFileSync(statePath, JSON.stringify(state));

      const result = await relayoutSlice({ sliceDir, targetDir, noMedia });

      expect(result.exitCode).toBe(1);
      expect(fs.existsSync(targetDir)).toBe(false);
    },
  );

  it("reads no link inside a code span that spans lines, and treats a lone backtick as text", async () => {
    const body = [
      "Code: `see [gone](../research/gone.md)",
      "and more` then [t](../source/transcript.txt).",
      "A lone ` backtick and [u](../source/transcript.txt).",
      "",
    ].join("\n");
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "key-frames/visual-frames.md": body },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      body.replaceAll("](../source/transcript.txt)", "](../transcript/transcript.txt)"),
    );
  });

  it("ends a code span search at a CRLF blank line, so a later link is still checked", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "analysis/notes.md": "A lone ` backtick.\r\n\r\n[gone](missing.md) then ` again.\r\n",
    });

    expect(checkLayoutLinks(root)).toEqual([{ file: "analysis/notes.md", ref: "missing.md" }]);
  });

  it("reads \\![x](dest) as a plain link and keeps the \\! when retiring it", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "key-frames/visual-frames.md":
          "Bang: \\![state](../run-state/watch.json) and \\![t](../source/transcript.txt).\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      "Bang: \\!state (run-state/watch.json, not retained in this copy) and \\![t](../transcript/transcript.txt).\n",
    );
  });

  it("catches, through the link check, a dangling path in a fence inside a block quote or list", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "recommendations/questions.md": [
          "> ```",
          "> [gone](../research/gone.md)",
          "> ```",
          "",
          "- item",
          "",
          "  ```",
          "  [also gone](../research/also-gone.md)",
          "  ```",
          "",
        ].join("\n"),
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([
      { file: "analysis/recommendations/questions.md", ref: "../research/gone.md" },
      { file: "analysis/recommendations/questions.md", ref: "../research/also-gone.md" },
    ]);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  it("does not read an escaped \\[label](...) as a link", async () => {
    const body = "Literal: \\[watch](../run-state/watch.json) and \\[x\\](../research/gone.md).\n";
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "key-frames/visual-frames.md": body },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(body);
  });

  it("leaves a command span alone and does not link-check it", async () => {
    const body = [
      "Run `node run.mjs source/transcript.txt --no-media` or `source/transcript.txt --verbose`.",
      "",
    ].join("\n");
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "recommendations/questions.md": body },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "analysis/recommendations/questions.md")).toBe(body);
  });

  it("leaves fenced code blocks alone and reads no link inside inline code", async () => {
    const body = [
      "Outside: [t](../source/transcript.txt).",
      "```",
      "[t](../source/transcript.txt) `source/transcript.txt` [gone](../research/gone.md)",
      "```",
      "~~~~ text",
      "[t](../source/transcript.txt)",
      "~~~~",
      "Inline: `[gone](../research/gone.md)`.",
      "",
    ].join("\n");
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "key-frames/visual-frames.md": body },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      body.replace(
        "Outside: [t](../source/transcript.txt)",
        "Outside: [t](../transcript/transcript.txt)",
      ),
    );
  });

  it.each([
    ["framesDir", "framesDir"],
    ["workDir", "workDir"],
  ])("refuses, without throwing, a recorded %s that is a file", async (_label, field) => {
    const fixture = makeFixture();
    const dir = field === "framesDir" ? fixture.framesDir : fixture.workDir;
    fs.rmSync(dir, { recursive: true, force: true });
    fs.writeFileSync(dir, "not a directory");
    const stderr = vi.spyOn(process.stderr, "write").mockImplementation(() => true);

    const result = await relayoutSlice({
      sliceDir: fixture.sliceDir,
      targetDir: fixture.targetDir,
    });
    const message = stderr.mock.calls.map(([chunk]) => String(chunk)).join("");
    stderr.mockRestore();

    expect(result.exitCode).toBe(1);
    expect(message).toContain(`${dir} is not a readable directory`);
    expect(fs.existsSync(fixture.targetDir)).toBe(false);
  });

  it("decodes backslash escapes in link and definition destinations, keeping \\# in the path", async () => {
    const body = [
      "[n](../research/findings/notes\\#1.md#intro) [q](../research/findings/what\\?.md)",
      "",
      "[def]: ../research/findings/notes\\#1.md",
      "",
    ].join("\n");
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "research/findings/notes#1.md": "n\n",
        "research/findings/what?.md": "w\n",
        "key-frames/visual-frames.md": body,
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      [
        "[n](../analysis/research/findings/notes\\#1.md#intro) [q](../analysis/research/findings/what\\?.md)",
        "",
        "[def]: ../analysis/research/findings/notes\\#1.md",
        "",
      ].join("\n"),
    );
  });

  it.skipIf(process.platform === "win32" || process.getuid?.() === 0)(
    "refuses, naming it, a slice holding an unreadable nested dir",
    async () => {
      const { sliceDir, targetDir } = makeFixture();
      const locked = path.join(sliceDir, "research", "findings");
      fs.chmodSync(locked, 0o000);
      const stderr = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
      try {
        const result = await relayoutSlice({ sliceDir, targetDir });
        const message = stderr.mock.calls.map(([chunk]) => String(chunk)).join("");

        expect(result.exitCode).toBe(1);
        expect(message).toContain(locked);
        expect(fs.readdirSync(path.dirname(targetDir))).toEqual([]);
      } finally {
        stderr.mockRestore();
        fs.chmodSync(locked, 0o755);
      }
    },
  );

  it("matches a backticked path whose name holds # or ? before reading a fragment", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "research/findings/notes#1.md": "n\n",
        "recommendations/questions.md":
          "Raw: `research/findings/notes#1.md`. Fragment: `research/findings/topic.md#intro`.\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "analysis/recommendations/questions.md")).toBe(
      "Raw: `../research/findings/notes#1.md`. Fragment: `../research/findings/topic.md#intro`.\n",
    );
  });

  it("reads a raw # in a link as a fragment, unlike the same backticked path", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "analysis/research/findings/notes#1.md": "n\n",
      "analysis/notes.md":
        "[notes](research/findings/notes#1.md) `research/findings/notes#1.md`\n",
    });

    expect(checkLayoutLinks(root)).toEqual([
      { file: "analysis/notes.md", ref: "research/findings/notes#1.md" },
    ]);
    writeTree(root, { "analysis/research/findings/notes": "n\n" });
    expect(checkLayoutLinks(root)).toEqual([]);
  });

  it("refuses a link whose raw # names a retained file only as part of the name", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "research/findings/notes#1.md": "n\n",
        "recommendations/questions.md": "[notes](research/findings/notes#1.md)\n",
      },
    });
    const stderr = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    try {
      const result = await relayoutSlice({ sliceDir, targetDir });

      expect(result.exitCode).toBe(1);
      expect(result.unresolved).toHaveLength(1);
      expect(result.unresolved[0].ref).toMatch(/research\/findings\/notes#1\.md$/);
    } finally {
      stderr.mockRestore();
    }
  });

  it.each([
    [
      "a frame name that is a directory",
      (/** @type {Record<string, string>} */ d) =>
        fs.mkdirSync(path.join(d.framesDir, "anchor_00030000_0002.png")),
    ],
    [
      "a frame-times.json that is a directory",
      (/** @type {Record<string, string>} */ d) => {
        fs.rmSync(path.join(d.framesDir, "frame-times.json"));
        fs.mkdirSync(path.join(d.framesDir, "frame-times.json"));
      },
    ],
  ])("refuses %s, naming it", async (label, damage) => {
    const { sliceDir, targetDir, workDir, framesDir } = makeFixture();
    damage({ workDir, framesDir });
    const stderr = vi.spyOn(process.stderr, "write").mockImplementation(() => true);

    const result = await relayoutSlice({ sliceDir, targetDir });
    const message = stderr.mock.calls.map(([chunk]) => String(chunk)).join("");
    stderr.mockRestore();

    expect(result.exitCode).toBe(1);
    expect(message).toContain("regular files for the frames entries");
    expect(message).toContain(
      label.includes("frame-times") ? "frame-times.json" : "anchor_00030000_0002.png",
    );
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  it("refuses, naming it, a frame-times.json key that is a directory", async () => {
    const { sliceDir, targetDir, framesDir } = makeFixture();
    fs.writeFileSync(
      path.join(framesDir, "frame-times.json"),
      JSON.stringify({ "scene_0001.png": { timestampSec: 1 }, scene_0002: { timestampSec: 2 } }),
    );
    fs.mkdirSync(path.join(framesDir, "scene_0002"));
    const stderr = vi.spyOn(process.stderr, "write").mockImplementation(() => true);

    const result = await relayoutSlice({ sliceDir, targetDir });
    const message = stderr.mock.calls.map(([chunk]) => String(chunk)).join("");
    stderr.mockRestore();

    expect(result.exitCode).toBe(1);
    expect(message).toContain("scene_0002");
    expect(fs.existsSync(targetDir)).toBe(false);
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

  // CommonMark: a backslash-escaped bracket is literal link text, so the link
  // opens at the unescaped `[` before it.
  it("reads a link whose text holds an escaped opening bracket", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "key-frames/visual-frames.md": "[see \\[draft](../source/transcript.txt)\n" },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      "[see \\[draft](../transcript/transcript.txt)\n",
    );
  });

  // CommonMark: entity and numeric character references are decoded in link
  // destinations, so `a&amp;b.pdf` names the file `a&b.pdf`.
  it("decodes character references in link and definition destinations", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "source/decks/a&b.pdf": "pdf",
        "key-frames/visual-frames.md": [
          "[deck](../source/decks/a&amp;b.pdf)",
          "[hex][d]",
          "",
          "[d]: ../source/decks/a&#x26;b.pdf",
          "",
        ].join("\n"),
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      [
        "[deck](../metadata/decks/a&amp;b.pdf)",
        "[hex][d]",
        "",
        "[d]: ../metadata/decks/a&amp;b.pdf",
        "",
      ].join("\n"),
    );
  });

  it("keeps a link whose destination names a retained file by a windows-1252 reference", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "source/decks/€.pdf": "pdf",
        "key-frames/visual-frames.md": "[deck](../source/decks/&#x80;.pdf)\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "metadata/decks/€.pdf")).toBe("pdf");
  });

  // The HTML parser decodes references before the URL parser drops tab, LF and CR,
  // so an encoded line break in an attribute is removed too.
  it("drops a line break written as a reference in an HTML URL", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "transcript/transcript.txt": "[0:01] hi\n",
      "metadata/notes.md": '<a href="../transcript/&#10;transcript.txt">t</a>\n',
    });

    expect(checkLayoutLinks(root)).toEqual([]);
  });

  // HTML attributes accept a numeric reference without its semicolon; Markdown
  // destinations do not, so only the attribute is decoded.
  it("decodes semicolonless numeric references in HTML attributes only", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "metadata/decks/a&b.pdf": "pdf",
      "metadata/deck-inventory.md":
        '<a href="decks/a&#38b.pdf">deck</a>\n[md](decks/c&#38d.pdf)\n',
    });

    expect(checkLayoutLinks(root)).toEqual([
      { file: "metadata/deck-inventory.md", ref: "decks/c&#38d.pdf" },
    ]);
  });

  // HTML attributes decode a legacy named reference without its semicolon,
  // except before a letter, digit or `=`: `&amp.` is `&`, `&ampx` stays.
  it("decodes a semicolonless legacy named reference in an HTML attribute", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "metadata/decks/a&.pdf": "pdf",
      "metadata/decks/a&x.pdf": "pdf",
      "metadata/deck-inventory.md":
        '<a href="decks/a&amp.pdf">deck</a>\n<a href="decks/a&ampx.pdf">x</a>\n',
    });

    expect(checkLayoutLinks(root)).toEqual([
      { file: "metadata/deck-inventory.md", ref: "decks/a&ampx.pdf" },
    ]);
  });

  // HTML numeric character reference replacements: 0x80 is windows-1252's
  // euro sign (U+20AC), and 0 becomes U+FFFD.
  it("applies HTML's numeric character reference replacements", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "metadata/decks/€.pdf": "pdf",
      "metadata/deck-inventory.md": "[deck](decks/&#x80;.pdf)\n",
    });

    expect(checkLayoutLinks(root)).toEqual([]);
    const replacement = String.fromCodePoint(0xfffd);
    expect(
      inlineLinks("[a](a&#0;b.md) [b](&#xD800;.md) [c](&#x110000;.md) [d](&#x81;.md)").map(
        ({ dest }) => dest,
      ),
    ).toEqual([`a${replacement}b.md`, `${replacement}.md`, `${replacement}.md`, "\u0081.md"]);
  });

  it("resolves a destination holding a character reference in the link check", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "metadata/decks/a&b.pdf": "pdf",
      "metadata/deck-inventory.md": "[deck](decks/a&amp;b.pdf) [gone](decks/c&amp;d.pdf)\n",
    });

    expect(checkLayoutLinks(root)).toEqual([
      { file: "metadata/deck-inventory.md", ref: "decks/c&d.pdf" },
    ]);
  });

  // Only `&amp; &lt; &gt; &quot; &apos;` and numeric references are decoded
  // (a documented limit): any other named reference stays as written, so the
  // destination names no file and the run fails closed instead of passing.
  it("refuses, naming it, a destination holding a named reference it does not decode", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "source/decks/a@b.pdf": "pdf",
        "key-frames/visual-frames.md": "[deck](../source/decks/a&commat;b.pdf)\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([
      { file: "frames/visual-frames.md", ref: "../metadata/decks/a&commat;b.pdf" },
    ]);
    expect(fs.existsSync(targetDir)).toBe(false);
  });

  // `:` is not allowed in a Windows file name.
  it.skipIf(process.platform === "win32")(
    "maps a code-span path whose real name ends in :12 before reading it as a line suffix",
    async () => {
      const { sliceDir, targetDir } = makeFixture({
        extraFiles: {
          "source/decks/slide.pdf:12": "pdf",
          "key-frames/vision-plan.md": "Deck: `source/decks/slide.pdf:12`.\n",
        },
      });

      const result = await relayoutSlice({ sliceDir, targetDir });

      expect(result.exitCode).toBe(0);
      expect(read(targetDir, "metadata/decks/slide.pdf:12")).toBe("pdf");
      expect(read(targetDir, "frames/vision-plan.md")).toBe(
        "Deck: `../metadata/decks/slide.pdf:12`.\n",
      );
    },
  );

  // `:` is not allowed in a Windows file name.
  it.skipIf(process.platform === "win32")(
    "maps a linked path whose real name ends in :12 before reading it as a line suffix",
    async () => {
      const { sliceDir, targetDir } = makeFixture({
        extraFiles: {
          "source/decks/slide.pdf:12": "pdf",
          "key-frames/vision-plan.md": [
            "Deck: [deck](source/decks/slide.pdf:12).",
            '<a href="source/decks/slide.pdf:12">deck</a>',
            "",
            "[d]: source/decks/slide.pdf:12",
            "",
          ].join("\n"),
        },
      });

      const result = await relayoutSlice({ sliceDir, targetDir });

      expect(result.exitCode).toBe(0);
      expect(read(targetDir, "frames/vision-plan.md")).toBe(
        [
          "Deck: [deck](../metadata/decks/slide.pdf:12).",
          '<a href="../metadata/decks/slide.pdf:12">deck</a>',
          "",
          "[d]: ../metadata/decks/slide.pdf:12",
          "",
        ].join("\n"),
      );
    },
  );

  // Creating a symlink on Windows needs a privilege a test run may lack.
  it.skipIf(process.platform === "win32")(
    "refuses, naming it, a recorded temp dir that is itself a symlink",
    async () => {
      const { sliceDir, workDir, targetDir } = makeFixture();
      const link = path.join(makeDir("relayout-link-"), "work");
      fs.symlinkSync(workDir, link);
      editState(sliceDir, (s) => ({ ...s, tempSession: { ...s.tempSession, workDir: link } }));
      const stderr = vi.spyOn(process.stderr, "write").mockImplementation(() => true);

      const result = await relayoutSlice({ sliceDir, targetDir });
      const message = stderr.mock.calls.map(([chunk]) => String(chunk)).join("");
      stderr.mockRestore();

      expect(result.exitCode).toBe(1);
      expect(message).toContain(`${link} is a symlink`);
      expect(fs.existsSync(targetDir)).toBe(false);
    },
  );

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

  // CommonMark ends a bare destination only at the ASCII space or a control.
  it("keeps non-ASCII whitespace inside a bare destination", () => {
    const nbsp = String.fromCodePoint(0xa0);
    expect(inlineLinks(`[deck](../source/decks/a${nbsp}b.pdf)`).map(({ dest }) => dest)).toEqual([
      `../source/decks/a${nbsp}b.pdf`,
    ]);
  });

  // CommonMark: a link title may span lines but not a blank line (one holding
  // only spaces or tabs); with such a title the construct is not a link.
  it("reads no link or definition whose title spans a blank line", () => {
    expect(inlineLinks('[example](missing.md "title\n\ncontinued")')).toEqual([]);
    expect(inlineLinks("[example](missing.md (title\n \t\ncontinued))")).toEqual([]);
    expect(inlineLinks('[ok](kept.md "title\ncontinued")').map(({ dest }) => dest)).toEqual([
      "kept.md",
    ]);
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "metadata/notes.md": [
        '[example](missing.md "title',
        "",
        'continued")',
        "",
        "[d]: gone.md 'title",
        "  ",
        "continued'",
        "",
        '[e]: lost.md "title',
        'continued"',
        "",
      ].join("\n"),
    });

    expect(checkLayoutLinks(root)).toEqual([{ file: "metadata/notes.md", ref: "lost.md" }]);
  });

  // CommonMark: a (...) title holds no unescaped parenthesis, so this is no link.
  it("reads no link whose parenthesized title holds a bare parenthesis", () => {
    expect(inlineLinks("[example](missing.md (title(with paren))")).toEqual([]);
  });

  // CommonMark: an autolink binds before link grouping, so its `](` is no link.
  it("flags no link inside a URI autolink", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "metadata/notes.md": "[foo<https://example.com/?search=](missing.md)>\n",
    });

    expect(checkLayoutLinks(root)).toEqual([]);
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

  it("reads an outer link whose label holds a link as literal text", () => {
    expect(inlineLinks("[outer [real](ok.md)](missing.md)").map(({ dest }) => dest)).toEqual([
      "ok.md",
    ]);
  });

  it("leaves the literal outer text of a link holding a link untouched", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "key-frames/visual-frames.md":
          "[outer [t](../source/transcript.txt)](missing.md)\n" +
          "[outer [t](../source/transcript.txt)](../run-state/watch.json)\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      "[outer [t](../transcript/transcript.txt)](missing.md)\n" +
        "[outer [t](../transcript/transcript.txt)](../run-state/watch.json)\n",
    );
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

  it("decodes HTML character references in src and href, re-encoding & as the original did", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "source/decks/s1/a&b.pdf": "pdf",
        "key-frames/visual-frames.md":
          '<a href="../source/decks/s1/a&amp;b.pdf">deck</a> <img src="frames/title&#45;slide.png">\n',
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      '<a href="../metadata/decks/s1/a&amp;b.pdf">deck</a> <img src="key/title-slide.png">\n',
    );
    const root = makeDir("relayout-check-");
    writeTree(root, { "frames/visual-frames.md": '<img src="key/x&amp;y.png">\n' });
    expect(checkLayoutLinks(root)).toEqual([
      { file: "frames/visual-frames.md", ref: "key/x&y.png" },
    ]);
  });

  it.skipIf(process.platform === "win32")(
    "escapes a rewritten src/href value for its quoting",
    async () => {
      const { sliceDir, targetDir } = makeFixture({
        extraFiles: {
          'source/decks/s1/a"b.pdf': "pdf",
          "source/decks/s1/it's.pdf": "pdf",
          "source/decks/s1/a&b.pdf": "pdf",
          "key-frames/visual-frames.md": [
            '<a href="../source/decks/s1/a&quot;b.pdf">dq</a>',
            "<a href='../source/decks/s1/it&#39;s.pdf'>sq</a>",
            "<a href=../source/decks/s1/it&#39;s.pdf>bare</a>",
            '<a href="../source/decks/s1/a&b.pdf">raw amp</a>',
            "",
          ].join("\n"),
        },
      });

      const result = await relayoutSlice({ sliceDir, targetDir });

      expect(result.exitCode).toBe(0);
      expect(read(targetDir, "frames/visual-frames.md")).toBe(
        [
          '<a href="../metadata/decks/s1/a&quot;b.pdf">dq</a>',
          "<a href='../metadata/decks/s1/it&#39;s.pdf'>sq</a>",
          '<a href="../metadata/decks/s1/it\'s.pdf">bare</a>',
          '<a href="../metadata/decks/s1/a&amp;b.pdf">raw amp</a>',
          "",
        ].join("\n"),
      );
    },
  );

  it.skipIf(process.platform === "win32")(
    "maps a real file whose name looks like a placeholder before treating it as one",
    async () => {
      const { sliceDir, targetDir } = makeFixture({
        extraFiles: {
          "research/findings/report-{draft}.pdf": "pdf",
          "research/findings/report-<final>.html": "html",
          "recommendations/questions.md":
            "Draft `research/findings/report-{draft}.pdf`, final `research/findings/report-<final>.html`, template `research/findings/report-{name}.pdf`.\n",
        },
      });

      const result = await relayoutSlice({ sliceDir, targetDir });

      expect(result.exitCode).toBe(0);
      expect(read(targetDir, "analysis/recommendations/questions.md")).toBe(
        "Draft `../research/findings/report-{draft}.pdf`, final `../research/findings/report-<final>.html`, template `research/findings/report-{name}.pdf`.\n",
      );
    },
  );

  it("flags a definition or src naming a dropped real file whose name looks like a placeholder", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "run-state/report-{draft}.md": "draft",
        "research/claim-inventory.md":
          '[state]: ../run-state/report-{draft}.md\n\nSee [state] and <img src="../run-state/report-{draft}.md">.\n',
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([
      { file: "analysis/research/claim-inventory.md", ref: "../run-state/report-{draft}.md" },
      { file: "analysis/research/claim-inventory.md", ref: "../run-state/report-{draft}.md" },
    ]);
  });

  it("flags a definition naming a dropped slice file that matches an allowed miss", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "AGENTS.md": "slice notes",
        "research/claim-inventory.md": "[rules]: AGENTS.md\n\nSee [rules].\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([
      { file: "analysis/research/claim-inventory.md", ref: "AGENTS.md" },
    ]);
  });

  it("matches the AGENTS.md allowed miss exactly and the directories by whole segment", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "research/claim-inventory.md":
          "[a](./AGENTS.md#rules) [b](AGENTS.md) [c](AGENTS.md.old) [d](docs-old/x.md) [e](docs/x.md)\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([
      { file: "analysis/research/claim-inventory.md", ref: "AGENTS.md.old" },
      { file: "analysis/research/claim-inventory.md", ref: "docs-old/x.md" },
    ]);
  });

  it.skipIf(process.platform === "win32")(
    "skips backslash-escaped < and > when finding the end of an angle destination",
    async () => {
      const { sliceDir, targetDir } = makeFixture({
        extraFiles: {
          "research/findings/a>b.md": "a\n",
          "key-frames/visual-frames.md": "[x](<../research/findings/a\\>b.md>)\n",
        },
      });

      const result = await relayoutSlice({ sliceDir, targetDir });

      expect(result.exitCode).toBe(0);
      expect(read(targetDir, "frames/visual-frames.md")).toBe(
        "[x](<../analysis/research/findings/a\\>b.md>)\n",
      );
    },
  );

  it.skipIf(process.platform === "win32")(
    "reads a reference definition's angle destination past a backslash-escaped >",
    async () => {
      const { sliceDir, targetDir } = makeFixture({
        extraFiles: {
          "source/decks/a>b.pdf": "pdf",
          "key-frames/vision-plan.md": "[deck][deck]\n\n[deck]: <../source/decks/a\\>b.pdf>\n",
        },
      });

      const result = await relayoutSlice({ sliceDir, targetDir });

      expect(result.exitCode).toBe(0);
      expect(read(targetDir, "frames/vision-plan.md")).toBe(
        "[deck][deck]\n\n[deck]: <../metadata/decks/a\\>b.pdf>\n",
      );
    },
  );

  // CommonMark: `&gt;` decodes to `>`, which written raw would close the
  // angle destination early.
  it.skipIf(process.platform === "win32")(
    "escapes a > decoded from a character reference in a rewritten angle destination",
    async () => {
      const { sliceDir, targetDir } = makeFixture({
        extraFiles: {
          "source/decks/a>b.pdf": "pdf",
          "key-frames/vision-plan.md": "[deck](<../source/decks/a&gt;b.pdf>)\n",
        },
      });

      const result = await relayoutSlice({ sliceDir, targetDir });

      expect(result.exitCode).toBe(0);
      expect(read(targetDir, "frames/vision-plan.md")).toBe(
        "[deck](<../metadata/decks/a\\>b.pdf>)\n",
      );
    },
  );

  it("escapes an unbalanced parenthesis in a rewritten bare destination", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "source/decks/a)b.pdf": "pdf",
        "key-frames/vision-plan.md":
          "[deck](<../source/decks/a)b.pdf>) [bare](../source/decks/a\\)b.pdf)\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/vision-plan.md")).toBe(
      "[deck](<../metadata/decks/a)b.pdf>) [bare](../metadata/decks/a\\)b.pdf)\n",
    );
  });

  // Round trip against the CommonMark reading inlineLinks applies: the written
  // destination spans exactly what was written and decodes to the new path.
  it.each(
    ["a>b.pdf", "a<b.pdf", "<a.pdf", "a)b.pdf", "a(b.pdf", "a b.pdf", "a&gt;b.pdf", "a\\b.pdf"]
      .flatMap((name) => [false, true].map((angle) => [name, angle]))
      .flatMap((row) => [false, true].map((references) => [...row, references])),
  )(
    "writes %s (angle %s, references %s) so it parses back unchanged",
    (name, angle, references) => {
      const newPath = `../metadata/decks/${name}`;
      const written = encodeDestination(newPath, {
        angle: Boolean(angle),
        escapedChars: "",
        references: Boolean(references),
      });
      const [link] = inlineLinks(`[x](${written})`);

      expect(link?.dest).toBe(newPath);
      expect(link?.destEnd).toBe(4 + written.length);
    },
  );

  it("link-checks a spaced code-span path with a raw # as one whole path", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "source/decks/My #1.pdf": "pdf",
        "key-frames/vision-plan.md": "Deck: `../source/decks/My #1.pdf`.\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.unresolved).toEqual([]);
    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/vision-plan.md")).toBe(
      "Deck: `../metadata/decks/My #1.pdf`.\n",
    );
  });

  it("maps a real path holding $ and skips only complete placeholder syntax", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "source/decks/budget$2026.pdf": "pdf",
        "key-frames/visual-frames.md": "[b](../source/decks/budget$2026.pdf)\n",
        "recommendations/questions.md": [
          "Missing: `research/budget$2025.md`.",
          "Placeholders: `<slice-dir>/research/x.md` `${ROOT}/research/x.md` `{tmp}/x.png` `research/*.md`.",
          "",
        ].join("\n"),
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([
      { file: "analysis/recommendations/questions.md", ref: "../research/budget$2025.md" },
    ]);
    fs.writeFileSync(
      path.join(sliceDir, "recommendations", "questions.md"),
      "Placeholders: `<slice-dir>/research/x.md` `${ROOT}/research/x.md` `research/*.md`.\n",
    );
    const fixed = await relayoutSlice({ sliceDir, targetDir });
    expect(fixed.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      "[b](../metadata/decks/budget$2026.pdf)\n",
    );
  });

  it("link-checks a spaced code span its rewrite placed through the unknown-child fallback", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "recommendations/questions.md": "Notes: `research/findings/My Missing Notes.md`.\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([
      {
        file: "analysis/recommendations/questions.md",
        ref: "../research/findings/My Missing Notes.md",
      },
    ]);
  });

  it("reads src and href only inside HTML tags, never in prose", async () => {
    const body = [
      "Set href=../research/gone.md or src='../source/transcript.txt' in the config.",
      '<a href="../source/transcript.txt">t</a>',
      "",
    ].join("\n");
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "key-frames/visual-frames.md": body },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      body.replace(
        '<a href="../source/transcript.txt">',
        '<a href="../transcript/transcript.txt">',
      ),
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

  it("reads an HTML href wrapped across lines without its tab, LF and CR", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "key-frames/visual-frames.md": '<a href="../source/\ntranscript.txt">t</a>\n' },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      '<a href="../transcript/transcript.txt">t</a>\n',
    );
    const root = makeDir("relayout-check-");
    writeTree(root, { "frames/visual-frames.md": '<img src="key/\r\n\tgone.png">\n' });
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

  it("reads no link, definition or backticked path inside an HTML tag or comment", async () => {
    const body = [
      '<span title="[example](../source/transcript.txt)">x</span>',
      "<abbr title='`source/transcript.txt`'>t</abbr>",
      "<!-- [old](../source/transcript.txt) -->",
      "<!--",
      "[t]: ../source/transcript.txt",
      "-->",
      "",
    ].join("\n");
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "key-frames/visual-frames.md": body },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(body);
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "frames/visual-frames.md": [
        '<span title="[example](../run-state/watch.json)">x</span>',
        "<abbr title='`key/gone.png`'>t</abbr>",
        "<!-- ![gone](key/gone.png) -->",
        "",
      ].join("\n"),
    });
    expect(checkLayoutLinks(root)).toEqual([]);
  });

  it("reads src and href only as attribute names, never inside another attribute's value", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "key-frames/visual-frames.md":
          '<a title="src=../source/transcript.txt" href="../source/transcript.txt">t</a>\n',
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      '<a title="src=../source/transcript.txt" href="../transcript/transcript.txt">t</a>\n',
    );
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "frames/visual-frames.md":
        "<img alt=\"href='key/gone.png'\" data-src='key/gone.png' src=key/missing.png>\n",
    });
    expect(checkLayoutLinks(root)).toEqual([
      { file: "frames/visual-frames.md", ref: "key/missing.png" },
    ]);
  });

  it("reads a reference definition only when the rest of its line is blank or a title", async () => {
    const body = "[note]: ../source/transcript.txt is illustrative\n";
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "key-frames/visual-frames.md": body },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(body);
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "frames/visual-frames.md": [
        "[note]: source/missing.txt is illustrative",
        '[t]: key/gone.png "A title"  ',
        "",
      ].join("\n"),
    });
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

  it("applies CommonMark's label rules: line endings yes, blank lines, brackets, blanks and 1000 characters no", async () => {
    const body = [
      "[deck",
      "slides]: ../source/transcript.txt",
      "",
      "[long]: ../source/transcript.txt",
      `[${"x".repeat(999)}]: ../source/transcript.txt`,
      `[${"x".repeat(1000)}]: ../research/gone.md`,
      "[ ]: ../research/gone.md",
      "[a[b]: ../research/gone.md",
      "",
      "[split",
      "",
      "label]: ../research/gone.md",
      "",
      "[text",
      "  ",
      "more](../research/gone.md)",
      "",
    ].join("\n");
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "key-frames/visual-frames.md": body },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      body.replaceAll("]: ../source/transcript.txt", "]: ../transcript/transcript.txt"),
    );
  });

  it("reads labels holding escaped brackets in definitions and inline links", async () => {
    const body = [
      "[deck\\]][d] and [a\\]b](../source/transcript.txt)",
      "",
      "[deck\\]]: ../source/transcript.txt",
      "[x\\[y]: ../research/gone.md",
      "",
    ].join("\n");
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "key-frames/visual-frames.md": body },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([
      { file: "frames/visual-frames.md", ref: "../analysis/research/gone.md" },
    ]);
    fs.writeFileSync(
      path.join(sliceDir, "key-frames", "visual-frames.md"),
      body.replace("[x\\[y]: ../research/gone.md\n", ""),
    );
    const fixed = await relayoutSlice({ sliceDir, targetDir });
    expect(fixed.exitCode).toBe(0);
    expect(read(targetDir, "frames/visual-frames.md")).toBe(
      [
        "[deck\\]][d] and [a\\]b](../transcript/transcript.txt)",
        "",
        "[deck\\]]: ../transcript/transcript.txt",
        "",
      ].join("\n"),
    );
  });

  it("reads a reference definition whose destination follows a line ending", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "source/decks/slides.pdf": "pdf",
        "key-frames/vision-plan.md": "[deck][d]\n\n[d]:\n  ../source/decks/slides.pdf\n",
        "recommendations/questions.md": "[g][g]\n\n[g]:\n  ../research/gone.md\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([
      { file: "analysis/recommendations/questions.md", ref: "../research/gone.md" },
    ]);
    fs.rmSync(path.join(sliceDir, "recommendations", "questions.md"));
    const fixed = await relayoutSlice({ sliceDir, targetDir });
    expect(fixed.exitCode).toBe(0);
    expect(read(targetDir, "frames/vision-plan.md")).toBe(
      "[deck][d]\n\n[d]:\n  ../metadata/decks/slides.pdf\n",
    );
  });

  it("checks a bare-file definition destination carrying a query, a fragment or both", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "research/claim-inventory.md":
          "[notes]: missing.md?download=1\n[both]: gone.md?download=1#top\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved.map((entry) => entry.ref)).toEqual([
      "missing.md?download=1",
      "gone.md?download=1#top",
    ]);
  });

  it("checks an extensionless definition destination", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "analysis/README": "readme",
      "analysis/notes.md": "[guide]: missing-thing\n[readme]: README\n",
    });

    expect(checkLayoutLinks(root)).toEqual([{ file: "analysis/notes.md", ref: "missing-thing" }]);
  });

  it("reads no angle destination broken by a backslash before a line ending", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "frames/visual-frames.md": [
        "[example](<source/missing\\",
        "rest>)",
        "",
        "[d]: <source/gone\\",
        "rest>",
        "",
      ].join("\n"),
    });

    expect(checkLayoutLinks(root)).toEqual([]);
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

  it("rewrites a tag-like angle link destination rather than masking it as HTML", async () => {
    const { sliceDir, targetDir } = makeFixture();
    fs.writeFileSync(
      path.join(sliceDir, "RESEARCH.md"),
      "[sources](<source>) beside <source>tag</source>.\n",
    );

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "analysis/RESEARCH.md")).toBe(
      "sources (source, split across analysis/, metadata/, transcript/ in this copy)" +
        " beside <source>tag</source>.\n",
    );
  });

  it("checks tag-like angle link and definition destinations", async () => {
    const { sliceDir, targetDir } = makeFixture();
    fs.writeFileSync(
      path.join(sliceDir, "RESEARCH.md"),
      "[x](<missing>) beside <missing>tag</missing>.\n\n[s]: <source>\n",
    );

    const result = await relayoutSlice({ sliceDir, targetDir });

    // A definition has no prose to take the split text, so the check flags it.
    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([
      { file: "analysis/RESEARCH.md", ref: "missing" },
      { file: "analysis/RESEARCH.md", ref: "source" },
    ]);
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

  it("checks a ~-prefixed relative name and skips only home paths", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, {
      "analysis/RESEARCH.md": "[notes](~notes.md), [home](~/x.md), [user](~someone/x.md).\n",
    });

    expect(checkLayoutLinks(root)).toEqual([{ file: "analysis/RESEARCH.md", ref: "~notes.md" }]);
  });

  it("checks a ..-prefixed name as inside the target", () => {
    const root = makeDir("relayout-check-");
    writeTree(root, { "README.md": "[notes](..notes.md)\n" });

    expect(checkLayoutLinks(root)).toEqual([{ file: "README.md", ref: "..notes.md" }]);
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

  it("rewrites every backticked path form and leaves prose spans alone", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "source/decks/s1/My Slides.pdf": "pdf",
        "recommendations/questions.md": [
          "Spaced: `../source/decks/s1/My Slides.pdf`.",
          "Double: `` source/transcript.txt `` and ``a `tick` in source/transcript.txt``.",
          'Quoted: `"source/transcript.txt"`.',
          "Line and column: `source/transcript.txt:3:5`.",
          "Backslash: `source\\transcript.txt`.",
          "Trailing slash: `research/findings/`.",
          "Dot prefix: `./menu.md`.",
          "Lane only: `research`.",
          "Prose: `run the source / research step`.",
          "",
        ].join("\n"),
        "recommendations/menu.md": "# Menu\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "analysis/recommendations/questions.md")).toBe(
      [
        "Spaced: `../../metadata/decks/s1/My Slides.pdf`.",
        "Double: `` ../../transcript/transcript.txt `` and ``a `tick` in source/transcript.txt``.",
        'Quoted: `"../../transcript/transcript.txt"`.',
        "Line and column: `../../transcript/transcript.txt:3:5`.",
        "Backslash: `../../transcript/transcript.txt`.",
        "Trailing slash: `../research/findings/`.",
        "Dot prefix: `menu.md`.",
        "Lane only: `research`.",
        "Prose: `run the source / research step`.",
        "",
      ].join("\n"),
    );
  });

  it("rewrites the exact slice-root aliases as split text", async () => {
    const { sliceDir: original, targetDir } = makeFixture();
    const slug = path.basename(original);
    const sliceDir = path.join(makeDir("relayout-root-"), ".work", "youtube-watch", slug);
    fs.mkdirSync(path.dirname(sliceDir), { recursive: true });
    fs.renameSync(original, sliceDir);
    fs.writeFileSync(
      path.join(sliceDir, "recommendations", "questions.md"),
      `\`SLICE\` \`SLICE/\` \`.work/youtube-watch/${slug}\` \`.work/youtube-watch/${slug}/\`\n`,
    );

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    const split = `${slug} (split across analysis/, frames/, metadata/, transcript/ in this copy)`;
    expect(read(targetDir, "analysis/recommendations/questions.md")).toBe(
      `${split} ${split} ${split} ${split}\n`,
    );
  });

  it("does not check a reference definition whose destination is prose", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "research/claim-inventory.md": "[0:33]: implementing a whole spec in one session\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
  });

  it("says so for a path below a lane folder this slice never produced", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "key-frames/vision-plan.md": "Slides: `source/decks/s1/slides.pdf`.\n" },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "frames/vision-plan.md")).toBe(
      "Slides: source/decks/s1/slides.pdf (none in this slice).\n",
    );
  });

  it("rewrites and checks Markdown files whatever the extension's case", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "research/notes.MD": "See `source/transcript.txt`.\n",
        "research/more.markdown": "See [t](../source/transcript.txt).\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "analysis/research/notes.MD")).toBe(
      "See `../../transcript/transcript.txt`.\n",
    );
    expect(read(targetDir, "analysis/research/more.markdown")).toBe(
      "See [t](../../transcript/transcript.txt).\n",
    );
    const root = makeDir("relayout-check-");
    writeTree(root, { "frames/log.MARKDOWN": "[gone](key/gone.png)\n" });
    expect(checkLayoutLinks(root)).toEqual([{ file: "frames/log.MARKDOWN", ref: "key/gone.png" }]);
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
