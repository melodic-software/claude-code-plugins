#!/usr/bin/env node
// Gate: a view lane's skill text names no list of media.
//
//   node scripts/check-view-medium-lists.mjs [--root <repo>]
//
// The rendered-view medium ids belong to lib/view-registry.mjs, which skills
// reach through the shared resolver. A view lane's `*.md` or `evals.json` that
// names two or more distinct medium ids, each as a backticked code span, on one
// line (or, in `evals.json`, in one JSON string) restates that registry and goes
// stale when it changes. One id on a line, such as a fixture prompt's setup,
// passes.
//
// The medium ids are the keys of `MEDIUMS` and the lanes the `lane(...)` entries,
// both read from the registry as text, never imported, so a run over a tree it
// must not execute stays a read. A `plugin:skill` lane covers
// plugins/<plugin>/skills/<skill>/ and a bare lane id plugins/<id>/. CHANGELOG.md,
// README.md and every copy scripts/shared-copies.txt lists for
// lib/rendered-view.md, which names the ids on purpose, are skipped.
//
// scripts/view-medium-list-exemptions.txt names the lanes still waiting on their
// slice, one lane id per row with a `# #<issue>` citation. A row whose lane has
// no flagged line, or names no registered lane, fails too, so the list only
// shrinks.
//
// Exit 0 clean, 1 findings, 2 usage or an unreadable input.
import { existsSync, readdirSync, readFileSync, realpathSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const REGISTRY = "lib/view-registry.mjs";
const EXEMPTIONS = "scripts/view-medium-list-exemptions.txt";
const SHARED = "scripts/shared-copies.txt";
const SHARED_SOURCE = "lib/rendered-view.md";
const SKIP_FILES = new Set(["CHANGELOG.md", "README.md"]);
const SKIP_DIRS = new Set([".git", "node_modules"]);

// readRegistry(text) -> { mediums: string[], lanes: string[] }
export function readRegistry(text) {
  const block = /^export const MEDIUMS = Object\.freeze\(\{\r?\n([\s\S]*?)^\}\);/m.exec(text);
  const mediums = block ? [...block[1].matchAll(/^\s*([A-Za-z_$][\w$]*)\s*:/gm)].map((m) => m[1]) : [];
  const lanes = [...text.matchAll(/\blane\(\s*"([^"]+)"/g)].map((m) => m[1]);
  return { mediums, lanes };
}

export const laneDir = (laneId) => {
  const [plugin, skill] = laneId.split(":");
  return skill ? `plugins/${plugin}/skills/${skill}` : `plugins/${plugin}`;
};

// mediaIn(text, mediums) -> the distinct medium ids `text` holds as backticked code spans.
export function mediaIn(text, mediums) {
  const ids = new Set();
  for (const m of text.matchAll(/`([^`\n]+)`/g)) if (mediums.has(m[1])) ids.add(m[1]);
  return [...ids];
}

// listings(rel, text, mediums) -> [{ line, ids }] for each line, or JSON string in
// evals.json, naming two or more medium ids.
export function listings(rel, text, mediums) {
  const found = [];
  const isEvals = path.basename(rel) === "evals.json";
  text.split(/\r?\n/).forEach((raw, i) => {
    const units = isEvals ? (raw.match(/"(?:[^"\\]|\\.)*"/g) ?? []).map(decoded) : [raw];
    for (const unit of units) {
      const ids = mediaIn(unit, mediums);
      if (ids.length >= 2) found.push({ line: i + 1, ids });
    }
  });
  return found;
}

function decoded(literal) {
  try {
    return JSON.parse(literal);
  } catch {
    return literal;
  }
}

function walk(root, rel, skip) {
  const files = [];
  for (const ent of readdirSync(path.join(root, rel), { withFileTypes: true })) {
    const r = `${rel}/${ent.name}`;
    if (ent.isDirectory()) {
      if (!SKIP_DIRS.has(ent.name)) files.push(...walk(root, r, skip));
    } else if (ent.isFile() && !skip.has(r) && !SKIP_FILES.has(ent.name) && (ent.name.endsWith(".md") || ent.name === "evals.json")) {
      files.push(r);
    }
  }
  return files;
}

const listRows = (file) =>
  existsSync(file)
    ? readFileSync(file, "utf8")
        .split(/\r?\n/)
        .map((l) => l.trim())
        .filter((l) => l && !l.startsWith("#"))
    : [];

// collect(root) -> { flagged: Map<laneId, string[]>, lanes: string[] }
export function collect(root) {
  const { mediums, lanes } = readRegistry(readFileSync(path.join(root, REGISTRY), "utf8"));
  if (!mediums.length || !lanes.length) throw new Error(`${REGISTRY}: found no MEDIUMS keys or no lane(...) entries`);
  const skip = new Set(
    listRows(path.join(root, SHARED))
      .map((l) => l.split(/\s+/))
      .filter(([src]) => src === SHARED_SOURCE)
      .map(([, dest]) => dest),
  );
  const ids = new Set(mediums);
  const flagged = new Map();
  for (const laneId of lanes) {
    const dir = laneDir(laneId);
    if (!existsSync(path.join(root, dir))) continue;
    for (const rel of walk(root, dir, skip).sort()) {
      for (const { line, ids: hit } of listings(rel, readFileSync(path.join(root, rel), "utf8"), ids)) {
        if (!flagged.has(laneId)) flagged.set(laneId, []);
        flagged.get(laneId).push(`${rel}:${line}: ${hit.map((id) => `\`${id}\``).join(", ")}`);
      }
    }
  }
  return { flagged, lanes };
}

// exemptions(root) -> [{ laneId, cites }]
function exemptions(root) {
  return listRows(path.join(root, EXEMPTIONS)).map((row) => {
    const hash = row.indexOf("#");
    return { laneId: (hash < 0 ? row : row.slice(0, hash)).trim(), cites: hash >= 0 && /#\d+/.test(row.slice(hash + 1)) };
  });
}

export function main(argv, out = { log: console.log, error: console.error }) {
  let root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--root" && argv[i + 1]) root = path.resolve(argv[++i]);
    else {
      out.error("usage: check-view-medium-lists.mjs [--root <repo>]");
      return 2;
    }
  }
  let result;
  let rows;
  try {
    result = collect(root);
    rows = exemptions(root);
  } catch (err) {
    out.error(`check-view-medium-lists: ${err.message}`);
    return 2;
  }
  const { flagged, lanes } = result;
  const findings = [];
  const exempt = new Set();
  for (const { laneId, cites } of rows) {
    if (!lanes.includes(laneId)) findings.push(`${EXEMPTIONS}: "${laneId}" is not a lane in ${REGISTRY}; delete the row`);
    else if (!flagged.has(laneId)) findings.push(`${EXEMPTIONS}: "${laneId}" lists no media any more; delete the row`);
    else if (exempt.has(laneId)) findings.push(`${EXEMPTIONS}: "${laneId}" is listed twice`);
    else if (!cites) findings.push(`${EXEMPTIONS}: "${laneId}" cites no issue; add "# #<issue>" naming its open slice`);
    exempt.add(laneId);
  }
  for (const [laneId, hits] of flagged) {
    if (exempt.has(laneId)) continue;
    for (const hit of hits) findings.push(`${hit} (lane ${laneId} lists media; leave the ids to ${REGISTRY})`);
  }
  if (findings.length) {
    for (const f of findings) out.error(f);
    out.error(`${findings.length} finding(s). A view lane names at most one medium id per line.`);
    return 1;
  }
  out.log(`view-medium-lists: no view lane lists media (${exempt.size} lane(s) exempt).`);
  return 0;
}

// Node loads the entry module from its real path, so a checkout reached through a
// symlink must compare real paths, or the gate never runs and exits 0.
const self = realpathSync(fileURLToPath(import.meta.url));
if (process.argv[1] && existsSync(process.argv[1]) && realpathSync(process.argv[1]) === self) {
  process.exitCode = main(process.argv.slice(2));
}
