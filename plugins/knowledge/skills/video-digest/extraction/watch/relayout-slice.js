#!/usr/bin/env node
/**
 * Copy a closed video-digest slice into a target directory in the
 * knowledge-corpus layout, rewrite the slice-internal paths its markdown names,
 * then link-check the result.
 *
 * Target layout: `transcript/` (transcript text and the served caption tracks),
 * `metadata/` (trimmed info JSON, harvested links and repo analysis, deck
 * inventory), `frames/all/` (every extracted frame plus `frame-times.json`),
 * `frames/key/` (promoted key frames) beside the frame logs in `frames/`,
 * `media/<id>.<ext>`, `analysis/` (`RESEARCH.md`, `research/`,
 * `recommendations/`) and a provenance `README.md` when the target has none.
 *
 * Every reference is rewritten through a path map built from the copy plan:
 * a reference resolves first against the naming file's own directory, then
 * against the slice root, and is left alone when neither lands on a mapped
 * path. The link check then reports what still does not resolve.
 *
 * Usage: node watch/relayout-slice.js <slice-dir> <target-dir> [--no-media]
 * Exit: 0 copied and every slice-internal path resolves; 1 refused or
 * unresolved paths (listed on stderr); 2 usage.
 */

import fs from "node:fs";
import path from "node:path";

import { isMainModule } from "@melodic/video-digestion/shared/main-module";
import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { listWorkDirFiles, resolveMediaArtifacts } from "../acquisition/acquire.js";
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
]);
const SOURCE_METADATA = new Set([
  "harvested-links.json",
  "harvested-repo-analysis.json",
  "deck-inventory.md",
]);
const TRANSCRIPT_TEXT = /^transcript(?:-\d+)?\.txt$/;

/** First path segments that name a slice or corpus-layout location. */
const LAYOUT_SEGMENTS = new Set([
  "transcript",
  "metadata",
  "frames",
  "media",
  "analysis",
  "SLICE",
  ...Object.values(LANES),
]);

const URL_SCHEME = /^[a-z][a-z0-9+.-]*:/i;
const PLACEHOLDER = /[<>{}*$\s]/;
const LINE_SUFFIX = /:\d+(?:[-,]\d+)*$/;
const MARKDOWN_LINK = /(\]\()(<[^>]+>|[^)\s]+)/g;
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
 */

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
 * Target-relative location a reference names, or null when the path map does
 * not hold it.
 *
 * @param {string} refPath
 * @param {string} sourceFile - slice-relative path of the file naming it
 * @param {PathMap} map
 * @returns {{ target: string, isDir: boolean }|null}
 */
function lookUpReference(refPath, sourceFile, map) {
  const bare = refPath.replace(/\/+$/, "");
  if (!bare || URL_SCHEME.test(bare) || PLACEHOLDER.test(bare) || bare.startsWith("/")) {
    return null;
  }
  const lookup = (/** @type {string} */ key) => {
    if (map.files.has(key))
      return { target: /** @type {string} */ (map.files.get(key)), isDir: false };
    if (map.dirs.has(key))
      return { target: /** @type {string} */ (map.dirs.get(key)), isDir: true };
    return null;
  };
  // `SLICE/<path>` and `.work/<epic>/<slice>/<path>` name the slice root explicitly.
  if (bare.startsWith("SLICE/")) return lookup(path.posix.normalize(bare.slice("SLICE/".length)));
  const marker = `/${map.sliceName}/`;
  if (bare.includes(marker)) {
    return lookup(path.posix.normalize(bare.slice(bare.indexOf(marker) + marker.length)));
  }

  const fromFile = path.posix.normalize(path.posix.join(path.posix.dirname(sourceFile), bare));
  const fromRoot = bare.startsWith(".") ? null : path.posix.normalize(bare);
  const found = lookup(fromFile) ?? (fromRoot === null ? null : lookup(fromRoot));
  if (found) return found;
  const frame = bare.includes("/") ? undefined : map.tempFrames.get(bare);
  return frame ? { target: frame, isDir: false } : null;
}

/**
 * Rewrite every markdown link and backticked path in `text` that names a
 * mapped slice path, relative to the file's target location.
 *
 * @param {string} text
 * @param {string} sourceFile - slice-relative path of the file
 * @param {string} targetFile - target-relative path the file is copied to
 * @param {PathMap} map
 * @returns {{ text: string, rewrites: number }}
 */
export function rewriteSliceReferences(text, sourceFile, targetFile, map) {
  let rewrites = 0;
  const rewrite = (/** @type {string} */ ref) => {
    const { refPath, suffix } = splitReference(ref);
    const found = lookUpReference(refPath, sourceFile, map);
    if (!found) return ref;
    const relative = path.posix.relative(path.posix.dirname(targetFile), found.target) || ".";
    const trailing = found.isDir && refPath.endsWith("/") ? "/" : "";
    const next = `${relative}${trailing}${suffix}`;
    if (next !== ref) rewrites += 1;
    return next;
  };
  const rewritten = text
    .replace(MARKDOWN_LINK, (_match, open, target) =>
      target.startsWith("<")
        ? `${open}<${rewrite(target.slice(1, -1))}>`
        : `${open}${rewrite(target)}`,
    )
    .replace(BACKTICK_SPAN, (match, span) =>
      PATH_LIKE.test(span) ? `\`${rewrite(span)}\`` : match,
    );
  return { text: rewritten, rewrites };
}

/**
 * True when a backticked span reads as a path into the slice: an explicit
 * `./` or `../` path, or one whose first segment is a layout directory or an
 * entry beside the naming file.
 *
 * @param {string} refPath
 * @param {string} fileDir - absolute directory of the naming file
 */
function looksSliceInternal(refPath, fileDir) {
  if (!refPath.includes("/")) return false;
  if (refPath.startsWith("./") || refPath.startsWith("../")) return true;
  const first = refPath.split("/")[0];
  return LAYOUT_SEGMENTS.has(first) || fs.existsSync(path.join(fileDir, first));
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
      if (!isLink && !looksSliceInternal(refPath, fileDir)) return;
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
    `- Fetched${fetched} through \`/knowledge:video-digest\` and re-laid out from its closed slice.`,
    "",
    "## Contents",
    "",
    ...contents,
    "",
  ].join("\n");
}

/**
 * @typedef {Object} RelayoutResult
 * @property {number} exitCode
 * @property {number} copied - files written to the target
 * @property {number} rewrites - references rewritten
 * @property {{ file: string, ref: string }[]} unresolved
 */

/**
 * @param {{ sliceDir: string, targetDir: string, noMedia?: boolean }} options
 * @returns {Promise<RelayoutResult>}
 */
export async function relayoutSlice({ sliceDir, targetDir, noMedia = false }) {
  const slice = path.resolve(sliceDir);
  const target = path.resolve(targetDir);
  const refuse = (/** @type {string} */ message) => {
    writeStderr(`relayout: ${message}`);
    return { exitCode: 1, copied: 0, rewrites: 0, unresolved: [] };
  };

  let state;
  try {
    state = JSON.parse(fs.readFileSync(watchStatePath(slice), "utf8"));
  } catch {
    return refuse(`no readable run-state/watch.json under ${slice}`);
  }
  if (state.status !== "complete") {
    return refuse(`slice status is "${state.status}", not "complete"; close the slice first`);
  }

  const temp = resolveTempSession(state.tempSession ?? {});
  const workFiles = temp.workDir ? await listWorkDirFiles(temp.workDir) : [];
  const media = resolveMediaArtifacts(workFiles, state.videoId);
  if (!media.videoPath && !noMedia) {
    return refuse(
      `the temp session's media is gone (${temp.workDir ?? "no tempSession.workDir"}); ` +
        "pass --no-media to re-lay out without media/, frames/all/, the caption tracks and info.json",
    );
  }

  /** @type {{ from: string, to: string, sourceFile?: string }[]} */
  const plan = [];
  for (const file of listFiles(slice)) {
    const to = corpusPathForSliceFile(file);
    if (to) plan.push({ from: path.join(slice, file), to, sourceFile: file });
  }
  for (const caption of media.captionPaths) {
    const name = path.basename(caption).replace(`${state.videoId}.`, "");
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
  if (media.videoPath && !noMedia) {
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
  };

  let rewrites = 0;
  const write = (/** @type {string} */ to, /** @type {string|Buffer} */ body) => {
    const dest = path.join(target, to);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, body);
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
      fs.mkdirSync(path.dirname(path.join(target, entry.to)), { recursive: true });
      fs.copyFileSync(entry.from, path.join(target, entry.to));
    }
  }
  let copied = plan.length;
  if (media.metadataPath) {
    const info = JSON.parse(fs.readFileSync(media.metadataPath, "utf8"));
    write("metadata/info.json", `${JSON.stringify(trimInfoJson(info), null, 2)}\n`);
    copied += 1;
  }

  const readmePath = path.join(target, "README.md");
  if (!fs.existsSync(readmePath)) {
    const present = new Set(
      CONTENTS_LINES.map(([dir]) => dir).filter((dir) => fs.existsSync(path.join(target, dir))),
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
    copied += 1;
  }

  const unresolved = checkLayoutLinks(target);
  return { exitCode: unresolved.length > 0 ? 1 : 0, copied, rewrites, unresolved };
}

/**
 * @param {string[]} args - argv after the script path
 * @returns {Promise<number>}
 */
export async function runRelayoutCli(args) {
  const noMedia = args.includes("--no-media");
  const positional = args.filter((arg) => arg !== "--no-media");
  if (positional.length !== 2 || positional.some((arg) => arg.startsWith("--"))) {
    writeStderr("Usage: node watch/relayout-slice.js <slice-dir> <target-dir> [--no-media]");
    return 2;
  }
  const [sliceDir, targetDir] = positional;
  const result = await relayoutSlice({ sliceDir, targetDir, noMedia });
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
