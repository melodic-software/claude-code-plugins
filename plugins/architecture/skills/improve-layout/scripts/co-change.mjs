#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";
import { resolve as resolveConfig } from "../../../lib/config-cascade.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const schema = JSON.parse(readFileSync(join(here, "../../../schemas/architecture.schema.json"), "utf8"));
const layoutSchema = schema.properties.layout;
const KEYS = Object.keys(layoutSchema.properties);
const CITED_COMMITS = 5;

const NUMERIC_FLAGS = Object.fromEntries(
  KEYS.filter((key) => layoutSchema.properties[key].type !== "array").map((key) => [`--${key.replaceAll("_", "-")}`, key]),
);

function fail(message) {
  process.stderr.write(`co-change: ${message}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const opts = { repo: ".", home: "docs/conventions", config: true, paths: [], overrides: {} };
  let authors = null;
  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    const value = () => {
      if (i + 1 >= argv.length) fail(`${flag} needs a value`);
      i += 1;
      return argv[i];
    };
    if (flag === "--repo") opts.repo = value();
    else if (flag === "--home") opts.home = value();
    else if (flag === "--no-config") opts.config = false;
    else if (flag === "--path") opts.paths.push(value());
    else if (flag === "--exclude-author") (authors ??= []).push(value());
    else if (flag === "--all-authors") authors = [];
    else if (Object.hasOwn(NUMERIC_FLAGS, flag)) {
      const key = NUMERIC_FLAGS[flag];
      const node = layoutSchema.properties[key];
      const raw = value();
      const number = Number(raw);
      const shaped = /^\d+(\.\d+)?$/.test(raw) && (node.type !== "integer" || Number.isInteger(number));
      const inRange = (node.minimum === undefined || number >= node.minimum) && (node.maximum === undefined || number <= node.maximum);
      if (!shaped || !inRange) fail(`${flag} ${JSON.stringify(raw)} is not a valid ${key} (${node.description})`);
      opts.overrides[key] = number;
    } else fail(`unknown argument ${JSON.stringify(flag)}`);
  }
  if (authors) opts.overrides.exclude_authors = authors;
  return opts;
}

function settingsOf(opts, root) {
  const defaults = { layout: Object.fromEntries(KEYS.map((key) => [key, layoutSchema.properties[key].default])) };
  const values = { ...defaults.layout };
  const source = Object.fromEntries(KEYS.map((key) => [key, "defaults"]));
  const errors = [];
  if (opts.config) {
    const result = resolveConfig({ plugin: "architecture", projectRoot: root, home: opts.home, schema, defaults, userConfig: {} });
    for (const key of KEYS) {
      if (result.values.layout && Object.hasOwn(result.values.layout, key)) {
        values[key] = result.values.layout[key];
        source[key] = result.provenance[`layout.${key}`] ?? "defaults";
      }
    }
    for (const layer of result.layers) {
      layer.errors.forEach((message, i) => {
        const key = layer.error_keys[i];
        if (key === null || key === "layout" || key.startsWith("layout.")) errors.push(message);
      });
    }
  }
  for (const [key, value] of Object.entries(opts.overrides)) {
    values[key] = value;
    source[key] = "argument";
  }
  if (values.min_coupling > values.max_coupling) fail(`min_coupling ${values.min_coupling} is above max_coupling ${values.max_coupling}`);
  return { values, source, errors };
}

const cmp = (x, y) => (x < y ? -1 : x > y ? 1 : 0);
const round2 = (x) => Math.round(x * 100) / 100;
const increment = (map, key) => map.set(key, (map.get(key) ?? 0) + 1);
const append = (map, key, value) => {
  if (!map.has(key)) map.set(key, []);
  map.get(key).push(value);
};

function readHistory(root, count, paths) {
  const args = ["-C", root, "-c", "core.quotepath=off", "-c", "log.showSignature=false", "log", "--no-color", "--no-merges", "--no-renames", "--full-diff", "--name-only", `--max-count=${count}`, "--format=%x1e%H%x1f%an"];
  if (paths.length) args.push("--", ...paths);
  const run = spawnSync("git", args, { encoding: "utf8", maxBuffer: 1024 * 1024 * 1024 });
  if (run.error) fail(`git did not run: ${run.error.message}`);
  if (run.status !== 0 && /does not have any commits/.test(run.stderr)) return [];
  if (run.status !== 0) fail(`git log failed: ${run.stderr.trim()}`);
  return run.stdout
    .split("\x1e")
    .slice(1)
    .map((record) => {
      const [head, ...lines] = record.split("\n");
      const [hash, author] = head.split("\x1f");
      return { hash, author, files: [...new Set(lines.filter((line) => line !== "").map(unquote))].sort() };
    });
}

const ESCAPES = { a: 7, b: 8, t: 9, n: 10, v: 11, f: 12, r: 13, '"': 34, "\\": 92 };

/** A path git printed C-quoted (one holding `"`, `\` or a control character), as written on disk. */
function unquote(line) {
  if (line.length < 2 || !line.startsWith('"') || !line.endsWith('"')) return line;
  const bytes = [];
  const body = line.slice(1, -1);
  for (let i = 0; i < body.length; i += 1) {
    if (body[i] !== "\\") {
      bytes.push(...Buffer.from(body[i], "utf8"));
    } else if (/^[0-7]{3}$/.test(body.slice(i + 1, i + 4))) {
      bytes.push(parseInt(body.slice(i + 1, i + 4), 8));
      i += 3;
    } else {
      bytes.push(ESCAPES[body[i + 1]] ?? body.charCodeAt(i + 1));
      i += 1;
    }
  }
  return Buffer.from(bytes).toString("utf8");
}

function analyze(commits, s, paths) {
  const prefixes = paths.map((p) => p.replace(/^(\.\/)+/, "").replace(/\/+$/, "")).filter((p) => p !== "" && p !== ".");
  const inScope = (file) => prefixes.length === 0 || prefixes.some((p) => file === p || file.startsWith(`${p}/`));
  const folderOf = (file) => {
    const parts = file.split("/").slice(0, -1);
    const kept = s.folder_depth > 0 ? parts.slice(0, s.folder_depth) : parts;
    return kept.length ? kept.join("/") : ".";
  };

  const dropped = { excluded_authors: 0, oversized: 0, no_files: 0 };
  const kept = [];
  for (const commit of commits) {
    if (s.exclude_authors.some((text) => text !== "" && commit.author.includes(text))) dropped.excluded_authors += 1;
    else if (commit.files.length > s.max_changeset_size) dropped.oversized += 1;
    else {
      const files = commit.files.filter(inScope);
      if (files.length) kept.push({ hash: commit.hash, files });
      else dropped.no_files += 1;
    }
  }

  const revs = new Map();
  for (const commit of kept) for (const file of commit.files) increment(revs, file);
  const folderSize = new Map();
  for (const file of revs.keys()) increment(folderSize, folderOf(file));
  const active = new Set([...revs].filter(([, n]) => n >= s.min_revs).map(([file]) => file));

  const shared = new Map();
  for (const commit of kept) {
    const files = commit.files.filter((file) => active.has(file));
    for (let i = 0; i < files.length; i += 1) {
      for (let j = i + 1; j < files.length; j += 1) {
        append(shared, `${files[i]}\0${files[j]}`, commit.hash);
      }
    }
  }

  let sharedReached = false;
  const pairs = [];
  for (const [key, hashes] of shared) {
    if (hashes.length < s.min_shared_revs) continue;
    sharedReached = true;
    const [a, b] = key.split("\0");
    const degree = Math.floor((200 * hashes.length) / (revs.get(a) + revs.get(b)));
    if (degree < s.min_coupling || degree > s.max_coupling) continue;
    pairs.push({ a, b, shared: hashes.length, revs_a: revs.get(a), revs_b: revs.get(b), degree, commits: hashes.slice(0, CITED_COMMITS), cluster: null });
  }
  pairs.sort((p, q) => cmp(p.a, q.a) || cmp(p.b, q.b));

  const parent = new Map();
  const find = (x) => {
    let root = x;
    while (parent.get(root) !== root) root = parent.get(root);
    return root;
  };
  for (const pair of pairs) for (const file of [pair.a, pair.b]) if (!parent.has(file)) parent.set(file, file);
  for (const pair of pairs) {
    const [ra, rb] = [find(pair.a), find(pair.b)].sort(cmp);
    if (ra !== rb) parent.set(rb, ra);
  }
  const groups = new Map();
  for (const file of [...parent.keys()].sort(cmp)) append(groups, find(file), file);

  const patternOf = (spread, focus) => {
    if (spread === 1) return focus >= s.encapsulated_min_focus ? "well-encapsulated" : "well-confined";
    if (spread >= s.crosscutting_min_spread && focus <= s.crosscutting_max_focus) return "crosscutting";
    return "unclassified";
  };
  const clusters = [...groups.values()]
    .filter((files) => files.length >= s.min_cluster_size)
    .sort((x, y) => cmp(x[0], y[0]))
    .map((files, i) => {
      const byFolder = new Map();
      for (const file of files) increment(byFolder, folderOf(file));
      const folders = [...byFolder]
        .sort((x, y) => cmp(x[0], y[0]))
        .map(([folder, n]) => ({ folder, cluster_files: n, folder_files: folderSize.get(folder) }));
      const focus = round2(folders.reduce((sum, f) => sum + (f.cluster_files / f.folder_files) * (f.cluster_files / files.length), 0));
      return { id: `c${i + 1}`, files, folders, spread: folders.length, focus, pattern: patternOf(folders.length, focus), mixed_folders: [] };
    });

  const clusterOf = new Map();
  for (const cluster of clusters) for (const file of cluster.files) clusterOf.set(file, cluster.id);
  for (const pair of pairs) pair.cluster = clusterOf.get(pair.a) ?? null;

  const touchedBy = new Map();
  for (const cluster of clusters) for (const { folder } of cluster.folders) append(touchedBy, folder, cluster.id);
  const mixedFolders = [...touchedBy]
    .filter(([, ids]) => ids.length >= 2)
    .sort((x, y) => cmp(x[0], y[0]))
    .map(([folder, ids]) => ({ folder, clusters: ids }));
  for (const { folder, clusters: ids } of mixedFolders) for (const cluster of clusters) if (ids.includes(cluster.id)) cluster.mixed_folders.push(folder);

  const history = active.size === 0 || !sharedReached ? "too-little" : "enough";
  const window = `${kept.length} of ${commits.length} commits read (window ${s.history_commits}) survived the filters`;
  let message;
  if (history === "too-little") {
    const short = active.size === 0 ? `no file reached ${s.min_revs} commits` : `no pair reached ${s.min_shared_revs} shared commits`;
    message = `too little history: ${window}, and ${short}; no candidate`;
  } else if (clusters.length === 0) message = `${window}; ${pairs.length} pair(s) passed, and no cluster reached ${s.min_cluster_size} files`;
  else message = `${window}; ${pairs.length} pair(s) passed, forming ${clusters.length} cluster(s)`;

  return {
    window: { history_commits: s.history_commits, read: commits.length, kept: kept.length, dropped },
    history,
    message,
    files: [...active].sort(cmp).map((path) => ({ path, revs: revs.get(path), folder: folderOf(path) })),
    pairs,
    clusters,
    mixed_folders: mixedFolders,
  };
}

const opts = parseArgs(process.argv.slice(2));
const root = resolvePath(opts.repo);
const settings = settingsOf(opts, root);
const commits = readHistory(root, settings.values.history_commits, opts.paths);
const report = { schema_version: 1, settings, scope: opts.paths, ...analyze(commits, settings.values, opts.paths) };
process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
