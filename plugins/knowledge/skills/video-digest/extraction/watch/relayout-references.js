/**
 * The path half of a video-digest slice re-layout: find the references in a
 * markdown file, rewrite them for the file's new location, and link-check a
 * staged layout. The copy plan, staging and CLI live in `relayout-slice.js`.
 *
 * Markdown is parsed with mdast-util-from-markdown; the links, images,
 * definitions and path-like code spans it finds are edited in place by source
 * offset, so nothing else in the file changes. A reference resolves first
 * against the naming file's own directory, then against the slice root
 * (`SLICE/<path>` names the root explicitly). One landing on a copied path is
 * rewritten relative to the file's new location; one landing on a slice file
 * or directory the layout does not keep becomes plain text naming it as not
 * retained; anything else (URLs, other repositories' paths) is left alone.
 */

import fs from "node:fs";
import path from "node:path";

import { fromMarkdown } from "mdast-util-from-markdown";

export const MARKDOWN_FILE = /\.(?:md|markdown)$/i;
/** Link paths naming another repository's files: a directory (trailing `/`) matches below it, a file exactly. */
const ALLOWED_MISSES = Object.freeze(["plugins/", "docs/", "templates/", ".claude/", "AGENTS.md"]);
const URL_SCHEME = /^[a-z][a-z0-9+.-]*:/i;
/** Placeholder or glob syntax (`<slice>/x`, `${ROOT}`, `{tmp}`, `*.md`), never a real path. */
const PLACEHOLDER = /[<>{}*$]/;
/** `:12`, `:12-20`, `:12,15` and `:12:5` endings on a backticked path. */
const LINE_SUFFIX = /(?::\d+(?:[-,]\d+)*)+$/;
const NOT_RETAINED = "not retained in this copy";

/**
 * @typedef {Object} MarkdownRef
 * @property {"link"|"code"} kind - link, image or definition destination; or code span
 * @property {string} value - the destination (escapes decoded) or code span text
 * @property {number|null} from - offset of `value` as written, null when it is written differently
 * @property {number} to
 * @property {number} nodeStart - the whole link, image, definition or code span
 * @property {number} nodeEnd
 * @property {string} label - link text, image alt or definition label
 * @property {number|null} labelStart - a link's text span, null for other nodes
 * @property {number|null} labelEnd
 * @property {boolean} definition
 *
 * @typedef {Object} PathMap
 * @property {Map<string, string>} files - slice file → target file
 * @property {Map<string, string>} dirs - slice directory → target directory, when its kept files moved together
 * @property {Set<string>} entries - every slice file and directory
 * @property {Map<string, string>} tempFrames - extracted frame name → target file
 *
 * @typedef {{ target: string } | { retired: string, note: string } | { missing: true }} Lookup
 */

/**
 * @param {string} dir
 * @param {string} [prefix]
 * @returns {string[]} posix paths of every regular file under dir, relative to
 *   it; symlinks are skipped so a copy never reads outside the slice
 */
export function listFiles(dir, prefix = "") {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) return listFiles(path.join(dir, entry.name), rel);
    return entry.isFile() ? [rel] : [];
  });
}

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
      const children = node.type === "link" && node.children.length > 0;
      const labelStart = children ? node.children[0].position.start.offset : null;
      const labelEnd = children ? node.children.at(-1).position.end.offset : null;
      const label = children ? text.slice(labelStart, labelEnd) : (node.alt ?? node.label ?? "");
      const from = at === -1 ? null : nodeStart + at;
      const to = at === -1 ? 0 : nodeStart + at + value.length;
      refs.push({
        kind,
        value,
        from,
        to,
        nodeStart,
        nodeEnd,
        label,
        labelStart,
        labelEnd,
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
  const [p, suffix] = fragment(ref.value);
  if (ref.kind === "code") {
    return [...withLines(ref.value, ""), ...(suffix ? withLines(p, suffix) : [])];
  }
  const decode = (/** @type {string} */ segment) => {
    try {
      return decodeURIComponent(segment);
    } catch {
      return segment;
    }
  };
  return withLines(p.split("/").map(decode).join("/"), suffix);
}

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
    const note =
      splitInto.length === 0
        ? NOT_RETAINED
        : `${splitInto.length === 1 ? "now under" : "split across"} ${splitInto.join(", ")} in this copy`;
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
  /** @type {{ from: number, to: number, text: string, part?: boolean, retire?: boolean }[]} */
  const edits = [];
  /** @type {[number, number][]} */
  const retiredLabels = [];
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
      if (ref.labelStart !== null && ref.labelEnd !== null) {
        // Keep the link text in place, so edits inside it (a rewritten image) still apply.
        edits.push({ from: ref.nodeStart, to: ref.labelStart, text: "", part: true });
        edits.push({ from: ref.labelEnd, to: ref.nodeEnd, text: ` (${named}, ${found.note})` });
        retiredLabels.push([ref.labelStart, ref.labelEnd]);
        continue;
      }
      const plain = ref.definition
        ? `${ref.label}: ${named} (${found.note})`
        : ref.label
          ? `${ref.label} (${named}, ${found.note})`
          : `${named} (${found.note})`;
      edits.push({ from: ref.nodeStart, to: ref.nodeEnd, text: plain, retire: true });
    }
  }
  // A retired link already names what it pointed at, so a retirement inside its
  // text (a code span naming the same file) is dropped; an overlapping edit
  // after one kept is dropped too.
  const inRetiredLabel = (/** @type {{ from: number, to: number }} */ edit) =>
    retiredLabels.some(([start, end]) => start <= edit.from && edit.to <= end);
  /** @type {typeof edits} */
  const kept = [];
  const candidates = edits.filter((edit) => !(edit.retire && inRetiredLabel(edit)));
  for (const edit of candidates.sort((a, b) => a.from - b.from || b.to - a.to)) {
    const last = kept.at(-1);
    if (!last || edit.from >= last.to) kept.push(edit);
  }
  // Back to front, so earlier offsets stay valid.
  let out = text;
  for (const edit of kept.reverse()) {
    out = out.slice(0, edit.from) + edit.text + out.slice(edit.to);
  }
  return { text: out, rewrites: kept.filter((edit) => !edit.part).length, missing };
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
      if (path.relative(root, path.resolve(dir, p)).startsWith("..")) continue;
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
