#!/usr/bin/env node
// Offered HTML view for testing:audit.
//
// Genre: report. The markdown findings record stays the deliverable. A later
// fix pass re-reads that record, never this page. Every interpolated field
// goes through escapeHtml. The page is self-contained: inline style, no
// script, no image, no link, no loop-closure control.

import { readFileSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  escapeHtml,
  stampPage,
  validateRenderedPage,
} from "../../../lib/html-escape.mjs";

const CSS = `
:root {
  --ivory: #faf9f5;
  --slate: #141413;
  --clay-deep: #a0512e;
  --gray-300: #d1cfc5;
  --gray-500: #87867f;
  --white: #ffffff;
  --serif: ui-serif, Georgia, serif;
  --sans: system-ui, sans-serif;
  --mono: ui-monospace, monospace;
  --bg: var(--ivory);
  --fg: var(--slate);
  --muted: var(--gray-500);
  --border: 1.5px solid var(--gray-300);
  --focus: var(--clay-deep);
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: var(--slate);
    --fg: var(--ivory);
    --muted: var(--gray-300);
    --border: 1.5px solid var(--gray-500);
    --focus: #e89b7e;
  }
}
@media (prefers-reduced-motion: reduce) {
  * { animation: none !important; transition: none !important; }
}
html { color-scheme: light dark; }
body {
  margin: 0 auto;
  max-width: 860px;
  padding: 2rem 1.25rem 4rem;
  background: var(--bg);
  color: var(--fg);
  font-family: var(--sans);
  line-height: 1.55;
}
h1, h2, h3 { font-family: var(--serif); font-weight: 600; }
:focus { outline: 2px solid var(--focus); outline-offset: 2px; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; border-bottom: 1px solid var(--gray-300); padding: 0.45rem 0.5rem; vertical-align: top; }
code { font-family: var(--mono); }
.muted, .record { color: var(--muted); }
`.trim();

function asText(value) {
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return "";
}

function asList(value) {
  return Array.isArray(value) ? value : [];
}

function e(value) {
  return escapeHtml(asText(value));
}

function findingRows(findings) {
  const rows = asList(findings).filter((row) => row && typeof row === "object");
  if (rows.length === 0) {
    return "<tr><td>None.</td><td></td><td></td></tr>";
  }
  return rows
    .map(
      (row) =>
        `<tr><td><code title="${e(row.rule)}">${e(row.rule)}</code></td><td><code title="${e(row.location)}">${e(row.location)}</code></td><td>${e(row.detail)}</td></tr>`,
    )
    .join("");
}

/**
 * @param {Record<string, unknown>} model
 * @returns {string}
 */
export function buildAuditPage(model) {
  const source = model && typeof model === "object" ? model : {};
  const title = asText(source.title) || "Can't-fail test audit";
  const summary = asText(source.summary) || "None.";
  const coverage = asText(source.coverage) || "None.";
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${e(title)}</title>
<style>
${CSS}
</style>
</head>
<body>
<p class="muted">Report</p>
<h1>${e(title)}</h1>
<p>${e(summary)}</p>
<h2 id="coverage">Coverage</h2>
<p>${e(coverage)}</p>
<h2 id="findings">Findings</h2>
<table>
<thead><tr><th>Rule</th><th>Location</th><th>Detail</th></tr></thead>
<tbody>
${findingRows(source.findings)}
</tbody>
</table>
<p class="record">The markdown findings record is the deliverable. This page is an offered view.</p>
</body>
</html>
`;
  return stampPage(html);
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function fail(message, code) {
  process.stderr.write(`build-audit-view: ${message}\n`);
  process.exit(code);
}

function runCheck(path) {
  let html;
  try {
    html = readFileSync(path, "utf8");
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    fail(message, 2);
  }
  const verdict = validateRenderedPage(html);
  if (!verdict.ok) {
    fail(verdict.failures.join(","), 1);
  }
}

function runBuild() {
  let model;
  try {
    model = JSON.parse(readStdin());
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    fail(`invalid JSON (${message})`, 2);
  }
  if (!model || typeof model !== "object" || Array.isArray(model)) {
    fail("JSON root must be an object", 2);
  }
  const page = buildAuditPage(model);
  const verdict = validateRenderedPage(page);
  if (!verdict.ok) {
    fail(`refused to emit (${verdict.failures.join(",")})`, 1);
  }
  process.stdout.write(page);
}

function main() {
  const args = process.argv.slice(2);
  if (args[0] === "--check") {
    if (!args[1]) {
      fail("usage: build-audit-view.mjs --check <file>", 2);
    }
    runCheck(args[1]);
    return;
  }
  if (args.length > 0) {
    fail("usage: build-audit-view.mjs [< model.json] | --check <file>", 2);
  }
  runBuild();
}

const selfPath = fileURLToPath(import.meta.url);

function invokedDirectly() {
  const arg = process.argv[1];
  if (!arg) return false;
  try {
    return realpathSync(arg) === realpathSync(selfPath);
  } catch {
    return false;
  }
}

if (invokedDirectly()) {
  main();
}

export const BUILDER_DIR = dirname(selfPath);
export const HELPER_PATH = join(BUILDER_DIR, "../../../lib/html-escape.mjs");
