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
 * inventory, companion sources), `frames/all/` (every extracted frame plus
 * `frame-times.json`), `frames/key/` (promoted key frames) beside the frame
 * logs in `frames/`, `media/<id>.<ext>`, `analysis/` (`RESEARCH.md`,
 * `research/`, `recommendations/`, `companion-digest/`) and a provenance
 * `README.md` when the target has none.
 *
 * Every reference is rewritten through a path map built from the copy plan:
 * a reference resolves first against the naming file's own directory, then
 * against the slice root. One landing on a copied path is rewritten relative
 * to the file's new location; one landing on a slice file or directory the
 * layout does not keep becomes plain text naming it as not retained; anything
 * else is left alone. The link check then reports what still does not resolve.
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

import { listWorkDirFiles } from "../acquisition/acquire.js";
import { runCheckWatchOutcomes } from "../evals/check-watch-outcomes.js";
import { LANES } from "../lib/slice-lanes.js";
import { resolveTempSession } from "../lib/temp-session-paths.js";
import { watchStatePath } from "./watch-state.js";

/** info.json keys the corpus copy drops: format, caption-URL, heatmap and request lists. */
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
  "requested_downloads",
]);

export const INFO_JSON_COMMENT_CAP = 20;

/** Path prefixes that name files in another repository, never in the slice. */
export const ALLOWED_MISS_PREFIXES = Object.freeze([
  "plugins/",
  "docs/",
  "templates/",
  ".claude/",
  "AGENTS.md",
]);

const KEY_FRAME_LOGS = new Set([
  "key-frames-manifest.md",
  "visual-frames.md",
  "key-frame-quality-audit.md",
  "frame-triage-log.md",
]);
const SOURCE_METADATA = new Set([
  "harvested-links.json",
  "harvested-repo-analysis.json",
  "deck-inventory.md",
  "companion-sources.md",
]);
const TRANSCRIPT_TEXT = /^transcript(?:-\d+)?\.txt$/;

const VIDEO_FILE = /\.(?:mp4|mkv|webm)$/;
const URL_SCHEME = /^[a-z][a-z0-9+.-]*:/i;
const PLACEHOLDER = /[<>{}*$\s]/;
const LINE_SUFFIX = /:\d+(?:[-,]\d+)*$/;
const MARKDOWN_LINK = /(\]\()(<[^>]+>|[^)\s]+)/g;
const FULL_LINK = /!?\[([^\]\n]*)\]\((<[^>]+>|[^)\s]+)[^)\n]*\)/g;
const BACKTICK_SPAN = /`([^`\s]+)`/g;
/** A backticked span names a path when it holds a separator or ends in an extension. */
const PATH_LIKE = /\/|\.[A-Za-z0-9]+(?::\d+(?:[-,]\d+)*)?(?:#.*)?$/;

/**
 * Corpus-layout path for a slice-relative file, or null when the corpus keeps
 * no copy of it.
 *
 * @param {string} sliceRel - posix path relative to the slice root
 * @returns {string|null}
 */
export function corpusPathForSliceFile(sliceRel) {
  const [lane, ...rest] = sliceRel.split("/");
  const name = rest.join("/");
  if (sliceRel === "RESEARCH.md") return "analysis/RESEARCH.md";
  if (lane === LANES.research || lane === LANES.recommendations) return `analysis/${sliceRel}`;
  if (lane === LANES.source && rest[0] === "companion-digest" && rest.length > 1) {
    return `analysis/${name}`;
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
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    return entry.isDirectory() ? listFiles(path.join(dir, entry.name), rel) : [rel];
  });
}

/**
 * Directory mappings implied by the file mappings: a source directory maps to
 * a target directory only when every mapped file under it agrees.
 *
 * @param {Map<string, string>} fileMap
 * @returns {Map<string, string>}
 */
function deriveDirectoryMap(fileMap) {
  /** @type {Map<string, string|null>} */
  const candidates = new Map();
  for (const [from, to] of fileMap) {
    const fromParts = from.split("/");
    const toParts = to.split("/");
    for (let depth = 1; depth < fromParts.length && depth < toParts.length; depth++) {
      if (fromParts.at(-depth) !== toParts.at(-depth)) break;
      const fromDir = fromParts.slice(0, -depth).join("/");
      const toDir = toParts.slice(0, -depth).join("/");
      const seen = candidates.get(fromDir);
      candidates.set(fromDir, seen === undefined || seen === toDir ? toDir : null);
    }
  }
  return new Map(
    [...candidates].filter(
      /** @returns {entry is [string, string]} */ (entry) => entry[1] !== null,
    ),
  );
}

/**
 * @typedef {Object} PathMap
 * @property {Map<string, string>} files - slice-relative file → target-relative file
 * @property {Map<string, string>} dirs - slice-relative directory → target-relative directory
 * @property {Map<string, string>} tempFrames - temp frame file name → target-relative file
 * @property {string} sliceName - the slice directory's own name
 * @property {Set<string>} sliceEntries - every slice-relative file and directory
 */

/** @typedef {{ target: string, isDir: boolean } | { retired: string }} Lookup */

/**
 * Split a reference into its path and the suffix to carry over unchanged
 * (`#anchor`, `?query`, `:line`).
 *
 * @param {string} ref
 * @returns {{ refPath: string, suffix: string }}
 */
function splitReference(ref) {
  const hash = ref.search(/[#?]/);
  let refPath = hash === -1 ? ref : ref.slice(0, hash);
  let suffix = hash === -1 ? "" : ref.slice(hash);
  const line = LINE_SUFFIX.exec(refPath);
  if (line) {
    suffix = line[0] + suffix;
    refPath = refPath.slice(0, line.index);
  }
  return { refPath, suffix };
}

/**
 * What a reference names: a copied path (its target), a slice file or
 * directory the layout does not keep (`retired`), or null when it names
 * neither.
 *
 * @param {string} refPath
 * @param {string} sourceFile - slice-relative path of the file naming it
 * @param {PathMap} map
 * @returns {Lookup|null}
 */
function lookUpReference(refPath, sourceFile, map) {
  const bare = refPath.replace(/\/+$/, "");
  if (!bare || URL_SCHEME.test(bare) || PLACEHOLDER.test(bare) || bare.startsWith("/")) {
    return null;
  }
  const lookup = (/** @type {string|null} */ key) => {
    if (key === null) return null;
    const file = map.files.get(key);
    if (file !== undefined) return { target: file, isDir: false };
    const dir = map.dirs.get(key);
    if (dir !== undefined) return { target: dir, isDir: true };
    return null;
  };
  /** @type {(string|null)[]} */
  let keys;
  // `SLICE/<path>` and `.work/<epic>/<slice>/<path>` name the slice root explicitly.
  const marker = `/${map.sliceName}/`;
  if (bare.startsWith("SLICE/")) {
    keys = [path.posix.normalize(bare.slice("SLICE/".length))];
  } else if (bare.includes(marker)) {
    keys = [path.posix.normalize(bare.slice(bare.indexOf(marker) + marker.length))];
  } else {
    keys = [
      path.posix.normalize(path.posix.join(path.posix.dirname(sourceFile), bare)),
      bare.startsWith(".") ? null : path.posix.normalize(bare),
    ];
  }
  for (const key of keys) {
    const found = lookup(key);
    if (found) return found;
  }
  const retired = keys.find((key) => key !== null && map.sliceEntries.has(key));
  if (retired) return { retired };
  // An unknown file in a copied directory moves with the directory, so the
  // link check flags it at its new location.
  for (const key of bare.includes("/") ? keys : []) {
    const dir = key === null ? undefined : map.dirs.get(path.posix.dirname(key));
    if (dir !== undefined && key !== null) {
      return { target: `${dir}/${path.posix.basename(key)}`, isDir: false };
    }
  }
  const frame = bare.includes("/") ? undefined : map.tempFrames.get(bare);
  return frame ? { target: frame, isDir: false } : null;
}

const NOT_RETAINED = "not retained in this copy";

/**
 * Rewrite every markdown link and backticked path in `text` that names a
 * slice path: a copied one relative to the file's target location, one the
 * layout does not keep as plain text naming it as not retained.
 *
 * @param {string} text
 * @param {string} sourceFile - slice-relative path of the file
 * @param {string} targetFile - target-relative path the file is copied to
 * @param {PathMap} map
 * @returns {{ text: string, rewrites: number }}
 */
export function rewriteSliceReferences(text, sourceFile, targetFile, map) {
  let rewrites = 0;
  const unwrap = (/** @type {string} */ target) =>
    target.startsWith("<") ? target.slice(1, -1) : target;
  const rewrite = (/** @type {string} */ ref) => {
    const { refPath, suffix } = splitReference(ref);
    const found = lookUpReference(refPath, sourceFile, map);
    if (!found || "retired" in found) return ref;
    const relative = path.posix.relative(path.posix.dirname(targetFile), found.target) || ".";
    const trailing = found.isDir && refPath.endsWith("/") ? "/" : "";
    const next = `${relative}${trailing}${suffix}`;
    if (next !== ref) rewrites += 1;
    return next;
  };
  const rewritten = text
    .replace(FULL_LINK, (match, label, target) => {
      const found = lookUpReference(splitReference(unwrap(target)).refPath, sourceFile, map);
      if (!found || !("retired" in found)) return match;
      rewrites += 1;
      return `${label} (${found.retired}, ${NOT_RETAINED})`;
    })
    .replace(MARKDOWN_LINK, (_match, open, target) =>
      target.startsWith("<") ? `${open}<${rewrite(unwrap(target))}>` : `${open}${rewrite(target)}`,
    )
    .replace(BACKTICK_SPAN, (match, span) => {
      if (!PATH_LIKE.test(span)) return match;
      const found = lookUpReference(splitReference(span).refPath, sourceFile, map);
      if (found && "retired" in found) {
        rewrites += 1;
        return `${found.retired} (${NOT_RETAINED})`;
      }
      return `\`${rewrite(span)}\``;
    });
  return { text: rewritten, rewrites };
}

/**
 * True when a backticked span reads as a path into the slice: `SLICE/`, an
 * explicit `./` or `../` path, or one whose first segment is a top-level
 * entry of the re-laid-out slice or an entry beside the naming file. Any
 * other path is one the path map did not know under no slice directory, a
 * path into another repository.
 *
 * @param {string} refPath
 * @param {string} fileDir - absolute directory of the naming file
 * @param {Set<string>} topLevel - top-level entries of the re-laid-out slice
 */
function looksSliceInternal(refPath, fileDir, topLevel) {
  if (!refPath.includes("/")) return false;
  if (/^(?:\.\.?|SLICE)\//.test(refPath)) return true;
  const first = refPath.split("/")[0];
  return topLevel.has(first) || fs.existsSync(path.join(fileDir, first));
}

/**
 * Link check over a re-laid-out slice: every markdown link and every
 * backticked slice path in its markdown must resolve against the naming
 * file's directory. URLs, placeholders, absolute paths, paths that leave the
 * slice (another repository) and the allowed-miss prefixes are skipped.
 *
 * @param {string} rootDir
 * @returns {{ file: string, ref: string }[]} unresolved references
 */
export function checkLayoutLinks(rootDir) {
  const root = path.resolve(rootDir);
  const topLevel = new Set(fs.existsSync(root) ? fs.readdirSync(root) : []);
  /** @type {{ file: string, ref: string }[]} */
  const unresolved = [];
  const markdown = listFiles(root).filter(
    (file) => file.endsWith(".md") && !file.startsWith("frames/all/") && !file.startsWith("media/"),
  );
  for (const file of markdown) {
    const fileDir = path.dirname(path.join(root, file));
    const text = fs.readFileSync(path.join(root, file), "utf8");
    const check = (/** @type {string} */ ref, /** @type {boolean} */ isLink) => {
      const { refPath } = splitReference(ref);
      if (!refPath || URL_SCHEME.test(refPath) || PLACEHOLDER.test(refPath)) return;
      if (refPath.startsWith("/") || refPath.startsWith("~")) return;
      if (ALLOWED_MISS_PREFIXES.some((prefix) => refPath.startsWith(prefix))) return;
      if (!isLink && !looksSliceInternal(refPath, fileDir, topLevel)) return;
      const resolved = path.resolve(fileDir, refPath);
      const rel = path.relative(root, resolved);
      if (rel.startsWith("..") || path.isAbsolute(rel)) return;
      if (!fs.existsSync(resolved)) unresolved.push({ file, ref });
    };
    for (const match of text.matchAll(MARKDOWN_LINK)) {
      check(match[2].replace(/^<|>$/g, ""), true);
    }
    for (const match of text.matchAll(BACKTICK_SPAN)) {
      check(match[1], false);
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
  if (Array.isArray(trimmed.comments)) {
    trimmed.comments = trimmed.comments.slice(0, INFO_JSON_COMMENT_CAP);
  }
  return trimmed;
}

const CONTENTS_LINES = /** @type {const} */ ([
  ["media/", "source video as downloaded"],
  ["transcript/", "timestamped transcript, plus the caption tracks as served when kept"],
  ["metadata/", "source metadata: trimmed info JSON, harvested links, repo analysis, decks"],
  ["frames/all/", "every frame the pipeline extracted, with their times in `frame-times.json`"],
  ["frames/key/", "the promoted key frames; the logs beside them in `frames/` describe them"],
  ["analysis/", "the digest's research and recommendations"],
]);

/**
 * @param {{ title: string, sourceUrl: string, videoId: string, acquiredAt?: string }} meta
 * @param {Set<string>} presentTopDirs - target directories that received files
 */
function provenanceReadme({ title, sourceUrl, videoId, acquiredAt }, presentTopDirs) {
  const fetched = acquiredAt ? ` on ${acquiredAt.slice(0, 10)}` : "";
  const contents = CONTENTS_LINES.filter(([dir]) => presentTopDirs.has(dir)).map(
    ([dir, label]) => `- \`${dir}\`: ${label}`,
  );
  return [
    `# ${title}`,
    "",
    "## Provenance",
    "",
    `- Canonical origin: <${sourceUrl}>`,
    `- Video id: \`${videoId}\``,
    `- Fetched${fetched} through \`/knowledge:video-digest\` and re-laid out from its finished slice.`,
    "",
    "## Contents",
    "",
    ...contents,
    "",
  ].join("\n");
}

/**
 * Real path of `p`, resolving symlinks through its nearest existing ancestor
 * when `p` itself does not exist yet.
 *
 * @param {string} p - absolute path
 * @returns {string}
 */
function realPathOf(p) {
  let existing = p;
  const rest = [];
  while (!fs.existsSync(existing) && path.dirname(existing) !== existing) {
    rest.unshift(path.basename(existing));
    existing = path.dirname(existing);
  }
  return path.join(fs.realpathSync.native(existing), ...rest);
}

/**
 * @param {string} inner
 * @param {string} outer
 */
function isSameOrInside(inner, outer) {
  const rel = path.relative(outer, inner);
  return rel === "" || (rel !== ".." && !rel.startsWith(`..${path.sep}`) && !path.isAbsolute(rel));
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
 *   copyFile?: (from: string, to: string) => void,
 * }} options - `noMedia` copies nothing from the temp session; `replace`
 *   allows an existing target, keeping its `README.md`; `verifyOutcomes` gates
 *   a slice that is not closed yet and returns 0 when its outcome checks pass
 * @returns {Promise<RelayoutResult>}
 */
export async function relayoutSlice({
  sliceDir,
  targetDir,
  noMedia = false,
  replace = false,
  verifyOutcomes = (dir) => runCheckWatchOutcomes(dir),
  copyFile = fs.copyFileSync,
}) {
  const slice = path.resolve(sliceDir);
  const target = path.resolve(targetDir);
  const refuse = (/** @type {string} */ message) => {
    writeStderr(`relayout: ${message}`);
    return { exitCode: 1, copied: 0, rewrites: 0, unresolved: [] };
  };

  // A target that is, holds, or sits inside the slice would copy the slice
  // into itself, and `--replace` would move the slice away and delete it.
  const realSlice = realPathOf(slice);
  const realTarget = realPathOf(target);
  if (isSameOrInside(realTarget, realSlice) || isSameOrInside(realSlice, realTarget)) {
    return refuse(`target ${target} overlaps the slice ${slice}; pick a target outside it`);
  }

  // An interrupted `--replace` swap leaves the previous target at this name.
  const backup = `${target}.relayout-backup`;
  if (fs.existsSync(backup)) {
    if (fs.existsSync(target)) {
      return refuse(
        `a leftover backup ${backup} sits beside ${target}; keep one of them and remove the other`,
      );
    }
    fs.renameSync(backup, target);
    writeStderr(`relayout: restored ${target} from the backup an interrupted run left`);
  }

  let state;
  try {
    state = JSON.parse(fs.readFileSync(watchStatePath(slice), "utf8"));
  } catch {
    return refuse(`no readable run-state/watch.json under ${slice}`);
  }
  const outcomesPass = () => {
    try {
      return verifyOutcomes(slice) === 0;
    } catch (error) {
      writeStderr(`relayout: outcome checks threw: ${/** @type {Error} */ (error).message}`);
      return false;
    }
  };
  if (state.status !== "complete" && !outcomesPass()) {
    return refuse(
      `slice status is "${state.status}" and its outcome checks fail; ` +
        "re-lay out a closed slice, or one whose check-watch-outcomes.js passes",
    );
  }

  if (fs.existsSync(target) && !replace) {
    return refuse(`${target} exists; pass --replace to replace it`);
  }

  // `--no-media` takes nothing from the temp session, even when it still exists.
  const temp = resolveTempSession(noMedia ? {} : (state.tempSession ?? {}));
  const workFiles = temp.workDir ? await listWorkDirFiles(temp.workDir) : [];
  // The watch does not record which work file is the primary entry's, so only
  // a work dir holding exactly one video is unambiguous (an X post with
  // several videos is not). That video's id, the `%(id)s` of yt-dlp's output
  // template, picks its info JSON and caption tracks.
  const videos = workFiles.filter((file) => VIDEO_FILE.test(file));
  if (!noMedia && videos.length > 1) {
    return refuse(
      `the temp session holds several videos (${videos.map((file) => path.basename(file)).join(", ")}) ` +
        "and the watch did not record which is primary; pass --no-media",
    );
  }
  const mediaId = videos.length === 1 ? path.basename(videos[0], path.extname(videos[0])) : null;
  const ofMedia = (/** @type {string} */ file) =>
    mediaId !== null && path.basename(file).startsWith(`${mediaId}.`);
  const media = {
    videoPath: videos[0] ?? "",
    captionPaths: workFiles.filter((file) => ofMedia(file) && file.endsWith(".vtt")),
    metadataPath: workFiles.find((file) => ofMedia(file) && file.endsWith(".info.json")) ?? "",
  };
  if (!noMedia) {
    // A partly removed temp session would yield a layout silently missing a part.
    const frameNames = temp.framesDir ? listFiles(temp.framesDir) : [];
    const captioned = Boolean(state.phases?.acquire?.metrics?.captionRung);
    const missing = [
      ...(media.videoPath ? [] : [`the video (${temp.workDir ?? "no tempSession.workDir"})`]),
      ...(media.videoPath && !media.metadataPath ? [`the info JSON (${mediaId}.info.json)`] : []),
      ...(frameNames.length > 0
        ? []
        : [`the frames (${temp.framesDir ?? "no tempSession.framesDir"})`]),
      ...(captioned && media.captionPaths.length === 0 ? ["the caption tracks"] : []),
    ];
    if (missing.length > 0) {
      return refuse(
        `the temp session is missing ${missing.join(", ")}; ` +
          "pass --no-media to re-lay out without media/, frames/all/, the caption tracks and info.json",
      );
    }
  }

  /** @type {{ from: string, to: string, sourceFile?: string }[]} */
  const plan = [];
  const sliceFiles = listFiles(slice);
  const sliceEntries = new Set(
    sliceFiles.flatMap((file) =>
      file.split("/").map((_part, index, parts) => parts.slice(0, index + 1).join("/")),
    ),
  );
  for (const file of sliceFiles) {
    const to = corpusPathForSliceFile(file);
    if (to) plan.push({ from: path.join(slice, file), to, sourceFile: file });
  }
  for (const caption of media.captionPaths) {
    const name = path.basename(caption).replace(`${mediaId}.`, "");
    plan.push({ from: caption, to: `transcript/${name}` });
  }
  /** @type {Map<string, string>} */
  const tempFrames = new Map();
  if (temp.framesDir) {
    for (const name of listFiles(temp.framesDir).filter((file) => !file.includes("/"))) {
      plan.push({ from: path.join(temp.framesDir, name), to: `frames/all/${name}` });
      tempFrames.set(name, `frames/all/${name}`);
    }
  }
  if (media.videoPath) {
    plan.push({
      from: media.videoPath,
      to: `media/${state.videoId}${path.extname(media.videoPath)}`,
    });
  }

  // A reference to the slice README lands on the target README, provenance or existing.
  const files = new Map([
    ["README.md", "README.md"],
    ...plan.flatMap((entry) =>
      entry.sourceFile ? [/** @type {[string, string]} */ ([entry.sourceFile, entry.to])] : [],
    ),
  ]);
  /** @type {PathMap} */
  const map = {
    files,
    dirs: deriveDirectoryMap(files),
    tempFrames,
    sliceName: path.basename(slice),
    sliceEntries,
  };

  // Build the whole layout in a sibling staging directory and move it into
  // place only after the link check passes, so a failure never leaves a
  // partial target.
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const staging = fs.mkdtempSync(
    path.join(path.dirname(target), `.${path.basename(target)}.relayout-`),
  );
  const discard = (/** @type {string} */ dir) => fs.rmSync(dir, { recursive: true, force: true });
  let rewrites = 0;
  let copied = 0;
  /** @type {{ file: string, ref: string }[]} */
  let unresolved;
  try {
    const write = (/** @type {string} */ to, /** @type {string} */ body) => {
      const dest = path.join(staging, to);
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      fs.writeFileSync(dest, body);
      copied += 1;
    };
    for (const entry of plan) {
      if (entry.sourceFile?.endsWith(".md")) {
        const result = rewriteSliceReferences(
          fs.readFileSync(entry.from, "utf8"),
          entry.sourceFile,
          entry.to,
          map,
        );
        rewrites += result.rewrites;
        write(entry.to, result.text);
      } else {
        fs.mkdirSync(path.dirname(path.join(staging, entry.to)), { recursive: true });
        copyFile(entry.from, path.join(staging, entry.to));
        copied += 1;
      }
    }
    if (media.metadataPath) {
      const info = JSON.parse(fs.readFileSync(media.metadataPath, "utf8"));
      write("metadata/info.json", `${JSON.stringify(trimInfoJson(info), null, 2)}\n`);
    }

    const existingReadme = path.join(target, "README.md");
    if (fs.existsSync(existingReadme)) {
      write("README.md", fs.readFileSync(existingReadme, "utf8"));
    } else {
      const present = new Set(
        CONTENTS_LINES.map(([dir]) => dir).filter((dir) => fs.existsSync(path.join(staging, dir))),
      );
      write(
        "README.md",
        provenanceReadme(
          {
            title: state.title,
            sourceUrl: state.sourceUrl,
            videoId: state.videoId,
            acquiredAt: state.tempSession?.acquiredAt,
          },
          present,
        ),
      );
    }

    unresolved = checkLayoutLinks(staging);
  } catch (error) {
    discard(staging);
    return refuse(`copy failed, target left untouched: ${/** @type {Error} */ (error).message}`);
  }
  if (unresolved.length > 0) {
    discard(staging);
    return { exitCode: 1, copied: 0, rewrites, unresolved };
  }

  // The backup keeps a fixed name so a run killed between the two renames is
  // recovered at the next start (see the backup check above).
  const hadTarget = fs.existsSync(target);
  try {
    if (hadTarget) fs.renameSync(target, backup);
    fs.renameSync(staging, target);
  } catch (error) {
    if (hadTarget && !fs.existsSync(target) && fs.existsSync(backup)) fs.renameSync(backup, target);
    discard(staging);
    return refuse(`could not move the layout into place: ${/** @type {Error} */ (error).message}`);
  }
  if (hadTarget) discard(backup);
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
    writeStderr(
      "Usage: node watch/relayout-slice.js <slice-dir> <target-dir> [--no-media] [--replace]",
    );
    return 2;
  }
  const [sliceDir, targetDir] = positional;
  const result = await relayoutSlice({ sliceDir, targetDir, noMedia, replace });
  if (result.copied > 0) {
    writeStdout(
      `relayout: ${result.copied} files written to ${path.resolve(targetDir)}, ` +
        `${result.rewrites} references rewritten`,
    );
  }
  for (const { file, ref } of result.unresolved) {
    writeStderr(`unresolved: ${file} -> ${ref}`);
  }
  if (result.unresolved.length > 0) {
    writeStderr(`relayout: ${result.unresolved.length} slice-internal paths do not resolve`);
  }
  return result.exitCode;
}

if (isMainModule(import.meta.url)) {
  process.exit(await runRelayoutCli(process.argv.slice(2)));
}
