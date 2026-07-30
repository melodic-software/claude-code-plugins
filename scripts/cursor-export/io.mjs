// Write and drift-check Cursor export artifacts.
// Owns filesystem effects only — planning stays in artifacts.mjs.

import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join } from "node:path";
import { stableStringify } from "./json.mjs";
import { rel } from "./paths.mjs";

function listUnderPlugins(repoRoot, relativeFile) {
  const pluginsRoot = join(repoRoot, "plugins");
  if (!existsSync(pluginsRoot)) return [];
  const paths = [];
  for (const entry of readdirSync(pluginsRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const path = join(pluginsRoot, entry.name, relativeFile);
    if (existsSync(path)) paths.push(path);
  }
  return paths.sort();
}

/** Managed Cursor outputs under plugins/ that must match the plan exactly. */
const MANAGED_PLUGIN_RELATIVES = [
  join(".cursor-plugin", "plugin.json"),
  join(".cursor-plugin", "hooks.json"),
  "mcp.json",
];

function removeOrphan(path) {
  rmSync(path);
  const parent = dirname(path);
  if (basename(parent) === ".cursor-plugin") {
    try {
      rmSync(parent);
    } catch {
      // keep siblings (e.g. plugin.json + hooks.json)
    }
  }
}

export function writeCursorExport(repoRoot, writes) {
  for (const [path, data] of writes) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, stableStringify(data));
  }

  for (const relative of MANAGED_PLUGIN_RELATIVES) {
    for (const path of listUnderPlugins(repoRoot, relative)) {
      if (!writes.has(path)) removeOrphan(path);
    }
  }
}

function firstDiffDetail(actual, expected) {
  const max = Math.max(actual.length, expected.length);
  for (let i = 0; i < max; i++) {
    if (actual[i] !== expected[i]) {
      const a = actual.slice(Math.max(0, i - 24), i + 24);
      const e = expected.slice(Math.max(0, i - 24), i + 24);
      return `byte ${i} actual=${JSON.stringify(a)} expected=${JSON.stringify(e)}`;
    }
  }
  return "length-only mismatch";
}

export function checkCursorExport(repoRoot, writes) {
  const errors = [];

  for (const [path, data] of writes) {
    if (!existsSync(path)) {
      errors.push(`missing ${rel(repoRoot, path)}`);
      continue;
    }
    const expected = stableStringify(data);
    const actual = readFileSync(path, "utf8");
    if (actual !== expected) {
      errors.push(
        `${rel(repoRoot, path)} is stale (${firstDiffDetail(actual, expected)})`,
      );
    }
  }

  for (const relative of MANAGED_PLUGIN_RELATIVES) {
    for (const path of listUnderPlugins(repoRoot, relative)) {
      if (!writes.has(path)) {
        errors.push(`unexpected orphan ${rel(repoRoot, path)}`);
      }
    }
  }

  return errors;
}
