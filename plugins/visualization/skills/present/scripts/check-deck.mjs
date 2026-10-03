#!/usr/bin/env node
// Decide whether a Slides deck written under <root>/project/ may be published,
// before anything is sent to claude.ai. Refuses a root inside a working tree (a
// view never sits beside its record), refuses a K2 deck carrying anything but
// text in the slide format, then runs the shared publish gate over every file
// the publish would send. Prints one JSON object.
//
//   check-deck.mjs <root> <PUBLIC|PRIVATE|INTERNAL|UNKNOWN|NONE> --class K0|K1|K2 [--explicit]
// Exit 0 decided (read `medium`), 1 a K2 deck refused, 2 usage or an unreadable root.

import { existsSync, readdirSync, readFileSync, realpathSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { publishGate } from "../../../lib/publish-gate.mjs";

/** What a K2 slide may not carry: each can run script, fetch, navigate, or inline attacker markup. */
export const K2_REFUSALS = Object.freeze([
  ["a live embed", /<x-embed\b/i],
  ["a script", /<script\b/i],
  ["inline SVG", /<svg\b/i],
  ["a link", /<a\b|\bhref\s*=/i],
  ["an event handler", /\son[a-z]+\s*=/i],
  ["a CSS url()", /url\s*\(/i],
  ["an image not uploaded by this session", /\bsrc\s*=\s*(?!["']?(?:\/_blob\/[A-Za-z0-9_-]+["'\s>]|project\/ds\/[A-Za-z0-9_/-]+\.[a-z0-9]+["'\s>]))/i],
  ["a style, link, frame, object, form, meta, or base element", /<(?:style|link|iframe|frame|object|embed|form|meta|base)\b/i],
]);

/** Every file under <root>/project, as [relative path, text]. */
export function deckFiles(root) {
  const out = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) walk(path);
      else if (entry.isFile()) out.push([relative(root, path).split("\\").join("/"), readFileSync(path, "utf8")]);
    }
  };
  walk(join(root, "project"));
  return out.sort(([a], [b]) => a.localeCompare(b));
}

/** The first refusal per K2 slide file, as {file, carries}. Only tags are read: text is escaped, so it holds no `<`. */
export function k2Refusals(files) {
  const refused = [];
  for (const [path, text] of files) {
    if (!path.startsWith("project/slides/")) continue;
    const tags = (text.match(/<[^>]*>?/g) ?? []).join("\n");
    const hit = K2_REFUSALS.find(([, re]) => re.test(tags));
    if (hit) refused.push({ file: path, carries: hit[0] });
  }
  return refused;
}

function workTree(dir) {
  for (let at = dir; ; at = dirname(at)) {
    if (existsSync(join(at, ".git"))) return at;
    if (dirname(at) === at) return null;
  }
}

/** @param {{root: string, visibility: string, cls: string, explicit: boolean}} input */
export function checkDeck({ root, visibility, cls, explicit }) {
  const real = realpathSync(root);
  const tree = workTree(real);
  if (tree) return { exit: 2, result: { medium: "file", reason: `the deck root ${real} is inside the working tree ${tree}; write it outside` } };
  const files = deckFiles(real);
  if (!files.some(([p]) => p === "project/deck.json")) {
    return { exit: 2, result: { medium: "file", reason: "no project/deck.json under the root" } };
  }
  if (cls === "K2") {
    const refused = k2Refusals(files);
    if (refused.length) {
      return { exit: 1, result: { medium: "file", class: cls, reason: "a K2 deck carries more than text in the slide format", refused } };
    }
  }
  const text = files.map(([p, t]) => `${p}\n${t}`).join("\n");
  return { exit: 0, result: { class: cls, files: files.length, ...publishGate({ explicit, visibility, text, subject: "deck" }) } };
}

function main(argv) {
  const [root, visibility, ...rest] = argv;
  let cls = null;
  let explicit = false;
  let bad = false;
  for (let i = 0; i < rest.length; i += 1) {
    if (rest[i] === "--explicit") explicit = true;
    else if (rest[i] === "--class" && ["K0", "K1", "K2"].includes(rest[i + 1])) cls = rest[++i];
    else bad = true;
  }
  if (bad || !root || !visibility || visibility.startsWith("--") || !cls) {
    process.stderr.write("usage: check-deck.mjs <root> <PUBLIC|PRIVATE|INTERNAL|UNKNOWN|NONE> --class K0|K1|K2 [--explicit]\n");
    return 2;
  }
  let outcome;
  try {
    outcome = checkDeck({ root: resolve(root), visibility: visibility.toUpperCase(), cls, explicit });
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
