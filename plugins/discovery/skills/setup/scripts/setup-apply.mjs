#!/usr/bin/env node
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
