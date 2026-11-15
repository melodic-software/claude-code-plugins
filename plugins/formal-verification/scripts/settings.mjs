#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { resolve } from "../lib/config-cascade.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const readJson = (file) => JSON.parse(readFileSync(join(root, file), "utf8"));

export const resolveSettings = (projectDir, home = "docs/conventions") =>
  resolve({
    plugin: "formal-verification",
    projectRoot: projectDir,
    home,
    schema: readJson("schemas/formal-verification.schema.json"),
    defaults: readJson("defaults.json"),
  });

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  let options;
  try {
    ({ values: options } = parseArgs({
      options: { "project-dir": { type: "string" }, home: { type: "string" } },
    }));
  } catch (error) {
    console.error(`${error.message}\nusage: settings.mjs [--project-dir DIR] [--home DIR]`);
    process.exit(2);
  }
  const { values, layers } = resolveSettings(options["project-dir"] ?? process.cwd(), options.home);
  for (const layer of layers)
    for (const error of layer.errors ?? []) console.error(`settings: ${error}`);
  process.stdout.write(`${JSON.stringify(values, null, 2)}\n`);
}
