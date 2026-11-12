#!/usr/bin/env node
// Write or check the repository layer of the discipline plugin's settings,
// <home>/discipline.yaml, against schemas/discipline.schema.json. <home> is
// the repository's convention home.
//
// Each key is written exactly as the schema names it, so a quoted key with
// spaces around its name is refused, and a $schema key, which apply never
// writes, must hold one non-empty, non-null string. The usage, options,
// guarantees and exit codes are in ../../../lib/setup-apply.mjs.

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { run, wholeFileReport } from "../../../lib/setup-apply.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
run({
  plugin: "discipline",
  provenance: true,
  schema: join(HERE, "..", "..", "..", "schemas", "discipline.schema.json"),
  reader: join(HERE, "parse-concern-value.sh"),
  exactKeyNames: true,
  report: wholeFileReport,
  schemaKey: true,
});
