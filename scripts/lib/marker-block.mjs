// Shared marker-block flow for the generated-block CI generators
// (scripts/generate-catalog.mjs, scripts/generate-cheatsheet.mjs). Both locate a
// marker-fenced block in a committed file, compare it against a freshly
// generated one, and then either report drift under --check or rewrite the block
// in place. scripts/generate-marketplace.mjs passes a whole file as the block.
//
// A block is fenced in one of two forms, and a file must carry exactly one:
// `<!-- x:start -->` ... `<!-- x:end -->`, or
// `<!-- BEGIN GENERATED: x. Run <command> -->` ... `<!-- END GENERATED: x -->`,
// the form the ai-slop audit skips. The generator rewrites the block inside the
// form it found, so either form passes --check.
//
// Two exports rather than one because the missing-marker outcome is the one part
// of the flow the generators do not share: findMarkerBlock returns an error and
// each caller raises in its own idiom (the catalog throws, the cheat sheet routes
// through its own fail()). The five messages differ per generator too, so each
// passes its own; their wording and stream (stdout for the in-sync and
// regenerated lines, stderr for the drift lines) are CI contracts.

import { writeFileSync } from "node:fs";
import process from "node:process";

import { reportFirstDifference } from "./report-first-difference.mjs";

// The marker pairs a block named `name` may carry, the start-and-end form first.
export function markerForms(name, command) {
  return [
    { start: `<!-- ${name}:start -->`, end: `<!-- ${name}:end -->` },
    { start: `<!-- BEGIN GENERATED: ${name}. Run ${command} -->`, end: `<!-- END GENERATED: ${name} -->` },
  ];
}

function count(content, literal) {
  return content.split(literal).length - 1;
}

// Markers are matched as literal text: the generated form contains `.`.
// Returns { form, block } for the one form the content carries, or { error }:
// "missing" when it carries none, otherwise a sentence naming the defect.
export function findMarkerBlock(content, forms) {
  const present = forms.filter((f) => content.includes(f.start) || content.includes(f.end));
  if (present.length === 0) return { error: "missing" };
  if (present.length > 1) {
    return { error: `carries markers of more than one form (${present.map((f) => f.start).join(", ")}); keep one` };
  }
  const [form] = present;
  const starts = count(content, form.start);
  const ends = count(content, form.end);
  const from = content.indexOf(form.start);
  const to = content.indexOf(form.end);
  if (starts !== 1 || ends !== 1 || to < from + form.start.length) {
    return {
      error:
        `has unbalanced markers (${starts} of ${form.start}, ${ends} of ${form.end}); ` +
        "it needs exactly one of each, start first",
    };
  }
  return { form, block: content.slice(from, to + form.end.length) };
}

// Exits 0 when the committed block already matches, exits 1 after reporting
// drift under check, and otherwise rewrites the block and returns.
export function syncMarkerBlock({ path, content, existing, expected, check, messages }) {
  if (existing === expected) {
    console.log(check ? messages.inSync : messages.unchanged);
    process.exit(0);
  }
  if (check) {
    console.error(messages.drift);
    console.error(messages.rerun);
    reportFirstDifference(expected, existing);
    process.exit(1);
  }
  // Function replacer: a string replacement would reinterpret `$`-sequences
  // (`$&`, `$'`, ...) inside the generated block.
  writeFileSync(path, content.replace(existing, () => expected));
  console.log(messages.regenerated);
}
