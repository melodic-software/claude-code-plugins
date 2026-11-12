#!/usr/bin/env node

// Checks an issue body against one type of the issue-body contract
// (plugins/work-items/reference/issue-body-contract.json, synced from melodic-software/standards).
// A field counts as present under a heading at any of the contract's `headingLevels` (`##` from a
// skill, `###` from an issue form), with text other than the contract's `emptyAnswer` before the
// next heading at that level or shallower, deeper sub-sections included. HTML comments and fenced
// code do not count.
//
// Usage: check-body.mjs --type <type> --body-file <path> [--contract <path>]
// Prints one JSON object: {type, missing: [heading...], empty: [heading...], unknownType}.
// Exit 0 when every required field is present and answered, 1 when one is not, 2 on usage error.

import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const DEFAULT_CONTRACT = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../../reference/issue-body-contract.json",
);

const normalize = (text) => text.trim().replace(/\s+/g, " ").toLowerCase();

// Lines outside fenced code, with HTML comments removed.
function proseLines(body) {
  const lines = body.replace(/<!--[\s\S]*?-->/g, "").split(/\r?\n/);
  let fence = null;
  return lines.map((line) => {
    const marker = line.match(/^ {0,3}(`{3,}|~{3,})/);
    if (fence) {
      if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length) fence = null;
      return "";
    }
    if (marker) {
      fence = marker[1];
      return "";
    }
    return line;
  });
}

// Maps each normalized heading at an allowed level to the text under it, its sub-sections' text included.
export function sections(body, levels) {
  const found = new Map();
  const open = [];
  for (const line of proseLines(body)) {
    const heading = line.match(/^ {0,3}(#{1,6})[ \t]+(.*?)[ \t#]*$/);
    if (heading) {
      const depth = heading[1].length;
      while (open.length && open.at(-1).depth >= depth) open.pop();
      if (levels.includes(depth)) {
        const section = { depth, text: [] };
        open.push(section);
        const key = normalize(heading[2]);
        if (!found.has(key)) found.set(key, section.text);
      }
      continue;
    }
    for (const section of open) section.text.push(line);
  }
  return found;
}

export function checkBody(contract, typeKey, body) {
  const type = contract.types[typeKey];
  if (!type) return { type: typeKey, unknownType: true, missing: [], empty: [] };
  const found = sections(body, contract.headingLevels);
  const missing = [];
  const empty = [];
  for (const field of type.fields.filter((f) => f.required)) {
    const text = found.get(normalize(field.heading));
    if (text === undefined) missing.push(field.heading);
    else {
      const answer = text.join("\n").trim();
      if (answer === "" || answer === contract.emptyAnswer) empty.push(field.heading);
    }
  }
  return { type: typeKey, unknownType: false, missing, empty };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const args = process.argv.slice(2);
  const flag = (name) => {
    const index = args.indexOf(name);
    return index === -1 ? undefined : args[index + 1];
  };
  const typeKey = flag("--type");
  const bodyFile = flag("--body-file");
  if (!typeKey || !bodyFile) {
    process.stderr.write("usage: check-body.mjs --type <type> --body-file <path> [--contract <path>]\n");
    process.exit(2);
  }
  const contract = JSON.parse(await readFile(flag("--contract") ?? DEFAULT_CONTRACT, "utf8"));
  const result = checkBody(contract, typeKey, await readFile(bodyFile, "utf8"));
  process.stdout.write(`${JSON.stringify(result)}\n`);
  process.exit(result.unknownType ? 2 : result.missing.length + result.empty.length > 0 ? 1 : 0);
}
