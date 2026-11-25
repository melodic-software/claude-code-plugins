#!/usr/bin/env node
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { run } from "../../../lib/setup-apply.mjs";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
run({
  plugin: "review",
  provenance: true,
  schema: join(PLUGIN, "schemas", "review.schema.json"),
  reader: join(PLUGIN, "lib", "parse-concern-value.sh"),
  ref: true,
});
