#!/usr/bin/env node

// Generates the stage-grouped skill cheat sheet block in
// docs/skill-cheat-sheet.md from each in-scope SKILL.md's `metadata:`
// frontmatter (`workflow-stage`, `summary`, `cadence`), its `argument-hint`
// (the Actions and Arguments columns) and its `## Next` section (the Next
// column), the Task kinds table in the workflow skill's steps.md (the By kind
// of task table), the attribution tables of the configured upstream records
// (the Upstream column), plus the hand-curated grouping layer in
// scripts/cheatsheet-config.mjs.
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
// (plain YAML scalar, <=100 codepoints); a Task kinds row naming a stage
// steps.md does not define fails naming the kind and the stage, and a missing
// Task kinds table or upstream attribution table fails. A `## Next` token naming no skill is
// rendered as written; scripts/check-next-graph.py fails on it. Swept values are plain scalars, and
// this reader takes the literal text after the key: it strips a trailing
// `#`-comment but never strips quotes, because a quoted value is a rejection
// here rather than a value to unwrap. skill-quality's
// skill_frontmatter::metadata_field reads the same way, and
// scripts/check-summary-reader-parity.test.sh holds the two readers to one
// value on a shared case table and on every SKILL.md in the tree.

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import process from "node:process";

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
  summaryError,
} = config;
const {
  REVIEW_PR_MAP = [], REVIEW_PR_MAP_HEADING = "", REVIEW_PR_AUDIENCES = [], REVIEW_PR_POSTS = [],
  UPSTREAM_RECORDS = [], STAGE_COMMANDS = [],
} = config;
const stageSlugs = new Set(STAGES.map((s) => s.slug));

function fail(messages) {
  for (const m of messages) console.error(`generate-cheatsheet: ${m}`);
  process.exit(1);
}

function listDirs(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => e.name)
    .sort();
}

const skills = [];
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
  let i = 1;
  for (; i < lines.length && lines[i].trim() !== "---"; i++) {
    const line = lines[i];
    const hint = line.match(/^argument-hint:\s*(.*)$/);
    if (hint) argumentHint = unquote(hint[1].trim());
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
      raw[m[1]] = m[2].trim();
      // Trailing-comment strip mirrors skill_frontmatter::metadata_field.
      values[m[1]] = m[2].replace(/\s+#.*$/, "").trim();
    }
  }
  return {
    values,
    raw,
    argumentHint,
    actions: actionWords(argumentHint ?? ""),
    successors: successorTokens(lines.slice(i + 1)),
  };
}

function unquote(value) {
  if (/^".*"$/.test(value)) return value.slice(1, -1).replace(/\\(.)/g, "$1");
  if (/^'.*'$/.test(value)) return value.slice(1, -1).replace(/''/g, "'");
  return value;
}

// The actions are the bare-word alternatives of the hint's first bracketed
// group: `[audit|fix] [target]` yields audit and fix, and a required
// `<fetch|diff>` group's choices are read the same way. Only a lone `<name>` is
// a placeholder, so `<<role>|all>` yields all. Flags, `key=value` choices and
// multi-word alternatives are not actions; a group with no `|` is an argument, and one led by a flag and its value
// (`[--output a|b]`) chooses that flag's value, so neither yields actions. A
// group whose first choice is a bare flag (`[--ledger|fix]`) still yields fix.
function actionWords(hint) {
  const open = hint.search(/[[<]/);
  if (open === -1) return [];
  const alternatives = [];
  let depth = 0;
  let current = "";
  for (const ch of hint.slice(open)) {
    if (ch === "[" || ch === "<") {
      depth++;
      if (depth === 1) continue;
    } else if (ch === "]" || ch === ">") {
      depth--;
      if (depth === 0) break;
    } else if (ch === "|" && depth === 1) {
      alternatives.push(current);
      current = "";
      continue;
    }
    current += ch;
  }
  alternatives.push(current);
  if (alternatives.length < 2) return [];
  const bare = alternatives.map((alt) => {
    let text = alt;
    for (let prev; prev !== text; ) {
      prev = text;
      text = text.replace(/[[<][^[\]<>]*[\]>]/g, "");
    }
    return text.replace(/…|\.\.\./g, "").trim().split(/\s+/);
  });
  const [lead, leadValue] = bare[0];
  const flagLed = lead.startsWith("-") && leadValue !== undefined && !leadValue.startsWith("-");
  if (flagLed || bare.some(([first]) => first.includes("="))) return [];
  const words = bare
    .filter(([first, ...rest]) => /^[a-z][a-z0-9-]*$/.test(first) && rest.every((t) => t.startsWith("-")))
    .map(([first]) => first);
  return [...new Set(words)];
}

function successorTokens(bodyLines) {
  const start = bodyLines.findIndex((l) => l.trim() === "## Next");
  if (start === -1) return [];
  const end = bodyLines.findIndex((l, j) => j > start && /^#{1,2} /.test(l));
  const text = bodyLines.slice(start + 1, end === -1 ? undefined : end).join("\n");
  const tokens = [...text.matchAll(/(?<![\w./:-])\/([a-z0-9][a-z0-9-]*):([a-z0-9][a-z0-9-]*)/g)]
    .map((m) => `${m[1]}/${m[2]}`);
  return [...new Set(tokens)];
}

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
  if (s.meta.values === undefined) {
    errors.push(`${key}: ${s.path} has no YAML frontmatter (line 1 is not ---)`);
    continue;
  }
  const reason =
    EXCLUDED_PLUGINS.get(s.plugin) ??
    EXCLUDED_SKILLS.get(key) ??
    (s.skill === EXCLUDED_SKILL_NAME.name ? EXCLUDED_SKILL_NAME.reason : undefined);
  const { "workflow-stage": stage, summary, cadence } = s.meta.values;

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
  mapped.push({ ...s, stage, summary, cadence });
}

const mappedKeys = new Set(mapped.map((s) => `${s.plugin}/${s.skill}`));
const mapRows = [];
for (const row of REVIEW_PR_MAP) {
  const skill = skills.find((s) => `${s.plugin}/${s.skill}` === row.skill);
  if (!skill || !mappedKeys.has(row.skill)) {
    errors.push(`review map: "${row.skill}" is not a listed skill`);
    continue;
  }
  for (const a of row.audience) {
    if (!REVIEW_PR_AUDIENCES.includes(a)) errors.push(`review map: ${row.skill} has unknown audience "${a}"`);
  }
  if (!REVIEW_PR_POSTS.includes(row.posts)) {
    errors.push(`review map: ${row.skill} has unknown posts value "${row.posts}"`);
  }
  if (!readFileSync(skill.path, "utf8").includes(row.basis)) {
    errors.push(`review map: ${row.skill} no longer contains its basis quote "${row.basis}"; re-check "posts"`);
  }
  mapRows.push({ ...row, plugin: skill.plugin, name: skill.skill });
}

const stageCommands = new Map();
for (const entry of STAGE_COMMANDS) {
  const id = `stage commands: ${entry.stage}`;
  const skill = mapped.find((s) => `${s.plugin}/${s.skill}` === entry.skill);
  if (!stageSlugs.has(entry.stage)) {
    errors.push(`${id} is not a stage in STAGES`);
  } else if (stageCommands.has(entry.stage)) {
    errors.push(`${id} has more than one entry`);
  } else if (!skill) {
    errors.push(`${id} names "${entry.skill}", which is not a listed skill`);
  } else if (skill.stage !== entry.stage) {
    errors.push(`${id} names "${entry.skill}", whose workflow-stage is "${skill.stage}"`);
  } else {
    const lines = readFileSync(skill.path, "utf8").split(/\r?\n/);
    const rel = `plugins/${skill.plugin}/skills/${skill.skill}/SKILL.md`;
    const command = `\`/${skill.plugin}:${skill.skill}\``;
    const runs = (entry.runs ?? []).map(({ claim, basis }) => {
      const at = lines.findIndex((l) => l.includes(basis));
      if (at === -1) errors.push(`${id} (${entry.skill}) no longer contains its basis quote "${basis}"`);
      return `${command}: ${claim} ([\`${rel}:${at + 1}\`](../${rel}))`;
    });
    const also = (entry.also ?? []).flatMap(({ when, skill: key }) => {
      const other = mapped.find((s) => `${s.plugin}/${s.skill}` === key);
      if (!other) {
        errors.push(`${id} also names "${key}", which is not a listed skill`);
        return [];
      }
      if (other.stage !== entry.stage) {
        errors.push(`${id} also names "${key}", whose workflow-stage is "${other.stage}"`);
        return [];
      }
      return [`(${when} \`/${other.plugin}:${other.skill}\`)`];
    });
    stageCommands.set(entry.stage, { command: [command, ...also].join(" "), runs });
  }
}

if (errors.length > 0) fail(errors);

// --- Spine-drift assertion ---------------------------------------------------
// Each workflow-stage heading must prefix-match its H2 in the session-flow
// workflow stage definitions, same order — a stage rename upstream fails this
// gate instead of silently stranding the copy. The Task kinds H2 in the same
// file is the kind-to-stages table, not a stage.
const TASK_KINDS_HEADING = "Task kinds";
const stepsPath = join(
  root, "plugins", "session-flow", "skills", "workflow", "context", "steps.md",
);
if (!existsSync(stepsPath)) fail([`spine source missing: ${stepsPath}`]);
const stepsLines = readFileSync(stepsPath, "utf8").split(/\r?\n/);
const stepHeadings = stepsLines
  .filter((l) => l.startsWith("## ") && l.slice(3).trim() !== TASK_KINDS_HEADING)
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

// --- Task kinds ---------------------------------------------------------------
// steps.md's Task kinds table is the one statement of which stages each kind of
// task enters and skips. A stage is named by its steps.md heading without the
// number and without anything after a colon or an opening parenthesis
// ("## 11. Verify outcome" is "Verify outcome", "## Ship: PR lifecycle ..." is
// "Ship"). An unknown name fails, so the table cannot rot silently.
const stageByName = new Map(
  workflowStages.map((s, i) => [
    stepHeadings[i].replace(/^\d+\.\s+/, "").split(/:|\s\(/)[0].trim(),
    s,
  ]),
);
// A conditional stage's trigger is the text after "conditional:" in its
// heading; the by-kind lead-in quotes steps.md's own sentences on conditional
// stages and detours, so neither rule is restated here.
const conditionBySlug = new Map(
  workflowStages.map((s, i) => [s.slug, stepHeadings[i].match(/\(conditional: ([^)]*)\)/)?.[1]]),
);
const stepsProse = stepsLines.join("\n").split(/\n\s*\n/).map((p) => p.replace(/\s*\n\s*/g, " "));
const leadIn = [
  "A conditional stage runs only when its trigger holds",
  "Stages 2-4 are detours",
].map((prefix) => {
  const sentence = stepsProse
    .map((p) => p.slice(p.indexOf(prefix)))
    .find((p) => p.startsWith(prefix))
    ?.match(/^.*?\.(?=\s|$)/)?.[0];
  if (!sentence) fail([`${stepsPath} has no sentence starting "${prefix}"`]);
  return sentence;
});
const kindsStart = stepsLines.findIndex((l) => l.trim() === `## ${TASK_KINDS_HEADING}`);
if (kindsStart === -1) fail([`${stepsPath} has no Task kinds table (## ${TASK_KINDS_HEADING})`]);
const kindsEnd = stepsLines.findIndex((l, j) => j > kindsStart && l.startsWith("## "));
const kindRows = stepsLines
  .slice(kindsStart + 1, kindsEnd === -1 ? undefined : kindsEnd)
  .filter((l) => l.trim().startsWith("|"))
  .slice(2)
  .map((l) => l.trim().replace(/^\||\|$/g, "").split("|").map((c) => c.trim()));
if (kindRows.length === 0) fail([`${stepsPath} has no Task kinds table rows`]);
const kindErrors = [];
const kinds = kindRows.map(([kind, enters = "", skips = "", why = ""]) => {
  const resolve = (list) =>
    list === "None"
      ? []
      : list.split(",").map((n) => n.trim()).map((name) => {
          const stage = stageByName.get(name);
          if (!stage) kindErrors.push(`task kinds: "${kind}" names stage "${name}", which steps.md does not define`);
          return { name, stage };
        });
  return { kind, enters: resolve(enters), skips: resolve(skips), why };
});
if (kindErrors.length > 0) fail(kindErrors);

// --- Upstream equivalents -----------------------------------------------------
// Each configured upstream record's "## Attribution table" is read for the
// skills its Ours column names; a listed skill links that table, named by the
// row's upstream skill. No other table in the record is read.

const upstreamBySkill = new Map(); // "plugin/skill" -> [markdown link]
for (const record of UPSTREAM_RECORDS) {
  const recordPath = join(root, record.path);
  const lines = existsSync(recordPath) ? readFileSync(recordPath, "utf8").split(/\r?\n/) : [];
  const start = lines.findIndex((l) => l.trim() === "## Attribution table");
  if (start === -1) fail([`upstream record ${record.path} has no ## Attribution table`]);
  const end = lines.findIndex((l, j) => j > start && l.startsWith("## "));
  const href = `${record.path.replace(/^docs\//, "")}#attribution-table`;
  const rows = lines
    .slice(start + 1, end === -1 ? undefined : end)
    .filter((l) => l.startsWith("|"))
    .slice(2);
  for (const row of rows) {
    const [upstream = "", ours = ""] = row.replace(/^\|/, "").split(" | ");
    const name = upstream.match(/`([^`]+)`/)?.[1] ?? upstream.match(/\[([^\]]+)\]/)?.[1];
    if (!name) continue;
    for (const m of ours.matchAll(/`([a-z0-9-]+):([a-z0-9-]+)[` ]/g)) {
      const key = `${m[1]}/${m[2]}`;
      if (!mappedKeys.has(key)) continue;
      const link = `[${record.label} \`${name}\`](${href})`;
      const links = upstreamBySkill.get(key) ?? [];
      if (!links.includes(link)) links.push(link);
      upstreamBySkill.set(key, links);
    }
  }
}

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

// Inside a code span the HTML entity would render literally; GFM tables honor
// a backslash-escaped pipe there instead.
function codeCell(text) {
  return text ? `\`${text.replace(/\|/g, "\\|")}\`` : "";
}

const sections = [];
const toc = [];
const renderedStages = new Set();
for (const stage of STAGES) {
  const rows = mapped
    .filter((s) => s.stage === stage.slug)
    .sort((a, b) => a.plugin.localeCompare(b.plugin) || a.skill.localeCompare(b.skill));
  if (rows.length === 0) continue;
  renderedStages.add(stage.slug);
  toc.push(`- [${stage.heading}](#${slugify(stage.heading)})`);
  const operator = stage.slug === "operator";
  const header = operator
    ? "| Skill | Plugin | Cadence | What it does | Actions | Arguments | Upstream | Next |\n" +
      "| --- | --- | --- | --- | --- | --- | --- | --- |"
    : "| Skill | Plugin | What it does | Actions | Arguments | Upstream | Next |\n" +
      "| --- | --- | --- | --- | --- | --- | --- |";
  const body = rows
    .map((s) => {
      const link = `[\`/${s.plugin}:${s.skill}\`](../plugins/${s.plugin}/skills/${s.skill}/SKILL.md)`;
      const id = `\`${installName.get(s.plugin)}\``;
      const actions = s.meta.actions.map((a) => `\`${a}\``).join(", ");
      const args = codeCell(s.meta.argumentHint ?? "");
      const upstream = (upstreamBySkill.get(`${s.plugin}/${s.skill}`) ?? []).join(", ");
      const next = s.meta.successors.map((t) => `\`/${t.replace("/", ":")}\``).join(", ");
      const tail = `${actions} | ${args} | ${upstream} | ${next} |`;
      return operator
        ? `| ${link} | ${id} | ${s.cadence} | ${cell(s.summary)} | ${tail}`
        : `| ${link} | ${id} | ${cell(s.summary)} | ${tail}`;
    })
    .join("\n");
  sections.push(`## ${stage.heading}\n\n${header}\n${body}`);
}

const BY_KIND_HEADING = "By kind of task";
const stageLink = ({ name, stage }) =>
  renderedStages.has(stage.slug) ? `[${name}](#${slugify(stage.heading)})` : name;
const kindRowsOut = kinds
  .map((k) => {
    const steps = k.enters.map((s) => {
      const command = stageCommands.get(s.stage.slug)?.command;
      const condition = conditionBySlug.get(s.stage.slug);
      const stage = condition ? `${stageLink(s)} (conditional: ${cell(condition)})` : stageLink(s);
      return command ? `${stage}: ${command}` : stage;
    });
    const runs = k.enters.flatMap((s) => stageCommands.get(s.stage.slug)?.runs ?? []);
    const skips = k.skips.length ? k.skips.map((s) => s.name).join(", ") : "None";
    return `| ${cell(k.kind)} | ${steps.join(" → ")} | ${runs.join("; ")} | ${skips} | ${cell(k.why)} |`;
  })
  .join("\n");
toc.unshift(`- [${BY_KIND_HEADING}](#${slugify(BY_KIND_HEADING)})`);
sections.unshift(
  `## ${BY_KIND_HEADING}\n\nFrom the stage definitions: ${cell(leadIn.join(" "))}\n\n` +
    "| Kind of task | Commands to type, in order | What they run for you | Skips | Why |\n" +
    "| --- | --- | --- | --- | --- |\n" +
    kindRowsOut,
);

if (mapRows.length > 0) {
  toc.push(`- [${REVIEW_PR_MAP_HEADING}](#${slugify(REVIEW_PR_MAP_HEADING)})`);
  const rows = mapRows
    .map((r) => {
      const link = `[\`/${r.plugin}:${r.name}\`](../plugins/${r.plugin}/skills/${r.name}/SKILL.md)`;
      return `| ${link} | ${cell(r.job)} | ${r.audience.join(", ")} | ${r.posts} |`;
    })
    .join("\n");
  sections.push(
    `## ${REVIEW_PR_MAP_HEADING}\n\n` +
      "| Skill | Job | Who it is for | Posts to the PR |\n| --- | --- | --- | --- |\n" +
      rows,
  );
}

const body = `${toc.join("\n")}\n\n${sections.join("\n\n")}`;

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
