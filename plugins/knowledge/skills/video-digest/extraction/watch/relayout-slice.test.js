import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { relayoutSlice, runRelayoutCli } from "./relayout-slice.js";

/** @type {string[]} */
const scratch = [];

function makeDir(/** @type {string} */ prefix) {
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
 * A small closed slice plus its temp session (video, caption tracks, info JSON
 * and two extracted frames).
 *
 * @param {{ status?: string, withMedia?: boolean, extraFiles?: Record<string, string> }} [options]
 */
function makeFixture({ status = "complete", withMedia = true, extraFiles = {} } = {}) {
  const sliceDir = path.join(makeDir("relayout-slice-"), "sample-talk-abc123XYZ_0");
  const workDir = makeDir("relayout-work-");
  const framesDir = makeDir("relayout-frames-");
  if (withMedia) {
    writeTree(workDir, {
      [`${VIDEO_ID}.mp4`]: "video-bytes",
      [`${VIDEO_ID}.en.vtt`]: "WEBVTT\n",
      [`${VIDEO_ID}.info.json`]: JSON.stringify({
        id: VIDEO_ID,
        title: "Sample Talk",
        formats: [{}],
        _filename: "/tmp/video-extraction-x/abc123XYZ_0.mp4",
        comments: Array.from({ length: 25 }, (_, index) => ({ id: `c${index}` })),
      }),
    });
    writeTree(framesDir, {
      "scene_0001.png": "png",
      "frame-times.json": JSON.stringify({ "scene_0001.png": { timestampSec: 1 } }),
    });
  }
  writeTree(sliceDir, {
    "run-state/watch.json": JSON.stringify({
      videoId: VIDEO_ID,
      sourceUrl: `https://www.youtube.com/watch?v=${VIDEO_ID}`,
      title: "Sample Talk",
      status,
      tempSession: { workDir, framesDir },
    }),
    "README.md": "# Sample Talk journey\n",
    "RESEARCH.md": "Clusters from `research/claim-inventory.md`; shards in `research/findings/`.\n",
    "source/transcript.txt": "[0:01] hello\n",
    "source/harvested-links.json": "[]",
    "key-frames/frames/title-slide.png": "png",
    "key-frames/visual-frames.md":
      "| `frames/title-slide.png` | `scene_0001.png` |\n\nTiers: [manifest](key-frames-manifest.md)\n",
    "key-frames/key-frames-manifest.md": "| title-slide.png |\n",
    "key-frames/selection.json": "{}",
    "source/companion-sources.md": "Companion: [digest](companion-digest/README.md).\n",
    "source/companion-digest/README.md": "Brief: `source/companion-sources.md`.\n",
    "research/claim-inventory.md": "Transcript: `source/transcript.txt`.\n",
    "research/findings/topic.md":
      "Quote at `SLICE/source/transcript.txt:3`; see [agenda](../claim-inventory.md#sessions).\n",
    "recommendations/menu.md": [
      "Evidence: `source/transcript.txt` and ![slide](../key-frames/frames/title-slide.png).",
      "Detail: `research/findings/topic.md`, the hub [README](README.md), the [journey](../README.md).",
      "Target file: `plugins/knowledge/skills/video-digest/SKILL.md`, [docs](https://example.com/source/transcript.txt).",
      "Run state: `run-state/watch.json`, [selection](../key-frames/selection.json).",
      "Upstream: `research/deepening/html-report.md:92` in mattpocock/skills.",
      "",
      "[inventory]: ../research/claim-inventory.md",
      "",
    ].join("\n"),
    "recommendations/README.md": "# Hub\n",
    ...extraFiles,
  });
  return { sliceDir, targetDir: path.join(makeDir("relayout-target-"), "out") };
}

afterEach(() => {
  for (const dir of scratch.splice(0)) fs.rmSync(dir, { recursive: true, force: true });
});

describe("relayoutSlice", () => {
  it("copies a closed slice into the corpus layout with a trimmed info.json", async () => {
    const { sliceDir, targetDir } = makeFixture();

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.unresolved).toEqual([]);
    expect(result.exitCode).toBe(0);
    for (const rel of [
      "transcript/transcript.txt",
      "transcript/en.vtt",
      "metadata/info.json",
      "metadata/harvested-links.json",
      "metadata/companion-sources.md",
      "frames/all/scene_0001.png",
      "frames/all/frame-times.json",
      "frames/key/title-slide.png",
      "frames/visual-frames.md",
      `media/${VIDEO_ID}.mp4`,
      "analysis/RESEARCH.md",
      "analysis/companion-digest/README.md",
      "analysis/research/findings/topic.md",
      "analysis/recommendations/menu.md",
      "README.md",
    ]) {
      expect(fs.existsSync(path.join(targetDir, rel)), rel).toBe(true);
    }
    expect(fs.existsSync(path.join(targetDir, "run-state"))).toBe(false);
    expect(fs.readdirSync(path.dirname(targetDir))).toEqual(["out"]);
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
        "Target file: `plugins/knowledge/skills/video-digest/SKILL.md`, [docs](https://example.com/source/transcript.txt).",
        "Run state: run-state/watch.json (not retained in this copy), selection (key-frames/selection.json, not retained in this copy).",
        "Upstream: `research/deepening/html-report.md:92` in mattpocock/skills.",
        "",
        "[inventory]: ../research/claim-inventory.md",
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
    expect(read(targetDir, "analysis/RESEARCH.md")).toBe(
      "Clusters from `research/claim-inventory.md`; shards in `research/findings/`.\n",
    );
  });

  it("names where a split directory's files went and retires a dropped definition", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "recommendations/questions.md": "Inputs: `source/`.\n\n[state]: ../run-state/watch.json\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "analysis/recommendations/questions.md")).toBe(
      "Inputs: source/ (split across analysis/, metadata/, transcript/ in this copy).\n\n" +
        "state: run-state/watch.json (not retained in this copy)\n",
    );
  });

  it("names the one directory a retired directory's files all went to", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: { "recommendations/lanes.md": "Verify artifacts stay in `key-frames/`.\n" },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "analysis/recommendations/lanes.md")).toBe(
      "Verify artifacts stay in key-frames/ (now under frames/ in this copy).\n",
    );
  });

  it("refuses while a backup from an interrupted --replace exists, and leaves it alone", async () => {
    const { sliceDir, targetDir } = makeFixture();
    writeTree(`${targetDir}.relayout-backup`, { "README.md": "# Curated\n" });

    const result = await relayoutSlice({ sliceDir, targetDir, replace: true });

    expect(result.exitCode).toBe(1);
    expect(fs.readdirSync(path.dirname(targetDir))).toEqual(["out.relayout-backup"]);
    expect(read(`${targetDir}.relayout-backup`, "README.md")).toBe("# Curated\n");
  });

  it("retires a dropped link whose label holds a code span or an image", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "research/a.md":
          "See [`run-state/watch.json`](../run-state/watch.json).\n\n" +
          "[![s](../key-frames/frames/title-slide.png)](../run-state/watch.json)\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(read(targetDir, "analysis/research/a.md")).toBe(
      "See `run-state/watch.json` (run-state/watch.json, not retained in this copy).\n\n" +
        "![s](../../frames/key/title-slide.png) (run-state/watch.json, not retained in this copy)\n",
    );
  });

  it("skips a symlink in the slice instead of copying what it points at", async () => {
    const { sliceDir, targetDir } = makeFixture();
    const outside = makeDir("relayout-outside-");
    fs.writeFileSync(path.join(outside, "secret.txt"), "OUTSIDE");
    fs.symlinkSync(path.join(outside, "secret.txt"), path.join(sliceDir, "research", "secret.txt"));

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(0);
    expect(fs.existsSync(path.join(targetDir, "analysis/research/secret.txt"))).toBe(false);
  });

  it("fails the link check on a missing slice file, writing nothing", async () => {
    const { sliceDir, targetDir } = makeFixture({
      extraFiles: {
        "recommendations/questions.md":
          "Slide: `key-frames/frames/deleted.png`, [gap](../research/findings/gone.md).\n",
      },
    });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(result.unresolved).toEqual([
      { file: "analysis/recommendations/questions.md", ref: "key-frames/frames/deleted.png" },
      { file: "analysis/recommendations/questions.md", ref: "../research/findings/gone.md" },
    ]);
    expect(fs.readdirSync(path.dirname(targetDir))).toEqual([]);
  });

  it("refuses an existing target without --replace and leaves it untouched", async () => {
    const { sliceDir, targetDir } = makeFixture();
    writeTree(targetDir, { "stale.md": "old\n" });

    const result = await relayoutSlice({ sliceDir, targetDir });

    expect(result.exitCode).toBe(1);
    expect(fs.readdirSync(targetDir)).toEqual(["stale.md"]);
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

  it("refuses a target inside the slice", async () => {
    const { sliceDir } = makeFixture();

    const result = await relayoutSlice({ sliceDir, targetDir: path.join(sliceDir, "out"), replace: true });

    expect(result.exitCode).toBe(1);
    expect(fs.existsSync(path.join(sliceDir, "out"))).toBe(false);
  });

  it("takes nothing from the temp session under --no-media", async () => {
    const { sliceDir, targetDir } = makeFixture();

    const result = await relayoutSlice({ sliceDir, targetDir, noMedia: true });

    expect(result.exitCode).toBe(0);
    for (const rel of ["media", "frames/all", "transcript/en.vtt", "metadata/info.json"]) {
      expect(fs.existsSync(path.join(targetDir, rel)), rel).toBe(false);
    }
    expect(read(targetDir, "transcript/transcript.txt")).toBe("[0:01] hello\n");
  });

  it("refuses when the temp session's media is gone, unless --no-media", async () => {
    const { sliceDir, targetDir } = makeFixture({ withMedia: false });

    expect((await relayoutSlice({ sliceDir, targetDir })).exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
    expect((await relayoutSlice({ sliceDir, targetDir, noMedia: true })).exitCode).toBe(0);
  });

  describe("a temp session holding two videos", () => {
    /** @param {Record<string, unknown>|null} primaryMedia */
    function makeTwoVideoFixture(primaryMedia) {
      const fixture = makeFixture();
      const state = JSON.parse(read(fixture.sliceDir, "run-state/watch.json"));
      const { workDir } = state.tempSession;
      writeTree(workDir, {
        "111.mp4": "other-video-bytes",
        "111.en.vtt": "WEBVTT\n",
        "111.info.json": JSON.stringify({ id: "111", display_id: "111" }),
      });
      state.phases = { acquire: { metrics: { entryCount: 2, ...(primaryMedia ? { primaryMedia } : {}) } } };
      fs.writeFileSync(path.join(fixture.sliceDir, "run-state/watch.json"), JSON.stringify(state));
      return fixture;
    }

    it("re-lays out the recorded primary entry's video", async () => {
      const { sliceDir, targetDir } = makeTwoVideoFixture({
        video: `${VIDEO_ID}.mp4`,
        infoJson: `${VIDEO_ID}.info.json`,
        caption: `${VIDEO_ID}.en.vtt`,
      });

      const result = await relayoutSlice({ sliceDir, targetDir });

      expect(result.exitCode).toBe(0);
      expect(read(targetDir, `media/${VIDEO_ID}.mp4`)).toBe("video-bytes");
      expect(JSON.parse(read(targetDir, "metadata/info.json")).title).toBe("Sample Talk");
      expect(fs.existsSync(path.join(targetDir, "transcript/en.vtt"))).toBe(true);
    });

    it("copies the primary entry even when it is not the one the filenames suggest", async () => {
      const { sliceDir, targetDir } = makeTwoVideoFixture({
        video: "111.mp4",
        infoJson: "111.info.json",
        caption: "111.en.vtt",
      });

      const result = await relayoutSlice({ sliceDir, targetDir });

      expect(result.exitCode).toBe(0);
      expect(read(targetDir, `media/${VIDEO_ID}.mp4`)).toBe("other-video-bytes");
    });

    it("keeps the caption tracks when the recorded metadata file lacks the .info.json suffix", async () => {
      const fixture = makeTwoVideoFixture({
        video: `${VIDEO_ID}.mp4`,
        infoJson: `${VIDEO_ID}.json`,
      });
      const state = JSON.parse(read(fixture.sliceDir, "run-state/watch.json"));
      writeTree(state.tempSession.workDir, { [`${VIDEO_ID}.json`]: JSON.stringify({ id: VIDEO_ID }) });

      const result = await relayoutSlice({ sliceDir: fixture.sliceDir, targetDir: fixture.targetDir });

      expect(result.exitCode).toBe(0);
      expect(fs.existsSync(path.join(fixture.targetDir, "transcript/en.vtt"))).toBe(true);
    });

    it("reads the recorded <id>.json when the work dir holds no .info.json for it", async () => {
      const fixture = makeTwoVideoFixture({
        video: `${VIDEO_ID}.mp4`,
        infoJson: `${VIDEO_ID}.json`,
      });
      const state = JSON.parse(read(fixture.sliceDir, "run-state/watch.json"));
      const { workDir } = state.tempSession;
      fs.rmSync(path.join(workDir, `${VIDEO_ID}.info.json`));
      writeTree(workDir, { [`${VIDEO_ID}.json`]: JSON.stringify({ id: VIDEO_ID, title: "Recorded Only" }) });

      const result = await relayoutSlice({ sliceDir: fixture.sliceDir, targetDir: fixture.targetDir });

      expect(result.exitCode).toBe(0);
      expect(JSON.parse(read(fixture.targetDir, "metadata/info.json")).title).toBe("Recorded Only");
      expect(fs.existsSync(path.join(fixture.targetDir, "transcript/en.vtt"))).toBe(true);
    });

    it("still refuses media mode when no primary entry is recorded", async () => {
      const { sliceDir, targetDir } = makeTwoVideoFixture(null);

      expect((await relayoutSlice({ sliceDir, targetDir })).exitCode).toBe(1);
      expect(fs.existsSync(targetDir)).toBe(false);
      expect((await relayoutSlice({ sliceDir, targetDir, noMedia: true })).exitCode).toBe(0);
    });
  });

  it("gates an unclosed slice on its outcome checks", async () => {
    const { sliceDir, targetDir } = makeFixture({ status: "synthesizing" });

    expect((await relayoutSlice({ sliceDir, targetDir, verifyOutcomes: () => 1 })).exitCode).toBe(1);
    expect(fs.existsSync(targetDir)).toBe(false);
    expect((await relayoutSlice({ sliceDir, targetDir, verifyOutcomes: () => 0 })).exitCode).toBe(0);
  });

  it("writes an upstream title with Markdown syntax as plain text in the README", async () => {
    const { sliceDir, targetDir } = makeFixture();
    const watchPath = path.join(sliceDir, "run-state/watch.json");
    const watch = JSON.parse(fs.readFileSync(watchPath, "utf8"));
    fs.writeFileSync(watchPath, JSON.stringify({ ...watch, title: "[Episode](trailer.md)\n#1" }));

    expect((await relayoutSlice({ sliceDir, targetDir })).exitCode).toBe(0);
    expect(read(targetDir, "README.md").split("\n")[0]).toBe("# \\[Episode\\]\\(trailer\\.md\\) \\#1");
  });
});

describe("runRelayoutCli", () => {
  it("exits 2 on a usage error", async () => {
    expect(await runRelayoutCli(["only-one"])).toBe(2);
  });
});
