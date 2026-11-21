import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
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
  return { values: result.values, provenance: result.provenance, layers: result.layers, errors };
}
