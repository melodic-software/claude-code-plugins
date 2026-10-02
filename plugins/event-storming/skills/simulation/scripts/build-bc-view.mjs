#!/usr/bin/env node
// Build the bounded-context analysis view for `--discover-bcs`: one row per
// context with its key events, primary personas, and heuristic evidence.
//
// Every interpolated field goes through escapeHtml from the synced helper.
// The page is self-contained: inline style, no script, no image, no link.
// stampPage adds the generator marker. validateRenderedPage refuses a page
// this builder would not accept, including its own output if a template edit
// breaks the allowlist.

import { readFileSync, realpathSync } from "node:fs";
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
  --serif: ui-serif, Georgia, serif;
  --sans: system-ui, sans-serif;
  --mono: ui-monospace, monospace;
  --bg: var(--ivory);
  --fg: var(--slate);
  --muted: var(--gray-500);
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: var(--slate);
    --fg: var(--ivory);
    --muted: var(--gray-300);
  }
}
@media (prefers-reduced-motion: reduce) {
  * { animation: none !important; transition: none !important; }
}
html { color-scheme: light dark; }
body {
  margin: 0 auto;
  max-width: 960px;
  padding: 2rem 1.25rem 4rem;
  background: var(--bg);
  color: var(--fg);
  font-family: var(--sans);
  line-height: 1.55;
}
h1, h2, h3 { font-family: var(--serif); font-weight: 600; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; border-bottom: 1px solid var(--gray-300); padding: 0.45rem 0.5rem; vertical-align: top; }
code { font-family: var(--mono); }
.muted { color: var(--muted); }
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

function texts(value) {
  return asList(value)
    .map((item) => asText(item))
    .filter((item) => item !== "");
}

function objects(value) {
  return asList(value).filter((row) => row && typeof row === "object" && !Array.isArray(row));
}

function numbered(value) {
  const items = texts(value);
  if (items.length === 0) return "<p>None.</p>";
  return `<ol>${items.map((item) => `<li>${e(item)}</li>`).join("")}</ol>`;
}

function joined(value) {
  return texts(value).map((item) => escapeHtml(item)).join(", ");
}

function contextRows(rows) {
  const items = objects(rows);
  if (items.length === 0) return "<tr><td>None.</td><td></td><td></td><td></td><td></td></tr>";
  return items
    .map(
      (row, index) =>
        `<tr><td>${index + 1}</td><td>${e(row.name)}</td><td>${joined(row.events)}</td><td>${joined(row.personas)}</td><td>${e(row.evidence)}</td></tr>`,
    )
    .join("\n");
}

/**
 * @param {Record<string, unknown>} model
 * @returns {string}
 */
export function buildBoundedContextPage(model) {
  const source = model && typeof model === "object" ? model : {};
  const title = asText(source.title) || "Bounded-context analysis";
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
<p class="muted">Bounded-context analysis</p>
<h1>${e(title)}</h1>
<p class="muted">${e(source.board)}</p>
<section id="contexts">
<h2>Bounded contexts</h2>
<table>
<thead><tr><th>#</th><th>Name</th><th>Key events</th><th>Primary personas</th><th>Heuristic evidence</th></tr></thead>
<tbody>
${contextRows(source.contexts)}
</tbody>
</table>
</section>
<section id="next">
<h2>Recommended next exploration target</h2>
<p>${e(source.target) || "None."}</p>
</section>
</body>
</html>
`;
  return stampPage(html);
}

function fail(message, code) {
  process.stderr.write(`build-bc-view: ${message}\n`);
  process.exit(code);
}

function runCheck(path) {
  let html;
  try {
    html = readFileSync(path, "utf8");
  } catch (error) {
    fail(error instanceof Error ? error.message : String(error), 2);
  }
  const verdict = validateRenderedPage(html);
  if (!verdict.ok) fail(verdict.failures.join(","), 1);
}

function runBuild() {
  let model;
  try {
    model = JSON.parse(readFileSync(0, "utf8"));
  } catch (error) {
    fail(`invalid JSON (${error instanceof Error ? error.message : String(error)})`, 2);
  }
  if (!model || typeof model !== "object" || Array.isArray(model)) {
    fail("JSON root must be an object", 2);
  }
  const page = buildBoundedContextPage(model);
  const verdict = validateRenderedPage(page);
  if (!verdict.ok) fail(`refused to emit (${verdict.failures.join(",")})`, 1);
  process.stdout.write(page);
}

function main() {
  const args = process.argv.slice(2);
  if (args[0] === "--check") {
    if (!args[1]) fail("usage: build-bc-view.mjs --check <file>", 2);
    runCheck(args[1]);
    return;
  }
  if (args.length > 0) fail("usage: build-bc-view.mjs [< model.json] | --check <file>", 2);
  runBuild();
}

function invokedDirectly() {
  const arg = process.argv[1];
  if (!arg) return false;
  try {
    return realpathSync(arg) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (invokedDirectly()) {
  main();
}
