#!/usr/bin/env node
// Write or check the repository layer of the session-flow plugin's settings,
// docs/conventions/session-flow.yaml, against schemas/session-flow.schema.json.
//
// Usage:
//   setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ...
//   setup-apply.mjs [--root <dir>] --check
//
//   --check  validate the existing file and print its keys as `PASS <key>: <value>`
//            lines, or a `WARN` line per problem; write nothing.
//
// The YAML reader and parser are the plugin's shared copies under
// skills/retro/scripts/. The other options, the guarantees and the exit codes
// are in ../../../lib/setup-apply.mjs.

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { run, wholeFileReport } from "../../../lib/setup-apply.mjs";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

// --check: a WARN line per problem; PASS `<key>: <value>` lines for every key
// only when the sole problems are keys outside the schema.
run({
  plugin: "session-flow",
  schema: join(PLUGIN, "schemas", "session-flow.schema.json"),
  reader: join(PLUGIN, "skills", "retro", "scripts", "parse-concern-value.sh"),
  parser: join(PLUGIN, "skills", "retro", "scripts", "yaml-subset.awk"),
  report: wholeFileReport,
});
