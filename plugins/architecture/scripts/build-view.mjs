#!/usr/bin/env node
// Build an interactive view of one map-* record: the checked-in template plus
// the record's own rows as escaped JSON data, through the shared view builder
// (interactive profile). Writes the page to one deterministic path under the OS
// temp directory, never beside the record, and prints that path.
//
//   node build-view.mjs <kind> --record <record.json> [--from <node-id>]
//
// kind: landscape containers components dependencies data events flow context deployment.
// --from keeps the nodes reachable from that node id and the edges between
// them (the closure a component view charts), and drops the record's other
// arrays; it needs a nodes and an edges array.
//
// Every value in the record reaches the page as data, never as markup or script.
//
// Exit 0 built, 1 the record or the page fails its checks, 2 usage or environment.

import { chmodSync, lstatSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { buildView, ViewBuildError } from "../lib/view-builder.mjs";

const TITLES = {
  landscape: "Landscape",
  containers: "Containers",
  components: "Components",
  dependencies: "Dependencies",
  data: "Data model",
  events: "Events",
  flow: "Flow",
  context: "Context",
  deployment: "Deployment",
};
const NAME_KEYS = ["id", "name", "message", "title", "path", "entry", "resource"];

const isText = (value) => typeof value === "string";
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const show = (value) => (isText(value) ? value : JSON.stringify(value));

class RecordError extends Error {}

const rowOf = (kind, item) => {
  if (!isObject(item)) return { kind, name: show(item), fields: [] };
  const key = NAME_KEYS.find((candidate) => isText(item[candidate]) && item[candidate] !== "");
  const name = isText(item.from) && isText(item.to) ? `${item.from} -> ${item.to}` : key ? item[key] : kind;
  return { kind, name, fields: Object.entries(item).map(([field, value]) => `${field}: ${show(value)}`) };
};

// The nodes reachable from `start` over from -> to edges, `start` included.
const closureFrom = (record, start) => {
  const { nodes, edges } = record;
  if (!Array.isArray(nodes) || !Array.isArray(edges)) throw new RecordError("--from needs a record with nodes and edges");
  if (!nodes.some((node) => isObject(node) && node.id === start)) throw new RecordError(`no node ${start} in the record`);
  const seen = new Set([start]);
  for (let grew = true; grew; ) {
    grew = false;
    for (const edge of edges) {
      if (isObject(edge) && seen.has(edge.from) && isText(edge.to) && !seen.has(edge.to)) {
        seen.add(edge.to);
        grew = true;
      }
    }
  }
  // Findings and cycles name nodes outside the closure, so only the scalars, nodes and edges stay.
  const scalars = Object.entries(record).filter(([, value]) => value === null || typeof value !== "object");
  return {
    ...Object.fromEntries(scalars),
    nodes: nodes.filter((node) => isObject(node) && seen.has(node.id)),
    edges: edges.filter((edge) => isObject(edge) && seen.has(edge.from)),
  };
};

// Scalars become facts; each array is counted and its items become rows; an object becomes one row.
const viewData = (kind, record, from) => {
  const source = from ? closureFrom(record, from) : record;
  const facts = from ? [`scope: reachable from ${from}`] : [];
  const rows = [];
  for (const [key, value] of Object.entries(source)) {
    if (Array.isArray(value)) {
      facts.push(`${key}: ${value.length}`);
      rows.push(...value.map((item) => rowOf(key, item)));
    } else if (isObject(value)) {
      rows.push(rowOf(key, { name: key, ...value }));
    } else if (value !== "" && value !== null) {
      facts.push(`${key}: ${value}`);
    }
  }
  return { title: `${TITLES[kind]} view`, facts, rows };
};

const [kind, ...rest] = process.argv.slice(2);
const flags = {};
for (let i = 0; i < rest.length; i += 2) flags[rest[i]] = rest[i + 1];
if (!Object.hasOwn(TITLES, kind) || !flags["--record"] || Object.keys(flags).some((flag) => !["--record", "--from"].includes(flag))) {
  console.error(`usage: build-view.mjs ${Object.keys(TITLES).join("|")} --record <record.json> [--from <node-id>]`);
  process.exit(2);
}

try {
  let record;
  try {
    record = JSON.parse(readFileSync(flags["--record"], "utf8"));
  } catch (err) {
    throw err instanceof SyntaxError ? new RecordError("the record is not JSON") : err;
  }
  if (!isObject(record) || record.schema_version !== 1) throw new RecordError("the record is not a schema_version 1 map record");
  const page = buildView({
    profile: "interactive",
    template: readFileSync(fileURLToPath(new URL("../templates/map-view.html", import.meta.url)), "utf8"),
    data: viewData(kind, record, flags["--from"]),
  });
  // The temp root is shared: keep the directory private and never write through a link.
  const dir = join(tmpdir(), "architecture-views");
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  if (!lstatSync(dir).isDirectory())
    throw new Error("build-view: refusing a symlinked or non-directory output path");
  chmodSync(dir, 0o700);
  const out = join(dir, `${kind}.html`);
  rmSync(out, { force: true });
  writeFileSync(out, page, { mode: 0o600 });
  console.log(out);
} catch (err) {
  console.error(err instanceof RecordError ? `build-view: ${err.message}` : err.message);
  process.exit(err instanceof RecordError || err instanceof ViewBuildError ? 1 : 2);
}
