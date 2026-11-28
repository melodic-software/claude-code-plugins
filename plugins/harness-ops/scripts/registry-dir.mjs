#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve as resolvePath, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { readLayers } from "../lib/config-cascade.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PLUGIN = "harness-ops";
const KEY = "registry_dir";
const DEFAULT_HOME = "docs/conventions";

let opts;
try {
  ({ values: opts } = parseArgs({ options: { project: { type: "string" }, "user-registry-dir": { type: "string" } } }));
} catch {
  process.stderr.write("usage: registry-dir.mjs [--project DIR] [--user-registry-dir VALUE]\n");
  process.exit(2);
}

function gitRoot(dir) {
  const r = spawnSync("git", ["-C", dir, "rev-parse", "--show-toplevel"], { cwd: ROOT, encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : dir;
}
const start = resolvePath(opts.project ?? process.cwd());
const project = resolvePath(gitRoot(start));

function conventionHome() {
  const r = spawnSync("bash", [join(ROOT, "lib/resolve-convention-home.sh"), "--root", project], { cwd: ROOT, encoding: "utf8", timeout: 15_000 });
  if (r.status === 0) return { home: r.stdout.trim() };
  if (r.status === 1) return { home: DEFAULT_HOME };
  if (r.status === 4) return { home: null, skipped: "the repository declined a convention home; the team and personal files are not read" };
  if (r.status === 5) return { home: null, skipped: "no convention home applies (the project is $HOME, an ancestor of it, or not a git work tree); the team and personal files are not read" };
  const cause = r.error?.code || r.stderr?.trim().split("\n").at(-1) || `exit ${r.status}`;
  return { home: null, skipped: `the convention home is unresolved (${cause}); the team and personal files are not read` };
}

const inside = (child, parent) => child === parent || child.startsWith(parent.endsWith(sep) ? parent : parent + sep);

const SAFE = /^[A-Za-z0-9._/\\-]+$/;

function contained(value, base) {
  const normalized = value.replaceAll("\\", "/");
  if (normalized.startsWith("/") || /^[A-Za-z]:/.test(normalized)) return null;
  if (normalized.split("/").includes("..")) return null;
  const candidate = join(base, normalized);
  let ancestor = candidate;
  while (!existsSync(ancestor) && dirname(ancestor) !== ancestor) ancestor = dirname(ancestor);
  try {
    return inside(realpathSync(ancestor), realpathSync(base)) ? candidate : null;
  } catch {
    return null;
  }
}

function check(value, base) {
  if (typeof value !== "string" || !SAFE.test(value)) return [null, "holds a character outside letters, digits, . _ - / and \\ (it reaches a shell command)"];
  const dir = contained(value, base);
  return dir ? [dir, null] : [null, "is not a contained relative path (no rooted, drive or UNC path, no .. segment, no symlink leading outside its base)"];
}

const schema = JSON.parse(readFileSync(join(ROOT, "schemas/harness-ops.schema.json"), "utf8"));
const { home, skipped } = conventionHome();
const scratch = mkdtempSync(join(tmpdir(), "harness-ops-registry-dir-"));
let layers;
try {
  const userConfig = opts["user-registry-dir"] === undefined ? undefined : { [KEY]: opts["user-registry-dir"] };
  ({ layers } = readLayers({ plugin: PLUGIN, projectRoot: project, home: home ?? scratch, schema, userConfig, userHome: scratch }));
} finally {
  rmSync(scratch, { recursive: true, force: true });
}

const DEFAULT = { registry_dir: null, layer: "default", path: null, data_dir: null };
const errors = [];
let result = DEFAULT;
for (const layer of layers) {
  const path = home === null || !layer.path ? null : relative(project, layer.path);
  layer.errors.forEach((e, i) => [KEY, null].includes(layer.error_keys[i]) && errors.push(e));
  const value = layer.values[KEY];
  let invalid = layer.error_keys.includes(KEY);
  let dir = null;
  if (value !== undefined && !invalid) {
    let why;
    [dir, why] = check(value, layer.name === "userConfig" ? start : project);
    if (why) {
      errors.push(`${layer.name}${path ? ` (${layer.path})` : ""}: "${KEY}": ${JSON.stringify(value)} ${why}`);
      invalid = true;
    }
  }
  if (invalid) {
    if (layer.name !== "local") result = DEFAULT;
  } else if (value !== undefined) result = { registry_dir: value, layer: layer.name, path, data_dir: dir };
}
console.log(JSON.stringify({ ...result, home, ...(skipped && { home_skipped: skipped }), errors }));
