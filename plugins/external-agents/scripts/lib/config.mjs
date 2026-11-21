import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join, posix, win32 } from "node:path";
import { fileURLToPath } from "node:url";
import { resolve } from "../../lib/config-cascade.mjs";

export const pluginRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const readJson = (file) => JSON.parse(readFileSync(join(pluginRoot, file), "utf8"));

const HELPER_FAIL = 3;

/** The convention home the repository's pointer region binds; an unbound repository gets the default. */
export function conventionHome(projectRoot) {
  const done = spawnSync("bash", [join(pluginRoot, "lib", "resolve-convention-home.sh"), "--root", projectRoot], { cwd: pluginRoot, encoding: "utf8", timeout: 15_000, windowsHide: true });
  if (done.status === 0 && done.stdout.trim()) return { home: done.stdout.trim(), problem: null };
  return { home: "docs/conventions", problem: done.status === HELPER_FAIL ? done.stderr.trim() : null };
}

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
