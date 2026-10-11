import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import { checkLayoutLinks, relayoutSlice } from "./relayout-slice.js";

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
      phases: { acquire: { metrics: { captionRung: "auto-en" } } },
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
        "Detail: `../research/findings/topic.md`, the hub [README](README.md), the [journey](../../README.md).",
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
    ["outside the OS temp dir", () => path.parse(os.tmpdir()).root],
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
    fs.symlinkSync(outside, path.join(framesDir, "scene_0002.png"));

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
});
