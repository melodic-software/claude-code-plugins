import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { readLayers, resolve } from "./lib/config-cascade.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PLUGIN = "engineering-concepts";
const DEFAULT_HOME = "docs/conventions";
const HOME_TIMEOUT_MS = 15_000;

const readJson = (file) => JSON.parse(readFileSync(file, "utf8"));
const unset = (v) => v === undefined || v === null || v === "" || (typeof v === "string" && v.startsWith("${user_config."));

/** The convention home for `projectRoot`, or null with the reason the repository layers are not read. */
function conventionHome(projectRoot) {
  const r = spawnSync("bash", [join(ROOT, "lib/resolve-convention-home.sh"), "--root", projectRoot], {
    cwd: ROOT,
    encoding: "utf8",
    timeout: HOME_TIMEOUT_MS,
  });
  if (r.status === 0) return { home: r.stdout.trim() };
  if (r.status === 1) return { home: DEFAULT_HOME };
  if (r.status === 4) return { home: null, skipped: "the repository declined a convention home" };
  if (r.status === 5) return { home: null, skipped: "convention home not applicable (outside git, or $HOME or an ancestor of it)" };
  return { home: null, error: r.error?.code || r.stderr?.trim().split("\n").at(-1) || `exit ${r.status}` };
}

/**
 * source_bar and exclude through the ADR 0075 cascade: defaults, userConfig, team file, personal
 * override. source_bar takes the cascade's per-key winner; exclude is the union of every layer.
 * Each rejected value goes to `err` as one JSON line.
 */
export function resolveSettings({ projectRoot, userConfig = {}, userHome, err }) {
  const schema = readJson(join(ROOT, "schemas", `${PLUGIN}.schema.json`));
  const manifest = readJson(join(ROOT, ".claude-plugin", "plugin.json")).userConfig;
  const { exclude: userExclude, ...cascadeUserConfig } = userConfig;
  const located = conventionHome(projectRoot);
  if (located.error) err(JSON.stringify({ level: "warn", event: "convention home unresolved", project: projectRoot, error: located.error }));
  const scratch = located.home === null ? mkdtempSync(join(tmpdir(), `${PLUGIN}-no-home-`)) : null;
  try {
    const home = located.home ?? scratch;
    const out = resolve({
      plugin: PLUGIN,
      projectRoot,
      home,
      schema,
      defaults: { source_bar: manifest.source_bar.default, exclude: [] },
      userConfig: cascadeUserConfig,
      userHome,
    });
    for (const layer of out.layers) {
      for (const error of layer.errors) err(JSON.stringify({ level: "warn", event: "setting rejected", layer: layer.name, path: layer.path, error }));
    }
    const fileLayers = readLayers({ plugin: PLUGIN, projectRoot, home, schema, userConfig: {}, userHome }).layers.filter((l) => l.name !== "userConfig");
    const exclude = new Set([
      ...(unset(userExclude) ? [] : String(userExclude).split(",")),
      ...fileLayers.flatMap((l) => l.values.exclude ?? []),
    ].map((v) => v.trim()).filter(Boolean));
    return { source_bar: out.values.source_bar, exclude: [...exclude] };
  } finally {
    if (scratch) rmSync(scratch, { recursive: true, force: true });
  }
}
