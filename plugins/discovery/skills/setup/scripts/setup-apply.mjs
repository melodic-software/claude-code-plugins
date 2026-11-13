#!/usr/bin/env node
// Write or check the repository layer of the discovery plugin's settings,
// <home>/discovery.yaml, against schemas/discovery.schema.json. <home> is
// the repository's convention home.
//
// The usage, options, guarantees and exit codes are in
// ../../../lib/setup-apply.mjs.

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { run, wholeFileReport } from "../../../lib/setup-apply.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
run({
  plugin: "discovery",
  provenance: true,
  schema: join(HERE, "..", "..", "..", "schemas", "discovery.schema.json"),
  reader: join(HERE, "parse-concern-value.sh"),
  report: wholeFileReport,
});
