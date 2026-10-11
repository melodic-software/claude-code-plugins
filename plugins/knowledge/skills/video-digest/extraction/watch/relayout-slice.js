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
import os from "node:os";
import path from "node:path";

import { isMainModule } from "@melodic/video-digestion/shared/main-module";
import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { listWorkDirFiles } from "../acquisition/acquire.js";
import { runCheckWatchOutcomes } from "../evals/check-watch-outcomes.js";
import { LANES } from "../lib/slice-lanes.js";
import { resolveTempSession } from "../lib/temp-session-paths.js";
import { watchStatePath } from "./watch-state.js";

/** info.json keys the corpus copy drops: format, caption-URL, heatmap and request lists, and the local download paths yt-dlp records. */
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

/**
 * Paths that name files in another repository, never in the slice: a
 * directory (trailing `/`) matches any path under it, a file only exactly.
 */
export const ALLOWED_MISS_PREFIXES = Object.freeze([
  "plugins/",
  "docs/",
  "templates/",
  ".claude/",
  "AGENTS.md",
]);

/**
 * True when `refPath` (fragment already split off) is an allowed miss:
 * under one of the directories, or exactly one of the files, with any
 * leading `./` ignored. `AGENTS.md.old` or `docs-old/x` does not match.
 *
 * @param {string} refPath
 */
function isAllowedMiss(refPath) {
  const plain = refPath.replace(/^(?:\.\/)+/, "");
  return ALLOWED_MISS_PREFIXES.some((entry) =>
    entry.endsWith("/") ? plain.startsWith(entry) : plain === entry,
  );
}

/** Source-lane folders the layout keeps, and where each one goes. */
const SOURCE_FOLDERS = new Map([
  ["companion-digest", "analysis/companion-digest"],
  ["decks", "metadata/decks"],
  ["attachments", "metadata/attachments"],
]);
/** Lane folders the output contract names, present in a slice only when produced. */
const KNOWN_LANE_FOLDERS = new Set([
  ...[...SOURCE_FOLDERS.keys()].map((folder) => `${LANES.source}/${folder}`),
  `${LANES.research}/findings`,
  `${LANES.keyFrames}/frames`,
]);
/** The pipeline's extracted frame names: scene, interval and anchor frames. */
const FRAME_NAME = /^(?:(?:scene|interval)_\d{4}|anchor_\d+_\d{4})\.png$/;
/** Frames scene detection writes and records in `frame-times.json`. */
const TIMED_FRAME = /^(?:scene|interval)_\d{4}\.png$/;
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

/** Markdown files, by extension, in any case. */
const MARKDOWN_FILE = /\.(?:md|markdown)$/i;
const VIDEO_FILE = /\.(?:mp4|mkv|webm)$/;
const FRAME_IMAGE = /\.(?:png|jpe?g)$/i;
/** The slice lane directories, plus the `SLICE/` root alias. */
const SLICE_LANE_NAMES = new Set([...Object.values(LANES), "SLICE"]);
const URL_SCHEME = /^[a-z][a-z0-9+.-]*:/i;
/** Placeholder syntax, not a real path: `<name>`, `${NAME}`, `{name}`, or a glob segment with `*`. */
const PLACEHOLDER = /<[^<>]*>|\$\{[^}]*\}|\{[^{}]*\}|(?:^|\/)[^/]*\*/;
/** `:12`, `:12-20`, `:12,15` and `:12:5` (line and column) suffixes. */
const LINE_SUFFIX = /(?::\d+(?:[-,]\d+)*)+$/;
/** A home path: `~` alone, `~/x` or `~user/x`; `~notes.md` is a relative name. */
const HOME_PATH = /^~(?:[^/]*\/|$)/;
/** ASCII punctuation: the only characters a CommonMark backslash escapes. */
const ESCAPABLE = /[!-/:-@[-`{-~]/;
/**
 * A backslash and the punctuation it escapes, or a lone literal backslash:
 * before anything else, a line ending included, it escapes nothing.
 */
const BACKSLASH = String.raw`\\[!-/:-@[-\x60{-~]|\\(?![!-/:-@[-\x60{-~])`;
/**
 * The `[label]:` opening of a reference-style link definition, with
 * CommonMark's label rules: up to 999 characters, backslash escapes allowed
 * (`[a\]b]`), no unescaped bracket, line endings allowed but not a blank line.
 * The destination may follow one line ending; parseDestination reads it.
 */
const REFERENCE_DEFINITION_LABEL = new RegExp(
  String.raw`^ {0,3}\[((?:${BACKSLASH}|[^[\]\\\r\n]|\r?\n(?![ \t]*\r?\n)){1,999})\]:[ \t]*(?:\r?\n[ \t]*)?`,
  "gm",
);
/** A line ending inside a title, which never spans a blank line (only spaces or tabs). */
const TITLE_LINE_END = String.raw`\r?\n(?![ \t]*\r?\n)`;
/** What may follow a definition's destination: a line ending, or a title then one. */
const DEFINITION_TAIL = new RegExp(
  String.raw`^(?:[ \t]+(?:"(?:${BACKSLASH}|${TITLE_LINE_END}|[^"\\\n])*"|'(?:${BACKSLASH}|${TITLE_LINE_END}|[^'\\\n])*'|\((?:${BACKSLASH}|${TITLE_LINE_END}|[^()\\\n])*\)))?[ \t]*(?:\r?\n|$)`,
);

/**
 * Every reference-style link definition in `text` whose label holds a
 * non-space character (CommonMark rejects an all-whitespace label), its
 * destination read by the same parser as inline links and followed, on its
 * line, by nothing but whitespace and an optional title. A line such as
 * `[note]: source/x.txt is illustrative` is prose, not a definition.
 *
 * @param {string} text
 * @returns {{ from: number, to: number, raw: string, angle: boolean }[]}
 */
function referenceDefinitions(text) {
  const found = [];
  for (const match of text.matchAll(REFERENCE_DEFINITION_LABEL)) {
    if (!/\S/.test(match[1])) continue;
    const from = /** @type {number} */ (match.index) + match[0].length;
    const parsed = parseDestination(text, from);
    if (parsed === null || parsed.raw === "") continue;
    if (!DEFINITION_TAIL.test(text.slice(parsed.end))) continue;
    found.push({ from, to: parsed.end, raw: parsed.raw, angle: parsed.angle });
  }
  return found;
}
/**
 * One attribute of an HTML start tag, read from where the previous one ended:
 * a name, then an optional double-, single- or unquoted value. Sticky, so a
 * `src=` inside another attribute's quoted value is never read as a name.
 */
const HTML_ATTRIBUTE = /[\s/]*([^\s"'>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/dy;
/**
 * A backticked span names a path when it holds a separator or ends in an
 * extension, optionally followed by a `?query`, a `#fragment`, or both.
 */
const PATH_LIKE = /[/\\]|\.[A-Za-z0-9]+(?::\d+(?:[-,]\d+)*)*(?:\?[^#]*)?(?:#.*)?$/;

/** An HTML start tag: `<name` then attributes, quoted values may hold `>`. */
const HTML_START_TAG =
  /<([A-Za-z][A-Za-z0-9-]*)(?:[ \t\r\n]+[A-Za-z_:][A-Za-z0-9_.:-]*(?:[ \t\r\n]*=[ \t\r\n]*(?:[^ \t\r\n"'=<>`]+|'[^']*'|"[^"]*"))?)*[ \t\r\n]*\/?>/g;
/** An HTML comment. */
const HTML_COMMENT = /<!-->|<!--->|<!--[\s\S]*?-->/g;
/** Other raw inline HTML: a closing tag, processing instruction, declaration or CDATA section. */
const HTML_OTHER =
  /<\/[A-Za-z][A-Za-z0-9-]*\s*>|<\?[\s\S]*?\?>|<![A-Za-z][^>]*>|<!\[CDATA\[[\s\S]*?\]\]>/g;
/** A CommonMark URI or email autolink: https://spec.commonmark.org/0.31.2/#autolinks */
const URI_AUTOLINK = /[A-Za-z][A-Za-z0-9+.-]{1,31}:[^\x00-\x20<>]*/.source;
const EMAIL_LABEL = /[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?/.source;
const EMAIL_AUTOLINK = `${/[\w.!#$%&'*+/=?^`{|}~-]+@/.source}${EMAIL_LABEL}(?:\\.${EMAIL_LABEL})*`;
const AUTOLINK = new RegExp(`<(?:${URI_AUTOLINK}|${EMAIL_AUTOLINK})>`, "g");
/**
 * A `<` opening a link or definition destination: after `](` or a definition
 * label's `]:`, plus optional whitespace with at most one line ending.
 */
const DESTINATION_OPENER =
  /(?<=(?:(?<!(?:^|[^\\])(?:\\\\)*\\)\]\(|(?:^|\n) {0,3}\[(?:[^\\[\]]|\\[\s\S])+\]:)[ \t]*(?:\r?\n[ \t]*)?)</y;

/**
 * Offsets (into `text`) of every `src`/`href` value inside an HTML start tag,
 * with the group that matched (2 double-quoted, 3 single-quoted,
 * 4 unquoted). The tag's attributes are read left to right, so only a real
 * attribute counts: not prose such as `set href=../x` outside a tag, not
 * `data-src`, and not `src=` text inside another attribute's value.
 *
 * @param {string} text
 * @returns {{ from: number, to: number, group: number }[]}
 */
function htmlAttributeValues(text) {
  /** @type {{ from: number, to: number, group: number }[]} */
  const values = [];
  for (const tag of text.matchAll(HTML_START_TAG)) {
    const base = /** @type {number} */ (tag.index);
    HTML_ATTRIBUTE.lastIndex = 1 + tag[1].length;
    for (let match; (match = HTML_ATTRIBUTE.exec(tag[0])) !== null; ) {
      if (!/^(?:src|href)$/i.test(match[1])) continue;
      const group = [2, 3, 4].find((at) => match?.[at] !== undefined) ?? 2;
      const span = match.indices?.[group];
      if (!span || span[0] === span[1]) continue;
      values.push({ from: base + span[0], to: base + span[1], group });
    }
  }
  return values;
}

/**
 * The URL an HTML `src`/`href` value names: ASCII tab, LF and CR removed, as
 * the URL parser removes them, so a value wrapped across lines still names its
 * path, then character references decoded.
 * https://url.spec.whatwg.org/#concept-basic-url-parser
 *
 * @param {string} value
 */
function htmlAttributeUrl(value) {
  // The HTML parser decodes references first; the URL parser then trims leading and
  // trailing C0 controls and spaces and drops tab, LF and CR.
  return decodeHtmlReferences(value, { attribute: true })
    .replace(/^[\x00-\x20]+|[\x00-\x20]+$/g, "")
    .replace(/[\t\n\r]/g, "");
}

/**
 * Ranges of `text` holding HTML start tags, comments and autolinks: attribute,
 * comment and autolink text is data, so the link, definition and
 * backticked-path passes skip it (an autolink's `](` is no link); only
 * htmlAttributeValues reads a tag. An angle-bracket link or definition
 * destination such as `<source>` is a destination, not a tag or autolink.
 *
 * @param {string} text
 * @returns {[number, number][]}
 */
function htmlRanges(text) {
  const isDestination = (/** @type {number} */ at) => {
    DESTINATION_OPENER.lastIndex = at;
    return DESTINATION_OPENER.test(text);
  };
  // A `<` after an odd run of backslashes is escaped, so it opens no HTML.
  const escaped = (/** @type {number} */ at) => {
    let run = 0;
    while (text[at - 1 - run] === "\\") run += 1;
    return run % 2 === 1;
  };
  const tags = [...text.matchAll(HTML_START_TAG), ...text.matchAll(AUTOLINK)].filter(
    (tag) => !isDestination(Number(tag.index)),
  );
  return [...text.matchAll(HTML_COMMENT), ...text.matchAll(HTML_OTHER), ...tags]
    .filter((match) => !escaped(Number(match.index)))
    .map((match) => {
      const from = /** @type {number} */ (match.index);
      return /** @type {[number, number]} */ ([from, from + match[0].length]);
    });
}

const HTML_NAMED_REFERENCES = /** @type {Record<string, string>} */ ({
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
});

/**
 * HTML's replacements for numeric references to 0x80-0x9F (windows-1252),
 * indexed from 0x80; a 0 entry keeps the code point.
 * https://html.spec.whatwg.org/multipage/parsing.html#numeric-character-reference-end-state
 */
const WINDOWS_1252 = [
  0x20ac, 0, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021,
  0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017d, 0,
  0, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
  0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0, 0x017e, 0x0178,
];

/**
 * An HTML attribute value with its character references decoded: the named
 * ones a path can hold (`&amp;` `&lt;` `&gt;` `&quot;` `&apos;`) and numeric
 * ones (`&#39;`, `&#x27;`) under HTML's replacements: 0, a surrogate or a
 * value past U+10FFFF is U+FFFD, and 0x80-0x9F map through windows-1252.
 * Anything else stays as written.
 *
 * @param {string} value
 */
function decodeHtmlReferences(value, { attribute = false } = {}) {
  // HTML attributes also accept a numeric reference without its semicolon, and a
  // legacy named one (amp, lt, gt, quot) unless a letter, digit or `=` follows;
  // Markdown accepts neither.
  const pattern = attribute
    ? /&(?:#(\d+);?|#[xX]([0-9A-Fa-f]+);?|([A-Za-z]+);|(amp|lt|gt|quot)(?![A-Za-z0-9=]))/g
    : /&(?:#(\d{1,7})|#[xX]([0-9A-Fa-f]{1,6})|([A-Za-z]+));/g;
  return value.replace(pattern, (match, dec, hex, named, legacy) => {
    const name = named ?? legacy;
    if (dec !== undefined || hex !== undefined) {
      const code = dec !== undefined ? Number(dec) : Number.parseInt(hex, 16);
      const invalid = code === 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff);
      return String.fromCodePoint(invalid ? 0xfffd : WINDOWS_1252[code - 0x80] || code);
    }
    return HTML_NAMED_REFERENCES[name] ?? match;
  });
}

/**
 * A code span's content split for path handling: CommonMark strips one space
 * on each side when both are there (`` ` x ` ``), and a path may sit in
 * quotes. `core` is null when the content cannot be one path. `spaced` marks
 * a candidate holding spaces (`My Slides.pdf`, or a command such as
 * `node run.mjs x.js --no-media`): it counts as a path only when the whole
 * span resolves through the path map, and it is never link-checked.
 *
 * @param {string} content
 * @returns {{ pad: string, quote: string, core: string|null, spaced: boolean }}
 */
function spanPath(content) {
  const pad = /^ .*[^ ].* $/.test(content) ? " " : "";
  let core = pad ? content.slice(1, -1) : content;
  const quoted = /^(["'])(.+)\1$/.exec(core);
  const quote = quoted ? quoted[1] : "";
  if (quoted) core = quoted[2];
  const readsAsPath =
    !core.includes("\n") &&
    (core === "SLICE" || (PATH_LIKE.test(core) && !/^\s|\s$|\s[/\\]|[/\\]\s|\s{2}/.test(core)));
  return { pad, quote, core: readsAsPath ? core : null, spaced: /\s/.test(core) };
}

/**
 * @typedef {Object} CodeSpan
 * @property {number} start - offset of the opening backtick run
 * @property {number} end - offset just past the closing run
 * @property {string} ticks - the backtick run
 * @property {string} content - what sits between the runs
 */

/**
 * Every inline code span in `text`, read as CommonMark does: an unescaped run
 * of backticks closed by the next run of exactly the same length, possibly on
 * a later line of the same paragraph (no blank line between). A run with no
 * such closer is literal backticks.
 *
 * @param {string} text
 * @returns {CodeSpan[]}
 */
export function codeSpans(text) {
  /** @type {CodeSpan[]} */
  const spans = [];
  let at = 0;
  while (at < text.length) {
    const open = text.indexOf("`", at);
    if (open === -1) break;
    let runEnd = open;
    while (text[runEnd] === "`") runEnd += 1;
    const ticks = text.slice(open, runEnd);
    if (isEscaped(text, open)) {
      at = open + 1;
      continue;
    }
    // Three or more backticks opening a line (after any block-quote or list
    // markers) are a fence, not a code span. Fences inside containers are not
    // masked (a known limit), so what they hold stays visible to the check.
    const lineStart = text.lastIndexOf("\n", open - 1) + 1;
    const lead = text.slice(lineStart, open);
    if (ticks.length >= 3 && /^[ \t]*(?:>[ \t]*)*(?:(?:[-*+]|\d+[.)])[ \t]+)?[ \t]*$/.test(lead)) {
      at = runEnd;
      continue;
    }
    let close = -1;
    let scan = runEnd;
    while (scan < text.length) {
      const next = text.indexOf("`", scan);
      if (next === -1) break;
      if (/\n[ \t]*\r?\n/.test(text.slice(runEnd, next))) break;
      let nextEnd = next;
      while (text[nextEnd] === "`") nextEnd += 1;
      if (nextEnd - next === ticks.length) {
        close = next;
        break;
      }
      scan = nextEnd;
    }
    if (close === -1) {
      at = runEnd;
      continue;
    }
    spans.push({
      start: open,
      end: close + ticks.length,
      ticks,
      content: text.slice(runEnd, close),
    });
    at = close + ticks.length;
  }
  return spans;
}

/**
 * True when the character at `at` is backslash-escaped: an odd number of
 * backslashes sits right before it.
 *
 * @param {string} text
 * @param {number} at
 */
function isEscaped(text, at) {
  let count = 0;
  for (let back = at - 1; back >= 0 && text[back] === "\\"; back -= 1) count += 1;
  return count % 2 === 1;
}

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
 * @property {boolean} framesDropped - the layout keeps no extracted frames (`--no-media`)
 * @property {string|null} sliceWorkPath - the slice's `.work/<epic>/<slug>` path under its work root, or null when it sits under none
 * @property {Set<string>} sliceEntries - every slice-relative file and directory
 * @property {string} sliceAbs - absolute slice directory
 * @property {string} targetAbs - absolute final target directory
 */

/** @typedef {{ target: string, isDir: boolean, guessed?: boolean } | { retired: string, note: string } | { outside: string }} Lookup */

/** Stand-ins for a backslash-escaped `#` or `?`, which are part of the path. */
const LITERAL_HASH = "";
const LITERAL_QUERY = "";

/** Stand-in for a backslash-escaped `&`, which starts no character reference. */
const LITERAL_AMP = "";

/**
 * A link or definition destination decoded as CommonMark does: backslash
 * escapes of ASCII punctuation, then character references (`&amp;`,
 * `&#x26;`). An escaped `#` or `?` is literal, not a fragment or query, so it
 * becomes a stand-in that splitReference keeps in the path. `escapedChars`
 * lists the characters the original escaped, to re-escape on rewrite;
 * `references` marks a destination that held a character reference, so a
 * rewrite writes `&` as `&amp;`.
 *
 * @param {string} raw
 * @returns {{ dest: string, escapedChars: string, references: boolean }}
 */
function unescapeDestination(raw) {
  let escapedChars = "";
  const unescaped = raw.replace(/\\([!-/:-@[-`{-~])/g, (_match, char) => {
    if (!escapedChars.includes(char)) escapedChars += char;
    if (char === "#") return LITERAL_HASH;
    if (char === "?") return LITERAL_QUERY;
    if (char === "&") return LITERAL_AMP;
    return char;
  });
  const decoded = decodeHtmlReferences(unescaped);
  return {
    dest: decoded.replaceAll(LITERAL_AMP, "&"),
    escapedChars,
    references: decoded !== unescaped,
  };
}

/** Text a CommonMark destination would decode as a character reference. */
const REFERENCE_START = /^&(?:#\d+|#[xX][0-9A-Fa-f]+|[A-Za-z]+);/;

/**
 * Write `newPath` as a Markdown destination that parses back to exactly
 * `newPath`, in the original's form. A literal `#` or `?` arrives as its
 * stand-in and is written backslash-escaped. Angle form escapes `<`, `>` and
 * `\`, and writes a line ending as a numeric reference; bare form escapes `\`,
 * a leading `<` and every unbalanced parenthesis, and switches to angle form
 * for a space or a control character. Punctuation the original escaped stays
 * escaped; an `&` is written `&amp;` where the original used references, and
 * escaped where it would otherwise start one.
 *
 * @param {string} newPath
 * @param {{ angle: boolean, escapedChars: string, references: boolean }} original
 * @returns {string} the destination as written, angle brackets included
 */
export function encodeDestination(newPath, { angle, escapedChars, references }) {
  const chars = [...newPath];
  const asAngle = angle || chars.some((char) => /[\x00-\x20\x7f]/.test(char));
  /** @type {Set<number>} */
  const unbalanced = new Set();
  if (!asAngle) {
    const open = [];
    chars.forEach((char, at) => {
      if (char === "(") open.push(at);
      else if (char === ")" && open.pop() === undefined) unbalanced.add(at);
    });
    for (const at of open) unbalanced.add(at);
  }
  const written = chars.map((char, at) => {
    if (char === LITERAL_HASH) return "\\#";
    if (char === LITERAL_QUERY) return "\\?";
    if (char === "&") {
      if (references) return "&amp;";
      const startsReference = REFERENCE_START.test(chars.slice(at).join(""));
      return escapedChars.includes("&") || startsReference ? "\\&" : "&";
    }
    if (asAngle && (char === "\n" || char === "\r")) return `&#${char.charCodeAt(0)};`;
    const structural =
      char === "\\" ||
      (asAngle ? char === "<" || char === ">" : unbalanced.has(at) || (at === 0 && char === "<"));
    // A raw `#` or `?` is a fragment or query; only its stand-in was escaped.
    const kept = escapedChars.includes(char) && char !== "#" && char !== "?";
    return structural || kept ? `\\${char}` : char;
  });
  return asAngle ? `<${written.join("")}>` : written.join("");
}

/** @param {string} value */
function literalText(value) {
  return value.replaceAll(LITERAL_HASH, "#").replaceAll(LITERAL_QUERY, "?");
}

/**
 * Split a reference into its path and the suffix to carry over unchanged
 * (`#anchor`, `?query`, `:line`). With `fragments: false`, a raw `#` or `?`
 * stays part of the path (a file named `notes#1.md`); with `lines: false`, so
 * does a `:12` or `:12:5` ending (a file named `slide.pdf:12`).
 *
 * @param {string} ref
 * @param {{ fragments?: boolean, lines?: boolean }} [options]
 * @returns {{ refPath: string, suffix: string, encoded: boolean }}
 */
function splitReference(ref, { fragments = true, lines = true } = {}) {
  const hash = fragments ? ref.search(/[#?]/) : -1;
  let refPath = hash === -1 ? ref : ref.slice(0, hash);
  let suffix = hash === -1 ? "" : ref.slice(hash);
  const line = lines ? LINE_SUFFIX.exec(refPath) : null;
  if (line) {
    suffix = line[0] + suffix;
    refPath = refPath.slice(0, line.index);
  }
  // Compare paths the way the filesystem sees them: Windows separators as
  // `/`, then each segment percent-decoded (`%23` is `#`, `%3F` is `?`). A
  // malformed escape, or one decoding to a separator, stays as written. A
  // rewrite re-encodes each segment when the original was encoded.
  if (!URL_SCHEME.test(refPath)) refPath = refPath.replace(/\\/g, "/");
  let encoded = false;
  if (refPath.includes("%")) {
    const decoded = refPath
      .split("/")
      .map((segment) => {
        try {
          const plain = decodeURIComponent(segment);
          return /[/\\]/.test(plain) ? segment : plain;
        } catch {
          return segment;
        }
      })
      .join("/");
    encoded = decoded !== refPath;
    refPath = decoded;
  }
  return { refPath: literalText(refPath), suffix: literalText(suffix), encoded };
}

/**
 * A reference to the slice directory itself: the slice has no single new
 * location, so name where its kept files went, as for any split directory.
 *
 * @param {PathMap} map
 * @returns {Lookup}
 */
function sliceRootLookup(map) {
  const splitInto = [
    ...new Set([...map.files.values()].map((to) => `${to.split("/")[0]}/`)),
  ].sort();
  return {
    retired: path.basename(map.sliceAbs),
    note: splitInto.length > 0 ? `split across ${splitInto.join(", ")} in this copy` : NOT_RETAINED,
  };
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
  if (!bare || URL_SCHEME.test(bare) || bare.startsWith("/")) {
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
  // `SLICE/<path>` names the slice root explicitly, and so does the work-root
  // form `.work/<epic>/<slug>/<path>`, but only with this slice's own prefix:
  // a path segment that merely equals the slice's name says nothing. The bare
  // aliases (`SLICE`, `SLICE/`, `.work/<epic>/<slug>/`) name the root itself.
  if (bare === "SLICE" || (map.sliceWorkPath !== null && bare === map.sliceWorkPath)) {
    return sliceRootLookup(map);
  }
  if (bare.startsWith("SLICE/")) {
    keys = [path.posix.normalize(bare.slice("SLICE/".length))];
  } else if (map.sliceWorkPath && bare.startsWith(`${map.sliceWorkPath}/`)) {
    keys = [path.posix.normalize(bare.slice(map.sliceWorkPath.length + 1))];
  } else {
    const fromFile = path.posix.normalize(path.posix.join(path.posix.dirname(sourceFile), bare));
    if (fromFile === ".." || fromFile.startsWith("../")) {
      // Resolved from the naming file's real location: a path that comes back
      // into the slice (`../<slug>/x` from the root) is the slice's; any other
      // (a sibling slice, the repo) keeps pointing at the same place from the
      // file's new, deeper location.
      const absolute = path.resolve(map.sliceAbs, ...fromFile.split("/"));
      const inside = path.relative(map.sliceAbs, absolute);
      if (inside === "") return sliceRootLookup(map);
      if (!isSameOrInside(absolute, map.sliceAbs)) return { outside: absolute };
      keys = [inside.split(path.sep).join("/")];
    } else {
      keys = [fromFile, bare.startsWith(".") ? null : path.posix.normalize(bare)];
    }
  }
  if (keys[0] === ".") return sliceRootLookup(map);
  for (const key of keys) {
    const found = lookup(key);
    if (found) return found;
  }
  const retired = keys.find((key) => key !== null && map.sliceEntries.has(key));
  if (retired) {
    // A directory whose kept files went to several places (`source/`) has no
    // single new location: name where they went instead.
    const splitInto = [
      ...new Set(
        [...map.files]
          .filter(([from]) => from.startsWith(`${retired}/`))
          .map(([, to]) => `${to.split("/")[0]}/`),
      ),
    ].sort();
    return {
      retired,
      note:
        splitInto.length > 0 ? `split across ${splitInto.join(", ")} in this copy` : NOT_RETAINED,
    };
  }
  // A placeholder (`<slice-dir>/x`, `${ROOT}/x`, `{tmp}/x`, `research/*.md`)
  // names no real file. It counts as one only now, after neither the path map
  // nor the slice's own entries named it, so a real `report-{draft}.pdf` is
  // still mapped or retired.
  if (PLACEHOLDER.test(bare)) return null;
  // A lane folder the layout knows but this slice never produced (prose such
  // as "no deck in `source/decks/`") names nothing to point at.
  // A path below such a folder (`source/decks/slides.pdf`) names nothing either.
  const absentFolder = keys.find(
    (key) =>
      key !== null &&
      [...KNOWN_LANE_FOLDERS].some(
        (folder) =>
          (key === folder || key.startsWith(`${folder}/`)) && !map.sliceEntries.has(folder),
      ),
  );
  if (absentFolder) return { retired: absentFolder, note: "none in this slice" };
  // An unknown file in a copied directory moves with the directory, so the
  // link check flags it at its new location.
  for (const key of bare.includes("/") ? keys : []) {
    const dir = key === null ? undefined : map.dirs.get(path.posix.dirname(key));
    if (dir !== undefined && key !== null) {
      return { target: `${dir}/${path.posix.basename(key)}`, isDir: false, guessed: true };
    }
  }
  if (bare.includes("/")) return null;
  const frame = map.tempFrames.get(bare);
  if (frame) return { target: frame, isDir: false };
  // Without the temp frames (`--no-media`) a frame name names nothing kept.
  return map.framesDropped && FRAME_NAME.test(bare) ? { retired: bare, note: NOT_RETAINED } : null;
}

const NOT_RETAINED = "not retained in this copy";

/**
 * How a code span is read, in order: the whole name, a raw `#` or `?` and a
 * `:12` ending included (`notes#1.md`, `slide.pdf:12`), then without its line
 * suffix, and only then with the rest read as a fragment. A code span names a
 * file literally.
 */
const WHOLE_NAME_FIRST = [{ fragments: false, lines: false }, { fragments: false }, {}];

/**
 * How a link destination (Markdown or HTML) is read: a raw `#` or `?` always
 * starts its fragment or query (an escaped `\#` or `%23` is a name
 * character), and the name is tried with its `:12` ending, then without it.
 */
const LINK_READINGS = [{ lines: false }, {}];

/**
 * What a reference names under the first of `readings` that names anything
 * (an earlier reading must name it exactly, not as a guess into a copied
 * directory), and that reading's split options (the last when none does).
 *
 * @param {string} ref
 * @param {string} sourceFile
 * @param {PathMap} map
 * @param {{ fragments?: boolean, lines?: boolean }[]} [readings]
 * @returns {{ found: Lookup|null, split: { fragments?: boolean, lines?: boolean } }}
 */
function findReference(ref, sourceFile, map, readings = LINK_READINGS) {
  for (const split of readings) {
    const found = lookUpReference(splitReference(ref, split).refPath, sourceFile, map);
    if (found && !("guessed" in found && split !== readings.at(-1))) {
      return { found, split };
    }
  }
  return { found: null, split: {} };
}

/**
 * @typedef {Object} InlineLink
 * @property {string} dest - the destination, angle brackets removed and backslash escapes decoded
 *   (an escaped `#` or `?` as a literal stand-in, see unescapeDestination)
 * @property {number} destStart - offset of the destination as written (its `<` when angled)
 * @property {number} destEnd - offset just past it
 * @property {boolean} angle - written as `<...>`
 * @property {string} escapedChars - the punctuation the destination backslash-escaped
 * @property {boolean} references - the destination held a character reference (`&amp;`)
 * @property {string} label - the link text, `!` and brackets removed
 * @property {number} labelStart - offset of the link's `[` (or its `!`), -1 when unmatched
 * @property {number} labelEnd - offset of the `]` that closes the link text
 * @property {number} linkStart - offset where the whole link starts
 * @property {number} linkEnd - offset just past the link's closing `)`
 */

/**
 * The offset past spaces and tabs at `at`, including at most one line ending
 * (CommonMark allows one between a link's destination and its title).
 *
 * @param {string} text
 * @param {number} at
 */
function skipLinkSpace(text, at) {
  let next = at;
  while (text[next] === " " || text[next] === "\t") next += 1;
  if (text[next] === "\r" && text[next + 1] === "\n") next += 2;
  else if (text[next] === "\n" || text[next] === "\r") next += 1;
  while (text[next] === " " || text[next] === "\t") next += 1;
  return next;
}

/**
 * The link destination starting at `at`, read as CommonMark does for both
 * inline links and reference definitions: `<...>` up to the first unescaped
 * `>` (an unescaped `<` or a line ending makes it no destination), or a bare
 * run with balanced parentheses up to whitespace or an unbalanced `)`, where
 * a backslash escapes any ASCII punctuation. `raw` is the destination as
 * written, without the angle brackets.
 *
 * @param {string} text
 * @param {number} at
 * @returns {{ raw: string, angle: boolean, end: number }|null}
 */
export function parseDestination(text, at) {
  if (text[at] === "<") {
    for (let scan = at + 1; scan < text.length; scan += 1) {
      const char = text[scan];
      if (char === "\\" && ESCAPABLE.test(text[scan + 1] ?? "")) {
        scan += 1;
        continue;
      }
      if (char === "\n" || char === "\r" || char === "<") return null;
      if (char === ">") return { raw: text.slice(at + 1, scan), angle: true, end: scan + 1 };
    }
    return null;
  }
  let end = at;
  let depth = 0;
  while (end < text.length) {
    const char = text[end];
    if (char === "\\" && ESCAPABLE.test(text[end + 1] ?? "")) {
      end += 2;
      continue;
    }
    // CommonMark ends a bare destination only at the ASCII space or an ASCII control.
    if (/[\x00-\x20\x7f]/.test(char)) break;
    if (char === "(") depth += 1;
    else if (char === ")") {
      if (depth === 0) break;
      depth -= 1;
    }
    end += 1;
  }
  if (end === at || depth !== 0) return null;
  return { raw: text.slice(at, end), angle: false, end };
}

/**
 * Every inline link in `text`, scanned the way CommonMark reads a
 * destination: `<...>`, or a run with balanced or backslash-escaped
 * parentheses up to whitespace or the unbalanced `)`. A regex stops at the
 * first `)`, which breaks `slides_(final).pdf`.
 *
 * @param {string} text
 * @returns {InlineLink[]}
 */
export function inlineLinks(text) {
  /** @type {InlineLink[]} */
  const links = [];
  let from = 0;
  for (;;) {
    const open = text.indexOf("](", from);
    // Links cannot contain links: one whose label holds another (non-image)
    // link is literal text. An image in the label leaves it a link.
    if (open === -1) {
      const isLink = (/** @type {InlineLink} */ link) => text[link.linkStart] !== "!";
      return links.filter(
        (outer) =>
          !isLink(outer) ||
          !links.some(
            (inner) =>
              isLink(inner) && inner.linkStart > outer.linkStart && inner.linkEnd <= outer.labelEnd,
          ),
      );
    }
    from = open + 2;
    let at = open + 2;
    at = skipLinkSpace(text, at);
    const destStart = at;
    const parsed = parseDestination(text, at);
    if (parsed === null) continue;
    const { raw, angle } = parsed;
    at = parsed.end;
    const destEnd = at;
    // An optional title, then the closing `)`.
    // Spaces with at most one line ending may separate the parts (CommonMark).
    at = skipLinkSpace(text, at);
    // A title is "...", '...' or (...), set off from the destination by space.
    const quote = text[at];
    if (at > destEnd && (quote === '"' || quote === "'" || quote === "(")) {
      // The closing delimiter, skipping backslash-escaped characters.
      const closer = quote === "(" ? ")" : quote;
      let closeQuote = -1;
      for (let scan = at + 1; scan < text.length; scan += 1) {
        if (text[scan] === "\\" && ESCAPABLE.test(text[scan + 1] ?? "")) {
          scan += 1;
          continue;
        }
        if (text[scan] === closer) {
          closeQuote = scan;
          break;
        }
        // A (...) title holds no unescaped `(`; with one, this is no link.
        if (quote === "(" && text[scan] === "(") break;
        // A title never spans a blank line (one holding only spaces or tabs).
        if (text[scan] === "\n" && /^[ \t]*\r?\n/.test(text.slice(scan + 1))) break;
      }
      if (closeQuote === -1) continue;
      at = closeQuote + 1;
      at = skipLinkSpace(text, at);
    }
    if (text[at] !== ")") continue;
    const linkEnd = at + 1;
    // The `[` that opens this link's text, matching nested brackets. An
    // escaped `]`, or no unescaped opening `[` (`\[watch](...)`), means this
    // is not a link.
    if (isEscaped(text, open)) continue;
    let labelStart = -1;
    let depth = 0;
    for (let back = open - 1; back >= 0; back -= 1) {
      // Link text never crosses a blank line (one holding only spaces counts).
      if (
        text[back] === "\n" &&
        /^[ \t\r]*$/.test(text.slice(text.lastIndexOf("\n", back - 1) + 1, back))
      ) {
        break;
      }
      // An escaped bracket is literal text and takes no part in nesting.
      if ((text[back] === "[" || text[back] === "]") && isEscaped(text, back)) continue;
      if (text[back] === "]") depth += 1;
      else if (text[back] === "[") {
        if (depth === 0) {
          labelStart = back;
          break;
        }
        depth -= 1;
      }
    }
    if (labelStart === -1) continue;
    const label = labelStart === -1 ? "" : text.slice(labelStart + 1, open);
    // A `!` right before the label marks an image, unless it is escaped (`\![x](dest)`).
    const image =
      labelStart > 0 && text[labelStart - 1] === "!" && !isEscaped(text, labelStart - 1);
    const linkStart = image ? labelStart - 1 : labelStart;
    links.push({
      ...unescapeDestination(raw),
      destStart,
      destEnd,
      angle,
      label,
      labelStart: linkStart,
      labelEnd: open,
      linkStart,
      linkEnd,
    });
    from = linkEnd;
  }
}

/**
 * Rewrite every markdown link and backticked path in `text` that names a
 * slice path: a copied one relative to the file's target location, one the
 * layout does not keep as plain text naming it as not retained.
 *
 * @param {string} text
 * @param {string} sourceFile - slice-relative path of the file
 * @param {string} targetFile - target-relative path the file is copied to
 * @param {PathMap} map
 * @returns {{ text: string, rewrites: number, spacedRefs: string[], retiredRefs: string[] }} -
 *   `spacedRefs`, the rewritten code spans holding spaces, for the link check to verify;
 *   `retiredRefs`, the references left unchanged because they name a slice path the
 *   layout drops, which the link check must flag whatever their name looks like
 */
export function rewriteSliceReferences(text, sourceFile, targetFile, map) {
  let rewrites = 0;
  /** @type {string[]} */
  const spacedRefs = [];
  /** @type {string[]} */
  const retiredRefs = [];
  const rewrite = (
    /** @type {string} */ ref,
    /** @type {{ fragments?: boolean, lines?: boolean }} */ split = {},
    escapedChars = "",
  ) => {
    const { refPath, suffix, encoded } = splitReference(ref, split);
    const found = lookUpReference(refPath, sourceFile, map);
    if (!found || "retired" in found) return ref;
    let relative;
    let trailing = "";
    if ("outside" in found) {
      const fileDir = path.dirname(path.join(map.targetAbs, targetFile));
      relative = path.relative(fileDir, found.outside).split(path.sep).join("/");
      trailing = refPath.endsWith("/") ? "/" : "";
    } else {
      relative = path.posix.relative(path.posix.dirname(targetFile), found.target) || ".";
      trailing = found.isDir && refPath.endsWith("/") ? "/" : "";
    }
    let written = encoded ? relative.split("/").map(encodeURIComponent).join("/") : relative;
    // A `#` or `?` the original escaped stays a literal path character:
    // its stand-in, which encodeDestination writes escaped.
    if (escapedChars.includes("#")) written = written.replaceAll("#", LITERAL_HASH);
    if (escapedChars.includes("?")) written = written.replaceAll("?", LITERAL_QUERY);
    const next = `${written}${trailing}${suffix}`;
    if (next === ref) return ref;
    rewrites += 1;
    return next;
  };
  const { fenceMasked, linkMasked, tagText } = maskCode(text);
  // Every pass records edits by offset into the original text; the scans run
  // over masked copies, so nothing inside a fenced code block, an HTML tag or
  // an HTML comment is touched and no link syntax inside an inline code span
  // is read as a link. Inline code spans themselves are read for paths (the
  // backticked-path rewrite); tags only for their src/href values.
  /** @type {{ from: number, to: number, text: string }[]} */
  const edits = [];
  // Inline links: a link naming a file the layout drops keeps its label in
  // place and loses only its syntax: the opening `[` (or `![`) goes and
  // `](dest)` becomes the note, so an image nested in the label keeps its
  // own rewrite. Any other destination takes the path rewrite.
  for (const link of inlineLinks(linkMasked)) {
    const { found, split } = findReference(link.dest, sourceFile, map);
    if (found && "retired" in found && link.labelStart !== -1) {
      rewrites += 1;
      const bracket = text[link.linkStart] === "!" ? link.linkStart + 2 : link.linkStart + 1;
      edits.push({ from: link.linkStart, to: bracket, text: "" });
      edits.push({
        from: link.labelEnd,
        to: link.linkEnd,
        text: ` (${found.retired}, ${found.note})`,
      });
      continue;
    }
    if (found && "retired" in found) retiredRefs.push(link.dest);
    const next = rewrite(link.dest, split, link.escapedChars);
    if (next === link.dest) continue;
    edits.push({ from: link.destStart, to: link.destEnd, text: encodeDestination(next, link) });
  }
  // Reference-style definitions and HTML src/href values take the same path
  // rewrite. One naming a file the layout drops is left for the link check to
  // flag: a definition or attribute has no prose to rewrite into.
  for (const { from, to, angle } of referenceDefinitions(linkMasked)) {
    const raw = text.slice(angle ? from + 1 : from, angle ? to - 1 : to);
    const original = { ...unescapeDestination(raw), angle };
    const { dest } = original;
    const { found, split } = findReference(dest, sourceFile, map);
    if (found && "retired" in found) retiredRefs.push(dest);
    const rewritten = rewrite(dest, split, original.escapedChars);
    if (rewritten === dest) continue;
    edits.push({ from, to, text: encodeDestination(rewritten, original) });
  }
  for (const { from, to, group } of htmlAttributeValues(tagText)) {
    // An attribute value may hold character references (`&amp;`): map the
    // decoded path, then escape the new value for its quoting: `&` always,
    // the enclosing quote character, and an unquoted value that now needs
    // quotes gets double quotes.
    const value = text.slice(from, to);
    const decoded = htmlAttributeUrl(value);
    const { found, split } = findReference(decoded, sourceFile, map);
    if (found && "retired" in found) retiredRefs.push(decoded);
    const next = rewrite(decoded, split);
    if (next === decoded) continue;
    let escaped = next.replaceAll("&", "&amp;");
    if (group === 2) escaped = escaped.replaceAll('"', "&quot;");
    else if (group === 3) escaped = escaped.replaceAll("'", "&#39;");
    else if (/[\s"'=<>`]/.test(escaped)) escaped = `"${escaped.replaceAll('"', "&quot;")}"`;
    edits.push({ from, to, text: escaped });
  }
  for (const span of codeSpans(fenceMasked)) {
    const from = span.start;
    const whole = text.slice(span.start, span.end);
    const { ticks, content } = span;
    const { pad, quote, core, spaced } = spanPath(content);
    if (core === null) continue;
    const { found, split } = findReference(core, sourceFile, map, WHOLE_NAME_FIRST);
    // A span with spaces is a path only when it resolves as one whole path.
    if (spaced && !found) continue;
    let next;
    if (found && "retired" in found) {
      rewrites += 1;
      next = `${found.retired} (${found.note})`;
    } else {
      const rewritten = rewrite(core, split);
      next = `${ticks}${pad}${quote}${rewritten}${quote}${pad}${ticks}`;
      // The link check skips spans with spaces (they may be commands), so a
      // spaced path this rewrite placed is handed to it explicitly.
      if (spaced) spacedRefs.push(rewritten);
    }
    if (next !== whole) edits.push({ from, to: from + whole.length, text: next });
  }
  edits.sort((a, b) => a.from - b.from);
  /** @type {typeof edits} */
  const kept = [];
  for (const edit of edits) {
    if (kept.length === 0 || edit.from >= kept[kept.length - 1].to) kept.push(edit);
  }
  let rewritten = text;
  for (const edit of kept.reverse()) {
    rewritten = rewritten.slice(0, edit.from) + edit.text + rewritten.slice(edit.to);
  }
  return { text: rewritten, rewrites, spacedRefs, retiredRefs };
}

/**
 * Copies of `text` with code and HTML masked by spaces (line endings kept, so
 * every offset still matches the original). All three blank top-level fenced
 * code blocks (``` or ~~~ opening at column 0; an unclosed fence runs to the
 * end). `fenceMasked` also blanks HTML start tags and comments, whose text is
 * data; `linkMasked` blanks those and inline code spans; `tagText` blanks
 * inline code spans and HTML comments, keeping start tags for the src/href
 * pass. Fences that are indented or inside a block quote or list item, and
 * indented code blocks, are not masked: telling them apart needs container
 * parsing. What they hold is read as ordinary text, so the link check still
 * sees a dangling path.
 *
 * @param {string} text
 * @returns {{ fenceMasked: string, linkMasked: string, tagText: string }}
 */
export function maskCode(text) {
  const blank = (/** @type {string} */ source, /** @type {[number, number][]} */ ranges) => {
    let out = source;
    for (const [from, to] of ranges) {
      out = out.slice(0, from) + out.slice(from, to).replace(/[^\n]/g, " ") + out.slice(to);
    }
    return out;
  };
  /** @type {[number, number][]} */
  const fences = [];
  let offset = 0;
  /** @type {{ char: string, length: number, start: number }|null} */
  let open = null;
  for (const line of text.split(/(?<=\n)/)) {
    const body = line.replace(/\r?\n$/, "");
    if (open === null) {
      const opening = /^(`{3,}|~{3,})(.*)$/.exec(body);
      if (opening && !(opening[1][0] === "`" && opening[2].includes("`"))) {
        open = { char: opening[1][0], length: opening[1].length, start: offset };
      }
    } else {
      const closing = /^ {0,3}(`{3,}|~{3,})[ \t]*$/.exec(body);
      if (closing && closing[1][0] === open.char && closing[1].length >= open.length) {
        fences.push([open.start, offset + line.length]);
        open = null;
      }
    }
    offset += line.length;
  }
  if (open !== null) fences.push([open.start, text.length]);
  const fenceMasked = blank(text, fences);
  /** @type {[number, number][]} */
  const spans = codeSpans(fenceMasked).map((span) => [span.start, span.end]);
  const codeMasked = blank(fenceMasked, spans);
  const html = htmlRanges(codeMasked);
  return {
    fenceMasked: blank(fenceMasked, html),
    linkMasked: blank(codeMasked, html),
    tagText: codeMasked
      .replace(HTML_COMMENT, (comment) => comment.replace(/[^\n]/g, " "))
      .replace(HTML_OTHER, (raw) => raw.replace(/[^\n]/g, " ")),
  };
}

/**
 * True when a backticked span reads as a path into the slice: `SLICE/`, an
 * explicit `./` or `../` path, or one whose first segment is a top-level
 * entry of the re-laid-out slice or an entry beside the naming file. Any
 * other path is one the path map did not know under no slice directory, a
 * path into another repository. A bare name reads as a slice path only when
 * it is an extracted frame's name, which the rewrite turns into a path or
 * not-retained text.
 *
 * @param {string} refPath
 * @param {string} fileDir - absolute directory of the naming file
 * @param {Set<string>} topLevel - top-level entries of the re-laid-out slice
 * @param {Set<string>} [sliceDirs] - posix directories of the source slice
 */
function looksSliceInternal(refPath, fileDir, topLevel, sliceDirs) {
  if (!refPath.includes("/")) return FRAME_NAME.test(refPath);
  if (/^(?:\.\.?|SLICE)\//.test(refPath)) return true;
  const first = refPath.split("/")[0];
  // A path under an original slice lane name (`source/missing.txt`) is the
  // slice's when its parent directory existed in the slice, so a path into
  // another repository that shares a lane name (`research/deepening/x.md`)
  // stays external even beside `analysis/research/`. Without the slice's
  // directories, any lane name counts.
  if (SLICE_LANE_NAMES.has(first)) {
    return (
      sliceDirs === undefined || sliceDirs.has(path.posix.dirname(refPath.replace(/\/+$/, "")))
    );
  }
  return topLevel.has(first) || fs.existsSync(path.join(fileDir, first));
}

/**
 * Link check over a re-laid-out slice: every markdown link and every
 * backticked slice path in its markdown must resolve against the naming
 * file's directory. URLs, placeholders, absolute paths, paths that leave the
 * slice (another repository) and the allowed-miss prefixes are skipped.
 *
 * @param {string} rootDir
 * @param {{
 *   sliceDirs?: Set<string>,
 *   spacedRefs?: Map<string, string[]>,
 *   retiredRefs?: Map<string, string[]>,
 * }} [options]
 *   `sliceDirs`, the source slice's directories, narrows which lane-named paths
 *   count as the slice's;
 *   `spacedRefs` maps a target-relative file to the spaced code-span paths a
 *   rewrite placed in it, which are checked like links;
 *   `retiredRefs` maps a target-relative file to the references a rewrite left
 *   naming a dropped slice file, always flagged
 * @returns {{ file: string, ref: string }[]} unresolved references
 */
export function checkLayoutLinks(
  rootDir,
  { sliceDirs, spacedRefs = new Map(), retiredRefs = new Map() } = {},
) {
  const root = path.resolve(rootDir);
  const topLevel = new Set(fs.existsSync(root) ? fs.readdirSync(root) : []);
  /** @type {{ file: string, ref: string }[]} */
  const unresolved = [];
  const markdown = listFiles(root).filter(
    (file) =>
      MARKDOWN_FILE.test(file) && !file.startsWith("frames/all/") && !file.startsWith("media/"),
  );
  for (const file of markdown) {
    const fileDir = path.dirname(path.join(root, file));
    const text = fs.readFileSync(path.join(root, file), "utf8");
    const retired = new Set(retiredRefs.get(file));
    const check = (
      /** @type {string} */ ref,
      /** @type {boolean} */ isLink,
      /** @type {boolean} */ knownPath = isLink,
    ) => {
      // A reference the rewrite found naming a dropped slice file dangles, whatever
      // its text looks like (an allowed miss, a placeholder).
      if (retired.has(ref)) {
        unresolved.push({ file, ref: literalText(ref) });
        return;
      }
      // A code span may hold a raw `#` or `?` in its name, and any reference a
      // `:12` ending: read as WHOLE_NAME_FIRST or LINK_READINGS orders it, the
      // first reading that resolves passes; the last one is checked below.
      for (const option of (isLink ? LINK_READINGS : WHOLE_NAME_FIRST).slice(0, -1)) {
        const whole = splitReference(ref, option).refPath;
        if (whole && fs.existsSync(path.resolve(fileDir, whole))) return;
      }
      const { refPath } = splitReference(ref);
      if (!refPath || URL_SCHEME.test(refPath)) return;
      if (refPath.startsWith("/") || HOME_PATH.test(refPath)) return;
      if (isAllowedMiss(refPath)) return;
      if (!knownPath && !looksSliceInternal(refPath, fileDir, topLevel, sliceDirs)) return;
      const resolved = path.resolve(fileDir, refPath);
      if (!isSameOrInside(resolved, root)) return;
      if (fs.existsSync(resolved)) return;
      // A placeholder that names no real file is not a dangling path.
      if (PLACEHOLDER.test(refPath)) return;
      unresolved.push({ file, ref: literalText(ref) });
    };
    const { fenceMasked, linkMasked, tagText } = maskCode(text);
    for (const link of inlineLinks(linkMasked)) check(link.dest, true);
    // A definition is unambiguous link syntax, so every relative destination is
    // checked, an extensionless one (`[guide]: README`) included.
    for (const { raw } of referenceDefinitions(linkMasked)) {
      check(unescapeDestination(raw).dest, true);
    }
    for (const { from, to } of htmlAttributeValues(tagText)) {
      check(htmlAttributeUrl(text.slice(from, to)), true);
    }
    for (const span of codeSpans(fenceMasked)) {
      // A span with spaces may be a command (`node run.mjs x.js --flag`): only
      // single-token spans are link-checked.
      const { core, spaced } = spanPath(span.content);
      if (core !== null && !spaced) check(core, false);
    }
    // Spaced spans a rewrite placed (see rewriteSliceReferences) are known to
    // be paths: checked by the backticked-path rules, whole span first.
    for (const ref of spacedRefs.get(file) ?? []) check(ref, false, true);
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
 * Plain text for a Markdown line: one line, with every Markdown-significant character
 * backslash-escaped, so an upstream title never renders (or is link-checked) as syntax.
 * @param {string} text
 */
export function markdownText(text) {
  return text.replace(/\s+/g, " ").trim().replace(/[\\`*_{}[\]()<>#+\-.!|~&]/g, "\\$&");
}

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
    `# ${markdownText(title)}`,
    "",
    "## Provenance",
    "",
    `- Canonical origin: <${sourceUrl.replace(/[\s<>]/g, encodeURIComponent)}>`,
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
 * The JSON object in `file`, or null when it cannot be read, does not parse,
 * or parses to anything but a plain object (null, an array, a scalar).
 *
 * @param {string} file
 * @returns {Record<string, unknown>|null}
 */
function readJsonObject(file) {
  /** @type {unknown} */
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
  return parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)
    ? /** @type {Record<string, unknown>} */ (parsed)
    : null;
}

/**
 * The slice's path under its work root, from the last `.work` segment of its
 * absolute path (`.work/<epic>/<slug>`), or null when no `.work` segment holds it.
 *
 * @param {string} slice - absolute slice directory
 * @returns {string|null}
 */
function workRootRelative(slice) {
  const segments = slice.split(path.sep);
  const at = segments.lastIndexOf(".work");
  return at === -1 || at === segments.length - 1 ? null : segments.slice(at).join("/");
}

/** @param {unknown} error */
function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

/** A video id as yt-dlp's `%(id)s` writes it: no separator, no `..`. */
const VIDEO_ID = /^[A-Za-z0-9_-]+$/;

/**
 * What is wrong with a parsed watch.json's shape for this script, or null.
 * `videoId` names `media/<id>.<ext>`, so it must not hold a path; the title
 * and source URL fill the provenance README; the temp session dirs are paths.
 *
 * @param {unknown} state
 * @returns {string|null}
 */
function watchStateShapeProblem(state) {
  if (!state || typeof state !== "object" || Array.isArray(state)) return "is not a JSON object";
  const record = /** @type {Record<string, unknown>} */ (state);
  if (typeof record.videoId !== "string" || !VIDEO_ID.test(record.videoId)) {
    return `videoId ${JSON.stringify(record.videoId)} is not a plain video id`;
  }
  for (const field of ["title", "sourceUrl"]) {
    if (typeof record[field] !== "string" || record[field] === "") {
      return `has no ${field} string`;
    }
  }
  const temp = record.tempSession;
  if (temp === undefined || temp === null) return null;
  if (typeof temp !== "object" || Array.isArray(temp)) return "tempSession is not an object";
  const session = /** @type {Record<string, unknown>} */ (temp);
  for (const field of ["workDir", "framesDir", "contactSheetsDir", "acquiredAt"]) {
    if (session[field] !== undefined && typeof session[field] !== "string") {
      return `tempSession.${field} is not a string`;
    }
  }
  return null;
}

/**
 * What the frames dir lacks for a complete `frames/all/`: `frame-times.json`
 * (an object keyed by frame file), at least one frame image, and every frame
 * the sidecar lists. Empty when nothing is missing.
 *
 * @param {string|undefined} framesDir
 * @returns {string[]}
 */
function missingFrames(framesDir) {
  if (!framesDir) return ["the frames (no tempSession.framesDir)"];
  if (!readableDirectory(framesDir)) {
    return [`the frames (${framesDir} is not a readable directory)`];
  }
  const names = new Set(fs.readdirSync(framesDir));
  const missing = [];
  // A frame image or the sidecar must be a regular file, not just a name.
  const notFiles = [...names].filter(
    (name) =>
      (FRAME_IMAGE.test(name) || name === "frame-times.json") &&
      !isRegularFile(path.join(framesDir, name)),
  );
  if (notFiles.length > 0) {
    missing.push(`regular files for the frames entries ${notFiles.sort().join(", ")}`);
  }
  /** @type {unknown} */
  let times = null;
  let readable = true;
  try {
    times = JSON.parse(fs.readFileSync(path.join(framesDir, "frame-times.json"), "utf8"));
  } catch {
    readable = false;
    missing.push(`a readable frame-times.json (${framesDir})`);
  }
  // Scene detection writes an object keyed by frame file; null, an array or
  // a scalar is not one, and `Object.keys` would read it as an empty listing.
  const isTimesObject = times !== null && typeof times === "object" && !Array.isArray(times);
  if (readable && !isTimesObject) {
    missing.push(`a frame-times.json holding a JSON object (${framesDir})`);
  }
  const emptyImages = [...names].filter(
    (name) => FRAME_IMAGE.test(name) && sizeOf(path.join(framesDir, name)) === 0,
  );
  if (emptyImages.length > 0)
    missing.push(`non-empty frames (empty: ${emptyImages.sort().join(", ")})`);
  if (![...names].some((name) => FRAME_IMAGE.test(name))) {
    missing.push(`any frame image (${framesDir})`);
  }
  if (isTimesObject) {
    const listing = /** @type {Record<string, unknown>} */ (times);
    const listed = Object.keys(listing);
    // Scene detection's writeFrameTimes writes each record as
    // { timestampSec, timestampSource, timestampMethod, timestampErrorSec },
    // with timestampSec a number, or null for an untimed frame.
    const malformed = listed.filter((name) => {
      const record = listing[name];
      if (!record || typeof record !== "object" || Array.isArray(record)) return true;
      const seconds = /** @type {Record<string, unknown>} */ (record).timestampSec;
      return !(seconds === null || (typeof seconds === "number" && Number.isFinite(seconds)));
    });
    if (malformed.length > 0) {
      missing.push(
        `frame-times.json records with an object and a finite or null timestampSec ` +
          `(malformed: ${malformed.sort().join(", ")})`,
      );
    }
    // Every key, whatever its extension, must name a regular file in the
    // frames dir itself: not a directory, a symlink or a missing name.
    const gone = listed.filter(
      (name) => !names.has(name) || !isRegularFile(path.join(framesDir, name)),
    );
    if (gone.length > 0) {
      missing.push(`regular files for the frame-times.json keys: ${gone.sort().join(", ")}`);
    }
    // Scene detection records every scene and interval frame it writes; an
    // anchor frame carries its time in its own name and is never listed.
    const untimed = [...names].filter(
      (name) => TIMED_FRAME.test(name) && !Object.hasOwn(listing, name),
    );
    if (untimed.length > 0) {
      missing.push(`frame-times.json entries for: ${untimed.sort().join(", ")}`);
    }
  }
  return missing;
}

/**
 * True when `dir` is a directory this run can list.
 *
 * @param {string} dir
 */
function readableDirectory(dir) {
  try {
    if (!fs.statSync(dir).isDirectory()) return false;
    fs.readdirSync(dir);
    return true;
  } catch {
    return false;
  }
}

/**
 * True when `file` is a regular file (not a directory, symlink or device).
 *
 * @param {string} file
 */
function isRegularFile(file) {
  try {
    return fs.lstatSync(file).isFile();
  } catch {
    return false;
  }
}

/**
 * True when `p` itself is a symlink (not followed); false when it is absent.
 *
 * @param {string} p
 */
function isSymlink(p) {
  try {
    return fs.lstatSync(p).isSymbolicLink();
  } catch {
    return false;
  }
}

/**
 * Size of `file` in bytes; 0 when it cannot be read, so an unreadable
 * artifact is refused like an empty one.
 *
 * @param {string} file
 */
function sizeOf(file) {
  if (!isRegularFile(file)) return 0;
  try {
    return fs.statSync(file).size;
  } catch {
    return 0;
  }
}

/**
 * posix paths, relative to `dir`, of every symlink under it.
 *
 * @param {string} dir
 * @param {string} [prefix]
 * @returns {string[]}
 */
function findSymlinks(dir, prefix = "") {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    // Missing or unreadable: the readability checks name it.
    return [];
  }
  return entries.flatMap((entry) => {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isSymbolicLink()) return [rel];
    return entry.isDirectory() ? findSymlinks(path.join(dir, entry.name), rel) : [];
  });
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

  // Every path this run creates, renames or deletes: the target, its backup
  // and its staging dirs (`.<name>.relayout-*` beside the target). One that
  // is, holds, or sits inside the slice would copy the slice into itself or
  // move it away and delete it. Real paths, so a symlink cannot hide overlap.
  const backup = `${target}.relayout-backup`;
  const realSlice = realPathOf(slice);
  const stagingPrefix = `.${path.basename(target)}.relayout-`;
  const overlapsSlice = (/** @type {string} */ p) => {
    const real = realPathOf(p);
    return isSameOrInside(real, realSlice) || isSameOrInside(realSlice, real);
  };
  const sliceInStaging = path
    .relative(realPathOf(path.dirname(target)), realSlice)
    .split(path.sep)[0]
    .startsWith(stagingPrefix);
  for (const written of [target, backup]) {
    if (overlapsSlice(written)) {
      return refuse(`${written} overlaps the slice ${slice}; pick a target outside it`);
    }
  }
  if (sliceInStaging) {
    return refuse(`the slice ${slice} sits in a relayout staging dir of ${target}`);
  }
  // Read the whole slice tree once, up front: an unreadable directory in it
  // is refused here, naming it, rather than failing mid-copy.
  /** @type {string[]} */
  let sliceFiles;
  try {
    sliceFiles = listFiles(slice);
  } catch (error) {
    const where = /** @type {NodeJS.ErrnoException} */ (error).path ?? slice;
    return refuse(`cannot read ${where} in the slice: ${errorMessage(error)}`);
  }
  const symlinks = findSymlinks(slice);
  if (symlinks.length > 0) {
    return refuse(`the slice holds symlinks, which a copy would follow: ${symlinks.join(", ")}`);
  }
  // The reference scanner reads LF and CRLF line endings only; refuse rather than misread.
  const bareCr = sliceFiles.filter(
    (file) =>
      MARKDOWN_FILE.test(file) && /\r(?!\n)/.test(fs.readFileSync(path.join(slice, file), "utf8")),
  );
  if (bareCr.length > 0) {
    return refuse(`Markdown with bare CR line endings is not supported: ${bareCr.join(", ")}`);
  }

  // An interrupted `--replace` swap leaves the previous target at this name.
  if (fs.existsSync(backup)) {
    if (fs.existsSync(target)) {
      return refuse(
        `a leftover backup ${backup} sits beside ${target}; keep one of them and remove the other`,
      );
    }
    try {
      fs.renameSync(backup, target);
    } catch (error) {
      return refuse(`could not restore ${target} from ${backup}: ${errorMessage(error)}`);
    }
    writeStderr(`relayout: restored ${target} from the backup an interrupted run left`);
  }

  // A killed run leaves its staging dir behind. Name any for deletion by
  // hand; never install or delete one: it may belong to another slice's run
  // or to a run still in progress.
  let siblings = [];
  try {
    siblings = fs.readdirSync(path.dirname(target));
  } catch {
    // No parent yet: nothing left behind.
  }
  const leftovers = siblings.filter((name) => name.startsWith(stagingPrefix));
  if (leftovers.length > 0) {
    writeStderr(
      `relayout: warning: staging dirs from an earlier run sit beside ${target}; ` +
        `delete them by hand when no run is using them: ${leftovers
          .map((name) => path.join(path.dirname(target), name))
          .join(", ")}`,
    );
  }

  let state;
  try {
    state = JSON.parse(fs.readFileSync(watchStatePath(slice), "utf8"));
  } catch {
    return refuse(`no readable run-state/watch.json under ${slice}`);
  }
  const shapeProblem = watchStateShapeProblem(state);
  if (shapeProblem) return refuse(`run-state/watch.json ${shapeProblem}`);
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
  if (fs.existsSync(target) && !fs.lstatSync(target).isDirectory()) {
    return refuse(`${target} exists and is not a directory; --replace only replaces a directory`);
  }

  // `--no-media` takes nothing from the temp session, even when it still exists.
  // `close` deletes every temp dir watch.json records, so in every mode,
  // `--no-media` included and whether or not the dir still exists, nothing
  // this run writes may sit in, hold, or be one of them.
  const recorded = resolveTempSession(state.tempSession ?? {});
  // A recorded temp dir that is itself a symlink points somewhere the watch
  // never made: checked before any containment or readability check follows it.
  for (const dir of [recorded.workDir, recorded.framesDir, recorded.contactSheetsDir]) {
    if (dir && isSymlink(dir)) {
      return refuse(`temp session dir ${dir} is a symlink`);
    }
  }
  for (const dir of [recorded.workDir, recorded.framesDir, recorded.contactSheetsDir]) {
    if (!dir) continue;
    const realDir = realPathOf(dir);
    const clashes =
      [target, backup].some((p) => {
        const real = realPathOf(p);
        return isSameOrInside(real, realDir) || isSameOrInside(realDir, real);
      }) || isSameOrInside(realPathOf(path.dirname(target)), realDir);
    if (clashes) {
      return refuse(`target ${target} overlaps the recorded temp session dir ${dir}`);
    }
  }

  // watch.json names the temp dirs, and the watch only ever makes them in the
  // OS temp dir; anything else (a hand-edited path, the slice, the target) is
  // not a temp session, and `close` would delete it. Checked in every mode,
  // whether or not the dir still exists.
  const realTmp = fs.realpathSync.native(os.tmpdir());
  for (const dir of [recorded.workDir, recorded.framesDir, recorded.contactSheetsDir]) {
    if (!dir) continue;
    if (!isSameOrInside(realPathOf(dir), realTmp) || realPathOf(dir) === realTmp) {
      return refuse(`temp session dir ${dir} is not inside the OS temp dir`);
    }
    if (overlapsSlice(dir)) {
      return refuse(`temp session dir ${dir} overlaps the slice`);
    }
  }
  // `--no-media` reads nothing from the temp session.
  const temp = noMedia ? {} : recorded;
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
  // The one video must be this slice's: its yt-dlp id is watch.json's videoId
  // (YouTube), or, for an X post, whose media id differs from the post id, its
  // info JSON's display_id is the post id the watch recorded.
  if (!noMedia && mediaId !== null && mediaId !== state.videoId) {
    const displayId = media.metadataPath ? readJsonObject(media.metadataPath)?.display_id : null;
    const postIds = [state.videoId, state.sourceMetadata?.["source:displayId"]].filter(Boolean);
    if (!(typeof displayId === "string" && postIds.includes(displayId))) {
      return refuse(
        `the temp session's video is ${mediaId}, not this slice's ${state.videoId}` +
          (typeof displayId === "string" ? ` (its info JSON names post ${displayId})` : ""),
      );
    }
  }
  if (!noMedia) {
    // A partly removed temp session would yield a layout silently missing a part.
    // Captions are required unless the transcript phase records that no
    // caption fed the transcript: run-watch.js writes `transcriptStrategy:
    // "asr"`, or `skipped: true` when no entry produced one. A
    // `transcriptDegradation` can be a caption's provenance note, so it is not
    // that evidence. A recovered watch records only `recovered`, and recovery
    // itself needs a caption track, so it requires them too.
    const transcriptMetrics = state.phases?.transcript?.metrics ?? {};
    const captioned = !(
      transcriptMetrics.transcriptStrategy === "asr" || transcriptMetrics.skipped === true
    );
    const missing = [
      ...(temp.workDir && !readableDirectory(temp.workDir)
        ? [`the work dir (${temp.workDir} is not a readable directory)`]
        : media.videoPath
          ? []
          : [`the video (${temp.workDir ?? "no tempSession.workDir"})`]),
      ...(media.videoPath && sizeOf(media.videoPath) === 0
        ? [`a non-empty video (${path.basename(media.videoPath)} is empty)`]
        : []),
      ...(media.videoPath && !media.metadataPath ? [`the info JSON (${mediaId}.info.json)`] : []),
      ...(media.metadataPath && !readJsonObject(media.metadataPath)
        ? [`an info JSON holding a JSON object (${path.basename(media.metadataPath)})`]
        : []),
      ...missingFrames(temp.framesDir),
      ...[temp.workDir, temp.framesDir]
        .flatMap((dir) => (dir ? findSymlinks(dir).map((link) => path.join(dir, link)) : []))
        .map((link) => `regular files in place of symlinks (${link})`),
      ...(captioned && media.captionPaths.length === 0 ? ["the caption tracks"] : []),
      ...media.captionPaths
        .filter((caption) => sizeOf(caption) === 0)
        .map((caption) => `a non-empty caption track (${path.basename(caption)} is empty)`),
      ...[media.videoPath, media.metadataPath, ...media.captionPaths]
        .filter((file) => file && fs.existsSync(file) && !isRegularFile(file))
        .map((file) => `a regular file at ${path.basename(file)}`),
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

  // The slice's own README (its journey) is not copied: the target's README is
  // a provenance page with other headings, so a reference to the slice README
  // becomes not-retained text rather than a link to a different page.
  const files = new Map(
    plan.flatMap((entry) =>
      entry.sourceFile ? [/** @type {[string, string]} */ ([entry.sourceFile, entry.to])] : [],
    ),
  );
  /** @type {PathMap} */
  const map = {
    files,
    dirs: deriveDirectoryMap(files),
    tempFrames,
    framesDropped: noMedia,
    sliceWorkPath: workRootRelative(slice),
    sliceEntries,
    sliceAbs: slice,
    targetAbs: target,
  };

  // Build the whole layout in a sibling staging directory and move it into
  // place only after the link check passes, so a failure never leaves a
  // partial target.
  let staging;
  try {
    fs.mkdirSync(path.dirname(target), { recursive: true });
    staging = fs.mkdtempSync(path.join(path.dirname(target), stagingPrefix));
  } catch (error) {
    return refuse(`cannot stage beside ${target}: ${errorMessage(error)}`);
  }
  const discard = (/** @type {string} */ dir) => fs.rmSync(dir, { recursive: true, force: true });
  let rewrites = 0;
  /** @type {Map<string, string[]>} */
  const spacedRefs = new Map();
  /** @type {Map<string, string[]>} */
  const retiredRefs = new Map();
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
      if (entry.sourceFile && MARKDOWN_FILE.test(entry.sourceFile)) {
        const result = rewriteSliceReferences(
          fs.readFileSync(entry.from, "utf8"),
          entry.sourceFile,
          entry.to,
          map,
        );
        rewrites += result.rewrites;
        if (result.spacedRefs.length > 0) spacedRefs.set(entry.to, result.spacedRefs);
        if (result.retiredRefs.length > 0) retiredRefs.set(entry.to, result.retiredRefs);
        write(entry.to, result.text);
      } else {
        fs.mkdirSync(path.dirname(path.join(staging, entry.to)), { recursive: true });
        copyFile(entry.from, path.join(staging, entry.to));
        copied += 1;
      }
    }
    if (media.metadataPath) {
      // Checked to be an object before staging; a change since then is a failure.
      const info = readJsonObject(media.metadataPath);
      if (!info) throw new Error(`${media.metadataPath} no longer holds a JSON object`);
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

    unresolved = checkLayoutLinks(staging, {
      sliceDirs: new Set([...sliceEntries].filter((entry) => !sliceFiles.includes(entry))),
      spacedRefs,
      retiredRefs,
    });
  } catch (error) {
    discard(staging);
    return refuse(`copy failed, target left untouched: ${/** @type {Error} */ (error).message}`);
  }
  if (unresolved.length > 0) {
    discard(staging);
    return { exitCode: 1, copied: 0, rewrites, unresolved };
  }

  // With --replace the old target moves to a fixed-name backup, so a run
  // killed between the two renames is recovered at the next start (see the
  // backup check above). Without --replace the install is one rename, which
  // fails (ENOTEMPTY or EEXIST on POSIX, EPERM on Windows) when a target with
  // content appeared during the run. POSIX rename replaces an empty directory
  // created meanwhile; that is accepted, since an empty directory holds no data.
  const hadTarget = replace && fs.existsSync(target);
  try {
    if (hadTarget) fs.renameSync(target, backup);
    fs.renameSync(staging, target);
  } catch (error) {
    try {
      if (hadTarget && !fs.existsSync(target) && fs.existsSync(backup)) {
        fs.renameSync(backup, target);
      }
      discard(staging);
    } catch (cleanupError) {
      return refuse(
        `could not move the layout into place (${errorMessage(error)}), and cleanup failed ` +
          `(${errorMessage(cleanupError)}); check ${target}, ${backup} and ${staging}`,
      );
    }
    if (!replace && fs.existsSync(target)) {
      return refuse(`${target} appeared during the run; pass --replace to replace it`);
    }
    return refuse(`could not move the layout into place: ${errorMessage(error)}`);
  }
  try {
    if (hadTarget) discard(backup);
  } catch (error) {
    writeStderr(`relayout: installed ${target}, but cleanup failed: ${errorMessage(error)}`);
  }
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
