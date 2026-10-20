#!/usr/bin/env node
// Prints the effective glossary file names as JSON, resolved through the config cascade
// (lib/config-cascade.mjs, ADR 0075): the plugin default, userConfig, the team file
// <home>/domain-driven-design.yaml and the personal overlay <home>/domain-driven-design.local.yaml.
//   {"values": {"glossary_file", "glossary_map_file"},
//    "provenance": {key: "default" | "userConfig" | "team" | "local"},
//    "layers": [{name, path, state, errors}], "legacy": [...], "home": dir | null,
//    "home_error"?: why the pointer line is unusable, "home_skipped"?: why no home applies}
// A value must be a file name, never a path: the schema's pattern is checked here because the
// cascade's schema subset has no pattern. A value that fails it is named with its layer, file, key
// and value and dropped from that layer, as the cascade drops any invalid value: an invalid team or
// userConfig value resolves to the default, and an invalid personal value leaves the team value.
// Usage: glossary-settings.mjs [--project DIR] [--home DIR] [--user-config FILE]
// --project defaults to the git root of the current directory; --home is the user home the cascade
// searches for legacy files (a test seam); --user-config is a JSON file of the plugin's userConfig
// values, read as data and never passed to a shell.
import { spawnSync } from "node:child_process";
import { copyFileSync, lstatSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { resolve } from "./lib/config-cascade.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PLUGIN = "domain-driven-design";
const DEFAULT_HOME = "docs/conventions";

const { values: opts } = parseArgs({
  options: {
    project: { type: "string" },
    home: { type: "string", default: homedir() },
    "user-config": { type: "string" },
  },
});

const readJson = (file) => JSON.parse(readFileSync(file, "utf8"));
const schema = readJson(join(ROOT, "schemas/domain-driven-design.schema.json"));
const KEYS = ["glossary_file", "glossary_map_file"];
const defaults = Object.fromEntries(KEYS.map((key) => [key, readJson(join(ROOT, ".claude-plugin/plugin.json")).userConfig[key].default]));
const isFileName = (key, value) => typeof value === "string" && new RegExp(schema.properties[key].pattern, "u").test(value);

/** The git root of `dir`, else `dir` itself: settings anchor at the repository root, never a subdirectory. */
function gitRoot(dir) {
  const r = spawnSync("git", ["-C", dir, "rev-parse", "--show-toplevel"], { encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : dir;
}
const project = resolvePath(opts.project ?? gitRoot(process.cwd()));

/** {home, error?, skipped?} from the project's pointer line, as lib/resolve-convention-home.sh reports it. */
function conventionHome() {
  const r = spawnSync("bash", [join(ROOT, "lib/resolve-convention-home.sh"), "--root", project], { cwd: ROOT, encoding: "utf8", timeout: 15_000 });
  if (r.status === 0) return { home: r.stdout.trim() };
  if (r.status === 1) return { home: DEFAULT_HOME };
  if (r.status === 4) return { home: null, skipped: "the repository declined a convention home; the team and local layers are not read" };
  if (r.status === 5) return { home: null, skipped: "convention home not applicable (the project is $HOME, an ancestor of it, or outside git); the team and local layers are not read" };
  const cause = r.error?.code || r.stderr?.trim().split("\n").at(-1) || `exit ${r.status}`;
  return { home: null, error: `convention home unresolved (${cause}); the team and local layers are not read` };
}

/** The userConfig values from --user-config, with each value that is not a file name dropped and named. */
function userConfig(file) {
  if (!file) return { value: undefined, errors: [] };
  let value;
  try {
    value = readJson(file);
  } catch (e) {
    return { value: undefined, errors: [`userConfig (${file}): unreadable or not JSON (${e.code ?? "parse error"})`] };
  }
  const errors = [];
  const kept = {};
  for (const [key, v] of Object.entries(value ?? {})) {
    const unset = v === "" || v === null || (typeof v === "string" && v.startsWith("${user_config."));
    if (KEYS.includes(key) && !unset && !isFileName(key, v)) errors.push(`userConfig (${file}): "${key}": ${JSON.stringify(v)} is not a file name; a value names a file, never a path`);
    else kept[key] = v;
  }
  return { value: kept, errors };
}

const scratch = mkdtempSync(join(tmpdir(), "ddd-settings-"));
try {
  const { home, error, skipped } = conventionHome();
  const user = userConfig(opts["user-config"]);
  const run = (homeDir) => resolve({ plugin: PLUGIN, projectRoot: project, home: homeDir, schema, defaults, userConfig: user.value, userHome: opts.home });
  // With no usable home, an empty scratch directory stands in, so neither repository layer is read.
  const out = run(home ?? scratch);
  const layer = (name) => out.layers.find((l) => l.name === name);
  if (user.errors.length) Object.assign(layer("userConfig"), { state: "invalid", errors: [...layer("userConfig").errors, ...user.errors] });
  if (home === null) for (const name of ["team", "local"]) layer(name).path = null;

  // The cascade without the personal overlay: the team file alone, copied only when the cascade read
  // it (a regular file in a home inside the project), so each team value can be checked on its own.
  let withoutLocal = out;
  if (home !== null) {
    const dir = mkdtempSync(join(scratch, "team-"));
    const team = join(resolvePath(project, home), `${PLUGIN}.yaml`);
    const read = lstatSync(team, { throwIfNoEntry: false })?.isFile() && !layer("team").errors.some((e) => e.includes("outside the project"));
    if (read) copyFileSync(team, join(dir, `${PLUGIN}.yaml`));
    withoutLocal = run(dir);
  }

  const values = {};
  const provenance = {};
  for (const key of KEYS) {
    const fail = (name, v) => {
      const l = layer(name);
      l.state = "invalid";
      l.errors.push(`${name} (${l.path}): "${key}": ${JSON.stringify(v)} is not a file name; a value names a file, never a path`);
    };
    const below = { value: withoutLocal.values[key], from: withoutLocal.provenance[key] };
    if (below.from === "team" && !isFileName(key, below.value)) {
      fail("team", below.value);
      Object.assign(below, { value: defaults[key], from: "defaults" });
    }
    const local = out.provenance[key] === "local" ? out.values[key] : undefined;
    if (local !== undefined && !isFileName(key, local)) fail("local", local);
    const { value, from } = local !== undefined && isFileName(key, local) ? { value: local, from: "local" } : below;
    values[key] = value;
    provenance[key] = from === "defaults" ? "default" : from;
  }
  console.log(JSON.stringify({ values, provenance, layers: out.layers, legacy: out.legacy, home, ...(error && { home_error: error }), ...(skipped && { home_skipped: skipped }) }));
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
