#!/usr/bin/env node
// Build the illustrate explainer from one JSON model: the markdown record, and
// optionally the interactive page view of it.
//
//   build-explainer.mjs --record <out.md> [--page <out.html>] < model.json
//   build-explainer.mjs --check <page.html>
//
// The page comes only from the checked-in template plus the model as JSON data,
// through the shared view builder's interactive profile, so no model text is
// ever written into markup. Exit 0 ok, 1 the page fails its profile, 2 usage
// or a model the page cannot draw (an unknown kind, a compare of the wrong width).
// A label cut to the cap prints one warning line on stderr and still exits 0.

import { mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { asText, rows, textList } from "../../../lib/page-kit.mjs";
import { buildView, validateView, ViewBuildError } from "../../../lib/view-builder.mjs";

const TEMPLATE = new URL("../templates/explainer.html", import.meta.url);

// A longer flow goes one step per line: a wrapped row of arrows would start a line with one.
const FLOW_ROW_MAX = 4;
const LABEL_MAX = 40;
const KINDS = ["flow", "stack", "hub", "timeline", "compare", "before-after"];
const COMPARE_MIN = 2;
const COMPARE_MAX = 4;

// A label over the cap, cut at the last space that fits, else hard, ending in an ellipsis.
function capLabel(label) {
  const chars = [...label];
  if (chars.length <= LABEL_MAX) return label;
  const head = chars.slice(0, LABEL_MAX);
  const space = head.findLastIndex((char) => /\s/.test(char));
  const kept = space > 0 ? head.slice(0, space) : head.slice(0, LABEL_MAX - 1);
  return `${kept.join("").trimEnd()}…`;
}

// Every diagram carries every kind's lists, empty but for its own kind's, so only one renders.
const EMPTY = { flow: [], flowcol: [], stack: [], center: "", branches: [], points: [], columns: [], before: [], after: [] };

/**
 * @param {Record<string, unknown>} diagram
 * @param {number} d the diagram's position, from 0
 * @param {string[]} warnings
 */
function shape(diagram, d, warnings) {
  const name = `diagram ${d + 1}`;
  const kind = diagram.kind === undefined || diagram.kind === null || diagram.kind === "" ? "flow" : diagram.kind;
  if (!KINDS.includes(kind)) {
    throw new Error(`${name}: unknown kind ${JSON.stringify(kind)}; use one of ${KINDS.join(", ")}`);
  }
  const cut = (text, where) => {
    const label = capLabel(text);
    if (label !== text) {
      warnings.push(
        `${name} ${where}: label of ${[...text].length} characters cut to ${LABEL_MAX}; put the detail in the diagram's text lines`,
      );
    }
    return label;
  };
  const labels = (value, where) => textList(value).map((text, n) => cut(text, `${where} ${n + 1}`));
  if (kind === "flow" || kind === "stack") {
    const steps = labels(diagram.steps, "step");
    if (kind === "stack") return { ...EMPTY, stack: steps };
    return steps.length > FLOW_ROW_MAX ? { ...EMPTY, flowcol: steps } : { ...EMPTY, flow: steps };
  }
  if (kind === "hub") {
    const center = asText(diagram.center);
    return { ...EMPTY, center: cut(center, "center"), branches: labels(diagram.branches, "branch") };
  }
  if (kind === "timeline") {
    const points = rows(diagram.points)
      .map((point) => ({ when: asText(point.when), label: asText(point.label) }))
      .filter((point) => point.when !== "" || point.label !== "")
      .map((point, n) => ({ when: point.when, label: cut(point.label, `point ${n + 1}`) }));
    return { ...EMPTY, points };
  }
  if (kind === "compare") {
    const columns = rows(diagram.columns)
      .map((column) => ({ heading: asText(column.heading), items: textList(column.items) }))
      .filter((column) => column.heading !== "" || column.items.length > 0)
      .map((column, c) => ({
        heading: column.heading,
        items: column.items.map((item, n) => cut(item, `column ${c + 1} item ${n + 1}`)),
      }));
    if (columns.length < COMPARE_MIN || columns.length > COMPARE_MAX) {
      throw new Error(`${name}: compare needs ${COMPARE_MIN} to ${COMPARE_MAX} columns, got ${columns.length}`);
    }
    return { ...EMPTY, columns };
  }
  return { ...EMPTY, before: labels(diagram.before, "before"), after: labels(diagram.after, "after") };
}

/**
 * @param {Record<string, unknown>} model
 * @param {string[]} [warnings] receives one line per label cut to the cap
 */
function normalize(model, warnings = []) {
  const source = model && typeof model === "object" ? model : {};
  return {
    title: asText(source.title) || "Explainer",
    summary: textList(source.summary),
    diagrams: rows(source.diagrams).map((diagram, d) => ({
      heading: asText(diagram.heading),
      ...shape(diagram, d, warnings),
      caption: asText(diagram.caption),
      text: textList(diagram.text),
    })),
    terms: rows(source.terms)
      .filter((row) => asText(row.term) !== "")
      .map((row) => ({ term: asText(row.term), plain: asText(row.plain) })),
    sources: textList(source.sources),
  };
}

/**
 * @param {Record<string, unknown>} model
 * @returns {string} the validated interactive page
 */
export function buildExplainerPage(model) {
  return buildView({
    profile: "interactive",
    template: readFileSync(TEMPLATE, "utf8"),
    data: normalize(model),
  });
}

// One line of record text: no line breaks, no raw HTML a markdown viewer would render, and no
// link or image syntax (escaped brackets cannot open one).
const md = (value) =>
  asText(value)
    .replace(/\s+/g, " ")
    .trim()
    .replaceAll("\\", "\\\\")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("[", "\\[")
    .replaceAll("]", "\\]");

const cell = (value) => md(value).replaceAll("|", "\\|");

/** @param {{heading: string, items: string[]}[]} columns */
function table(columns) {
  const depth = Math.max(0, ...columns.map((column) => column.items.length));
  const line = (cells) => `| ${cells.join(" | ")} |`;
  return [
    line(columns.map((column) => cell(column.heading))),
    line(columns.map(() => "---")),
    ...Array.from({ length: depth }, (_, n) => line(columns.map((column) => cell(column.items[n] ?? "")))),
  ];
}

// One mermaid label, always written inside double quotes. Collapsing line breaks means no label
// text starts a statement line (click, style, classDef), and with backticks gone none can close
// the fence. Mermaid entity codes stand in for every character that could end the quotes, open a
// %%{...}%% directive, or render as HTML, and `#` is coded too so a label's own entity reads
// literally. Mermaid refuses an empty quoted label, so one with nothing left is a single space.
const MERMAID_ENTITIES = { "#": "#35;", '"': "#quot;", "%": "#37;", "&": "#amp;", "<": "#lt;", ">": "#gt;" };
const mermaidLabel = (value) =>
  asText(value)
    .replace(/\s+/g, " ")
    .replace(/[`\p{C}]/gu, "")
    .replace(/ {2,}/g, " ")
    .trim()
    .replace(/[#"%&<>]/g, (char) => MERMAID_ENTITIES[char]) || " ";

/**
 * The diagram as mermaid source, built only from builder-made ids and quoted labels, or null when
 * it has nothing to draw. Every kind is a flowchart so one label rule covers them all.
 * @param {ReturnType<typeof normalize>["diagrams"][number]} diagram
 */
function mermaid(diagram) {
  let count = 0;
  const lines = [];
  const node = (label, indent = "    ") => {
    count += 1;
    lines.push(`${indent}n${count}["${mermaidLabel(label)}"]`);
    return `n${count}`;
  };
  const chain = (labels, link) => {
    const ids = labels.map((label) => node(label));
    if (ids.length > 1) lines.push(`    ${ids.join(` ${link} `)}`);
  };
  const group = (id, title, items) => {
    lines.push(`    subgraph ${id}["${mermaidLabel(title)}"]`);
    for (const item of items) node(item, "        ");
    lines.push("    end");
  };
  let direction = "LR";
  if (diagram.flow.length) chain(diagram.flow, "-->");
  if (diagram.flowcol.length) {
    direction = "TB";
    chain(diagram.flowcol, "-->");
  }
  if (diagram.stack.length) {
    direction = "TB";
    chain(diagram.stack, "---");
  }
  if (diagram.center || diagram.branches.length) {
    const center = diagram.center ? node(diagram.center) : null;
    const branches = diagram.branches.map((branch) => node(branch));
    if (center) for (const branch of branches) lines.push(`    ${center} --> ${branch}`);
  }
  if (diagram.points.length) {
    direction = "TB";
    chain(
      diagram.points.map((point) => [point.when, point.label].filter(Boolean).join(": ")),
      "-->",
    );
  }
  for (const [c, column] of diagram.columns.entries()) group(`s${c + 1}`, column.heading, column.items);
  if (diagram.before.length) group("s1", "Before", diagram.before);
  if (diagram.after.length) group("s2", "After", diagram.after);
  if (diagram.before.length && diagram.after.length) lines.push("    s1 --> s2");
  return lines.length ? ["```mermaid", `flowchart ${direction}`, ...lines, "```"] : null;
}

/**
 * @param {Record<string, unknown>} model
 * @returns {string} the markdown record
 */
export function buildExplainerRecord(model) {
  const view = normalize(model);
  const out = [`# ${md(view.title)}`, ""];
  for (const line of view.summary) out.push(md(line), "");
  for (const diagram of view.diagrams) {
    out.push(`## ${md(diagram.heading) || "Diagram"}`, "");
    const flow = [...diagram.flow, ...diagram.flowcol];
    if (flow.length) out.push(flow.map(md).join(" → "), "");
    if (diagram.stack.length) out.push(...diagram.stack.map((step) => `- ${md(step)}`), "");
    if (diagram.center) out.push(md(diagram.center), "");
    if (diagram.branches.length) out.push(...diagram.branches.map((branch) => `- ${md(branch)}`), "");
    if (diagram.points.length) {
      out.push(...diagram.points.map((point) => `- ${[point.when, point.label].filter(Boolean).map(md).join(": ")}`), "");
    }
    if (diagram.columns.length) out.push(...table(diagram.columns), "");
    if (diagram.before.length) out.push("Before:", "", ...diagram.before.map((item) => `- ${md(item)}`), "");
    if (diagram.after.length) out.push("After:", "", ...diagram.after.map((item) => `- ${md(item)}`), "");
    const drawing = mermaid(diagram);
    if (drawing) out.push(...drawing, "");
    if (diagram.caption) out.push(`**${md(diagram.caption)}**`, "");
    for (const line of diagram.text) out.push(md(line), "");
  }
  if (view.terms.length) {
    out.push("## Words used here", "", ...view.terms.map((row) => `- **${md(row.term)}**: ${md(row.plain)}`), "");
  }
  if (view.sources.length) {
    out.push("## Where this came from", "", ...view.sources.map((item) => `- ${md(item)}`), "");
  }
  return `${out.join("\n").trimEnd()}\n`;
}

function invokedDirectly() {
  try {
    return Boolean(process.argv[1]) && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

// The path with its nearest existing ancestor resolved through symlinks.
function realTarget(path) {
  const parts = [];
  let dir = resolve(path);
  for (;;) {
    try {
      return join(realpathSync(dir), ...parts);
    } catch {
      if (dirname(dir) === dir) return resolve(path);
      parts.unshift(basename(dir));
      dir = dirname(dir);
    }
  }
}

function write(path, text) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text);
  return `wrote ${path}\n`;
}

function main(args) {
  const usage = "usage: build-explainer.mjs --record <out.md> [--page <out.html>] < model.json | --check <page.html>";
  const opts = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!["--record", "--page", "--check"].includes(args[i]) || !args[i + 1]) return [2, "", usage];
    opts[args[i].slice(2)] = args[i + 1];
  }
  if (opts.check) {
    if (args.length > 2) return [2, "", usage];
    let html;
    try {
      html = readFileSync(opts.check, "utf8");
    } catch (error) {
      return [2, "", error.message];
    }
    const verdict = validateView(html);
    return verdict.ok ? [0, "ok\n", ""] : [1, "", verdict.failures.join(",")];
  }
  if (!opts.record) return [2, "", usage];
  let model;
  try {
    model = JSON.parse(readFileSync(0, "utf8"));
  } catch (error) {
    return [2, "", `invalid JSON (${error.message})`];
  }
  if (!model || typeof model !== "object" || Array.isArray(model)) {
    return [2, "", "JSON root must be an object"];
  }
  if (opts.page && dirname(realTarget(opts.record)) === dirname(realTarget(opts.page))) {
    return [2, "", "--page and --record must not share a directory; keep HTML views away from the markdown record"];
  }
  try {
    // Build the page before writing anything, so a refused page leaves no half-written pair.
    const page = opts.page ? buildExplainerPage(model) : null;
    let out = write(opts.record, buildExplainerRecord(model));
    if (page !== null) {
      try {
        out += write(opts.page, page);
      } catch (error) {
        rmSync(opts.record, { force: true });
        throw error;
      }
    }
    const warnings = [];
    normalize(model, warnings);
    return [0, out, warnings.join("\n")];
  } catch (error) {
    return [error instanceof ViewBuildError ? 1 : 2, "", error.message];
  }
}

if (invokedDirectly()) {
  const [code, out, err] = main(process.argv.slice(2));
  if (out) process.stdout.write(out);
  for (const line of err ? err.split("\n") : []) process.stderr.write(`build-explainer: ${line}\n`);
  process.exitCode = code;
}
