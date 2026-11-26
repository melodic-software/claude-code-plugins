#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { join, relative, sep } from "node:path";
import process from "node:process";

import { syncMarkerBlock } from "./lib/marker-block.mjs";

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
