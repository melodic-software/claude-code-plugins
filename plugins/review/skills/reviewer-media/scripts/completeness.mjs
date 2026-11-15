#!/usr/bin/env node
// Every changed file of the pull request must appear in some moment's `covers` of the storyboard
// (an "also changed" moment counts). Prints each uncovered path, one per line.
//
//   completeness.mjs --storyboard <storyboard.json> --facts <facts.json>
// Exit 0 every file covered, 1 one or more uncovered (listed), 2 usage or unreadable input.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const norm = (p) => String(p).replace(/\\/g, "/").replace(/^(\.\/)+/, "");

/** The changed paths no moment covers, in the pull request's order. */
export function uncovered(storyboard, files) {
  const covered = new Set((storyboard?.moments ?? []).flatMap((m) => (Array.isArray(m?.covers) ? m.covers : [])).map(norm));
  return (files ?? []).map((f) => norm(f?.path ?? "")).filter((p) => p && !covered.has(p));
}

function main(argv) {
  const at = (flag) => argv[argv.indexOf(flag) + 1];
  if (argv.length !== 4 || !argv.includes("--storyboard") || !argv.includes("--facts")) {
    process.stderr.write("usage: completeness.mjs --storyboard <storyboard.json> --facts <facts.json>\n");
    return 2;
  }
  let storyboard, facts;
  try {
    storyboard = JSON.parse(readFileSync(at("--storyboard"), "utf8"));
    facts = JSON.parse(readFileSync(at("--facts"), "utf8"));
  } catch (error) {
    process.stderr.write(`completeness: ${error.message}\n`);
    return 2;
  }
  const missing = uncovered(storyboard, facts.files);
  for (const path of missing) process.stdout.write(`uncovered: ${JSON.stringify(path)}\n`);
  return missing.length ? 1 : 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
