#!/usr/bin/env node
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { run } from "../../../lib/setup-apply.mjs";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

function report({ rel, keys, problems, value }) {
  const parseError = problems.some((p) => p.kind === "parse");
  const badKeys = new Set(problems.map((p) => p.key));
  const out = problems.map((p) => `WARN ${rel}: ${p.msg}\n`);
  for (const k of Object.keys(keys)) {
    if (parseError || badKeys.has(k)) {
      out.push(`WARN ${k}: dropped from ${rel}; resolves to its default, ${keys[k].default}, not to userConfig\n`);
    } else {
      out.push(`PASS ${k}: ${value(k) || "(unset)"}\n`);
    }
  }
  process.stdout.write(out.join(""));
  return problems.length ? 1 : 0;
}

run({
  plugin: "docs-hygiene",
  provenance: true,
  schema: join(PLUGIN, "schemas", "docs-hygiene.schema.json"),
  reader: join(PLUGIN, "lib", "parse-concern-value.sh"),
  fixedTemp: true,
  report,
});
