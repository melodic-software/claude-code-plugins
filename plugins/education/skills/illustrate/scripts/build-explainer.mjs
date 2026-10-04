#!/usr/bin/env node
// Build the illustrate explainer from one JSON model: the markdown record, and
// optionally the interactive page view of it.
//
//   build-explainer.mjs --record <out.md> [--page <out.html>] < model.json
//   build-explainer.mjs --check <page.html>
//
// The page comes only from the checked-in template plus the model as JSON data,
// through the shared view builder's interactive profile, so no model text is
// ever written into markup. Exit 0 ok, 1 the page fails its profile, 2 usage.
// A step label cut to the cap prints one warning line on stderr and still exits 0.

import { mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { asText, rows, textList } from "../../../lib/page-kit.mjs";
import { buildView, validateView, ViewBuildError } from "../../../lib/view-builder.mjs";

const TEMPLATE = new URL("../templates/explainer.html", import.meta.url);

// A longer flow goes one step per line: a wrapped row of arrows would start a line with one.
const FLOW_ROW_MAX = 4;
const LABEL_MAX = 40;

// A label over the cap, cut at the last space that fits, else hard, ending in an ellipsis.
function capLabel(label) {
  const chars = [...label];
  if (chars.length <= LABEL_MAX) return label;
  const head = chars.slice(0, LABEL_MAX);
  const space = head.findLastIndex((char) => /\s/.test(char));
  const kept = space > 0 ? head.slice(0, space) : head.slice(0, LABEL_MAX - 1);
  return `${kept.join("").trimEnd()}…`;
}

/**
 * @param {Record<string, unknown>} model
 * @param {string[]} [warnings] receives one line per step label cut to the cap
 */
function normalize(model, warnings = []) {
  const source = model && typeof model === "object" ? model : {};
  return {
    title: asText(source.title) || "Explainer",
    summary: textList(source.summary),
    diagrams: rows(source.diagrams).map((diagram, d) => {
      const steps = textList(diagram.steps).map((step, s) => {
        const label = capLabel(step);
        if (label !== step) {
          warnings.push(
            `diagram ${d + 1} step ${s + 1}: label of ${[...step].length} characters cut to ${LABEL_MAX}; put the detail in the diagram's text lines`,
          );
        }
        return label;
      });
      const stack = asText(diagram.kind) === "stack";
      const column = !stack && steps.length > FLOW_ROW_MAX;
      return {
        heading: asText(diagram.heading),
        flow: stack || column ? [] : steps,
        flowcol: column ? steps : [],
        stack: stack ? steps : [],
        caption: asText(diagram.caption),
        text: textList(diagram.text),
      };
    }),
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

/**
 * @param {Record<string, unknown>} model
 * @returns {string} the markdown record
 */
export function buildExplainerRecord(model) {
  const view = normalize(model);
  const out = [`# ${md(view.title)}`, ""];
  for (const line of view.summary) out.push(md(line), "");
  for (const diagram of view.diagrams) {
    out.push(`## ${md(diagram.heading) || "Picture"}`, "");
    const flow = [...diagram.flow, ...diagram.flowcol];
    if (flow.length) out.push(flow.map(md).join(" → "), "");
    if (diagram.stack.length) out.push(...diagram.stack.map((step) => `- ${md(step)}`), "");
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
