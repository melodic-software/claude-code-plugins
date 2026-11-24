#!/usr/bin/env node

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
