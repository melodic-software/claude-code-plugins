#!/usr/bin/env node
// Write or check the repository layer of the planning plugin's settings,
// docs/conventions/planning.yaml, against schemas/planning.schema.json.
//
// Usage:
//   setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ...
//   setup-apply.mjs [--root <dir>] --check
//
// Each key is written exactly as the schema names it, so a quoted key with
// spaces around its name is refused. The options, guarantees and exit codes
// are in ../../../lib/setup-apply.mjs.

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { run, wholeFileReport } from "../../../lib/setup-apply.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
run({
  plugin: "planning",
  schema: join(HERE, "..", "..", "..", "schemas", "planning.schema.json"),
  reader: join(HERE, "parse-concern-value.sh"),
  parser: join(HERE, "yaml-subset.awk"),
  exactKeyNames: true,
  report: wholeFileReport,
});
