#!/usr/bin/env node
// Prints the known-issues registry directory as JSON, resolved through the config cascade
// (lib/config-cascade.mjs, ADR 0075): the plugin default, the registry_dir userConfig option, the
// team file <home>/harness-ops.yaml and the personal override <home>/harness-ops.local.yaml, later
// layer winning, <home> from the convention-home pointer line.
//   {"registry_dir": value | null, "layer": "default" | "userConfig" | "team" | "local",
//    "path": the supplying file relative to the project | null,
//    "data_dir": the absolute registry directory | null (null: use the plugin data directory),
//    "home": dir | null, "home_skipped"?: why no repository file is read, "errors": [...]}
// Every layer's value must be made of letters, digits, `.`, `_`, `-`, `/` and `\` only: data_dir is
// pasted into a double-quoted shell argument, where `$(...)`, backticks and quotes would run or break
// out, and a committed file is text from whoever can push to the repository. That is stricter than
// the hooks' rule, which never meets a shell. The value must then be a contained relative path, the
// rule hooks/harness-ops-paths.sh (harness_ops::resolve_project_relative_dir) applies to the hook
// paths: no rooted, drive or UNC path, no `..` segment with either separator, and no existing
// symlink on the way that leads outside its base. A value that fails either rule, or the schema, is
// named with its layer, file, key and value and dropped: an invalid team or userConfig value
// resolves to the default, never to a lower layer, and an invalid personal value leaves the value
// below it standing.
// Usage: registry-dir.mjs [--project DIR] [--user-registry-dir VALUE]
// --project (default: the current directory) is the session's project directory. The userConfig
// value joins to it as given, so a session started in a subdirectory keeps the registry it always
// had; the team and personal files and their values anchor at its git toplevel, where <home> lives.
// --user-registry-dir is the option as the skill renders it; an empty value or an unrendered
// placeholder is unset.
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

/** The git toplevel of `dir`, else `dir`: settings anchor at the repository root, never a subdirectory. */
function gitRoot(dir) {
  const r = spawnSync("git", ["-C", dir, "rev-parse", "--show-toplevel"], { cwd: ROOT, encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : dir;
}
const start = resolvePath(opts.project ?? process.cwd());
const project = resolvePath(gitRoot(start));

/** {home} or {home: null, skipped} from the project's pointer line, as lib/resolve-convention-home.sh reports it. */
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

/** The absolute directory for a value contained in `base`, else null. Checked after SAFE. */
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

/** [data_dir, null] for a usable value, else [null, why it is not]. */
function check(value, base) {
  if (typeof value !== "string" || !SAFE.test(value)) return [null, "holds a character outside letters, digits, . _ - / and \\ (it reaches a shell command)"];
  const dir = contained(value, base);
  return dir ? [dir, null] : [null, "is not a contained relative path (no rooted, drive or UNC path, no .. segment, no symlink leading outside its base)"];
}

const schema = JSON.parse(readFileSync(join(ROOT, "schemas/harness-ops.schema.json"), "utf8"));
const { home, skipped } = conventionHome();
// The scratch directory stands in for the user home (only legacy files are looked up there) and,
// with no usable convention home, for the home itself, so neither repository file is read.
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
  // Errors about this key or about the whole file; other keys belong to other readers.
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
