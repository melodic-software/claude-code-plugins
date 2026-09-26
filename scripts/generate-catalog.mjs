#!/usr/bin/env node

// Generates the grouped plugin catalog in docs/catalog.md from the manifests,
// per the generation contract in docs/catalog-taxonomy.md: marketplace.json owns
// each plugin's category and ordering; plugin.json owns each description. The
// block between the catalog markers is generated, never hand-edited. Run with no
// argument to rewrite the block; run with --check to fail on drift (CI gate).

import { readFileSync } from "node:fs";
import { dirname, join, relative, sep } from "node:path";
import process from "node:process";

// scripts/lib/marker-block.mjs: the locate / compare / report-drift-or-write
// flow shared with scripts/generate-cheatsheet.mjs, whose suite exercises it.
import { findMarkerBlock, syncMarkerBlock } from "./lib/marker-block.mjs";

// Paths render with forward slashes on every platform, in messages and in
// generated links alike.
function toPosix(path) {
  return path.split(sep).join("/");
}

const root = join(import.meta.dirname, "..");
const outputPath = join(root, "docs", "catalog.md");
const outputLabel = toPosix(relative(root, outputPath));
const marketplacePath = join(root, ".claude-plugin", "marketplace.json");
const taxonomyPath = join(root, "docs", "catalog-taxonomy.md");
const taxonomyLabel = toPosix(relative(root, taxonomyPath));

const START = "<!-- catalog:start -->";
const END = "<!-- catalog:end -->";

// Category render order, conforming to the vocabulary tiers owned by
// docs/catalog-taxonomy.md (lifecycle spine, then domain-and-cross-cutting).
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
  "visual-arts",
  "music",
  "personal",
];

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

// An unknown category in marketplace.json hard-errors below, but that gate is
// one-way: it never compares CATEGORY_ORDER back to the document that claims
// sole ownership of the vocabulary. Assert full order equality on
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
    if (!byCategory.has(plugin.category)) {
      throw new Error(
        `${plugin.name}: category "${plugin.category}" is not in the taxonomy ` +
          "vocabulary (docs/catalog-taxonomy.md). Add it there and to CATEGORY_ORDER first.",
      );
    }
    const path = plugin.source.replace(/^\.\//, "");
    const manifest = join(root, path, ".claude-plugin", "plugin.json");
    const { description } = JSON.parse(readFileSync(manifest, "utf8"));
    if (!description) throw new Error(`${plugin.name}: plugin.json has no description`);
    // Link relative to the output file's directory, so the rendered links
    // resolve wherever outputPath points.
    const link = toPosix(relative(dirname(outputPath), join(root, path)));
    byCategory.get(plugin.category).push(`- [\`${plugin.name}\`](${link}): ${description}`);
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
  const block = findMarkerBlock(content, START, END);
  if (block === null) {
    throw new Error(
      `${outputLabel} is missing the catalog markers (${START} … ${END}); add them once.`,
    );
  }
  return block;
}

const check = process.argv.includes("--check");
const content = readFileSync(outputPath, "utf8");
const expected = buildBlock();
const existing = currentBlock(content);

syncMarkerBlock({
  path: outputPath,
  content,
  existing,
  expected,
  check,
  messages: {
    inSync: "Catalog is in sync with the manifests.",
    drift: `Catalog drift: ${outputLabel} catalog block is stale.`,
    rerun: `Run \`node scripts/generate-catalog.mjs\` and commit ${outputLabel}.`,
    unchanged: `Catalog already in sync; ${outputLabel} unchanged.`,
    regenerated: `Catalog regenerated in ${outputLabel}.`,
  },
});
