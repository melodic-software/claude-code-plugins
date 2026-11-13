// Shared marker-block flow for the generated-block CI generators
// (scripts/generate-catalog.mjs, scripts/generate-cheatsheet.mjs). Both locate a
// marker-fenced block in a committed file, compare it against a freshly
// generated one, and then either report drift under --check or rewrite the block
// in place. scripts/generate-marketplace.mjs passes a whole file as the block.
//
// A block is fenced in one of two forms, and a file must carry exactly one:
// `<!-- BEGIN GENERATED: x. <instruction> -->` ... `<!-- END GENERATED: x -->`,
// the form this repository's docs carry and the ai-slop audit skips, or the
// older `<!-- x:start -->` ... `<!-- x:end -->`, still read. The instruction is
// `Run <command>` for these generators; the native-surfaces view
// (plugins/harness-ops/skills/audit-native-overlap/scripts/overlap.py) uses the
// longer `Edit <store>, then run <command>`. The generator rewrites the block
// inside the form it found, so either form passes --check.
//
// A marker is a standalone line, as the ai-slop audit reads it. A line opening
// with `<!-- BEGIN GENERATED: x.` belongs to the generated form even when the
// instruction differs, and is refused with the expected line rather than
// reported as a missing start marker.
//
// The missing-marker outcome is the one part of the flow the generators do not
// share: findMarkerBlock and wrapMarkerBlock return an error and each caller
// raises in its own idiom (the catalog throws, the cheat sheet routes through
// its own fail()). The five messages differ per generator too, so each passes
// its own; their wording and stream (stdout for the in-sync and regenerated
// lines, stderr for the drift lines) are CI contracts.

import { writeFileSync } from "node:fs";
import process from "node:process";

import { reportFirstDifference } from "./report-first-difference.mjs";

// The marker pairs a block named `name` may carry, the BEGIN GENERATED form first.
// `prefix` is the start of every line that opens a block of that form.
export function markerForms(name, instruction) {
  return [
    {
      prefix: `<!-- BEGIN GENERATED: ${name}.`,
      start: `<!-- BEGIN GENERATED: ${name}. ${instruction} -->`,
      end: `<!-- END GENERATED: ${name} -->`,
    },
    { prefix: `<!-- ${name}:start -->`, start: `<!-- ${name}:start -->`, end: `<!-- ${name}:end -->` },
  ];
}

// Per form, the standalone marker lines in content: { starts, ends }, each a
// list of { at, text } with `at` the offset where the marker text begins.
function scanMarkers(content, forms) {
  const found = forms.map(() => ({ starts: [], ends: [] }));
  let at = 0;
  for (const raw of content.split("\n")) {
    const text = raw.trim();
    const offset = at + raw.indexOf(text);
    forms.forEach((form, i) => {
      if (text.startsWith(form.prefix)) found[i].starts.push({ at: offset, text });
      else if (text === form.end) found[i].ends.push({ at: offset, text });
    });
    at += raw.length + 1;
  }
  return found;
}

// Returns { form, block } for the one form the content carries, or { error }:
// "missing" when it carries none, otherwise a sentence naming the defect.
export function findMarkerBlock(content, forms) {
  const present = scanMarkers(content, forms)
    .map((lines, i) => ({ form: forms[i], ...lines }))
    .filter((f) => f.starts.length > 0 || f.ends.length > 0);
  if (present.length === 0) return { error: "missing" };
  if (present.length > 1) {
    const found = present.map((f) => [...new Set([...f.starts, ...f.ends].map((m) => m.text))].join(", "));
    return { error: `carries markers of more than one form (${found.join("; ")}); keep one form` };
  }
  const [{ form, starts, ends }] = present;
  const odd = starts.find((m) => m.text !== form.start);
  if (odd) {
    return { error: `has the start marker line ${odd.text}, which differs from the expected line ${form.start}` };
  }
  if (starts.length !== 1 || ends.length !== 1 || ends[0].at < starts[0].at) {
    return {
      error:
        `has unbalanced markers (${starts.length} of ${form.start}, ${ends.length} of ${form.end}); ` +
        "it needs exactly one of each, start first",
    };
  }
  return { form, block: content.slice(starts[0].at, ends[0].at + form.end.length) };
}

// Fences a generated body in form's markers, or returns { error } when the body
// itself holds a marker line of any form, which the next run would refuse.
export function wrapMarkerBlock(form, body, forms) {
  const stray = scanMarkers(body, forms).flatMap((f) => [...f.starts, ...f.ends])[0];
  if (stray) return { error: `would get generated content holding the marker line ${stray.text}` };
  return { block: `${form.start}\n\n${body}\n\n${form.end}` };
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
