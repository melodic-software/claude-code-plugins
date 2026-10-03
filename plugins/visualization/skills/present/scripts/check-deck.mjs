#!/usr/bin/env node
// Decide whether a Slides deck written under <root>/project/ may be published,
// before anything is sent to claude.ai. Refuses a root inside a working tree (a
// view never sits beside its record) or reached through a symlink, gates the
// deck title the create call will use, refuses a K2 slide holding anything
// outside a fixed text-and-layout allowlist, resolves the user's own medium
// layers, then runs the shared publish gate over every file the publish would
// send. Prints one JSON object.
//
//   check-deck.mjs <root> <PUBLIC|PRIVATE|INTERNAL|UNKNOWN|NONE> --class K0|K1|K2
//                  [--argument terminal|file|artifact] [--option <plugin medium option>]
// Exit 0 decided (read `medium`), 1 a deck refused, 2 usage or an unreadable root.

import { existsSync, lstatSync, readdirSync, readFileSync, realpathSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { publishGate, trustedMedium } from "../../../lib/publish-gate.mjs";

// ------------------------------------------------------------ K2 allowlist

const UNPARSED = "markup the gate cannot parse cleanly";
const TAGS = new Set(
  "section div p span h1 h2 h3 h4 h5 h6 ul ol li strong em b i u s small sub sup br hr blockquote aside header footer figure figcaption img table thead tbody tr th td code pre mark".split(" "),
);
const ATTRS = new Set("class id style alt title lang dir colspan rowspan width height aria-label aria-hidden src".split(" "));
const NAMED_ELEMENTS = { "x-embed": "a live embed", script: "a script", svg: "inline SVG", a: "a link" };
const FENCED = new Set("style link iframe frame object embed form meta base".split(" "));
/** The two image sources a K2 slide may use: an asset this session uploaded, or a design-system file. */
const UPLOADED = /^(?:\/_blob\/[A-Za-z0-9_-]+|project\/ds\/[A-Za-z0-9_/-]+\.[a-z0-9]+)$/;
const ENTITIES = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
const WS = /[\t\n\f\r ]/;
const NAME = /[A-Za-z][A-Za-z0-9-]*/y;
const UNQUOTED = /[^\t\n\f\r "'=<>`]+/y;

/** An attribute value with its character references decoded, or null when one is malformed or unknown. */
export function decodeAttribute(raw) {
  if (/&(?!(?:amp|lt|gt|quot|apos|nbsp|#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6});)/.test(raw)) return null;
  let ok = true;
  const out = raw.replace(/&(#[xX][0-9A-Fa-f]+|#[0-9]+|[a-z]+);/g, (_, ref) => {
    if (!ref.startsWith("#")) return ENTITIES[ref];
    const code = ref[1] === "x" || ref[1] === "X" ? Number.parseInt(ref.slice(2), 16) : Number(ref.slice(1));
    if (code === 0 || code > 0x10ffff) ok = false;
    return ok ? String.fromCodePoint(code) : "";
  });
  return ok ? out : null;
}

function attributeRefusal(tag, key, raw) {
  if (key.startsWith("on")) return "an event handler";
  if (key === "href") return "a link";
  if (!ATTRS.has(key)) return "an attribute outside the allowlist";
  const value = raw === null ? "" : decodeAttribute(raw);
  if (value === null) return UNPARSED;
  if (key === "src" && !(tag === "img" && UPLOADED.test(value))) return "an image not uploaded by this session";
  if (key === "style" && /[(\\&]/.test(raw)) return "a style value holding (, \\, or &";
  return null;
}

function elementRefusal(tag) {
  if (Object.hasOwn(NAMED_ELEMENTS, tag)) return NAMED_ELEMENTS[tag];
  if (FENCED.has(tag)) return "a style, link, frame, object, form, meta, or base element";
  if (!TAGS.has(tag)) return "an element outside the text and layout set";
  return null;
}

const nameAt = (html, at) => {
  NAME.lastIndex = at;
  return NAME.exec(html)?.[0] ?? null;
};

/**
 * Why a K2 slide may not publish, or null. A small tokenizer that respects
 * quotes: every `<` must open a well-formed tag on the allowlist, attributes are
 * whitespace-separated, named once, and on the allowlist, and anything it cannot
 * read cleanly is refused. Text between tags is the type's escaped text.
 */
export function k2Refusal(html) {
  const n = html.length;
  let i = 0;
  for (;;) {
    const lt = html.indexOf("<", i);
    if (lt < 0) return null;
    i = lt + 1;
    const close = html[i] === "/";
    if (close) i += 1;
    const name = nameAt(html, i);
    if (!name) return UNPARSED;
    i += name.length;
    const tag = name.toLowerCase();
    const refused = elementRefusal(tag);
    if (refused) return refused;
    const seen = new Set();
    for (;;) {
      const start = i;
      while (i < n && WS.test(html[i])) i += 1;
      if (i >= n) return UNPARSED;
      if (html[i] === ">") break;
      if (!close && html.startsWith("/>", i)) {
        i += 1;
        break;
      }
      if (close || i === start) return UNPARSED;
      const attr = nameAt(html, i);
      if (!attr) return UNPARSED;
      i += attr.length;
      const key = attr.toLowerCase();
      if (seen.has(key)) return UNPARSED;
      seen.add(key);
      let j = i;
      while (j < n && WS.test(html[j])) j += 1;
      let raw = null;
      if (html[j] === "=") {
        j += 1;
        while (j < n && WS.test(html[j])) j += 1;
        const quote = html[j];
        if (quote === '"' || quote === "'") {
          const end = html.indexOf(quote, j + 1);
          if (end < 0) return UNPARSED;
          raw = html.slice(j + 1, end);
          i = end + 1;
        } else {
          UNQUOTED.lastIndex = j;
          raw = UNQUOTED.exec(html)?.[0] ?? null;
          if (raw === null) return UNPARSED;
          i = j + raw.length;
        }
      }
      const why = attributeRefusal(tag, key, raw);
      if (why) return why;
    }
    i += 1;
  }
}

/** The first refusal per K2 slide file, as {file, carries}. */
export function k2Refusals(files) {
  const refused = [];
  for (const [path, text] of files) {
    if (!path.startsWith("project/slides/")) continue;
    const carries = k2Refusal(text);
    if (carries) refused.push({ file: path, carries });
  }
  return refused;
}

// ------------------------------------------------------------ deck files

class Refused extends Error {}

/** Every file under <root>/project, as [relative path, text]. A symlink or special file anywhere refuses the deck. */
export function deckFiles(root) {
  const out = [];
  const walk = (dir, rel) => {
    if (lstatSync(dir).isSymbolicLink()) throw new Refused(`${rel} is a symlink`);
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      const at = `${rel}/${entry.name}`;
      if (entry.isSymbolicLink()) throw new Refused(`${at} is a symlink`);
      if (entry.isDirectory()) walk(path, at);
      else if (entry.isFile()) out.push([at, readFileSync(path, "utf8")]);
      else throw new Refused(`${at} is not a regular file or folder`);
    }
  };
  walk(join(root, "project"), "project");
  return out.sort(([a], [b]) => a.localeCompare(b));
}

/** Why the deck title may not go to the create call, or null. It is plain text, on one line. */
export function titleRefusal(title) {
  if (typeof title !== "string" || title.trim() === "") return "deck.json has no title string";
  if (title.length > 200) return "the deck title is longer than 200 characters";
  if (/[\u0000-\u001f\u007f<>‪-‮⁦-⁩]/.test(title)) return "the deck title holds a control character, < or >";
  return null;
}

function workTree(dir) {
  for (let at = dir; ; at = dirname(at)) {
    if (existsSync(join(at, ".git"))) return at;
    if (dirname(at) === at) return null;
  }
}

/**
 * @param {{root: string, visibility: string, cls: string, layers?: {argument?: string|null, option?: string|null, home?: string, project?: string|null}}} input
 */
export function checkDeck({ root, visibility, cls, layers = {} }) {
  const local = (exit, reason) => ({ exit, result: { medium: "file", class: cls, reason } });
  const resolved = resolve(root);
  if (lstatSync(resolved).isSymbolicLink() || realpathSync(resolved) !== resolved) {
    return local(2, `the deck root ${resolved} is or passes through a symlink; pass its real path`);
  }
  const tree = workTree(resolved);
  if (tree) return local(2, `the deck root ${resolved} is inside the working tree ${tree}; write it outside`);
  let files;
  try {
    files = deckFiles(resolved);
  } catch (error) {
    if (error instanceof Refused) return local(2, `${error.message}; write the deck as plain files`);
    throw error;
  }
  const index = files.find(([p]) => p === "project/deck.json");
  if (!index) return local(2, "no project/deck.json under the root");
  let title;
  try {
    title = JSON.parse(index[1])?.title;
  } catch (error) {
    return local(2, `project/deck.json is not JSON (${error.message})`);
  }
  const badTitle = titleRefusal(title);
  if (badTitle) return local(1, badTitle);
  if (cls === "K2") {
    const refused = k2Refusals(files);
    if (refused.length) {
      return { exit: 1, result: { medium: "file", class: cls, reason: "a K2 deck carries more than text in the slide format", refused } };
    }
  }
  const { medium, source, warnings } = trustedMedium(layers);
  const extra = warnings.length ? { warnings } : {};
  if (medium === "terminal" || medium === "file") {
    return { exit: 0, result: { medium, class: cls, reason: `${source} sets medium: ${medium}`, ...extra } };
  }
  const text = files.map(([p, t]) => `${p}\n${t}`).join("\n");
  const gate = publishGate({ explicit: medium === "artifact", visibility, text, subject: "deck" });
  if (medium === "artifact") gate.reason = `${source} sets medium: artifact`;
  // The title is printed only for a create call; a deck kept local never echoes it.
  const named = gate.medium === "artifact" ? { title } : {};
  return { exit: 0, result: { class: cls, files: files.length, ...named, ...gate, ...extra } };
}

function main(argv) {
  const [root, visibility, ...rest] = argv;
  let cls = null;
  let argument = null;
  let option = null;
  let bad = false;
  for (let i = 0; i < rest.length; i += 1) {
    const next = rest[i + 1];
    if (rest[i] === "--class" && ["K0", "K1", "K2"].includes(next)) cls = rest[++i];
    else if (rest[i] === "--argument" && ["terminal", "file", "artifact"].includes(next)) argument = rest[++i];
    else if (rest[i] === "--option" && next !== undefined) option = rest[++i];
    else bad = true;
  }
  if (bad || !root || !visibility || visibility.startsWith("--") || !cls) {
    process.stderr.write(
      "usage: check-deck.mjs <root> <PUBLIC|PRIVATE|INTERNAL|UNKNOWN|NONE> --class K0|K1|K2 [--argument terminal|file|artifact] [--option <value>]\n",
    );
    return 2;
  }
  let outcome;
  try {
    outcome = checkDeck({ root, visibility: visibility.toUpperCase(), cls, layers: { argument, option } });
  } catch (error) {
    process.stderr.write(`check-deck: ${error.message}\n`);
    return 2;
  }
  process.stdout.write(`${JSON.stringify(outcome.result, null, 2)}\n`);
  return outcome.exit;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
