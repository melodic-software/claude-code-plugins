#!/usr/bin/env node
// Write or check the repository layer of the discovery plugin's settings,
// docs/conventions/discovery.yaml, against schemas/discovery.schema.json.
//
// Usage:
//   setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ...
//   setup-apply.mjs [--root <dir>] --check
//
// The options, guarantees and exit codes are in ../../../lib/setup-apply.mjs.

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { run, wholeFileReport } from "../../../lib/setup-apply.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
run({
  plugin: "discovery",
  schema: join(HERE, "..", "..", "..", "schemas", "discovery.schema.json"),
  reader: join(HERE, "parse-concern-value.sh"),
  parser: join(HERE, "yaml-subset.awk"),
  report: wholeFileReport,
});
