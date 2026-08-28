#!/usr/bin/env node

// Generates the grouped plugin catalog in docs/CATALOG.md from the manifests,
// per the generation contract in docs/CATALOG-TAXONOMY.md: marketplace.json owns
// each plugin's category and ordering; plugin.json owns each description. The
// block between the catalog markers is generated, never hand-edited. Run with no
// argument to rewrite the block; run with --check to fail on drift (CI gate).

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, sep } from "node:path";
import process from "node:process";

// scripts/lib/report-first-difference.mjs — the drift detail shared with
// scripts/generate-cheatsheet.mjs, whose suite exercises it.
import { reportFirstDifference } from "./lib/report-first-difference.mjs";

const root = join(import.meta.dirname, "..");
const outputPath = join(root, "docs", "CATALOG.md");
const outputLabel = relative(root, outputPath).split(sep).join("/");
const marketplacePath = join(root, ".claude-plugin", "marketplace.json");
const taxonomyPath = join(root, "docs", "CATALOG-TAXONOMY.md");
const taxonomyLabel = relative(root, taxonomyPath).split(sep).join("/");

const START = "<!-- catalog:start -->";
const END = "<!-- catalog:end -->";

// Category render order, conforming to the vocabulary tiers owned by
// docs/CATALOG-TAXONOMY.md (lifecycle spine, then domain-and-cross-cutting).
// The generator conforms to that document; it does not redefine the vocabulary
// — and taxonomyCategories() below holds it to that: the list here is asserted
// equal, in order, to the document's own tables on every run, so editing one
// side without the other fails --check instead of drifting quietly.
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
  "presentation",
  "project-management",
  "operations",
  "learning",
  "music",
  "personal",
];
const KNOWN_CATEGORIES = new Set(CATEGORY_ORDER);

// The document's own statement of the vocabulary: the backticked first column
// of the two tier tables under "## Vocabulary", in document order. This is a
// deliberately narrow parse of a stable shape, not a markdown engine — and it
// FAILS CLOSED on shape: a reworked section that yields no rows, or rows this
// pattern no longer matches, throws rather than returning a shorter list that
// happens to compare equal to a shorter CATEGORY_ORDER.
function taxonomyCategories() {
  const text = readFileSync(taxonomyPath, "utf8");
  const section = text.match(/^## Vocabulary$([\s\S]*?)(?=^## )/m);
  if (!section) {
    throw new Error(
      `${taxonomyLabel}: no "## Vocabulary" section followed by another "## " heading; ` +
        "the taxonomy parity check cannot read the vocabulary it asserts against.",
    );
  }
  const values = [...section[1].matchAll(/^\| `([a-z][a-z0-9-]*)` \|/gm)].map((m) => m[1]);
  if (values.length === 0) {
    throw new Error(
      `${taxonomyLabel}: the "## Vocabulary" section yields no \`category\` table rows; ` +
        "the taxonomy parity check cannot read the vocabulary it asserts against.",
    );
  }
  return values;
}

// One-way gates existed before this: an unknown category in marketplace.json
// hard-errors below, but nothing compared CATEGORY_ORDER back to the document
// that claims sole ownership of the vocabulary. Assert full order equality on
// every run (generate and --check both), so a value added, dropped, renamed,
// or reordered on either side is loud.
{
  const documented = taxonomyCategories();
  if (JSON.stringify(documented) !== JSON.stringify(CATEGORY_ORDER)) {
    throw new Error(
      `CATEGORY_ORDER disagrees with ${taxonomyLabel}'s vocabulary tables.\n` +
        `  document:  ${documented.join(", ")}\n` +
        `  generator: ${CATEGORY_ORDER.join(", ")}\n` +
        `${taxonomyLabel} owns the vocabulary; update CATEGORY_ORDER to match it ` +
        "(or land the taxonomy change there first).",
    );
  }
}

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
  console.error(`Catalog drift: ${outputLabel} catalog block is stale.`);
  console.error(`Run \`node scripts/generate-catalog.mjs\` and commit ${outputLabel}.`);
  reportFirstDifference(expected, existing);
  process.exit(1);
}

if (existing === expected) {
  console.log(`Catalog already in sync; ${outputLabel} unchanged.`);
  process.exit(0);
}
writeFileSync(outputPath, content.replace(existing, expected));
console.log(`Catalog regenerated in ${outputLabel}.`);
