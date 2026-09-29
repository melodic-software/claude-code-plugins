#!/usr/bin/env node
// Build the review plugin's pull-request explainer page.
//
// Every interpolated field goes through escapeHtml from the synced helper.
// The page is self-contained: inline style, no script, no image, no link.
// stampPage adds the generator marker. validateRenderedPage refuses a page
// this builder would not accept, including its own output if a template edit
// breaks the allowlist.

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
a:focus-visible, button:focus-visible, [tabindex]:focus-visible {
  outline: 3px solid var(--focus); outline-offset: 2px; border-radius: 2px;
}
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

function riskRows(risks) {
  const rows = asList(risks).filter((row) => row && typeof row === "object");
  if (rows.length === 0) {
    return "<tr><td>None.</td><td></td><td></td></tr>";
  }
  return rows
    .map(
      (row) =>
        `<tr><td>${e(row.area)}</td><td>${e(row.level)}</td><td>${e(row.why)}</td></tr>`,
    )
    .join("");
}

function fileBlocks(files) {
  const rows = asList(files).filter((row) => row && typeof row === "object");
  if (rows.length === 0) {
    return "<p>None.</p>";
  }
  return rows
    .map(
      (row) =>
        `<section><h3><code title="${e(row.path)}">${e(row.path)}</code></h3><p>${e(row.notes)}</p></section>`,
    )
    .join("");
}

function focusItems(focus) {
  const items = asList(focus).map((item) => asText(item)).filter((item) => item !== "");
  if (items.length === 0) {
    return "<li>None.</li>";
  }
  return items.map((item) => `<li>${e(item)}</li>`).join("");
}

/**
 * @param {Record<string, unknown>} model
 * @returns {string}
 */
export function buildExplainerPage(model) {
  const source = model && typeof model === "object" ? model : {};
  const title = asText(source.title) || "Pull-request explainer";
  const prLabel = asText(source.pr);
  const summary = asText(source.summary) || "None.";
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
<p class="muted">Pull-request explainer</p>
<h1>${e(title)}</h1>
<p class="muted">${e(prLabel)}</p>
<p>${e(summary)}</p>
<h2 id="risk-map">Risk map</h2>
<table>
<thead><tr><th>Area</th><th>Level</th><th>Why</th></tr></thead>
<tbody>
${riskRows(source.risks)}
</tbody>
</table>
<h2 id="files">File by file</h2>
${fileBlocks(source.files)}
<h2 id="focus">Where to focus</h2>
<ol>
${focusItems(source.focus)}
</ol>
<p class="record">The markdown record is the deliverable. This page is an offered view.</p>
</body>
</html>
`;
  return stampPage(html);
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function fail(message, code) {
  process.stderr.write(`build-explainer: ${message}\n`);
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
  const page = buildExplainerPage(model);
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
      fail("usage: build-explainer.mjs --check <file>", 2);
    }
    runCheck(args[1]);
    return;
  }
  if (args.length > 0) {
    fail("usage: build-explainer.mjs [< model.json] | --check <file>", 2);
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
