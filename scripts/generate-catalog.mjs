#!/usr/bin/env node

// Generates the grouped plugin catalog in docs/catalog.md from the manifests,
// per the generation contract in docs/catalog-taxonomy.md: marketplace.json owns
// the ordering; plugin.json owns each description and category (metadata.category,
// copied into marketplace.json by scripts/generate-marketplace.mjs). The
// block between the catalog markers is generated, never hand-edited. Run with no
// argument to rewrite the block; run with --check to fail on drift (CI gate).

import { readFileSync } from "node:fs";
import { dirname, join, relative, sep } from "node:path";
import process from "node:process";

// scripts/lib/marker-block.mjs: the locate / compare / report-drift-or-write
// flow shared with scripts/generate-cheatsheet.mjs, whose suite exercises it.
import { findMarkerBlock, markerForms, syncMarkerBlock, wrapMarkerBlock } from "./lib/marker-block.mjs";

// Paths render with forward slashes on every platform, in messages and in
// generated links alike.
function toPosix(path) {
  return path.split(sep).join("/");
}

// CHECK_DATA_ROOT: the tree to check, when it is not the one holding this script.
const root = process.env.CHECK_DATA_ROOT || join(import.meta.dirname, "..");
const outputPath = join(root, "docs", "catalog.md");
const outputLabel = toPosix(relative(root, outputPath));
const marketplacePath = join(root, ".claude-plugin", "marketplace.json");
const taxonomyPath = join(root, "docs", "catalog-taxonomy.md");
const taxonomyLabel = toPosix(relative(root, taxonomyPath));

const FORMS = markerForms("catalog", "Run node scripts/generate-catalog.mjs");

// Category render order, conforming to the vocabulary tiers owned by
// docs/catalog-taxonomy.md (lifecycle spine, then domain-and-cross-cutting).
// Every run (generate and --check) asserts this list equal, in order, to the
// document's own tables, so a value added, dropped, renamed or reordered on
// one side only fails instead of drifting quietly.
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
  "audio",
  "personal",
];

// The document's own statement of the vocabulary: the backticked first column
// of the two tier tables under "## Vocabulary", in document order. A narrow
// parse of a stable shape that FAILS CLOSED: a reworked section that yields no
// rows throws rather than returning a shorter list that happens to compare
// equal to a shorter CATEGORY_ORDER.
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

function buildBody() {
  const marketplace = JSON.parse(readFileSync(marketplacePath, "utf8"));

  const byCategory = new Map(CATEGORY_ORDER.map((category) => [category, []]));
  for (const plugin of marketplace.plugins) {
    if (!byCategory.has(plugin.category)) {
      throw new Error(
        `${plugin.name}: category "${plugin.category}" (plugin.json metadata.category) is not in ` +
          "the taxonomy vocabulary (docs/catalog-taxonomy.md). Add it there and to CATEGORY_ORDER first.",
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

  return sections.join("\n\n");
}

const check = process.argv.includes("--check");
const content = readFileSync(outputPath, "utf8");
const found = findMarkerBlock(content, FORMS);
if (found.error === "missing") {
  throw new Error(
    `${outputLabel} is missing the catalog markers (${FORMS.map((f) => `${f.start} … ${f.end}`).join(" or ")}); add one pair once.`,
  );
}
if (found.error) throw new Error(`${outputLabel} ${found.error}.`);
const existing = found.block;
const wrapped = wrapMarkerBlock(found.form, buildBody(), FORMS);
if (wrapped.error) throw new Error(`${outputLabel} ${wrapped.error}.`);
const expected = wrapped.block;

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
