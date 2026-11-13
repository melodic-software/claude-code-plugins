#!/usr/bin/env node
// Write or check the repository layer of the review plugin's settings,
// <home>/review.yaml, against schemas/review.schema.json. <home> is the
// repository's convention home.
//
// --ref reads the file as committed at a 40-hex commit id or origin/<name>, so
// a policy-floor key is read from the default branch and a branch cannot set
// its own. The options, guarantees and exit codes are in
// ../../../lib/setup-apply.mjs.

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
