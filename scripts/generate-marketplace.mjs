#!/usr/bin/env node

// Generates each plugin entry's `category` and `tags` in
// .claude-plugin/marketplace.json from that plugin's own
// .claude-plugin/plugin.json: `metadata.category` and `keywords`. Plugin facts
// live in plugin files; plugin.json cannot carry `category` or `tags` itself, so
// the marketplace entry is their published copy. Entry order, `name`, `source`,
// `relevance` and `defaultEnabled` stay owned by marketplace.json
// (validate-plugin-contracts.mjs forbids defaultEnabled in plugin.json). Run with
// no argument to rewrite the file; run with --check to fail on drift (CI gate).

import { readFileSync } from "node:fs";
import { join, relative, sep } from "node:path";
import process from "node:process";

// The compare / report-drift-or-write flow shared with the catalog and
// cheat-sheet generators; here the whole file is the generated block.
import { syncMarkerBlock } from "./lib/marker-block.mjs";

// CHECK_DATA_ROOT: the tree to check, when it is not the one holding this script.
const root = process.env.CHECK_DATA_ROOT || join(import.meta.dirname, "..");
const outputPath = join(root, ".claude-plugin", "marketplace.json");
const outputLabel = relative(root, outputPath).split(sep).join("/");

function buildEntry(entry) {
  const manifestPath = join(root, entry.source, ".claude-plugin", "plugin.json");
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  if (manifest.name !== entry.name) {
    throw new Error(`${entry.name}: plugin.json at ${entry.source} names "${manifest.name}"`);
  }
  const category = manifest.metadata?.category;
  if (typeof category !== "string" || category === "") {
    throw new Error(`${entry.name}: plugin.json has no metadata.category`);
  }
  const { keywords } = manifest;
  if (!Array.isArray(keywords) || keywords.length === 0) {
    throw new Error(`${entry.name}: plugin.json has no keywords`);
  }
  // Spread first so every key keeps its place in the entry.
  return { ...entry, category, tags: keywords };
}

const check = process.argv.includes("--check");
const content = readFileSync(outputPath, "utf8");
const marketplace = JSON.parse(content);
const expected = `${JSON.stringify({ ...marketplace, plugins: marketplace.plugins.map(buildEntry) }, null, 2)}\n`;

syncMarkerBlock({
  path: outputPath,
  content,
  existing: content,
  expected,
  check,
  messages: {
    inSync: "Marketplace entries are in sync with the plugin manifests.",
    drift: `Marketplace drift: ${outputLabel} differs from what the plugin manifests produce.`,
    rerun: `Run \`node scripts/generate-marketplace.mjs\` and commit ${outputLabel}.`,
    unchanged: `Marketplace already in sync; ${outputLabel} unchanged.`,
    regenerated: `Marketplace entries regenerated in ${outputLabel}.`,
  },
});
