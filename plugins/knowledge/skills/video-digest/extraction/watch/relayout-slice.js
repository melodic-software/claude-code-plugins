#!/usr/bin/env node
/**
 * Copy a finished video-digest slice into a target directory in the
 * knowledge-corpus layout, rewrite the slice-internal paths its markdown names,
 * then link-check the result. A slice is finished when it is closed, or when
 * it is not closed yet and its outcome checks pass. Run it before `close` to
 * keep the media: `close` removes the temp session, so on a closed slice only
 * `--no-media` works.
 *
 * Target layout: `transcript/` (transcript text and the served caption tracks),
 * `metadata/` (trimmed info JSON, harvested links and repo analysis, deck
 * inventory, companion sources, decks, attachments), `frames/all/` (every
 * extracted frame plus `frame-times.json`), `frames/key/` (promoted key frames)
 * beside the frame logs in `frames/`, `media/<id>.<ext>`, `analysis/`
 * (`RESEARCH.md`, `research/`, `recommendations/`, `companion-digest/`) and a
 * provenance `README.md` when the target has none.
 *
 * This file owns the CLI, the copy plan, staging and the move into place. How
 * references are found, rewritten and link-checked is `relayout-references.js`.
 *
 * The layout is built in a sibling staging directory and moved into place only
 * when the link check passes; on any failure the target is left untouched. An
 * existing target is replaced only with `--replace`, which keeps its README;
 * a `<target-dir>.relayout-backup` left by an interrupted replace blocks every run.
 * `--no-media` copies nothing from the temp session.
 *
 * Usage: node watch/relayout-slice.js <slice-dir> <target-dir> [--no-media] [--replace]
 * Exit: 0 written and every slice-internal path resolves; 1 refused, failed,
 * or unresolved paths (listed on stderr, nothing written); 2 usage.
 */

import fs from "node:fs";
import path from "node:path";

import { isMainModule } from "@melodic/video-digestion/shared/main-module";
import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { runCheckWatchOutcomes } from "../evals/check-watch-outcomes.js";
import { LANES } from "../lib/slice-lanes.js";
import { resolveTempSession } from "../lib/temp-session-paths.js";
import {
  checkLayoutLinks,
  listFiles,
  MARKDOWN_FILE,
  rewriteReferences,
} from "./relayout-references.js";
import { watchStatePath } from "./watch-state.js";

/** info.json keys the corpus copy drops: format, caption-URL, heatmap and request lists, and local download paths. */
export const INFO_JSON_DROPPED_KEYS = Object.freeze(
  (
    "formats requested_formats thumbnails automatic_captions subtitles heatmap http_headers " +
    "requested_subtitles _format_sort_fields _filename filename __files_to_move requested_downloads"
  ).split(" "),
);
export const INFO_JSON_COMMENT_CAP = 20;

const SOURCE_FOLDERS = new Map([
  ["companion-digest", "analysis/companion-digest"],
  ["decks", "metadata/decks"],
  ["attachments", "metadata/attachments"],
]);
const KEY_FRAME_LOGS = new Set(
  "key-frames-manifest.md visual-frames.md key-frame-quality-audit.md frame-triage-log.md vision-plan.md visual-gaps.md".split(" "),
);
const SOURCE_METADATA = new Set(
  "harvested-links.json harvested-repo-analysis.json deck-inventory.md companion-sources.md".split(" "),
);
const TRANSCRIPT_TEXT = /^transcript(?:-\d+)?\.txt$/;
const VIDEO_FILE = /\.(?:mp4|mkv|webm)$/;

/**
 * Corpus-layout path for a slice-relative file, or null when the corpus keeps none.
 *
 * @param {string} sliceRel - posix path relative to the slice root
 * @returns {string|null}
 */
export function corpusPathForSliceFile(sliceRel) {
  const [lane, ...rest] = sliceRel.split("/");
  const name = rest.join("/");
  if (sliceRel === "RESEARCH.md") return "analysis/RESEARCH.md";
  if (lane === LANES.research || lane === LANES.recommendations) return `analysis/${sliceRel}`;
  if (lane === LANES.source && SOURCE_FOLDERS.has(rest[0]) && rest.length > 1) {
    return `${SOURCE_FOLDERS.get(rest[0])}/${rest.slice(1).join("/")}`;
  }
  if (lane === LANES.source && rest.length === 1) {
    if (TRANSCRIPT_TEXT.test(name)) return `transcript/${name}`;
    if (SOURCE_METADATA.has(name)) return `metadata/${name}`;
  }
  if (lane === LANES.keyFrames) {
    if (rest[0] === "frames" && rest.length > 1) return `frames/key/${rest.slice(1).join("/")}`;
    if (rest.length === 1 && KEY_FRAME_LOGS.has(name)) return `frames/${name}`;
  }
  return null;
}

/**
 * @param {Record<string, unknown>} info
 * @returns {Record<string, unknown>}
 */
export function trimInfoJson(info) {
  const trimmed = Object.fromEntries(
    Object.entries(info).filter(([key]) => !INFO_JSON_DROPPED_KEYS.includes(key)),
  );
  if (Array.isArray(trimmed.comments)) trimmed.comments = trimmed.comments.slice(0, INFO_JSON_COMMENT_CAP);
  return trimmed;
}

/** One line of plain text with every Markdown-significant character escaped. */
export function markdownText(/** @type {string} */ text) {
  return text.replace(/\s+/g, " ").trim().replace(/[\\`*_{}[\]()<>#+\-.!|~&]/g, "\\$&");
}

/** @param {string} file */
function readJsonObject(file) {
  try {
    const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

/** @param {string} inner @param {string} outer */
function isSameOrInside(inner, outer) {
  const rel = path.relative(outer, inner);
  return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
}

/**
 * @typedef {Object} RelayoutResult
 * @property {number} exitCode
 * @property {number} copied - files written to the target
 * @property {number} rewrites - references rewritten
 * @property {{ file: string, ref: string }[]} unresolved
 */

/**
 * @param {{
 *   sliceDir: string,
 *   targetDir: string,
 *   noMedia?: boolean,
 *   replace?: boolean,
 *   verifyOutcomes?: (sliceDir: string) => number,
 * }} options - `verifyOutcomes` gates a slice that is not closed yet; 0 means its checks pass
 * @returns {Promise<RelayoutResult>}
 */
export async function relayoutSlice({
  sliceDir,
  targetDir,
  noMedia = false,
  replace = false,
  verifyOutcomes = (dir) => runCheckWatchOutcomes(dir),
}) {
  const slice = path.resolve(sliceDir);
  const target = path.resolve(targetDir);
  const refuse = (/** @type {string} */ message) => {
    writeStderr(`relayout: ${message}`);
    return { exitCode: 1, copied: 0, rewrites: 0, unresolved: [] };
  };
  if (isSameOrInside(target, slice) || isSameOrInside(slice, target)) {
    return refuse(`${target} overlaps the slice ${slice}; pick a target outside it`);
  }
  const backup = `${target}.relayout-backup`;
  if (fs.existsSync(backup)) {
    return refuse(
      `${backup} exists: a previous --replace was interrupted and it holds the old target; ` +
        "restore it to the target path or remove it first",
    );
  }
  const state = readJsonObject(watchStatePath(slice));
  if (!state || typeof state.videoId !== "string" || !/^[\w-]+$/.test(state.videoId)) {
    return refuse(`no readable run-state/watch.json with a plain videoId under ${slice}`);
  }
  if (state.status !== "complete") {
    let pass = false;
    try {
      pass = verifyOutcomes(slice) === 0;
    } catch (error) {
      writeStderr(`relayout: outcome checks threw: ${/** @type {Error} */ (error).message}`);
    }
    if (!pass) {
      return refuse(
        `slice status is "${state.status}" and its outcome checks fail; ` +
          "re-lay out a closed slice, or one whose check-watch-outcomes.js passes",
      );
    }
  }
  if (fs.existsSync(target) && !replace) return refuse(`${target} exists; pass --replace to replace it`);
  if (fs.existsSync(target) && !fs.statSync(target).isDirectory()) {
    return refuse(`${target} exists and is not a directory; --replace only replaces a directory`);
  }

  /** @type {{ from: string, to: string, sourceFile?: string }[]} */
  const plan = [];
  /** @type {Record<string, unknown>|null} */
  let info = null;
  /** @type {Map<string, string>} */
  const tempFrames = new Map();
  if (!noMedia) {
    const { workDir = "", framesDir = "" } = resolveTempSession(state.tempSession ?? {});
    const ls = (/** @type {string} */ dir) => {
      try {
        return fs.readdirSync(dir, { withFileTypes: true }).filter((e) => e.isFile()).map((e) => e.name);
      } catch {
        return [];
      }
    };
    const work = ls(workDir);
    const frames = ls(framesDir);
    const acquireMetrics = /** @type {{ primaryMedia?: unknown }|undefined} */ (state.phases?.acquire?.metrics);
    const recorded = acquireMetrics?.primaryMedia;
    const recordedName = (/** @type {string} */ key) => {
      const value = recorded && typeof recorded === "object" ? /** @type {Record<string, unknown>} */ (recorded)[key] : null;
      return typeof value === "string" && value === path.basename(value) && work.includes(value) ? value : null;
    };
    const recordedVideo = recordedName("video");
    // Acquisition can record a bare `<id>.json` fallback; only an `.info.json` name yields a caption stem.
    const recordedInfo = recordedName("infoJson")?.endsWith(".info.json") ? recordedName("infoJson") : null;
    const videos = recordedVideo ? [recordedVideo] : work.filter((name) => VIDEO_FILE.test(name));
    const id = videos.length === 1 ? path.basename(videos[0], path.extname(videos[0])) : "";
    const infoName = recordedVideo && recordedInfo ? recordedInfo : `${id}.info.json`;
    info = id ? readJsonObject(path.join(workDir, infoName)) : null;
    if (!info || frames.length === 0) {
      return refuse(
        `the temp session needs one video with its info JSON and the extracted frames ` +
          `(found ${videos.length} videos, ${info ? "an" : "no"} info JSON, ${frames.length} frames); ` +
          "to keep the media, re-lay out before `close`, which removes the temp session; " +
          "otherwise pass --no-media to re-lay out without media/, frames/all/, the caption tracks and info.json",
      );
    }
    // A recorded primary entry is authoritative: an X post's entry ids differ from the post id.
    if (!recordedVideo && id !== state.videoId && info.display_id !== state.videoId) {
      return refuse(`the temp session's video is ${id}, not this slice's ${state.videoId}`);
    }
    plan.push({ from: path.join(workDir, videos[0]), to: `media/${state.videoId}${path.extname(videos[0])}` });
    const stem = infoName.slice(0, -".info.json".length);
    for (const name of work.filter((each) => each.startsWith(`${stem}.`) && each.endsWith(".vtt"))) {
      plan.push({ from: path.join(workDir, name), to: `transcript/${name.slice(stem.length + 1)}` });
    }
    for (const name of frames) {
      plan.push({ from: path.join(framesDir, name), to: `frames/all/${name}` });
      tempFrames.set(name, `frames/all/${name}`);
    }
  }

  const sliceFiles = listFiles(slice);
  /** @type {Map<string, string>} */
  const files = new Map();
  for (const file of sliceFiles) {
    const to = corpusPathForSliceFile(file);
    if (to) files.set(file, to);
  }
  const entries = new Set(
    sliceFiles.flatMap((file) => file.split("/").map((_, i, parts) => parts.slice(0, i + 1).join("/"))),
  );
  // A slice directory maps to one target directory when every kept file under it agrees.
  /** @type {Map<string, string>} */
  const dirs = new Map();
  for (const dir of entries) {
    const targets = new Set(
      [...files]
        .filter(([from]) => from.startsWith(`${dir}/`))
        .map(([from, to]) => {
          const rest = from.slice(dir.length);
          return to.endsWith(rest) ? to.slice(0, -rest.length) : null;
        }),
    );
    const [only] = targets;
    if (targets.size === 1 && only) dirs.set(dir, only);
  }
  /** @type {import("./relayout-references.js").PathMap} */
  const map = { files, dirs, entries, tempFrames };

  /** @type {string} */
  let staging;
  try {
    fs.mkdirSync(path.dirname(target), { recursive: true });
    staging = fs.mkdtempSync(path.join(path.dirname(target), `.${path.basename(target)}.relayout-`));
  } catch (error) {
    return refuse(`cannot stage beside ${target}: ${/** @type {Error} */ (error).message}`);
  }
  let copied = 0;
  let rewrites = 0;
  /** @type {{ file: string, ref: string }[]} */
  const unresolved = [];
  const write = (/** @type {string} */ to, /** @type {string} */ body) => {
    fs.mkdirSync(path.dirname(path.join(staging, to)), { recursive: true });
    fs.writeFileSync(path.join(staging, to), body);
    copied += 1;
  };
  try {
    for (const [from, to] of files) {
      if (MARKDOWN_FILE.test(from)) {
        const result = rewriteReferences(fs.readFileSync(path.join(slice, from), "utf8"), from, to, map);
        rewrites += result.rewrites;
        unresolved.push(...result.missing.map((ref) => ({ file: to, ref })));
        write(to, result.text);
      } else {
        plan.push({ from: path.join(slice, from), to });
      }
    }
    for (const entry of plan) {
      fs.mkdirSync(path.dirname(path.join(staging, entry.to)), { recursive: true });
      fs.copyFileSync(entry.from, path.join(staging, entry.to));
      copied += 1;
    }
    if (info) write("metadata/info.json", `${JSON.stringify(trimInfoJson(info), null, 2)}\n`);
    const existingReadme = path.join(target, "README.md");
    if (fs.existsSync(existingReadme)) {
      write("README.md", fs.readFileSync(existingReadme, "utf8"));
    } else {
      const present = ["media/", "transcript/", "metadata/", "frames/", "analysis/"].filter((dir) =>
        fs.existsSync(path.join(staging, dir)),
      );
      write(
        "README.md",
        [
          `# ${markdownText(String(state.title ?? state.videoId))}`,
          "",
          `- Canonical origin: <${String(state.sourceUrl ?? "").replace(/[\s<>]/g, encodeURIComponent)}>`,
          `- Video id: \`${state.videoId}\``,
          "- Re-laid out from a finished `/knowledge:video-digest` slice.",
          `- Contents: ${present.map((dir) => `\`${dir}\``).join(", ")}`,
          "",
        ].join("\n"),
      );
    }
    unresolved.push(...checkLayoutLinks(staging));
  } catch (error) {
    fs.rmSync(staging, { recursive: true, force: true });
    return refuse(`copy failed, target left untouched: ${/** @type {Error} */ (error).message}`);
  }
  if (unresolved.length > 0) {
    fs.rmSync(staging, { recursive: true, force: true });
    return { exitCode: 1, copied: 0, rewrites, unresolved };
  }
  const hadTarget = fs.existsSync(target);
  try {
    if (hadTarget) fs.renameSync(target, backup);
    fs.renameSync(staging, target);
  } catch (error) {
    if (hadTarget && !fs.existsSync(target)) fs.renameSync(backup, target);
    fs.rmSync(staging, { recursive: true, force: true });
    return refuse(`could not move the layout into place: ${/** @type {Error} */ (error).message}`);
  }
  if (hadTarget) fs.rmSync(backup, { recursive: true, force: true });
  return { exitCode: 0, copied, rewrites, unresolved };
}

/**
 * @param {string[]} args - argv after the script path
 * @returns {Promise<number>}
 */
export async function runRelayoutCli(args) {
  const noMedia = args.includes("--no-media");
  const replace = args.includes("--replace");
  const positional = args.filter((arg) => arg !== "--no-media" && arg !== "--replace");
  if (positional.length !== 2 || positional.some((arg) => arg.startsWith("--"))) {
    writeStderr("Usage: node watch/relayout-slice.js <slice-dir> <target-dir> [--no-media] [--replace]");
    return 2;
  }
  const [sliceDir, targetDir] = positional;
  const result = await relayoutSlice({ sliceDir, targetDir, noMedia, replace });
  if (result.exitCode === 0) {
    writeStdout(
      `relayout: ${result.copied} files written to ${path.resolve(targetDir)}, ${result.rewrites} references rewritten`,
    );
  }
  for (const { file, ref } of result.unresolved) writeStderr(`unresolved: ${file} -> ${ref}`);
  if (result.unresolved.length > 0) {
    writeStderr(`relayout: ${result.unresolved.length} slice-internal paths do not resolve`);
  }
  return result.exitCode;
}

if (isMainModule(import.meta.url)) {
  process.exit(await runRelayoutCli(process.argv.slice(2)));
}
