// Shared marker-block flow for the generated-block CI generators
// (scripts/generate-catalog.mjs, scripts/generate-cheatsheet.mjs). Both locate a
// `<!-- x:start -->` ... `<!-- x:end -->` block in a committed file, compare it
// against a freshly generated one, and then either report drift under --check or
// rewrite the block in place.
//
// Two exports rather than one because the missing-marker outcome is the one part
// of the flow the generators do not share: findMarkerBlock returns null and each
// caller raises in its own idiom (the catalog throws, the cheat sheet routes
// through its own fail()). The five messages differ per generator too, so each
// passes its own; their wording and stream (stdout for the in-sync and
// regenerated lines, stderr for the drift lines) are CI contracts.

import { writeFileSync } from "node:fs";
import process from "node:process";

import { reportFirstDifference } from "./report-first-difference.mjs";

export function findMarkerBlock(content, start, end) {
  const match = content.match(new RegExp(`${start}[\\s\\S]*?${end}`));
  return match ? match[0] : null;
}

// Exits 0 when the committed block already matches, exits 1 after reporting
// drift under check, and otherwise rewrites the block and returns.
export function syncMarkerBlock({ path, content, existing, expected, check, messages }) {
  if (check) {
    if (existing === expected) {
      console.log(messages.inSync);
      process.exit(0);
    }
    console.error(messages.drift);
    console.error(messages.rerun);
    reportFirstDifference(expected, existing);
    process.exit(1);
  }

  if (existing === expected) {
    console.log(messages.unchanged);
    process.exit(0);
  }
  // Function replacer: a string replacement would reinterpret `$`-sequences
  // (`$&`, `$'`, ...) inside the generated block.
  writeFileSync(path, content.replace(existing, () => expected));
  console.log(messages.regenerated);
}
