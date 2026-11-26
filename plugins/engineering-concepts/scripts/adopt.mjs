#!/usr/bin/env node
import { randomBytes } from "node:crypto";
import { closeSync, existsSync, lstatSync, mkdirSync, openSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
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

A concept already in the file, or in another standards file of the layer or its
subfolders (symbolic links are not followed), is skipped and the file citing it
is named; an existing row for the file is kept, and none is added when nothing
is. A plugin settings file that cannot be read stops the run, so its exclude
and source_bar are never ignored. Added lines keep the file's line endings.
The preview prints the exact text the write adds: the whole file when it is new
or empty, the appended lines otherwise, and the index row, or the table holding
it when the index has none. When the file or the index does not end with a line
break, the preview says one will be added. A file past ${LINE_BUDGET} lines is
written with a warning. A surface file or index that is a symbolic link is
refused. Diagnostics: one JSON record per line on the error output.
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

const entry = (r, eol) => `- ${r.name} (\`${r.id}\`): ${r.source_url}${eol}`;

/** A file's line ending, so lines added to it match the ones it has. */
const eolOf = (text) => (text?.includes("\r\n") ? "\r\n" : "\n");

const FS_REASONS = {
  ENOENT: "file not found",
  EISDIR: "is a folder, not a file",
  ENOTDIR: "a folder in its path is a file",
  EACCES: "permission denied",
  EPERM: "permission denied",
  ENOSPC: "the disk is full",
  EROFS: "the file system is read-only",
};

const plainReason = (e, fallback) => FS_REASONS[e.code] ?? (e instanceof SyntaxError ? `not valid JSON: ${e.message}` : fallback);

const cites = (text, id) => text?.split("\n").some((line) => line.startsWith("- ") && line.includes(`(\`${id}\`)`));

/** Where each settings layer comes from, in the words a person uses for it. */
const LAYER_NAMES = {
  defaults: "the plugin's defaults",
  userConfig: "your saved plugin options",
  team: "the repository's settings file",
  local: "your personal settings file for this repository",
};

const read = (path) => (existsSync(path) ? readFileSync(path, "utf8") : null);

/**
 * `{text, added, table}`: the row inserted after the last row of the index table, or a table
 * holding it appended when there is none. `added` is the text inserted, apart from a line break
 * ending an index that lacked one.
 */
function withRow(index, row) {
  const eol = eolOf(index);
  const lines = index.replace(/\r?\n$/u, "").split(eol);
  const header = lines.findIndex((line) => /^\|\s*Surface\s*\|/u.test(line));
  if (header < 0) {
    const added = `${eol}| Surface | Applies when | File |${eol}|---|---|---|${eol}${row}${eol}`;
    return { text: `${lines.join(eol)}${eol}${added}`, added, table: true };
  }
  let end = header;
  while (end + 1 < lines.length && lines[end + 1].startsWith("|")) end++;
  lines.splice(end + 1, 0, row);
  return { text: `${lines.join(eol)}${eol}`, added: `${row}${eol}`, table: false };
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
    return { error: { file, reason: `the settings file could not be read: ${e.message}` } };
  }
  if (value !== undefined && typeof value !== "string") return { error: { file, reason: "standards_dir is not a path" } };
  return { dir: join(project, value || "docs/standards") };
}

/** A random name and an exclusive create, so a link planted at the temporary path is never followed. */
function write(path, text) {
  mkdirSync(dirname(path), { recursive: true });
  const temp = `${path}.${randomBytes(8).toString("hex")}.tmp`;
  const fd = openSync(temp, "wx");
  try {
    writeFileSync(fd, text);
    closeSync(fd);
    renameSync(temp, path);
  } catch (e) {
    rmSync(temp, { force: true });
    throw e;
  }
}

/**
 * The layer's other standards files by path: `.md` files in it and its subfolders, as the standards
 * contract allows, regular files only, so a symbolic link never leads the walk out of the layer.
 */
function otherFiles(dir, skip, sub = "") {
  let names;
  try {
    names = readdirSync(join(dir, sub), { withFileTypes: true });
  } catch {
    return [];
  }
  return names
    .flatMap((d) => {
      const rel = join(sub, d.name);
      if (d.isDirectory()) return otherFiles(dir, skip, rel);
      return d.isFile() && d.name.endsWith(".md") && rel !== INDEX_FILE && rel !== skip ? [join(dir, rel)] : [];
    })
    .sort();
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
  if (!positionals.length) return invalid("concepts", null, null, "name at least one concept: an id, a name or an alias");
  let userConfig = {};
  if (opts["user-config"]) {
    try {
      userConfig = readUserConfig(opts["user-config"]);
    } catch (e) {
      return invalid("user-config", opts["user-config"], null, plainReason(e, "the file could not be read"));
    }
  }
  const project = resolvePath(opts.project ?? gitRoot(process.cwd()));
  const warnings = [];
  const settings = resolveSettings({ projectRoot: project, userConfig, userHome: opts.home, err: (line) => warnings.push(line) });
  const unreadable = new Set(settings.unreadable.map((u) => u.layer));
  for (const line of warnings) {
    const { event, layer } = JSON.parse(line);
    if (!(event === "setting rejected" && unreadable.has(layer))) err(line);
  }
  for (const { layer, path, detail } of settings.unreadable) {
    const reason = `${LAYER_NAMES[layer] ?? layer}, ${path}, could not be read, so nothing is adopted until it is fixed: ${detail}`;
    err(JSON.stringify({ level: "error", event: "settings file unreadable", layer, path, reason }));
  }
  if (unreadable.size) return 1;
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
    const where = LAYER_NAMES[from.layer] ?? from.layer;
    const reason =
      drop.setting === "exclude"
        ? `the exclude setting in ${where} lists ${drop.value}, so the lookup leaves this concept out`
        : `the source_bar setting in ${where} is ${drop.value}, and this concept lists no confirming source`;
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
  const indexText = read(indexPath);
  const currentIndex = isIndex(indexText) ? indexText : null;
  if (currentIndex === null && opts.layer === "team") {
    err(JSON.stringify({ level: "error", event: "no team index", index: indexPath, fix: "create the index with a standards setup skill first" }));
    return 1;
  }
  const others = otherFiles(dir, file).map((path) => [path, read(path)]);
  const unique = [...new Map(records.map((r) => [r.id, r])).values()];
  const fresh = [];
  for (const r of unique) {
    if (cites(current, r.id)) continue;
    const [elsewhere] = others.find(([, text]) => cites(text, r.id)) ?? [];
    if (elsewhere) out(`${r.name} (${r.id}) is already adopted in ${elsewhere}, so it is not added again.`);
    else fresh.push(r);
  }
  if (!fresh.length) {
    out(`Nothing to write: every concept named is already adopted.`);
    return 0;
  }
  const blank = !current?.trim();
  const needsRow = currentIndex !== null && !currentIndex.split("\n").some((line) => line.startsWith("|") && line.split(/(?<!\\)\|/u)[3]?.trim() === file);
  const unindexed = currentIndex === null ? `No index at ${indexPath}: the standards folder is read file by file, so the file still loads.` : null;
  const eol = eolOf(current);
  const entries = fresh.map((r) => entry(r, eol)).join("");
  const breakNote = (path) => `A line break will also be added at the end of ${path}, which does not end with one.`;
  const fileLacksBreak = !blank && !current.endsWith("\n");
  const next = blank ? `${HEADER(opts.surface).replaceAll("\n", eol)}${entries}` : `${current}${fileLacksBreak ? eol : ""}${entries}`;
  const lineCount = next.split("\n").length - 1;
  if (lineCount > LINE_BUDGET) {
    err(JSON.stringify({ level: "warn", event: "standards file over budget", file: filePath, lines: lineCount, budget: LINE_BUDGET, contract: BUDGET_RULE }));
  }

  const indexed = needsRow ? withRow(currentIndex, row) : null;

  if (!opts.yes) {
    const action = current === null ? "Would create" : blank ? "Would fill the empty file" : "Would append to";
    out(`${action} ${filePath}:\n${blank ? next : entries}`);
    if (fileLacksBreak) out(breakNote(filePath));
    if (indexed) {
      out(`Would add ${indexed.table ? "a table holding this row" : "this row"} to ${indexPath}:\n${indexed.added}`);
      if (!currentIndex.endsWith("\n")) out(breakNote(indexPath));
    }
    if (unindexed) out(unindexed);
    out("Re-run with --yes to write.");
    return 3;
  }
  for (const [path, text] of [[filePath, next], ...(indexed ? [[indexPath, indexed.text]] : [])]) {
    try {
      write(path, text);
    } catch (e) {
      const message = `${path} could not be written: ${plainReason(e, "the file system refused the write")}`;
      err(JSON.stringify({ level: "error", event: "write failed", path, code: e.code ?? null, message }));
      return 1;
    }
  }
  out(`Adopted ${fresh.length} concept(s) into ${filePath}.`);
  if (unindexed) out(unindexed);
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exitCode = await main(process.argv.slice(2));
