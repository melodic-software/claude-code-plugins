#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { resolveSettings } from "./settings.mjs";

const DATA_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "data");
const STAGES = ["interview", "design", "plan", "build", "review", "operate", "any"];
const REVERSIBILITY = ["one-way", "two-way", "unrated"];
const SOURCE_BARS = ["official", "official-plus-confirming"];
const ID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/u;
const SKILL_OWNER = /^\/?[a-z0-9-]+:[a-z0-9-]+$/u;
const FETCH_TIMEOUT_MS = 10_000;
const FETCH_CONCURRENCY = 8;

const HELP = `Usage: lookup.mjs [TERM] [options]

Finds built-in engineering-concept records: pointers to each concept's official
source, never a definition. TERM matches an id, a name or an alias, whatever its
case; a merged id kept as an alias redirects to the surviving record. With no
TERM, every record that passes the filters is printed.

Options:
  --topic TOPIC             records from data/TOPIC.jsonl only
  --concern CONCERN         records with this concern
  --kind KIND               records of this kind
  --stage STAGE             ${STAGES.join("|")}; a record staged "any" always matches
  --reversibility VALUE     ${REVERSIBILITY.join("|")}
  --exclude ID|TOPIC        drop a record id or a whole topic; repeatable, unioned
                            with the exclude setting of every layer
  --source-bar BAR          ${SOURCE_BARS.join("|")}; overrides the source_bar
                            setting for this run
  --check-sources           fetch each source_url and mark unreachable ones for
                            re-sourcing; the only mode that touches the network
  --data-dir DIR            read records from DIR instead of the plugin's data/
  --project DIR             repository whose settings layers apply (default: the
                            git root of the working directory)
  --user-config FILE|-      the plugin's userConfig values: a JSON file, or - for
                            name=value lines on stdin
  --home DIR                user home, used only to report legacy config files
  -h, --help                show this help

Settings source_bar and exclude resolve through the plugin config cascade:
defaults, userConfig, <home>/engineering-concepts.yaml, then
<home>/engineering-concepts.local.yaml. A rejected value is reported on stderr.

Output: one JSON record per line on stdout, counterweights and conflicts_with as
{id, name}. Diagnostics: JSON lines on stderr, each rejected record with its
file:line in "at".
Exit: 0 records printed, 1 none matched, 2 invalid option.`;

const OPTIONS = {
  topic: { type: "string" },
  concern: { type: "string" },
  kind: { type: "string" },
  stage: { type: "string" },
  reversibility: { type: "string" },
  exclude: { type: "string", multiple: true, default: [] },
  "source-bar": { type: "string" },
  "check-sources": { type: "boolean", default: false },
  "data-dir": { type: "string" },
  project: { type: "string" },
  "user-config": { type: "string" },
  home: { type: "string", default: homedir() },
  help: { type: "boolean", short: "h", default: false },
};

const isText = (v) => typeof v === "string" && v.length > 0;
const isList = (v) => v === undefined || (Array.isArray(v) && v.every(isText));

function rejection(record) {
  if (!isText(record.id) || !ID.test(record.id)) return "id is not a kebab-case slug";
  for (const field of ["name", "concern", "kind", "owner"]) if (!isText(record[field])) return `${field} is missing`;
  if (!record.owner.startsWith("https://") && !SKILL_OWNER.test(record.owner)) return "owner is neither an https URL nor a plugin:skill name";
  if (!isText(record.source_url) || !record.source_url.startsWith("https://")) return "source_url is not an https URL";
  if (!STAGES.includes(record.stage)) return `stage is not one of ${STAGES.join("|")}`;
  if (!REVERSIBILITY.includes(record.reversibility)) return `reversibility is not one of ${REVERSIBILITY.join("|")}`;
  for (const field of ["aliases", "confirming_sources", "counterweights", "conflicts_with"]) {
    if (!isList(record[field])) return `${field} is not a list of strings`;
  }
  return null;
}

export function recordLines(path) {
  return readFileSync(path, "utf8")
    .split(/\r?\n/u)
    .map((text, i) => ({ line: i + 1, text }))
    .filter(({ text }) => text.trim());
}

export function parseRecord(text) {
  let record;
  try {
    record = JSON.parse(text);
  } catch (e) {
    return { reason: `not JSON: ${e.message}` };
  }
  const reason = record && typeof record === "object" ? rejection(record) : "not a JSON object";
  return reason ? { reason } : { record };
}

export function dataFiles(dataDir) {
  return readdirSync(dataDir).filter((f) => f.endsWith(".jsonl")).sort();
}

/** `shipped` marks the plugin's own data/, which is absent or empty until curated records ship. */
export function loadIndex(dataDir, err, { shipped = false } = {}) {
  const byId = new Map();
  const byName = new Map();
  let files = [];
  try {
    files = dataFiles(dataDir);
  } catch (e) {
    if (!(shipped && e.code === "ENOENT")) {
      err(JSON.stringify({ level: "error", event: "data directory unreadable", dir: dataDir, code: e.code }));
    }
  }
  if (shipped && files.length === 0) {
    err(JSON.stringify({ level: "info", event: "catalog empty", dir: dataDir, note: "no curated concepts ship yet" }));
  }
  for (const file of files) {
    const path = join(dataDir, file);
    const topic = basename(file, ".jsonl");
    for (const { line, text } of recordLines(path)) {
      const { record, reason } = parseRecord(text);
      if (reason) {
        err(JSON.stringify({ level: "error", event: "record rejected", at: `${path}:${line}`, file: path, line, reason }));
        continue;
      }
      byId.set(record.id, { aliases: [], counterweights: [], conflicts_with: [], ...record, topic });
      for (const name of [record.name, ...(record.aliases ?? [])]) byName.set(name.toLowerCase(), record.id);
    }
  }
  return { byId, byName };
}

const resolveId = (index, term) => (index.byId.has(term) ? term : index.byName.get(term.toLowerCase()));

function select(index, term, opts) {
  const excluded = new Set(opts.exclude.flatMap((v) => v.split(",")).map((v) => v.trim()).filter(Boolean));
  const id = term ? resolveId(index, term) : undefined;
  const pool = term ? (id === undefined ? [] : [index.byId.get(id)]) : [...index.byId.values()];
  return pool.filter(
    (r) =>
      !excluded.has(r.id) &&
      !excluded.has(r.topic) &&
      (!opts.topic || r.topic === opts.topic) &&
      (!opts.concern || r.concern === opts.concern) &&
      (!opts.kind || r.kind === opts.kind) &&
      (!opts.stage || r.stage === opts.stage || r.stage === "any") &&
      (!opts.reversibility || r.reversibility === opts.reversibility) &&
      (opts["source-bar"] === "official" || (r.confirming_sources ?? []).length > 0),
  );
}

function present(index, record) {
  const ref = (raw) => {
    const id = resolveId(index, raw);
    return id === undefined ? { id: raw, name: null } : { id, name: index.byId.get(id).name };
  };
  return { ...record, counterweights: record.counterweights.map(ref), conflicts_with: record.conflicts_with.map(ref) };
}

async function probe(url, fetchImpl) {
  try {
    const res = await fetchImpl(url, { redirect: "follow", signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
    await res.body?.cancel?.();
    return res.ok ? { reachable: true, status: res.status } : { reachable: false, status: res.status, needs_resourcing: true };
  } catch (e) {
    return { reachable: false, error: e.message, needs_resourcing: true };
  }
}

export async function checkSources(records, fetchImpl) {
  const checked = new Array(records.length);
  let next = 0;
  const worker = async () => {
    while (next < records.length) {
      const i = next++;
      checked[i] = { ...records[i], source_check: await probe(records[i].source_url, fetchImpl) };
    }
  };
  await Promise.all(Array.from({ length: Math.min(FETCH_CONCURRENCY, records.length) }, worker));
  return checked;
}

const STDIN_FD = 0;

function readUserConfig(source) {
  if (source !== "-") return JSON.parse(readFileSync(source, "utf8"));
  return Object.fromEntries(
    readFileSync(STDIN_FD, "utf8")
      .split(/\r?\n/u)
      .filter((line) => line.includes("="))
      .map((line) => [line.slice(0, line.indexOf("=")), line.slice(line.indexOf("=") + 1)]),
  );
}

function gitRoot(dir) {
  const r = spawnSync("git", ["-C", dir, "rev-parse", "--show-toplevel"], { encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : dir;
}

export async function main(
  argv,
  { fetch: fetchImpl = globalThis.fetch, out = console.log, err = console.error, shippedDataDir = DATA_DIR } = {},
) {
  const invalid = (option, value, allowed, error) => {
    err(JSON.stringify({ level: "error", event: "invalid option", option, value, ...(allowed && { allowed }), ...(error && { error }) }));
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
  if (opts.stage && !STAGES.includes(opts.stage)) return invalid("stage", opts.stage, STAGES);
  if (opts.reversibility && !REVERSIBILITY.includes(opts.reversibility)) return invalid("reversibility", opts.reversibility, REVERSIBILITY);
  if (opts["source-bar"] !== undefined && !SOURCE_BARS.includes(opts["source-bar"])) return invalid("source-bar", opts["source-bar"], SOURCE_BARS);

  let userConfig = {};
  if (opts["user-config"]) {
    try {
      userConfig = readUserConfig(opts["user-config"]);
    } catch (e) {
      return invalid("user-config", opts["user-config"], null, e.code ?? e.message);
    }
  }
  const settings = resolveSettings({ projectRoot: resolvePath(opts.project ?? gitRoot(process.cwd())), userConfig, userHome: opts.home, err });
  const filters = { ...opts, "source-bar": opts["source-bar"] ?? settings.source_bar, exclude: [...settings.exclude, ...opts.exclude] };

  const index = loadIndex(opts["data-dir"] ?? shippedDataDir, err, { shipped: opts["data-dir"] === undefined });
  let records = select(index, positionals.join(" ").trim(), filters).map((r) => present(index, r));
  if (opts["check-sources"]) records = await checkSources(records, fetchImpl);
  for (const record of records) out(JSON.stringify(record));
  return records.length ? 0 : 1;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exitCode = await main(process.argv.slice(2));
