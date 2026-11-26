#!/usr/bin/env node
import { existsSync, lstatSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, relative, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { escapes } from "./lib/config-cascade.mjs";
import { parse } from "./lib/yaml-subset.mjs";
import { DATA_DIR, droppedBy, gitRoot, loadIndex, present, readUserConfig, resolveId } from "./lookup.mjs";
import { resolveSettings } from "./settings.mjs";

const LAYERS = ["personal", "team"];
const KEBAB = /^[a-z0-9]+(?:-[a-z0-9]+)*$/u;
const INDEX_FILE = "README.md";
const LINE_BUDGET = 200;
const BUDGET_RULE =
  "Size guidance: soft budget of roughly 200 lines per file. When a file outgrows it, split by concern and add rows. (docs/contracts/standards/README.md, Standards files)";

const HELP = `Usage: adopt.mjs CONCEPT... --layer personal|team --surface NAME [options]

Adopts shipped engineering concepts into a standards layer: writes each concept as
one line naming it, its id and its official source into NAME.md, and adds that
file's row to the layer's index. Counterweights and conflicts are not copied:
lookup.mjs --counterweights-of prints them for the ids the file cites. CONCEPT is
an id, a name or an alias, as lookup.mjs matches it; a concept the exclude or
source_bar setting drops is refused, as lookup.mjs leaves it out.

  --layer personal          ~/.claude/standards/ (under --home); with no index
                            there, the standards folder is read file by file
  --layer team              the repository's standards root (.claude/standards.yaml
                            standards_dir, default docs/standards/); needs an index
  --surface NAME            the index row's name: a short lowercase name with
                            dashes, like api-design; the file is NAME.md, and
                            readme is refused because README.md is the index
  --applies-when TEXT       the index row's "Applies when" clues (default: the
                            concepts' concerns); a | is escaped, a line break
                            becomes a space, and an empty value or a backslash
                            is refused
  --yes                     write; without it, print what would be written
  --data-dir DIR            read concepts from DIR instead of the plugin's data/
  --project DIR             repository for --layer team, and whose settings
                            layers apply (default: the git root of the working
                            directory)
  --user-config FILE|-      the plugin's userConfig values, as lookup.mjs reads them
  --home DIR                user home for --layer personal
  -h, --help                show this help

A concept already in the file is skipped, and an existing row for the file is kept.
The preview prints the exact text the write adds: the whole file when it is new,
the appended lines otherwise, and the index row, or the table holding it when the
index has none. The one change it does not show is a line break added to the end
of an index that lacks one. A file past ${LINE_BUDGET} lines is written with a
warning. A surface file or index that is a symbolic link is refused. Diagnostics:
one JSON record per line on the error output.
Exit: 0 written or nothing new, 1 refused, 2 invalid option, 3 preview only.`;

const OPTIONS = {
  layer: { type: "string" },
  surface: { type: "string" },
  "applies-when": { type: "string" },
  yes: { type: "boolean", default: false },
  "data-dir": { type: "string" },
  project: { type: "string" },
  "user-config": { type: "string" },
  home: { type: "string", default: homedir() },
  help: { type: "boolean", short: "h", default: false },
};

const HEADER = (surface) => `# Adopted engineering concepts: ${surface}

Each entry is an engineering concept adopted here, named by its id in the engineering-concepts
plugin and linked to its official source. Apply it together with its counterweights and
conflicts, which this file does not copy: to list them, run the engineering-concepts plugin's
lookup with \`--counterweights-of\` and the ids cited below, comma separated.

`;

const entry = (r) => `- ${r.name} (\`${r.id}\`): ${r.source_url}\n`;

const read = (path) => (existsSync(path) ? readFileSync(path, "utf8") : null);

/**
 * `{text, added, table}`: the row inserted after the last row of the index table, or a table
 * holding it appended when there is none. `added` is the text inserted, apart from a line break
 * ending an index that lacked one.
 */
function withRow(index, row) {
  const lines = index.replace(/\n$/u, "").split("\n");
  const header = lines.findIndex((line) => /^\|\s*Surface\s*\|/u.test(line));
  if (header < 0) {
    const added = `\n| Surface | Applies when | File |\n|---|---|---|\n${row}\n`;
    return { text: `${lines.join("\n")}\n${added}`, added, table: true };
  }
  let end = header;
  while (end + 1 < lines.length && lines[end + 1].startsWith("|")) end++;
  lines.splice(end + 1, 0, row);
  return { text: `${lines.join("\n")}\n`, added: `${row}\n`, table: false };
}

const isLink = (path) => {
  try {
    return lstatSync(path).isSymbolicLink();
  } catch {
    return false;
  }
};

/** The standards contract's presence test: an index carries `standards-contract` in its frontmatter. */
const isIndex = (text) => /^---\r?\n(?:.*\r?\n)*?standards-contract:.*\r?\n(?:.*\r?\n)*?---\r?\n/u.test(text ?? "");

/** `{dir}`, or `{error}` when the repository's concern file cannot be read as a standards root. */
function teamRoot(project) {
  const file = join(project, ".claude", "standards.yaml");
  const concern = read(file);
  let value;
  try {
    value = concern ? parse(concern)?.standards_dir : undefined;
  } catch (e) {
    return { error: { file, reason: e.message } };
  }
  if (value !== undefined && typeof value !== "string") return { error: { file, reason: "standards_dir is not a path" } };
  return { dir: join(project, value || "docs/standards") };
}

function write(path, text) {
  mkdirSync(dirname(path), { recursive: true });
  const temp = `${path}.${process.pid}.tmp`;
  writeFileSync(temp, text);
  renameSync(temp, path);
}

export async function main(argv, { out = console.log, err = console.error, shippedDataDir = DATA_DIR } = {}) {
  const invalid = (option, value, allowed, reason) => {
    err(JSON.stringify({ level: "error", event: "invalid option", option, value, ...(allowed && { allowed }), ...(reason && { reason }) }));
    return 2;
  };
  let parsed;
  try {
    parsed = parseArgs({ args: argv, allowPositionals: true, options: OPTIONS });
  } catch (e) {
    return invalid(null, e.message);
  }
  const { values: opts, positionals } = parsed;
  if (opts.help) {
    out(HELP);
    return 0;
  }
  if (!LAYERS.includes(opts.layer)) return invalid("layer", opts.layer ?? null, LAYERS);
  if (!KEBAB.test(opts.surface ?? "")) {
    return invalid("surface", opts.surface ?? null, null, "a short lowercase name with dashes, like api-design");
  }
  if (`${opts.surface}.md`.toLowerCase() === INDEX_FILE.toLowerCase()) {
    return invalid("surface", opts.surface, null, `${INDEX_FILE} is the layer's index, so it cannot hold adopted concepts`);
  }
  if (opts["applies-when"]?.includes("\\")) {
    return invalid("applies-when", opts["applies-when"], null, "a backslash cannot be written into the index row safely; remove it (a | needs no escaping)");
  }
  if (opts["applies-when"] !== undefined && !opts["applies-when"].trim()) {
    return invalid("applies-when", opts["applies-when"], null, "empty: name the tasks and files the concepts bear on, or leave the option out to use their concerns");
  }
  if (!positionals.length) return invalid("concepts", null);
  let userConfig = {};
  if (opts["user-config"]) {
    try {
      userConfig = readUserConfig(opts["user-config"]);
    } catch (e) {
      return invalid("user-config", opts["user-config"], null, e.code ?? e.message);
    }
  }
  const project = resolvePath(opts.project ?? gitRoot(process.cwd()));
  const settings = resolveSettings({ projectRoot: project, userConfig, userHome: opts.home, err });
  const index = loadIndex(opts["data-dir"] ?? shippedDataDir, err, { shipped: opts["data-dir"] === undefined });
  const missing = positionals.filter((term) => resolveId(index, term) === undefined);
  for (const term of missing) err(JSON.stringify({ level: "error", event: "concept not found", term }));
  if (missing.length) return 1;
  const excluded = new Set(settings.exclude);
  let refused = 0;
  for (const term of positionals) {
    const drop = droppedBy(index.byId.get(resolveId(index, term)), excluded, settings.source_bar);
    if (!drop) continue;
    refused++;
    const from = drop.setting === "exclude" ? settings.exclude_from[drop.value] : settings.source_bar_from;
    const reason =
      drop.setting === "exclude"
        ? `the ${from.layer} layer's exclude setting lists ${drop.value}, so the lookup leaves this concept out`
        : `the ${from.layer} layer sets source_bar to ${drop.value}, and this concept lists no confirming source`;
    err(JSON.stringify({ level: "error", event: "concept excluded", term, ...drop, ...from, reason }));
  }
  if (refused) return 1;
  const records = positionals.map((term) => present(index, index.byId.get(resolveId(index, term))));
  let dir = join(opts.home, ".claude", "standards");
  if (opts.layer === "team") {
    const root = teamRoot(project);
    if (root.error) {
      err(JSON.stringify({ level: "error", event: "standards config unreadable", ...root.error }));
      return 1;
    }
    if (/^\.\.(?:[\\/]|$)/u.test(relative(project, root.dir)) || escapes(root.dir, project)) {
      err(JSON.stringify({ level: "error", event: "standards root outside the repository", dir: root.dir, project }));
      return 1;
    }
    dir = root.dir;
  }
  const file = `${opts.surface}.md`;
  const filePath = join(dir, file);
  const concerns = [...new Set(records.map((r) => r.concern))].sort();
  const appliesWhen = (opts["applies-when"] ?? concerns.join(", ")).replace(/\s+/gu, " ").replace(/\|/gu, "\\|");
  const row = `| ${opts.surface} | ${appliesWhen} | ${file} |`;
  const indexPath = join(dir, INDEX_FILE);
  const links = [filePath, indexPath].filter(isLink);
  for (const path of links) {
    err(JSON.stringify({ level: "error", event: "symbolic link refused", path, reason: "a symbolic link: writing would replace the link with a regular file; edit the file it points to by hand" }));
  }
  if (links.length) return 1;

  const current = read(filePath);
  const isAdopted = (id) => current?.split("\n").some((line) => line.startsWith("- ") && line.includes(`(\`${id}\`)`));
  const fresh = [...new Map(records.filter((r) => !isAdopted(r.id)).map((r) => [r.id, r])).values()];
  const indexText = read(indexPath);
  const currentIndex = isIndex(indexText) ? indexText : null;
  if (currentIndex === null && opts.layer === "team") {
    err(JSON.stringify({ level: "error", event: "no team index", index: indexPath, fix: "create the index with a standards setup skill first" }));
    return 1;
  }
  const needsRow = currentIndex !== null && !currentIndex.split("\n").some((line) => line.startsWith("|") && line.split(/(?<!\\)\|/u)[3]?.trim() === file);
  const unindexed = currentIndex === null ? `No index at ${indexPath}: the standards folder is read file by file, so the file still loads.` : null;
  if (!fresh.length && !needsRow) {
    out(`Every concept named is already adopted in ${filePath}.`);
    return 0;
  }
  const entries = fresh.map(entry).join("");
  const appended = current === null || current === "" || current.endsWith("\n") ? entries : `\n${entries}`;
  const next = current === null ? `${HEADER(opts.surface)}${entries}` : `${current}${appended}`;
  const lineCount = next.split("\n").length - 1;
  if (entries && lineCount > LINE_BUDGET) {
    err(JSON.stringify({ level: "warn", event: "standards file over budget", file: filePath, lines: lineCount, budget: LINE_BUDGET, contract: BUDGET_RULE }));
  }

  const indexed = needsRow ? withRow(currentIndex, row) : null;

  if (!opts.yes) {
    if (entries) out(current === null ? `Would create ${filePath}:\n${next}` : `Would append to ${filePath}:\n${appended}`);
    if (indexed) out(`Would add ${indexed.table ? "a table holding this row" : "this row"} to ${indexPath}:\n${indexed.added}`);
    if (unindexed) out(unindexed);
    out("Re-run with --yes to write.");
    return 3;
  }
  try {
    if (entries) write(filePath, next);
    if (indexed) write(indexPath, indexed.text);
  } catch (e) {
    err(JSON.stringify({ level: "error", event: "write failed", path: e.path ?? null, code: e.code ?? null, message: e.message }));
    return 1;
  }
  out(`Adopted ${fresh.length} concept(s) into ${filePath}.`);
  if (unindexed) out(unindexed);
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exitCode = await main(process.argv.slice(2));
