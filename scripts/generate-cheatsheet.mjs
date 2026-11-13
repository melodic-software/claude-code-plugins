#!/usr/bin/env node

// Generates the stage-grouped skill cheat sheet block in
// docs/skill-cheat-sheet.md from each in-scope SKILL.md's `metadata:`
// frontmatter (`workflow-stage`, `summary`, `cadence`) and top-level
// `argument-hint`, the hand-curated grouping layer in
// scripts/cheatsheet-config.mjs, the "Task kinds" table in the session-flow
// workflow's steps.md (the "By kind of task" view joins it with each stage's
// command), and the attribution tables of the upstream records the config
// names (the Upstream column).
// Sibling of generate-catalog.mjs: the block between the markers is
// generated, never hand-edited; run with no argument to rewrite it, with
// --check to fail on drift (CI gate). --root <dir> points every input and the
// output at another tree so a fixture can drive the enforcement tests.
//
// Enforcement (each failure exits 1 naming the skill): an in-scope skill must
// carry `workflow-stage` XOR match an exclusion entry; exclusion entries
// must name existing plugins/skills; stage and cadence values must be in the
// config enums; `cadence` is required with `workflow-stage:
// operator` and forbidden otherwise; summaries must pass the shared guard
// (plain YAML scalar, <=100 codepoints); a Task kinds row must name only
// stages steps.md defines, each once; every stage a row runs or calls needs a
// STAGE_COMMANDS entry naming mapped skills; each RUNS_FOR_YOU cite must sit
// on exactly one line of the file it cites. Swept values are plain scalars, and
// this reader takes the literal text after the key: it strips a trailing
// `#`-comment but never strips quotes, because a quoted value is a rejection
// here rather than a value to unwrap. skill-quality's
// skill_frontmatter::metadata_field reads the same way, and
// scripts/check-summary-reader-parity.test.sh holds the two readers to one
// value on a shared case table and on every SKILL.md in the tree.

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import process from "node:process";

// scripts/lib/marker-block.mjs: the locate / compare / report-drift-or-write
// flow shared with scripts/generate-catalog.mjs; exercised through this file's
// --check path.
import { findMarkerBlock, markerForms, syncMarkerBlock, wrapMarkerBlock } from "./lib/marker-block.mjs";

const argv = process.argv.slice(2);
const check = argv.includes("--check");
const rootFlag = argv.indexOf("--root");
const root =
  rootFlag !== -1 ? argv[rootFlag + 1] : join(import.meta.dirname, "..");
if (rootFlag !== -1 && (!root || root.startsWith("--"))) {
  fail(["--root requires a directory argument"]);
}

const OUTPUT_PATH = join(root, "docs", "skill-cheat-sheet.md");
const FORMS = markerForms("cheatsheet", "Run node scripts/generate-cheatsheet.mjs");
const FORMS_TEXT = FORMS.map((f) => `${f.start} ... ${f.end}`).join(" or ");

const config = await import(
  pathToFileURL(join(root, "scripts", "cheatsheet-config.mjs")).href
);
const {
  STAGES, CADENCES, EXCLUDED_PLUGINS, EXCLUDED_SKILL_NAME, EXCLUDED_SKILLS,
  STAGE_COMMANDS, RUNS_FOR_YOU, UPSTREAM_RECORDS, summaryError,
} = config;
const stageSlugs = new Set(STAGES.map((s) => s.slug));

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

// Minimal frontmatter reader with no dependencies. Frontmatter is the block
// between a line-1 `---` fence and the next `---` fence; `metadata:` sits at
// column 0 with its keys indented one level.
function readCheatsheetMeta(path) {
  const lines = readFileSync(path, "utf8").split(/\r?\n/);
  if (lines[0]?.trim() !== "---") return {};
  const values = {};
  const raw = {};
  let argumentHint;
  let inMetadata = false;
  for (let i = 1; i < lines.length && lines[i].trim() !== "---"; i++) {
    const line = lines[i];
    if (/^metadata:\s*$/.test(line)) {
      inMetadata = true;
      continue;
    }
    // A blank line inside the block does not end it — the shell reader
    // (skill_frontmatter::metadata_field) matches indented keys anywhere in
    // the frontmatter, so ending here would silently diverge from it. A
    // column-0 line does end it, and is read as a top-level key.
    if (inMetadata && !/^\s/.test(line) && line.trim() !== "") inMetadata = false;
    if (!inMetadata) {
      const hint = line.match(/^argument-hint:\s*(.*)$/);
      if (hint) argumentHint = hint[1].trim();
      continue;
    }
    if (line.trim() === "") continue;
    const m = line.match(/^\s+([A-Za-z0-9-]+):\s*(.*)$/);
    if (!m) continue;
    // Raw value kept alongside the stripped one: the guard's " #" rejection
    // must see the value BEFORE comment semantics apply, or a hand-edited
    // trailing comment silently truncates instead of being rejected.
    raw[m[1]] = m[2].trim();
    // Trailing-comment strip mirrors skill_frontmatter::metadata_field.
    values[m[1]] = m[2].replace(/\s+#.*$/, "").trim();
  }
  return { values, raw, argumentHint };
}

// `argument-hint` is free text, usually a double-quoted YAML scalar. A
// double-quoted value is unescaped as JSON (YAML's double-quoted escapes this
// repository uses are JSON's), a single-quoted one by doubling '', and a plain
// one is taken as written. Returns { value } or { error }.
function unquoteHint(text) {
  if (text === undefined || text === "") return { value: "" };
  if (text.startsWith('"')) {
    try {
      return { value: JSON.parse(text) };
    } catch {
      return { error: `argument-hint ${text} is not a readable double-quoted scalar` };
    }
  }
  if (text.startsWith("'")) {
    if (!text.endsWith("'") || text.length < 2) {
      return { error: `argument-hint ${text} is not a closed single-quoted scalar` };
    }
    return { value: text.slice(1, -1).replace(/''/g, "'") };
  }
  return { value: text };
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
  // readCheatsheetMeta returns bare {} when line 1 is not a `---` fence; a
  // named diagnostic here beats the TypeError that reading .values would throw.
  if (s.meta.values === undefined) {
    errors.push(`${key}: ${s.path} has no YAML frontmatter (line 1 is not ---)`);
    continue;
  }
  const reason =
    EXCLUDED_PLUGINS.get(s.plugin) ??
    EXCLUDED_SKILLS.get(key) ??
    (s.skill === EXCLUDED_SKILL_NAME.name ? EXCLUDED_SKILL_NAME.reason : undefined);
  const { "workflow-stage": stage, summary, cadence } = s.meta.values;

  // Reject a trailing comment on any swept key from the RAW value — after the
  // strip the guard's own " #" branch is unreachable, and the stripped value
  // would render a silently truncated row that reads as intended content.
  for (const k of ["workflow-stage", "summary", "cadence"]) {
    const rawValue = s.meta.raw[k];
    if (rawValue !== undefined && rawValue !== s.meta.values[k]) {
      errors.push(
        `${key}: ${k} carries a trailing " #" comment — not allowed on swept keys (ambiguous YAML scalar)`,
      );
    }
  }

  if (reason !== undefined) {
    if (stage !== undefined || summary !== undefined || cadence !== undefined) {
      errors.push(`${key}: excluded (${reason}) but carries workflow-stage/summary/cadence metadata`);
    }
    continue;
  }
  if (stage === undefined) {
    errors.push(`${key}: no workflow-stage and no exclusion entry`);
    continue;
  }
  if (!stageSlugs.has(stage)) {
    errors.push(`${key}: unknown workflow-stage "${stage}"`);
    continue;
  }
  if (stage === "operator") {
    if (cadence === undefined) {
      errors.push(`${key}: workflow-stage operator requires cadence`);
    } else if (!CADENCES.includes(cadence)) {
      errors.push(`${key}: unknown cadence "${cadence}"`);
    }
  } else if (cadence !== undefined) {
    errors.push(`${key}: cadence is only valid with workflow-stage operator`);
  }
  const guardError = summaryError(summary ?? "");
  if (guardError) errors.push(`${key}: ${guardError}`);
  const hint = unquoteHint(s.meta.argumentHint);
  if (hint.error) errors.push(`${key}: ${hint.error}`);
  mapped.push({ ...s, key, stage, summary, cadence, args: hint.value ?? "" });
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
// The Task kinds table sits under its own H2 in steps.md; it is not a stage.
const TASK_KINDS_HEADING = "Task kinds";
const stepsLines = readFileSync(stepsPath, "utf8").split(/\r?\n/);
const stepHeadings = stepsLines
  .filter((l) => l.startsWith("## "))
  .map((l) => l.slice(3).trim())
  .filter((h) => h !== TASK_KINDS_HEADING);
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

// --- Task kinds: the kind-to-stages table in steps.md ---------------------------
// A stage is named by its steps.md heading up to the first colon or " (":
// "1. Interview (optional: ...)" is "1. Interview", "Ship: PR lifecycle ..." is
// "Ship". The spine check above holds steps.md and STAGES to one order, so the
// i-th heading is the i-th workflow stage.

function splitRow(line) {
  return line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => c.trim());
}

// The rows of the first table under `## <heading>` in lines, header and
// delimiter row dropped; undefined when the heading is absent.
function tableUnder(lines, heading) {
  const start = lines.findIndex((l) => l.trim() === `## ${heading}`);
  if (start === -1) return undefined;
  const table = [];
  for (let i = start + 1; i < lines.length && !lines[i].startsWith("## "); i++) {
    if (lines[i].startsWith("|")) table.push(lines[i]);
    else if (table.length > 0) break;
  }
  return table.slice(2).map(splitRow);
}

const stageByName = new Map(
  stepHeadings.map((h, i) => [h.split(/:| \(/)[0].trim(), workflowStages[i]]),
);
const kindRows = tableUnder(stepsLines, TASK_KINDS_HEADING);
if (kindRows === undefined) fail([`${stepsPath} has no "## ${TASK_KINDS_HEADING}" table`]);
if (kindRows.length === 0) fail([`${stepsPath} "## ${TASK_KINDS_HEADING}" table has no rows`]);

const kindErrors = [];
const kinds = []; // { name, runs, onTrigger, skips }: arrays of [name, stage]
for (const cells of kindRows) {
  const name = cells[0];
  if (cells.length !== 4) {
    kindErrors.push(`Task kinds row "${name}": ${cells.length} cells, expected 4`);
    continue;
  }
  if (kinds.some((k) => k.name === name)) {
    kindErrors.push(`Task kinds row "${name}": kind listed twice`);
    continue;
  }
  const seen = new Set();
  const column = (cell) => {
    if (cell === "none") return [];
    return cell.split(",").map((s) => s.trim()).flatMap((s) => {
      if (!stageByName.has(s)) {
        kindErrors.push(`Task kinds row "${name}": unknown stage "${s}" (no such stage heading in steps.md)`);
        return [];
      }
      if (seen.has(s)) kindErrors.push(`Task kinds row "${name}": stage "${s}" listed twice`);
      seen.add(s);
      return [[s, stageByName.get(s)]];
    });
  };
  kinds.push({ name, runs: column(cells[1]), onTrigger: column(cells[2]), skips: column(cells[3]) });
}
if (kindErrors.length > 0) fail(kindErrors);

// --- Stage commands and what each runs for you ---------------------------------

const mappedByKey = new Map(mapped.map((s) => [s.key, s]));
const kindNames = new Set(kinds.map((k) => k.name));
const commandErrors = [];
const checkSkills = (where, list) => {
  if (!Array.isArray(list) || list.length === 0) {
    commandErrors.push(`${where}: names no skill`);
    return;
  }
  for (const key of list) {
    if (!mappedByKey.has(key)) commandErrors.push(`${where}: "${key}" is not a skill on the sheet`);
  }
};
for (const [slug, entry] of STAGE_COMMANDS) {
  if (!workflowStages.some((s) => s.slug === slug)) {
    commandErrors.push(`stage command "${slug}": not a workflow stage`);
    continue;
  }
  checkSkills(`stage command "${slug}"`, entry.skills);
  for (const [kind, list] of Object.entries(entry.byKind ?? {})) {
    if (!kindNames.has(kind)) {
      commandErrors.push(`stage command "${slug}": byKind names "${kind}", not a Task kinds row`);
    }
    checkSkills(`stage command "${slug}" for "${kind}"`, list);
  }
}
for (const kind of kinds) {
  for (const [name, stage] of [...kind.runs, ...kind.onTrigger]) {
    if (!STAGE_COMMANDS.has(stage.slug)) {
      commandErrors.push(`Task kinds row "${kind.name}": stage "${name}" has no STAGE_COMMANDS entry`);
    }
  }
}
// A cite is plain text found on exactly one line of the file it cites (the
// skill's SKILL.md unless `file` names another file in the skill directory),
// so a cite whose line was edited away fails here instead of pointing nowhere.
const runsFor = new Map(); // skill key -> rendered claims
for (const [key, claims] of RUNS_FOR_YOU) {
  const skill = mappedByKey.get(key);
  if (!skill) {
    commandErrors.push(`runs for you "${key}": not a skill on the sheet`);
    continue;
  }
  const rendered = [];
  for (const { does, cite, file = "SKILL.md" } of claims) {
    const where = `runs for you "${key}"`;
    if (!does || !cite) {
      commandErrors.push(`${where}: a claim needs both does and cite`);
      continue;
    }
    if (/[`*|]/.test(cite)) {
      commandErrors.push(`${where}: cite "${cite}" holds a backtick, asterisk or pipe`);
      continue;
    }
    const path = join(dirname(skill.path), file);
    if (!existsSync(path)) {
      commandErrors.push(`${where}: cited file ${file} does not exist`);
      continue;
    }
    const hits = readFileSync(path, "utf8").split(/\r?\n/).filter((l) => l.includes(cite)).length;
    if (hits !== 1) {
      commandErrors.push(`${where}: cite "${cite}" is on ${hits} lines of ${file}, not exactly one`);
      continue;
    }
    const href = `../plugins/${skill.plugin}/skills/${skill.skill}/${file}`;
    rendered.push(`${does} ([${file}](${href}): "${cite}")`);
  }
  runsFor.set(key, rendered);
}
if (commandErrors.length > 0) fail(commandErrors);

// --- Upstream equivalents from the upstream records' attribution tables ---------
// A row's first cell names the upstream units as [`name`](<tree link>); its
// second cell names ours as `plugin:skill`. The sheet links the record's table,
// never restating the row.

const upstreamFor = new Map(); // skill key -> rendered links
const upstreamErrors = [];
for (const record of UPSTREAM_RECORDS) {
  const path = join(root, record.path);
  if (!existsSync(path)) {
    upstreamErrors.push(`upstream record ${record.path} does not exist`);
    continue;
  }
  const rows = tableUnder(readFileSync(path, "utf8").split(/\r?\n/), record.heading);
  if (rows === undefined) {
    upstreamErrors.push(`upstream record ${record.path} has no "## ${record.heading}" table`);
    continue;
  }
  const href = `${record.path.replace(/^docs\//, "")}#${slugify(record.heading)}`;
  for (const cells of rows) {
    // A unit links its directory (`/tree/.../skills/...`); a commit, pull
    // request or single file (`/blob/`) in the same cell is not a unit.
    const names = [...(cells[0] ?? "").matchAll(/\[`([^`]+)`\]\(https:\/\/github\.com\/[^)\s]*\/tree\/[^)\s]*\/skills\/[^)\s]*\)/g)]
      .map((m) => `\`${m[1]}\``);
    if (names.length === 0) continue;
    const link = `[${record.label} ${names.join(", ")}](${href})`;
    for (const m of (cells[1] ?? "").matchAll(/`([a-z0-9-]+):([a-z0-9-]+)`/g)) {
      const key = `${m[1]}/${m[2]}`;
      if (!mappedByKey.has(key)) continue;
      const links = upstreamFor.get(key) ?? [];
      if (!links.includes(link)) links.push(link);
      upstreamFor.set(key, links);
    }
  }
}
if (upstreamErrors.length > 0) fail(upstreamErrors);

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

// An argument hint as a code span. GFM splits table cells before it parses
// code spans, so a pipe is escaped as \| (the span renders it as |), and a
// hint holding a backtick takes a double-backtick fence.
function argsCell(args) {
  if (args === "") return "";
  const escaped = args.replace(/\|/g, "\\|");
  return args.includes("`") ? `\`\` ${escaped} \`\`` : `\`${escaped}\``;
}

function command(key) {
  const s = mappedByKey.get(key);
  return `\`/${s.plugin}:${s.skill}\``;
}

function commandLink(key) {
  const s = mappedByKey.get(key);
  return `[${command(key)}](../plugins/${s.plugin}/skills/${s.skill}/SKILL.md)`;
}

function stageSkills(stage, kind) {
  const entry = STAGE_COMMANDS.get(stage.slug);
  return entry.byKind?.[kind] ?? entry.skills;
}

const KINDS_HEADING = "By kind of task";
const kindTable = kinds
  .map((kind) => {
    const typed = kind.runs.flatMap(([, stage]) => stageSkills(stage, kind.name).map(command));
    const onTrigger = kind.onTrigger.map(
      ([name, stage]) => `${name} (${stageSkills(stage, kind.name).map(command).join(", ")})`,
    );
    const skips = kind.skips.map(([name]) => name);
    return `| ${kind.name} | ${typed.join(" → ")} | ${onTrigger.join(", ") || "none"} | ${skips.join(", ") || "none"} |`;
  })
  .join("\n");
const commandKeys = [];
for (const kind of kinds) {
  for (const [, stage] of [...kind.runs, ...kind.onTrigger]) {
    for (const key of stageSkills(stage, kind.name)) {
      if (!commandKeys.includes(key)) commandKeys.push(key);
    }
  }
}
const commandTable = commandKeys
  .map((key) => {
    const s = mappedByKey.get(key);
    const stage = STAGES.find((st) => st.slug === s.stage);
    return `| ${commandLink(key)} | ${stage.heading} | ${argsCell(s.args)} | ${(runsFor.get(key) ?? []).join("; ")} |`;
  })
  .join("\n");
const kindsSection = [
  `## ${KINDS_HEADING}`,
  "Type the commands in order for the kind of task in front of you. The stages each kind runs, calls" +
    " on a stage's trigger and skips come from the Task kinds table in the" +
    " [workflow's stage definitions](../plugins/session-flow/skills/workflow/context/steps.md#task-kinds).",
  "| Kind | Type, in order | Calls on its trigger | Skips |\n| --- | --- | --- | --- |\n" + kindTable,
  "### What each command runs for you",
  "Each claim quotes the line of the skill that makes the call.",
  "| Command | Stage | Arguments | Runs for you |\n| --- | --- | --- | --- |\n" + commandTable,
].join("\n\n");

const sections = [kindsSection];
const toc = [`- [${KINDS_HEADING}](#${slugify(KINDS_HEADING)})`];
for (const stage of STAGES) {
  const rows = mapped
    .filter((s) => s.stage === stage.slug)
    .sort((a, b) => a.plugin.localeCompare(b.plugin) || a.skill.localeCompare(b.skill));
  if (rows.length === 0) continue;
  toc.push(`- [${stage.heading}](#${slugify(stage.heading)})`);
  const operator = stage.slug === "operator";
  const header = operator
    ? "| Skill | Plugin | Cadence | Arguments | What it does | Upstream |\n| --- | --- | --- | --- | --- | --- |"
    : "| Skill | Plugin | Arguments | What it does | Upstream |\n| --- | --- | --- | --- | --- |";
  const body = rows
    .map((s) => {
      const link = commandLink(s.key);
      const id = `\`${installName.get(s.plugin)}\``;
      const args = argsCell(s.args);
      const upstream = (upstreamFor.get(s.key) ?? []).join(", ");
      return operator
        ? `| ${link} | ${id} | ${s.cadence} | ${args} | ${cell(s.summary)} | ${upstream} |`
        : `| ${link} | ${id} | ${args} | ${cell(s.summary)} | ${upstream} |`;
    })
    .join("\n");
  sections.push(`## ${stage.heading}\n\n${header}\n${body}`);
}

const body = `${toc.join("\n")}\n\n${sections.join("\n\n")}`;

// --- Write / check -------------------------------------------------------------

if (!existsSync(OUTPUT_PATH)) {
  fail([`${OUTPUT_PATH} is missing; create it once with the markers (${FORMS_TEXT})`]);
}
const sheet = readFileSync(OUTPUT_PATH, "utf8");
const found = findMarkerBlock(sheet, FORMS);
if (found.error === "missing") {
  fail([`${OUTPUT_PATH} is missing the cheatsheet markers (${FORMS_TEXT})`]);
}
if (found.error) fail([`${OUTPUT_PATH} ${found.error}`]);
const existing = found.block;
const wrapped = wrapMarkerBlock(found.form, body, FORMS);
if (wrapped.error) fail([`${OUTPUT_PATH} ${wrapped.error}`]);
const block = wrapped.block;

syncMarkerBlock({
  path: OUTPUT_PATH,
  content: sheet,
  existing,
  expected: block,
  check,
  messages: {
    inSync: "Cheat sheet is in sync with skill frontmatter.",
    drift: "Cheat sheet drift: docs/skill-cheat-sheet.md block is stale.",
    rerun: "Run `node scripts/generate-cheatsheet.mjs` and commit the sheet.",
    unchanged: "Cheat sheet already in sync; output unchanged.",
    regenerated: `Cheat sheet regenerated (${mapped.length} skills).`,
  },
});
