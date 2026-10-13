#!/usr/bin/env node
// Write or check the repository layer of the verification plugin's settings,
// docs/conventions/verification.yaml, against schemas/verification.schema.json.
//
// Usage:
//   setup-apply.mjs [--root <dir>] [--yes] <key>=<value> ...
//   setup-apply.mjs [--root <dir>] --check [--ref <ref>]
//
// --ref reads the file as committed at a 40-hex commit id or origin/<name>, so
// proof_level is read from the default branch and a branch cannot lower it.
// The options, guarantees and exit codes are in ../../../lib/setup-apply.mjs.

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { run } from "../../../lib/setup-apply.mjs";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
run({
  plugin: "verification",
  schema: join(PLUGIN, "schemas", "verification.schema.json"),
  reader: join(PLUGIN, "lib", "parse-concern-value.sh"),
  parser: join(PLUGIN, "lib", "yaml-subset.awk"),
  ref: true,
});
