#!/usr/bin/env node
// GENERATED from lib/check-convention-facts.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// Flag universal claims in a conventions file that may be targets written as current facts.
// Usage: check-convention-facts.mjs <file>...
// HEURISTIC and advisory: a line outside the `## Not yet` section whose sentence holds
// `every`, `all`, `always`, `never` or `each` before more words is printed as
// `<file>:<line>: universal claim "<word>": <text>`, for a reader to verify against the
// repository. A finding is not proof of a false fact, and a missing finding is not proof of
// a true one. Front matter, fenced code, inline code, HTML comments, headings and sentences
// that open with "New" (a team rule for new work, which claims nothing about today) are skipped.
// Exit 0 with or without findings, 2 on a usage error or an unreadable file.
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const QUANTIFIER = /\b(every|all|always|never|each)\b(?=\W+\w)/i;
const NOT_YET = /^##\s+Not yet\s*#*\s*$/i;
const SECTION_END = /^#{1,2}\s/;
const FENCE = /^\s*(`{3,}|~{3,})/;
const FENCE_CLOSE = /^\s*(`{3,}|~{3,})\s*$/;
const LIST_ITEM = /^\s*(?:[-*+]|\d+[.)])\s+/;

function sentences(text) {
  return text.split(/(?<=[.!?])\s+/).filter((s) => s.trim());
}

export function findClaims(text) {
  const lines = text.split(/\r?\n/);
  const claims = [];
  let start = 0;
  if (lines[0]?.trim() === "---") {
    const end = lines.findIndex((l, i) => i > 0 && l.trim() === "---");
    if (end > 0) start = end + 1;
  }
  let fence = null;
  let inComment = false;
  let notYet = false;
  // A "New ..." team rule hard-wrapped onto the next line is still a team rule there.
  let ruleOpen = false;
  for (let i = start; i < lines.length; i++) {
    const line = lines[i];
    if (fence) {
      const close = FENCE_CLOSE.exec(line);
      if (close && close[1][0] === fence[0] && close[1].length >= fence.length) fence = null;
      continue;
    }
    if (inComment) {
      if (line.includes("-->")) inComment = false;
      continue;
    }
    const open = FENCE.exec(line);
    if (open) {
      fence = open[1];
      ruleOpen = false;
      continue;
    }
    let prose = line.replace(/`[^`]*`/g, "``").replace(/<!--.*?-->/g, "");
    if (prose.includes("<!--")) {
      prose = prose.slice(0, prose.indexOf("<!--"));
      inComment = true;
    }
    if (SECTION_END.test(line)) notYet = NOT_YET.test(line.trim());
    if (notYet || /^\s*#/.test(line)) {
      ruleOpen = false;
      continue;
    }
    if (!prose.trim() || LIST_ITEM.test(prose)) ruleOpen = false;
    let hit = null;
    for (const sentence of sentences(prose.replace(LIST_ITEM, ""))) {
      const rule = ruleOpen || /^\W*New\b/.test(sentence);
      ruleOpen = rule && !/[.!?]\s*$/.test(sentence);
      if (!rule && !hit) hit = QUANTIFIER.exec(sentence);
    }
    if (hit) claims.push({ line: i + 1, word: hit[1].toLowerCase(), text: line.trim() });
  }
  return claims;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const files = process.argv.slice(2);
  if (!files.length || files.some((f) => f.startsWith("-"))) {
    console.error("usage: check-convention-facts.mjs <file>...");
    process.exit(2);
  }
  const texts = [];
  for (const file of files) {
    try {
      texts.push([file, readFileSync(file, "utf8")]);
    } catch (err) {
      console.error(`check-convention-facts: cannot read ${file}: ${err.code ?? err.message}`);
      process.exit(2);
    }
  }
  for (const [file, text] of texts) {
    for (const { line, word, text: found } of findClaims(text)) {
      console.log(`${file}:${line}: universal claim "${word}": ${found}`);
    }
  }
}
