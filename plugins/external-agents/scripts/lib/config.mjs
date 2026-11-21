import { readFileSync } from "node:fs";
import { dirname, join, posix, win32 } from "node:path";
import { fileURLToPath } from "node:url";
import { resolve } from "../../lib/config-cascade.mjs";

export const pluginRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const readJson = (file) => JSON.parse(readFileSync(join(pluginRoot, file), "utf8"));

export function loadConfig({ projectRoot, home = "docs/conventions", userConfig } = {}) {
  const result = resolve({
    plugin: "external-agents",
    projectRoot,
    home,
    schema: readJson("schemas/external-agents.schema.json"),
    defaults: readJson("defaults.json"),
    userConfig,
  });
  const errors = result.layers.flatMap((layer) => layer.errors ?? []);
  for (const [product, settings] of Object.entries(result.values)) {
    const path = settings?.binary_path;
    if (path === undefined) continue;
    const key = `${product}.binary_path`;
    const why = result.provenance[key] === "team"
      ? "is set only in the personal layer, never a committed team file, since it picks the executable that runs"
      : !(posix.isAbsolute(path) || win32.isAbsolute(path)) && "must be an absolute path";
    if (!why) continue;
    errors.push(`${result.provenance[key]}: ${key} ${why}; ignored`);
    delete settings.binary_path;
    delete result.provenance[key];
  }
  return { values: result.values, provenance: result.provenance, layers: result.layers, errors };
}
