#!/usr/bin/env node
// Check or write docs/conventions/docs-hygiene.yaml, the repository layer of
// the docs-hygiene plugin's settings, against schemas/docs-hygiene.schema.json.
//
// Usage:
//   setup-apply.mjs [--root <dir>] --check
//   setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ...
//
//   --check  validate the file as it stands and print one line per schema key:
//            PASS with its value, or WARN when the file's value is invalid and
//            the key resolves to its default; write nothing.
//
// The YAML reader and parser are the plugin's bundled copies under lib/. The
// other options, the guarantees and the exit codes are in
// ../../../lib/setup-apply.mjs.

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { run } from "../../../lib/setup-apply.mjs";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

// A key whose own value is invalid, or every key when the file does not
// parse, drops this layer for that key. The repository is the highest layer,
// so the key resolves to its default, never to the lower userConfig value. A
// key the schema does not list is reported and leaves the other keys' values
// in force, as compress reads them.
function report({ rel, keys, problems, value }) {
  const parseError = problems.some((p) => p.kind === "parse");
  const out = problems.map((p) => `WARN ${rel}: ${p.msg}\n`);
  for (const k of Object.keys(keys)) {
    if (parseError || problems.some((p) => p.key === k)) {
      out.push(`WARN ${k}: dropped from ${rel}; resolves to its default, ${keys[k].default}, not to userConfig\n`);
    } else {
      out.push(`PASS ${k}: ${value(k) || "(unset)"}\n`);
    }
  }
  process.stdout.write(out.join(""));
  return problems.length ? 1 : 0;
}

run({
  plugin: "docs-hygiene",
  schema: join(PLUGIN, "schemas", "docs-hygiene.schema.json"),
  reader: join(PLUGIN, "lib", "parse-concern-value.sh"),
  parser: join(PLUGIN, "lib", "yaml-subset.awk"),
  fixedTemp: true,
  report,
});
