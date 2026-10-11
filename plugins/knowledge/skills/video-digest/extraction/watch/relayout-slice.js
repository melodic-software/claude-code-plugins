#!/usr/bin/env node
/**
 * Copy a finished video-digest slice into a target directory in the
 * knowledge-corpus layout, rewrite the slice-internal paths its markdown names,
 * then link-check the result. A slice is finished when it is closed, or when
 * it is not closed yet and its outcome checks pass (the pre-close run, while
 * the temp session still holds the media).
 *
 * Target layout: `transcript/` (transcript text and the served caption tracks),
 * `metadata/` (trimmed info JSON, harvested links and repo analysis, deck
 * inventory, companion sources, decks, attachments), `frames/all/` (every
 * extracted frame plus `frame-times.json`), `frames/key/` (promoted key frames)
 * beside the frame logs in `frames/`, `media/<id>.<ext>`, `analysis/`
 * (`RESEARCH.md`, `research/`, `recommendations/`, `companion-digest/`) and a
 * provenance `README.md` when the target has none.
 *
 * Markdown is parsed with mdast-util-from-markdown; the links, images,
 * definitions and path-like code spans it finds are edited in place by source
 * offset, so nothing else in the file changes. A reference resolves first
 * against the naming file's own directory, then against the slice root
 * (`SLICE/<path>` names the root explicitly). One landing on a copied path is
 * rewritten relative to the file's new location; one landing on a slice file
 * or directory the layout does not keep becomes plain text naming it as not
 * retained; anything else (URLs, other repositories' paths) is left alone.
 * The link check then reports what still does not resolve.
 *
 * The layout is built in a sibling staging directory and moved into place only
 * when the link check passes; on any failure the target is left untouched. An
 * existing target is replaced only with `--replace`, which keeps its README.
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
import { fromMarkdown } from "mdast-util-from-markdown";

import { runCheckWatchOutcomes } from "../evals/check-watch-outcomes.js";
import { LANES } from "../lib/slice-lanes.js";
import { resolveTempSession } from "../lib/temp-session-paths.js";
import { watchStatePath } from "./watch-state.js";

/** info.json keys the corpus copy drops: format, caption-URL, heatmap and request lists, and local download paths. */
export const INFO_JSON_DROPPED_KEYS = Object.freeze([
  "formats",
  "requested_formats",
  "thumbnails",
  "automatic_captions",
  "subtitles",
  "heatmap",
  "http_headers",
  "requested_subtitles",
  "_format_sort_fields",
  "_filename",
  "filename",
  "__files_to_move",
  "requested_downloads",
]);
export const INFO_JSON_COMMENT_CAP = 20;

/** Link paths naming another repository's files: a directory (trailing `/`) matches below it, a file exactly. */
const ALLOWED_MISSES = Object.freeze(["plugins/", "docs/", "templates/", ".claude/", "AGENTS.md"]);
const SOURCE_FOLDERS = new Map([
  ["companion-digest", "analysis/companion-digest"],
  ["decks", "metadata/decks"],
  ["attachments", "metadata/attachments"],
]);
const KEY_FRAME_LOGS = new Set([
  "key-frames-manifest.md",
  "visual-frames.md",
  "key-frame-quality-audit.md",
  "frame-triage-log.md",
  "vision-plan.md",
  "visual-gaps.md",
]);
const SOURCE_METADATA = new Set([
  "harvested-links.json",
  "harvested-repo-analysis.json",
  "deck-inventory.md",
  "companion-sources.md",
]);
const TRANSCRIPT_TEXT = /^transcript(?:-\d+)?\.txt$/;
const MARKDOWN_FILE = /\.(?:md|markdown)$/i;
const VIDEO_FILE = /\.(?:mp4|mkv|webm)$/;
const URL_SCHEME = /^[a-z][a-z0-9+.-]*:/i;
/** Placeholder or glob syntax (`<slice>/x`, `${ROOT}`, `{tmp}`, `*.md`), never a real path. */
const PLACEHOLDER = /[<>{}*$]/;
/** `:12`, `:12-20`, `:12,15` and `:12:5` endings on a backticked path. */
const LINE_SUFFIX = /(?::\d+(?:[-,]\d+)*)+$/;
const NOT_RETAINED = "not retained in this copy";

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
 * @param {string} dir
 * @param {string} [prefix]
 * @returns {string[]} posix paths of every file under dir, relative to it
 */
function listFiles(dir, prefix = "") {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    return entry.isDirectory() ? listFiles(path.join(dir, entry.name), rel) : [rel];
  });
}

/**
 * @typedef {Object} MarkdownRef
 * @property {"link"|"code"} kind - link, image or definition destination; or code span
 * @property {string} value - the destination (escapes decoded) or code span text
 * @property {number|null} from - offset of `value` as written, null when it is written differently
 * @property {number} to
 * @property {number} nodeStart - the whole link, image, definition or code span
 * @property {number} nodeEnd
 * @property {string} label - link text, image alt or definition label
 * @property {boolean} definition
 */

/**
 * Every link, image and definition destination, and every path-like code span
 * (no whitespace, a `/` or a `.ext`), in a markdown text. Fenced code and raw
 * HTML hold none.
 *
 * @param {string} text
 * @returns {MarkdownRef[]}
 */
export function markdownReferences(text) {
  /** @type {MarkdownRef[]} */
  const refs = [];
  /** @param {any} node */
  const walk = (node) => {
    const nodeStart = node.position?.start.offset ?? 0;
    const nodeEnd = node.position?.end.offset ?? 0;
    const raw = text.slice(nodeStart, nodeEnd);
    const push = (/** @type {"link"|"code"} */ kind, /** @type {string} */ value, after = 0) => {
      const at = value ? raw.indexOf(value, Math.max(after, 0)) : -1;
      const label =
        node.type === "link" && node.children.length > 0
          ? text.slice(node.children[0].position.start.offset, node.children.at(-1).position.end.offset)
          : (node.alt ?? node.label ?? "");
      refs.push({
        kind,
        value,
        from: at === -1 ? null : nodeStart + at,
        to: at === -1 ? 0 : nodeStart + at + value.length,
        nodeStart,
        nodeEnd,
        label,
        definition: node.type === "definition",
      });
    };
    if (node.type === "link") {
      push("link", node.url, (node.children.at(-1)?.position.end.offset ?? nodeStart) - nodeStart);
    } else if (node.type === "image") {
      push("link", node.url, raw.indexOf("]("));
    } else if (node.type === "definition") {
      push("link", node.url, raw.indexOf("]:"));
    } else if (node.type === "inlineCode" && !/\s/.test(node.value) && /[/]|\.\w/.test(node.value)) {
      push("code", node.value);
    }
    for (const child of node.children ?? []) walk(child);
  };
  walk(fromMarkdown(text));
  return refs;
}

/**
 * The ways to read a reference, as [path, suffix] pairs in order. A link's
 * `#` or `?` always starts its fragment or query; a code span is first read
 * whole (`notes#1.md`), then without a `:12` ending, then without a fragment.
 * Link paths are percent-decoded per segment.
 *
 * @param {MarkdownRef} ref
 * @returns {[string, string][]}
 */
function readings(ref) {
  const fragment = (/** @type {string} */ value) => {
    const at = value.search(/[#?]/);
    return at === -1 ? [value, ""] : [value.slice(0, at), value.slice(at)];
  };
  /** @returns {[string, string][]} */
  const withLines = (/** @type {string} */ p, /** @type {string} */ suffix) => {
    const line = LINE_SUFFIX.exec(p);
    return line ? [[p, suffix], [p.slice(0, line.index), line[0] + suffix]] : [[p, suffix]];
  };
  if (ref.kind === "code") {
    const [p, suffix] = fragment(ref.value);
    return [...withLines(ref.value, ""), ...(suffix ? withLines(p, suffix) : [])];
  }
  const [p, suffix] = fragment(ref.value);
  const decoded = p
    .split("/")
    .map((segment) => {
      try {
        return decodeURIComponent(segment);
      } catch {
        return segment;
      }
    })
    .join("/");
  return withLines(decoded, suffix);
}

/**
 * @typedef {Object} PathMap
 * @property {Map<string, string>} files - slice file → target file
 * @property {Map<string, string>} dirs - slice directory → target directory, when its kept files moved together
 * @property {Set<string>} entries - every slice file and directory
 * @property {Map<string, string>} tempFrames - extracted frame name → target file
 */

/** @typedef {{ target: string } | { retired: string, note: string } | { missing: true }} Lookup */

/**
 * What a reference path names: a copied path, a slice path the layout drops
 * (`retired`), a missing file in a slice directory, or null for anything else.
 *
 * @param {string} refPath
 * @param {string} sourceFile - slice-relative path of the naming file
 * @param {PathMap} map
 * @returns {Lookup|null}
 */
function lookUp(refPath, sourceFile, map) {
  const bare = refPath.replace(/\/+$/, "");
  if (!bare || URL_SCHEME.test(bare) || /^[/~]/.test(bare)) return null;
  const keys = (
    bare.startsWith("SLICE/")
      ? [bare.slice("SLICE/".length)]
      : [path.posix.join(path.posix.dirname(sourceFile), bare), ...(bare.startsWith(".") ? [] : [bare])]
  )
    .map((key) => path.posix.normalize(key))
    .filter((key) => key !== "." && key !== ".." && !key.startsWith("../"));
  for (const key of keys) {
    const target = map.files.get(key) ?? map.dirs.get(key);
    if (target !== undefined) return { target };
  }
  const retired = keys.find((key) => map.entries.has(key));
  if (retired) {
    const splitInto = [
      ...new Set(
        [...map.files]
          .filter(([from]) => from.startsWith(`${retired}/`))
          .map(([, to]) => `${to.split("/")[0]}/`),
      ),
    ].sort();
    const note = splitInto.length > 0 ? `split across ${splitInto.join(", ")} in this copy` : NOT_RETAINED;
    return { retired, note };
  }
  if (bare.includes("/") && keys.some((key) => map.entries.has(path.posix.dirname(key)))) {
    return { missing: true };
  }
  const frame = bare.includes("/") ? undefined : map.tempFrames.get(bare);
  return frame ? { target: frame } : null;
}

/**
 * Rewrite the slice-internal references in one markdown file for its new location.
 *
 * @param {string} text
 * @param {string} sourceFile - slice-relative path
 * @param {string} targetFile - target-relative path
 * @param {PathMap} map
 * @returns {{ text: string, rewrites: number, missing: string[] }}
 */
export function rewriteReferences(text, sourceFile, targetFile, map) {
  /** @type {{ from: number, to: number, text: string }[]} */
  const edits = [];
  /** @type {string[]} */
  const missing = [];
  for (const ref of markdownReferences(text)) {
    // The first reading that names something wins, a missing file only when no other does.
    /** @type {Lookup|null} */
    let found = null;
    let reading = /** @type {[string, string]} */ (["", ""]);
    for (const each of readings(ref)) {
      const hit = lookUp(each[0], sourceFile, map);
      if (hit && (!found || "missing" in found)) [found, reading] = [hit, each];
      if (hit && !("missing" in hit)) break;
    }
    if (!found) continue;
    if ("missing" in found) {
      // A link is checked in the staged layout anyway; a code span may not look like a path there.
      if (ref.kind === "code") missing.push(ref.value);
    } else if ("target" in found) {
      if (ref.from === null) continue; // written with escapes: left for the link check
      let rel = path.posix.relative(path.posix.dirname(targetFile), found.target) || ".";
      if (reading[0].endsWith("/")) rel += "/";
      if (ref.kind === "link" && (ref.value.includes("%") || /[\s()<>]/.test(rel))) {
        rel = rel.split("/").map(encodeURIComponent).join("/");
      }
      edits.push({ from: ref.from, to: ref.to, text: rel + reading[1] });
    } else {
      const named = `${found.retired}${reading[0].endsWith("/") ? "/" : ""}`;
      const plain = ref.label ? `${ref.label} (${named}, ${found.note})` : `${named} (${found.note})`;
      edits.push({ from: ref.nodeStart, to: ref.nodeEnd, text: ref.definition ? `${ref.label}: ${named} (${found.note})` : plain });
    }
  }
  // Back to front, so earlier offsets stay valid; an edit overlapping one
  // already applied (a link around a rewritten image) is skipped, and the
  // link check judges what it left.
  let out = text;
  let floor = Infinity;
  let rewrites = 0;
  for (const edit of edits.sort((a, b) => b.from - a.from)) {
    if (edit.to > floor) continue;
    out = out.slice(0, edit.from) + edit.text + out.slice(edit.to);
    floor = edit.from;
    rewrites += 1;
  }
  return { text: out, rewrites, missing };
}

/**
 * Link check over a staged layout: every relative link, image or definition
 * that stays inside it, and every backticked path that looks like one of its
 * own (`./`, `../`, `SLICE/`, or a first segment that exists), must resolve.
 * URLs, absolute and home paths, placeholders, paths leaving the layout and
 * the allowed other-repository misses are skipped.
 *
 * @param {string} rootDir
 * @returns {{ file: string, ref: string }[]}
 */
export function checkLayoutLinks(rootDir) {
  const root = path.resolve(rootDir);
  const topLevel = new Set(fs.readdirSync(root));
  /** @type {{ file: string, ref: string }[]} */
  const unresolved = [];
  const markdown = listFiles(root).filter(
    (file) => MARKDOWN_FILE.test(file) && !/^(?:media|frames\/all)\//.test(file),
  );
  for (const file of markdown) {
    const dir = path.dirname(path.join(root, file));
    for (const ref of markdownReferences(fs.readFileSync(path.join(root, file), "utf8"))) {
      const paths = readings(ref).map(([p]) => p);
      const p = /** @type {string} */ (paths.at(-1));
      if (paths.some((each) => each && fs.existsSync(path.resolve(dir, each)))) continue;
      if (!p || URL_SCHEME.test(p) || /^[/~]/.test(p) || PLACEHOLDER.test(p)) continue;
      const resolved = path.resolve(dir, p);
      if (path.relative(root, resolved).startsWith("..")) continue;
      const plain = p.replace(/^(?:\.\/)+/, "");
      const internal =
        ref.kind === "link"
          ? !ALLOWED_MISSES.some((miss) => (miss.endsWith("/") ? plain.startsWith(miss) : plain === miss))
          : /^(?:\.\.?|SLICE)\//.test(p) ||
            topLevel.has(p.split("/")[0]) ||
            (p.includes("/") && fs.existsSync(path.join(dir, p.split("/")[0])));
      if (internal) unresolved.push({ file, ref: ref.value });
    }
  }
  return unresolved;
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
    const videos = work.filter((name) => VIDEO_FILE.test(name));
    const id = videos.length === 1 ? path.basename(videos[0], path.extname(videos[0])) : "";
    info = id ? readJsonObject(path.join(workDir, `${id}.info.json`)) : null;
    if (!info || frames.length === 0) {
      return refuse(
        `the temp session needs one video with its info JSON and the extracted frames ` +
          `(found ${videos.length} videos, ${info ? "an" : "no"} info JSON, ${frames.length} frames); ` +
          "pass --no-media to re-lay out without media/, frames/all/, the caption tracks and info.json",
      );
    }
    if (id !== state.videoId && info.display_id !== state.videoId) {
      return refuse(`the temp session's video is ${id}, not this slice's ${state.videoId}`);
    }
    plan.push({ from: path.join(workDir, videos[0]), to: `media/${state.videoId}${path.extname(videos[0])}` });
    for (const name of work.filter((each) => each.startsWith(`${id}.`) && each.endsWith(".vtt"))) {
      plan.push({ from: path.join(workDir, name), to: `transcript/${name.slice(id.length + 1)}` });
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
  /** @type {PathMap} */
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
  const backup = `${target}.relayout-backup`;
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
