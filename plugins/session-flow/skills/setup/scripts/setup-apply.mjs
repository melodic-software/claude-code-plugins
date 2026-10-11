#!/usr/bin/env node
// Write or check the repository layer of the session-flow plugin's settings,
// docs/conventions/session-flow.yaml, against schemas/session-flow.schema.json.
//
// Usage:
//   setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ...
//   setup-apply.mjs [--root <dir>] --check
//
//   --check  validate the existing file and print its keys as `<key>: <value>`
//            lines, or one line per problem; write nothing.
//
// The YAML reader and parser are the plugin's shared copies under
// skills/retro/scripts/. The other options, the guarantees and the exit codes
// are in ../../../lib/setup-apply.mjs.

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { run } from "../../../lib/setup-apply.mjs";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

// Any problem other than a key outside the schema prints only the problems.
// Otherwise each key outside the schema gets its line, then every key its value.
function report({ rel, keys, problems, value }) {
  const lines = problems.map((p) => `${rel}: ${p.msg}\n`);
  if (problems.some((p) => p.kind !== "unknown")) {
    process.stdout.write(lines.join(""));
    return 1;
  }
  for (const k of Object.keys(keys)) lines.push(`${k}: ${value(k) || "(unset)"}\n`);
  process.stdout.write(lines.join(""));
  return problems.length ? 1 : 0;
}

run({
  plugin: "session-flow",
  schema: join(PLUGIN, "schemas", "session-flow.schema.json"),
  reader: join(PLUGIN, "skills", "retro", "scripts", "parse-concern-value.sh"),
  parser: join(PLUGIN, "skills", "retro", "scripts", "yaml-subset.awk"),
  report,
});
