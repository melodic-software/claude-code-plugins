#!/usr/bin/env node
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { run, wholeFileReport } from "../../../lib/setup-apply.mjs";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

run({
  plugin: "session-flow",
  provenance: true,
  schema: join(PLUGIN, "schemas", "session-flow.schema.json"),
  reader: join(PLUGIN, "skills", "retro", "scripts", "parse-concern-value.sh"),
  report: wholeFileReport,
});
