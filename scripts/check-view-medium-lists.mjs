#!/usr/bin/env node
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

export function readRegistry(text) {
  const block = /^export const MEDIUMS = Object\.freeze\(\{\r?\n([\s\S]*?)^\}\);/m.exec(text);
  const mediums = block ? [...block[1].matchAll(/^\s*([A-Za-z_$][\w$]*)\s*:/gm)].map((m) => m[1]) : [];
  const producers = [...text.matchAll(/\bproducer\(\s*"([^"]+)"/g)].map((m) => m[1]);
  return { mediums, producers };
}

export const producerDir = (producerId) => {
  const [plugin, skill] = producerId.split(":");
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

export function collect(root) {
  const { mediums, producers } = readRegistry(readFileSync(path.join(root, REGISTRY), "utf8"));
  if (!mediums.length || !producers.length) throw new Error(`${REGISTRY}: found no MEDIUMS keys or no producer(...) entries`);
  const skip = new Set(
    listRows(path.join(root, SHARED))
      .map((l) => l.split(/\s+/))
      .filter(([src]) => src === SHARED_SOURCE)
      .map(([, dest]) => dest),
  );
  const ids = new Set(mediums);
  const flagged = new Map();
  for (const producerId of producers) {
    const dir = producerDir(producerId);
    if (!existsSync(path.join(root, dir))) continue;
    for (const rel of walk(root, dir, skip).sort()) {
      for (const { line, ids: hit } of listings(rel, readFileSync(path.join(root, rel), "utf8"), ids)) {
        if (!flagged.has(producerId)) flagged.set(producerId, []);
        flagged.get(producerId).push(`${rel}:${line}: ${hit.map((id) => `\`${id}\``).join(", ")}`);
      }
    }
  }
  return { flagged, producers };
}

function exemptions(root) {
  return listRows(path.join(root, EXEMPTIONS)).map((row) => {
    const hash = row.indexOf("#");
    return { producerId: (hash < 0 ? row : row.slice(0, hash)).trim(), cites: hash >= 0 && /#\d+/.test(row.slice(hash + 1)) };
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
  const { flagged, producers } = result;
  const findings = [];
  const exempt = new Set();
  for (const { producerId, cites } of rows) {
    if (!producers.includes(producerId)) findings.push(`${EXEMPTIONS}: "${producerId}" is not a producer in ${REGISTRY}; delete the row`);
    else if (!flagged.has(producerId)) findings.push(`${EXEMPTIONS}: "${producerId}" lists no media any more; delete the row`);
    else if (exempt.has(producerId)) findings.push(`${EXEMPTIONS}: "${producerId}" is listed twice`);
    else if (!cites) findings.push(`${EXEMPTIONS}: "${producerId}" cites no issue; add "# #<issue>" naming its open slice`);
    exempt.add(producerId);
  }
  for (const [producerId, hits] of flagged) {
    if (exempt.has(producerId)) continue;
    for (const hit of hits) findings.push(`${hit} (producer ${producerId} lists media; leave the ids to ${REGISTRY})`);
  }
  if (findings.length) {
    for (const f of findings) out.error(f);
    out.error(`${findings.length} finding(s). A view producer names at most one medium id per line.`);
    return 1;
  }
  out.log(`view-medium-lists: no view producer lists media (${exempt.size} producer(s) exempt).`);
  return 0;
}

// Node loads the entry module from its real path, so a checkout reached through a
// symlink must compare real paths, or the gate never runs and exits 0.
const self = realpathSync(fileURLToPath(import.meta.url));
if (process.argv[1] && existsSync(process.argv[1]) && realpathSync(process.argv[1]) === self) {
  process.exitCode = main(process.argv.slice(2));
}
