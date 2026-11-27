#!/usr/bin/env node
import { chmodSync, lstatSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { applyBranding } from "../lib/html-branding.mjs";
import { managedSettingsFiles, readOperatorOptions, resolveInstall } from "../lib/plugin-options.mjs";
import { buildView, ViewBuildError } from "../lib/view-builder.mjs";
import { brandingReportLines, findRoot, resolveBranding } from "../lib/view-settings.mjs";
import { DeepeningRecordError, parseDeepening, renderDeepening, validateDeepeningPage } from "./deepening-report.mjs";

const PLUGIN_ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));

const readBrandingOption = (flagValue) => {
  if (flagValue !== undefined) return flagValue;
  try {
    const install = resolveInstall(PLUGIN_ROOT);
    const configDir = process.env.CLAUDE_CONFIG_DIR;
    const managed = configDir ? [] : managedSettingsFiles();
    const userSettings = install.userSettings ?? (configDir ? join(configDir, "settings.json") : null);
    const opts = readOperatorOptions({ ...install, userSettings }, managed, ["branding"]);
    return opts.branding?.value ?? null;
  } catch (err) {
    console.error(`notice: userConfig branding could not be read (${err.message}); ignored`);
    return null;
  }
};

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
  deepening: "Deepening review",
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

const closureFrom = (record, start) => {
  const { nodes, edges } = record;
  if (!Array.isArray(nodes) || !Array.isArray(edges)) throw new RecordError("--from needs a record with nodes and edges");
  if (!nodes.some((node) => isObject(node) && node.id === start)) throw new RecordError(`no node ${start} in the record`);
  const projects = new Set(nodes.filter((node) => isObject(node) && node.kind === "project").map((node) => node.id));
  const seen = new Set([start]);
  for (let grew = true; grew; ) {
    grew = false;
    for (const edge of edges) {
      if (
        isObject(edge) &&
        edge.kind === "project" &&
        edge.status !== "unresolved" &&
        seen.has(edge.from) &&
        projects.has(edge.to) &&
        !seen.has(edge.to)
      ) {
        seen.add(edge.to);
        grew = true;
      }
    }
  }
  const scalars = Object.entries(record).filter(([, value]) => value === null || typeof value !== "object");
  return {
    ...Object.fromEntries(scalars),
    nodes: nodes.filter((node) => isObject(node) && seen.has(node.id)),
    edges: edges.filter((edge) => isObject(edge) && seen.has(edge.from) && seen.has(edge.to)),
  };
};

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

const deepeningPage = (record, branding) => {
  const page = renderDeepening(parseDeepening(record), { branding });
  const checked = validateDeepeningPage(page);
  if (!checked.ok) throw new ViewBuildError(checked.failures);
  return page;
};

const ALLOWED_FLAGS = ["--record", "--from", "--branding-option", "--team-ref"];
const [kind, ...rest] = process.argv.slice(2);
const flags = {};
let flagError = rest.length % 2 !== 0;
for (let i = 0; i < rest.length; i += 2) {
  flags[rest[i]] = rest[i + 1];
  if (typeof rest[i + 1] !== "string") flagError = true;
}
if (flagError || !Object.hasOwn(TITLES, kind) || !flags["--record"] || Object.keys(flags).some((flag) => !ALLOWED_FLAGS.includes(flag))) {
  console.error(`usage: build-view.mjs ${Object.keys(TITLES).join("|")} --record <record.json> [--from <node-id>] [--branding-option <json>] [--team-ref <ref>]`);
  process.exit(2);
}

try {
  let record;
  try {
    record = JSON.parse(readFileSync(flags["--record"], "utf8"));
  } catch (err) {
    throw err instanceof SyntaxError ? new RecordError("the record is not JSON") : err;
  }
  if (kind === "deepening" && flags["--from"]) throw new RecordError("--from does not apply to the deepening record");
  if (kind !== "deepening" && (!isObject(record) || record.schema_version !== 1)) throw new RecordError("the record is not a schema_version 1 record");
  const branding = resolveBranding({
    userConfig: readBrandingOption(flags["--branding-option"]),
    projectRoot: findRoot(),
    teamRef: flags["--team-ref"] ?? null,
  });
  const tokensCss = readFileSync(fileURLToPath(new URL("../reference/html-tokens.css", import.meta.url)), "utf8");
  const page = kind === "deepening" ? deepeningPage(record, branding) : buildView({
    profile: "interactive",
    template: applyBranding(
      readFileSync(fileURLToPath(new URL("../templates/map-view.html", import.meta.url)), "utf8"),
      { tokensCss, branding },
    ),
    data: viewData(kind, record, flags["--from"]),
  });
  if (branding.notices.length) {
    for (const line of brandingReportLines(branding)) {
      if (line.startsWith("notice:")) console.error(line);
    }
  }
  const dir = join(tmpdir(), "architecture-views");
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  if (!lstatSync(dir).isDirectory())
    throw new Error("build-view: refusing a symlinked or non-directory output path");
  chmodSync(dir, 0o700);
  const stem = basename(flags["--record"]).replace(/\.json$/i, "");
  const out = join(dir, kind === "deepening" && /^[A-Za-z0-9._-]{1,80}$/.test(stem) && !stem.startsWith(".") ? `${stem}.html` : `${kind}.html`);
  rmSync(out, { force: true });
  writeFileSync(out, page, { mode: 0o600 });
  console.log(out);
} catch (err) {
  console.error(err instanceof RecordError ? `build-view: ${err.message}` : err.message);
  process.exit(err instanceof RecordError || err instanceof DeepeningRecordError || err instanceof ViewBuildError ? 1 : 2);
}
