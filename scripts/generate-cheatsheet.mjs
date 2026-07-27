#!/usr/bin/env node

// Generates the stage-grouped skill cheat sheet block in
// docs/SKILL-CHEAT-SHEET.md from each in-scope SKILL.md's `metadata:`
// frontmatter (`cheatsheet-stage`, `cheatsheet-summary`, `cheatsheet-cadence`)
// plus the hand-curated grouping layer in scripts/cheatsheet-config.mjs.
// Sibling of generate-catalog.mjs: the block between the markers is
// generated, never hand-edited; run with no argument to rewrite it, with
// --check to fail on drift (CI gate). --root <dir> points every input and the
// output at another tree so a fixture can drive the enforcement tests.
//
// Enforcement (each failure exits 1 naming the skill): an in-scope skill must
// carry `cheatsheet-stage` XOR match an exclusion entry; exclusion entries
// must name existing plugins/skills; stage and cadence values must be in the
// config enums; `cheatsheet-cadence` is required with `cheatsheet-stage:
// operator` and forbidden otherwise; summaries must pass the shared guard
// (plain YAML scalar, <=100 codepoints). Swept values are plain scalars —
// this reader strips trailing `#`-comments exactly as skill-quality's
// skill_frontmatter::metadata_field does, so both consumers see one value.

import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import process from "node:process";

const argv = process.argv.slice(2);
const check = argv.includes("--check");
const rootFlag = argv.indexOf("--root");
const root =
  rootFlag !== -1 ? argv[rootFlag + 1] : join(import.meta.dirname, "..");
if (rootFlag !== -1 && (!root || root.startsWith("--"))) {
  fail(["--root requires a directory argument"]);
}

const OUTPUT_PATH = join(root, "docs", "SKILL-CHEAT-SHEET.md");
const START = "<!-- cheatsheet:start -->";
const END = "<!-- cheatsheet:end -->";

const config = await import(
  pathToFileURL(join(root, "scripts", "cheatsheet-config.mjs")).href
);
const {
  STAGES, CADENCES, EXCLUDED_PLUGINS, EXCLUDED_SKILL_NAME, EXCLUDED_SKILLS,
  summaryError,
} = config;
const stageBySlug = new Map(STAGES.map((s) => [s.slug, s]));

function fail(messages) {
  for (const m of messages) console.error(`generate-cheatsheet: ${m}`);
  process.exit(1);
}

// --- Inventory: exact-depth glob plugins/*/skills/*/SKILL.md ---------------

function listDirs(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => e.name)
    .sort();
}

const skills = []; // { plugin, skill, path, meta }
for (const plugin of listDirs(join(root, "plugins"))) {
  for (const skill of listDirs(join(root, "plugins", plugin, "skills"))) {
    const path = join(root, "plugins", plugin, "skills", skill, "SKILL.md");
    if (!existsSync(path)) continue;
    skills.push({ plugin, skill, path, meta: readCheatsheetMeta(path) });
  }
}

// Minimal frontmatter reader (native, no deps — repo precedent: the catalog
// generator uses JSON.parse only). Frontmatter is the block between a line-1
// `---` fence and the next `---` fence; `metadata:` sits at column 0 with its
// keys indented one level.
function readCheatsheetMeta(path) {
  const lines = readFileSync(path, "utf8").split(/\r?\n/);
  if (lines[0]?.trim() !== "---") return {};
  const fm = [];
  for (let i = 1; i < lines.length; i++) {
    if (lines[i].trim() === "---") break;
    fm.push(lines[i]);
  }
  const meta = {};
  let inMetadata = false;
  for (const line of fm) {
    if (/^metadata:\s*$/.test(line)) {
      inMetadata = true;
      continue;
    }
    if (inMetadata) {
      // A blank line inside the block does not end it — the shell reader
      // (skill_frontmatter::metadata_field) matches indented keys anywhere in
      // the frontmatter, so ending here would silently diverge from it.
      if (line.trim() === "") continue;
      if (!/^\s/.test(line)) {
        inMetadata = false;
        continue;
      }
      const m = line.match(/^\s+([A-Za-z0-9-]+):\s*(.*)$/);
      if (!m) continue;
      // Trailing-comment strip mirrors skill_frontmatter::metadata_field.
      meta[m[1]] = m[2].replace(/\s+#.*$/, "").trim();
    }
  }
  return meta;
}

// --- Enforcement ------------------------------------------------------------

const errors = [];
const bySkillKey = new Set(skills.map((s) => `${s.plugin}/${s.skill}`));
const pluginDirs = new Set(skills.map((s) => s.plugin));

for (const name of EXCLUDED_PLUGINS.keys()) {
  if (!pluginDirs.has(name)) {
    errors.push(`orphaned exclusion: plugin "${name}" has no skills in the tree`);
  }
}
for (const key of EXCLUDED_SKILLS.keys()) {
  if (!bySkillKey.has(key)) {
    errors.push(`orphaned exclusion: skill "${key}" does not exist`);
  }
}

const mapped = [];
for (const s of skills) {
  const key = `${s.plugin}/${s.skill}`;
  const reason =
    EXCLUDED_PLUGINS.get(s.plugin) ??
    EXCLUDED_SKILLS.get(key) ??
    (s.skill === EXCLUDED_SKILL_NAME.name ? EXCLUDED_SKILL_NAME.reason : undefined);
  const stage = s.meta["cheatsheet-stage"];
  const summary = s.meta["cheatsheet-summary"];
  const cadence = s.meta["cheatsheet-cadence"];

  if (reason !== undefined) {
    if (stage !== undefined || summary !== undefined || cadence !== undefined) {
      errors.push(`${key}: excluded (${reason}) but carries cheatsheet-* metadata`);
    }
    continue;
  }
  if (stage === undefined) {
    errors.push(`${key}: no cheatsheet-stage and no exclusion entry`);
    continue;
  }
  if (!stageBySlug.has(stage)) {
    errors.push(`${key}: unknown cheatsheet-stage "${stage}"`);
    continue;
  }
  if (stage === "operator") {
    if (cadence === undefined) {
      errors.push(`${key}: cheatsheet-stage operator requires cheatsheet-cadence`);
    } else if (!CADENCES.includes(cadence)) {
      errors.push(`${key}: unknown cheatsheet-cadence "${cadence}"`);
    }
  } else if (cadence !== undefined) {
    errors.push(`${key}: cheatsheet-cadence is only valid with cheatsheet-stage operator`);
  }
  const guardError = summaryError(summary ?? "");
  if (guardError) errors.push(`${key}: ${guardError}`);
  mapped.push({ ...s, stage, summary, cadence });
}

if (errors.length > 0) fail(errors);

// --- Spine-drift assertion ---------------------------------------------------
// Each workflow-stage heading must prefix-match its H2 in the session-flow
// workflow stage definitions, same order — a stage rename upstream fails this
// gate instead of silently stranding the copy.

const stepsPath = join(
  root, "plugins", "session-flow", "skills", "workflow", "context", "steps.md",
);
if (!existsSync(stepsPath)) fail([`spine source missing: ${stepsPath}`]);
const stepHeadings = readFileSync(stepsPath, "utf8")
  .split(/\r?\n/)
  .filter((l) => l.startsWith("## "))
  .map((l) => l.slice(3).trim());
const workflowStages = STAGES.filter((s) => s.workflow);
const spineErrors = [];
if (stepHeadings.length !== workflowStages.length) {
  spineErrors.push(
    `spine drift: ${workflowStages.length} workflow stages in config, ` +
      `${stepHeadings.length} H2 headings in steps.md`,
  );
} else {
  workflowStages.forEach((s, i) => {
    if (!stepHeadings[i].startsWith(s.heading)) {
      spineErrors.push(
        `spine drift: config heading "${s.heading}" does not prefix-match ` +
          `steps.md H2 "${stepHeadings[i]}"`,
      );
    }
  });
}
if (spineErrors.length > 0) fail(spineErrors);

// --- Render -------------------------------------------------------------------

const marketplacePath = join(root, ".claude-plugin", "marketplace.json");
const marketplace = JSON.parse(readFileSync(marketplacePath, "utf8"));
const installName = new Map(
  marketplace.plugins.map((p) => [p.source.replace(/^\.\//, "").replace(/^plugins\//, ""), p.name]),
);
for (const s of mapped) {
  if (!installName.has(s.plugin)) {
    errors.push(`${s.plugin}: not listed in marketplace.json (no install identifier)`);
  }
}
if (errors.length > 0) fail(errors);

// GitHub's GFM heading slugger: lowercase, drop everything but word
// characters / spaces / hyphens, then spaces become hyphens. The offline
// lychee lane resolves these anchors with include_fragments, so this must
// match GitHub exactly for the heading shapes used here.
function slugify(heading) {
  return heading
    .toLowerCase()
    .replace(/[^a-z0-9 _-]/g, "")
    .replace(/ /g, "-");
}

function cell(text) {
  return text.replace(/\|/g, "&#124;");
}

const sections = [];
const toc = [];
for (const stage of STAGES) {
  const rows = mapped
    .filter((s) => s.stage === stage.slug)
    .sort((a, b) => a.plugin.localeCompare(b.plugin) || a.skill.localeCompare(b.skill));
  if (rows.length === 0) continue;
  toc.push(`- [${stage.heading}](#${slugify(stage.heading)})`);
  const operator = stage.slug === "operator";
  const header = operator
    ? "| Skill | Plugin | Cadence | What it does |\n| --- | --- | --- | --- |"
    : "| Skill | Plugin | What it does |\n| --- | --- | --- |";
  const body = rows
    .map((s) => {
      const link = `[\`/${s.plugin}:${s.skill}\`](../plugins/${s.plugin}/skills/${s.skill}/SKILL.md)`;
      const id = `\`${installName.get(s.plugin)}\``;
      return operator
        ? `| ${link} | ${id} | ${s.cadence} | ${cell(s.summary)} |`
        : `| ${link} | ${id} | ${cell(s.summary)} |`;
    })
    .join("\n");
  sections.push(`## ${stage.heading}\n\n${header}\n${body}`);
}

const block = `${START}\n\n${toc.join("\n")}\n\n${sections.join("\n\n")}\n\n${END}`;

// --- Write / check -------------------------------------------------------------

if (!existsSync(OUTPUT_PATH)) {
  fail([`${OUTPUT_PATH} is missing; create it once with the markers (${START} ... ${END})`]);
}
const sheet = readFileSync(OUTPUT_PATH, "utf8");
const match = sheet.match(new RegExp(`${START}[\\s\\S]*?${END}`));
if (!match) {
  fail([`${OUTPUT_PATH} is missing the cheatsheet markers (${START} ... ${END})`]);
}
const existing = match[0];

if (check) {
  if (existing === block) {
    console.log("Cheat sheet is in sync with skill frontmatter.");
    process.exit(0);
  }
  const expectedLines = block.split("\n");
  const existingLines = existing.split("\n");
  const at = expectedLines.findIndex((line, i) => line !== existingLines[i]);
  console.error("Cheat sheet drift: docs/SKILL-CHEAT-SHEET.md block is stale.");
  console.error("Run `node scripts/generate-cheatsheet.mjs` and commit the sheet.");
  if (at !== -1) {
    console.error(`First difference at generated line ${at + 1}:`);
    console.error(`  expected: ${JSON.stringify(expectedLines[at] ?? null)}`);
    console.error(`  found:    ${JSON.stringify(existingLines[at] ?? null)}`);
  }
  process.exit(1);
}

if (existing === block) {
  console.log("Cheat sheet already in sync; output unchanged.");
  process.exit(0);
}
writeFileSync(OUTPUT_PATH, sheet.replace(existing, block));
console.log(`Cheat sheet regenerated (${mapped.length} skills).`);
