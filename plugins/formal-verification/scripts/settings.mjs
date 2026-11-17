#!/usr/bin/env node
import { readFileSync, realpathSync } from "node:fs";
import { dirname, join, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { resolve } from "../lib/config-cascade.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const readJson = (file) => JSON.parse(readFileSync(join(root, file), "utf8"));

export const resolveSettings = (projectDir, home = "docs/conventions") => {
  const defaults = readJson("defaults.json");
  const result = resolve({
    plugin: "formal-verification",
    projectRoot: projectDir,
    home,
    schema: readJson("schemas/formal-verification.schema.json"),
    defaults,
  });
  const allowed = new Set(defaults.allowed_modules);
  const modules = result.values.allowed_modules;
  result.values.allowed_modules = modules.filter((m) => allowed.has(m));
  const dropped = modules.filter((m) => !allowed.has(m));
  return { ...result, dropped };
};

export const droppedLine = (dropped) =>
  `settings: allowed_modules: a repository file can only remove modules, so ${dropped.map((m) => JSON.stringify(m)).join(", ")} stays out.`;

const realPath = (p) => {
  try {
    return realpathSync(p);
  } catch {
    return resolvePath(p);
  }
};

if (process.argv[1] && realPath(process.argv[1]) === realPath(fileURLToPath(import.meta.url))) {
  let options;
  try {
    ({ values: options } = parseArgs({
      options: { "project-dir": { type: "string" }, home: { type: "string" } },
    }));
  } catch (error) {
    console.error(`${error.message}\nusage: settings.mjs [--project-dir DIR] [--home DIR]`);
    process.exit(2);
  }
  const { values, layers, dropped } = resolveSettings(options["project-dir"] ?? process.cwd(), options.home);
  for (const layer of layers)
    for (const error of layer.errors ?? []) console.error(`settings: ${error}`);
  if (dropped.length) console.error(droppedLine(dropped));
  process.stdout.write(`${JSON.stringify(values, null, 2)}\n`);
}
