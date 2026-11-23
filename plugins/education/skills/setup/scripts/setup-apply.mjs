#!/usr/bin/env node

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
