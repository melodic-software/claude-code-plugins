#!/usr/bin/env node

// Generates the grouped plugin catalog in docs/CATALOG.md from the manifests,
// per the generation contract in docs/CATALOG-TAXONOMY.md: marketplace.json owns
// each plugin's category and ordering; plugin.json owns each description. The
// block between the catalog markers is generated, never hand-edited. Run with no
// argument to rewrite the block; run with --check to fail on drift (CI gate).

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, sep } from "node:path";
import process from "node:process";

const root = join(import.meta.dirname, "..");
const outputPath = join(root, "docs", "CATALOG.md");
const outputLabel = relative(root, outputPath).split(sep).join("/");
const marketplacePath = join(root, ".claude-plugin", "marketplace.json");

const START = "<!-- catalog:start -->";
const END = "<!-- catalog:end -->";

// Category render order, conforming to the vocabulary tiers owned by
// docs/CATALOG-TAXONOMY.md (lifecycle spine, then domain-and-cross-cutting).
// The generator conforms to that document; it does not redefine the vocabulary.
const CATEGORY_ORDER = [
  "discovery",
  "design",
  "development",
  "testing",
  "verification",
  "quality",
  "maintenance",
  "deployment",
  "claude-code",
  "autonomy",
  "security",
  "workflow",
  "project-management",
  "operations",
  "learning",
  "music",
  "personal",
];
const KNOWN_CATEGORIES = new Set(CATEGORY_ORDER);

function heading(category) {
  return category
    .split("-")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

function buildBlock() {
  const marketplace = JSON.parse(readFileSync(marketplacePath, "utf8"));

  const byCategory = new Map(CATEGORY_ORDER.map((category) => [category, []]));
  for (const plugin of marketplace.plugins) {
    if (!KNOWN_CATEGORIES.has(plugin.category)) {
      throw new Error(
        `${plugin.name}: category "${plugin.category}" is not in the taxonomy ` +
          "vocabulary (docs/CATALOG-TAXONOMY.md). Add it there and to CATEGORY_ORDER first.",
      );
    }
    const path = plugin.source.replace(/^\.\//, "");
    const manifest = join(root, path, ".claude-plugin", "plugin.json");
    const { description } = JSON.parse(readFileSync(manifest, "utf8"));
    if (!description) throw new Error(`${plugin.name}: plugin.json has no description`);
    // Link relative to the output file's directory, so the rendered links
    // resolve wherever outputPath points.
    const link = relative(dirname(outputPath), join(root, path)).split(sep).join("/");
    byCategory.get(plugin.category).push(`- [\`${plugin.name}\`](${link}) — ${description}`);
  }

  const sections = [];
  for (const category of CATEGORY_ORDER) {
    const items = byCategory.get(category);
    if (items.length === 0) continue; // skip empty categories (e.g. reserved deployment)
    // H2: the categories sit directly under the output page's H1.
    sections.push(`## ${heading(category)}\n\n${items.join("\n")}`);
  }

  return `${START}\n\n${sections.join("\n\n")}\n\n${END}`;
}

function currentBlock(content) {
  const match = content.match(new RegExp(`${START}[\\s\\S]*?${END}`));
  if (!match) {
    throw new Error(
      `${outputLabel} is missing the catalog markers (${START} … ${END}); add them once.`,
    );
  }
  return match[0];
}

const check = process.argv.includes("--check");
const content = readFileSync(outputPath, "utf8");
const expected = buildBlock();
const existing = currentBlock(content);

if (check) {
  if (existing === expected) {
    console.log("Catalog is in sync with the manifests.");
    process.exit(0);
  }
  const expectedLines = expected.split("\n");
  const existingLines = existing.split("\n");
  const at = expectedLines.findIndex((line, i) => line !== existingLines[i]);
  console.error(`Catalog drift: ${outputLabel} catalog block is stale.`);
  console.error(`Run \`node scripts/generate-catalog.mjs\` and commit ${outputLabel}.`);
  if (at !== -1) {
    console.error(`First difference at generated line ${at + 1}:`);
    console.error(`  expected: ${JSON.stringify(expectedLines[at] ?? null)}`);
    console.error(`  found:    ${JSON.stringify(existingLines[at] ?? null)}`);
  }
  process.exit(1);
}

if (existing === expected) {
  console.log(`Catalog already in sync; ${outputLabel} unchanged.`);
  process.exit(0);
}
writeFileSync(outputPath, content.replace(existing, expected));
console.log(`Catalog regenerated in ${outputLabel}.`);
