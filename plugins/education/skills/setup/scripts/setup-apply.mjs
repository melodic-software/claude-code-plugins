#!/usr/bin/env node
// Check or write docs/conventions/education.yaml, the repository layer of the
// education plugin's settings, against schemas/education.schema.json.
//
// Usage:
//   setup-apply.mjs [--root <dir>] --check
//   setup-apply.mjs [--root <dir>] [--yes] [--default <key>] ... <key>=<value> ...
//
// The YAML reader is the copy bundled with /education:explain,
// under skills/explain/scripts/. The options, guarantees and exit codes are in
// ../../../lib/setup-apply.mjs.

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { run, wholeFileReport } from "../../../lib/setup-apply.mjs";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
run({
  plugin: "education",
  provenance: true,
  schema: join(PLUGIN, "schemas", "education.schema.json"),
  reader: join(PLUGIN, "skills", "explain", "scripts", "parse-concern-value.sh"),
  fixedTemp: true,
  report: wholeFileReport,
});
