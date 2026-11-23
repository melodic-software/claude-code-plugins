#!/usr/bin/env node
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

const STDIN_FD = 0;
const readJson = (file) => JSON.parse(readFileSync(file, "utf8"));
const readNameValueLines = (fd) =>
  Object.fromEntries(
    readFileSync(fd, "utf8")
      .split(/\r?\n/u)
      .filter((line) => line.includes("="))
      .map((line) => [line.slice(0, line.indexOf("=")), line.slice(line.indexOf("=") + 1)]),
  );
const schema = readJson(join(ROOT, "schemas/domain-driven-design.schema.json"));
const KEYS = ["glossary_file", "glossary_map_file"];
const manifestConfig = readJson(join(ROOT, ".claude-plugin/plugin.json")).userConfig;
const defaults = Object.fromEntries(KEYS.map((key) => [key, manifestConfig[key].default]));
const isFileName = (key, value) => typeof value === "string" && new RegExp(schema.properties[key].pattern, "u").test(value);
const notFileName = (key, value) => `"${key}": ${JSON.stringify(value)} is not a file name; a value names a file, never a path`;

function gitRoot(dir) {
  const r = spawnSync("git", ["-C", dir, "rev-parse", "--show-toplevel"], { cwd: ROOT, encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : dir;
}
const project = resolvePath(opts.project ?? gitRoot(process.cwd()));

function conventionHome() {
  const r = spawnSync("bash", [join(ROOT, "lib/resolve-convention-home.sh"), "--root", project], { cwd: ROOT, encoding: "utf8", timeout: 15_000 });
  if (r.status === 0) return { home: r.stdout.trim() };
  if (r.status === 1) return { home: DEFAULT_HOME };
  if (r.status === 4) return { home: null, skipped: "the repository declined a convention home; the team and local layers are not read" };
  if (r.status === 5) return { home: null, skipped: "convention home not applicable (the project is $HOME, an ancestor of it, or outside git); the team and local layers are not read" };
  const cause = r.error?.code || r.stderr?.trim().split("\n").at(-1) || `exit ${r.status}`;
  return { home: null, error: `convention home unresolved (${cause}); the team and local layers are not read` };
}

function userConfig(file) {
  if (!file) return { value: undefined, errors: [], keys: [] };
  let value;
  try {
    value = file === "-" ? readNameValueLines(STDIN_FD) : readJson(file);
  } catch (e) {
    return { value: undefined, errors: [`userConfig (${file}): unreadable or not JSON (${e.code ?? "parse error"})`], keys: [null] };
  }
  const errors = [];
  const keys = [];
  const kept = {};
  for (const [key, v] of Object.entries(value ?? {})) {
    const unset = v === "" || v === null || (typeof v === "string" && v.startsWith("${user_config."));
    if (KEYS.includes(key) && !unset && !isFileName(key, v)) {
      errors.push(`userConfig (${file}): ${notFileName(key, v)}`);
      keys.push(key);
    } else kept[key] = v;
  }
  return { value: kept, errors, keys };
}

const scratch = mkdtempSync(join(tmpdir(), "ddd-settings-"));
try {
  const { home, error, skipped } = conventionHome();
  const user = userConfig(opts["user-config"]);
  const run = (homeDir) => resolve({ plugin: PLUGIN, projectRoot: project, home: homeDir, schema, defaults, userConfig: user.value, userHome: opts.home });
  const out = run(home ?? scratch);
  const layer = (name) => out.layers.find((l) => l.name === name);
  if (user.errors.length) {
    const u = layer("userConfig");
    Object.assign(u, { state: "invalid", errors: [...u.errors, ...user.errors], error_keys: [...u.error_keys, ...user.keys] });
  }
  if (home === null) for (const name of ["team", "local"]) layer(name).path = null;

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
      l.errors.push(`${name} (${l.path}): ${notFileName(key, v)}`);
      l.error_keys.push(key);
    };
    const below = { value: withoutLocal.values[key], from: withoutLocal.provenance[key] };
    if (below.from === "team" && !isFileName(key, below.value)) {
      fail("team", below.value);
      Object.assign(below, { value: defaults[key], from: "defaults" });
    }
    const local = out.provenance[key] === "local" ? out.values[key] : undefined;
    const localOk = isFileName(key, local);
    if (local !== undefined && !localOk) fail("local", local);
    const { value, from } = localOk ? { value: local, from: "local" } : below;
    values[key] = value;
    provenance[key] = from === "defaults" ? "default" : from;
  }
  console.log(JSON.stringify({ values, provenance, layers: out.layers, legacy: out.legacy, home, ...(error && { home_error: error }), ...(skipped && { home_skipped: skipped }) }));
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
