#!/usr/bin/env node
// The interview page's repository settings: the `interview_surface` keys of the planning concern,
// resolved through the shared cascade (docs/adr/0075) from <home>/planning.yaml and its personal
// <home>/planning.local.yaml, and printed as one JSON line for interview_server.py. The keys have
// no userConfig option, so that layer contributes nothing; the server applies the plugin default.
//
//   repo_settings.mjs --root <dir>
//     -> {"home", "skipped", "values": {key: value}, "layers": {key: "team" | "personal"},
//         "notes": [text], "watch": [paths whose change means resolve again]}
// Exit 0 resolved (a skipped repository layer included), 2 usage.

import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";
import { resolve } from "../lib/config-cascade.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = join(HERE, "..");
const KEY = "interview_surface";
const DEFAULT_HOME = "docs/conventions";
const LAYER_NAMES = { team: "team", local: "personal" };

function toplevel(root) {
  try {
    return execFileSync("git", ["-C", root, "rev-parse", "--show-toplevel"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  } catch {
    return null;
  }
}

/** The bound convention home ({home}), or why the repository layers are skipped ({skipped}). */
function conventionHome(root) {
  const run = spawnSync("bash", [join(PLUGIN_ROOT, "lib", "resolve-convention-home.sh"), "--root", root], { encoding: "utf8", timeout: 20000 });
  if (run.error) return { skipped: `the convention home could not be resolved (${run.error.message})` };
  if (run.status === 0) return { home: run.stdout.trim() };
  if (run.status === 1 || run.status === 4) return { home: DEFAULT_HOME };
  if (run.status === 5) return { skipped: "the repository is the home directory or above it, so no repository layer applies" };
  const why = (run.stderr || "").trim().split("\n")[0];
  return { skipped: `the convention home did not resolve (exit ${run.status}${why ? `: ${why}` : ""})` };
}

const ours = (dotted) => dotted === KEY || dotted.startsWith(`${KEY}.`);

export function repoSettings(start) {
  const out = { home: null, skipped: null, values: {}, layers: {}, notes: [], watch: [] };
  const root = start && toplevel(start);
  if (!root) {
    out.skipped = "not inside a git working tree, so no repository layer applies";
    return out;
  }
  out.watch.push(join(root, "AGENTS.md"), join(root, "CLAUDE.md"));
  const bound = conventionHome(root);
  if (bound.skipped) {
    out.skipped = bound.skipped;
    out.notes.push(`planning.yaml not read: ${bound.skipped}`);
    return out;
  }
  out.home = bound.home;
  const schema = JSON.parse(readFileSync(join(PLUGIN_ROOT, "schemas", "planning.schema.json"), "utf8"));
  const got = resolve({ plugin: "planning", projectRoot: root, home: bound.home, schema, defaults: {}, userConfig: {} });
  for (const layer of got.layers) {
    if (layer.path) out.watch.push(resolvePath(root, layer.path));
    layer.errors.forEach((error, i) => {
      const key = layer.error_keys[i];
      if (key === null || ours(key)) out.notes.push(error);
    });
  }
  out.watch.push(join(root, bound.home, "planning.yaml"), join(root, bound.home, "planning.local.yaml"));
  for (const [dotted, from] of Object.entries(got.provenance)) {
    if (!dotted.startsWith(`${KEY}.`)) continue;
    const [name, mode] = dotted.slice(KEY.length + 1).split(".");
    const value = mode ? got.values[KEY][name][mode] : got.values[KEY][name];
    if (mode) out.values[name] = { ...(out.values[name] ?? {}), [mode]: value };
    else out.values[name] = value;
    out.layers[mode ? `${name}.${mode}` : name] = LAYER_NAMES[from] ?? from;
  }
  out.watch = [...new Set(out.watch)];
  return out;
}

function main(argv) {
  if (argv.length !== 2 || argv[0] !== "--root") {
    process.stderr.write("usage: repo_settings.mjs --root <dir>\n");
    return 2;
  }
  process.stdout.write(`${JSON.stringify(repoSettings(resolvePath(argv[1])))}\n`);
  return 0;
}

if (process.argv[1] && resolvePath(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
