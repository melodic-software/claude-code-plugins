#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { resolve } from "../lib/config-cascade.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const readJson = (file) => JSON.parse(readFileSync(join(root, file), "utf8"));

let options;
try {
  ({ values: options } = parseArgs({
    options: { "project-dir": { type: "string" }, home: { type: "string" } },
  }));
} catch (error) {
  console.error(`${error.message}\nusage: settings.mjs [--project-dir DIR] [--home DIR]`);
  process.exit(2);
}

const { values, layers } = resolve({
  plugin: "formal-verification",
  projectRoot: options["project-dir"] ?? process.cwd(),
  home: options.home ?? "docs/conventions",
  schema: readJson("schemas/formal-verification.schema.json"),
  defaults: readJson("defaults.json"),
});
for (const layer of layers)
  for (const error of layer.errors ?? []) console.error(`settings: ${error}`);
process.stdout.write(`${JSON.stringify(values, null, 2)}\n`);
