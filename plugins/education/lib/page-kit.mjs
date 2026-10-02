// Shared parts of the education page builders: the stylesheet, the field
// coercion that keeps non-string input from reaching the page, and the CLI
// wrapper that validates a page before it is printed.
//
// Every value reaches the page through e(), which is escapeHtml from the synced
// helper. A page is stamped, then refused unless validateRenderedPage accepts it.

import { readFileSync, realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { escapeHtml, stampPage, validateRenderedPage } from "./html-escape.mjs";

export { stampPage };

export const CSS = `
:root {
  --bg: #ffffff;
  --fg: #1a1a19;
  --muted: #5f5e58;
  --line: #c9c7bd;
  --focus: #a0512e;
  --serif: ui-serif, Georgia, serif;
  --sans: system-ui, sans-serif;
  --mono: ui-monospace, monospace;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #141413;
    --fg: #f1f0ea;
    --muted: #b9b7ac;
    --line: #4a4943;
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
code { font-family: var(--mono); }
code.block { display: block; white-space: pre; overflow-x: auto; border: 1px solid var(--line); border-radius: 6px; padding: 0.6rem 0.75rem; margin: 0.75rem 0; }
.muted { color: var(--muted); }
table.flow { width: 100%; table-layout: fixed; border-collapse: separate; border-spacing: 0.25rem; margin: 1rem 0 0.5rem; }
table.flow td { border: 2px solid var(--line); border-radius: 6px; padding: 0.6rem 0.5rem; text-align: center; overflow-wrap: anywhere; }
table.flow td.arrow { border: 0; width: 2rem; padding: 0; color: var(--muted); font-size: 1.5rem; }
table.stack td { border: 2px solid var(--line); border-radius: 6px; padding: 0.6rem 0.75rem; }
.caption { font-weight: 600; margin-top: 0; }
ol.choices { list-style: upper-alpha; }
`.trim();

/**
 * @param {unknown} value
 * @returns {string}
 */
export function asText(value) {
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return "";
}

/**
 * @param {unknown} value
 * @returns {unknown[]}
 */
export function asList(value) {
  return Array.isArray(value) ? value : [];
}

/**
 * @param {unknown} value
 * @returns {string[]}
 */
export function textList(value) {
  return (Array.isArray(value) ? value : [value]).map(asText).filter((item) => item !== "");
}

/**
 * @param {unknown} value
 * @returns {Record<string, unknown>[]}
 */
export function rows(value) {
  return asList(value).filter((row) => row && typeof row === "object");
}

/**
 * @param {unknown} value
 * @returns {string}
 */
export function e(value) {
  return escapeHtml(asText(value));
}

/**
 * @param {unknown} value a string or a list of strings
 * @returns {string}
 */
export function paragraphs(value) {
  return textList(value)
    .map((item) => `<p>${e(item)}</p>`)
    .join("\n");
}

/**
 * @param {unknown} value a string or a list of strings, each a code snippet
 * @returns {string}
 */
export function codeBlocks(value) {
  return textList(value)
    .map((item) => `<p><code class="block">${e(item)}</code></p>`)
    .join("\n");
}

/**
 * @param {string} title
 * @param {string} body markup built from e() calls
 * @param {string} [head] extra head markup built from e() calls
 * @returns {string}
 */
export function pageShell(title, body, head = "") {
  return stampPage(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
${head}
<title>${e(title)}</title>
<style>
${CSS}
</style>
</head>
<body>
${body}
</body>
</html>
`);
}

function invokedDirectly(metaUrl) {
  const arg = process.argv[1];
  if (!arg) return false;
  try {
    return realpathSync(arg) === realpathSync(fileURLToPath(metaUrl));
  } catch {
    return false;
  }
}

/**
 * Run a builder as a command: a JSON object on stdin becomes a page on stdout,
 * and `--check <file>` validates a page that already exists. Runs only when the
 * calling module is the process entry point.
 *
 * @param {string} metaUrl import.meta.url of the calling builder
 * @param {string} name builder file name, for messages
 * @param {(model: Record<string, unknown>) => string} build
 */
export function runCli(metaUrl, name, build) {
  if (!invokedDirectly(metaUrl)) return;
  const fail = (message, code) => {
    process.stderr.write(`${name}: ${message}\n`);
    process.exit(code);
  };
  const args = process.argv.slice(2);
  if (args[0] === "--check") {
    if (!args[1]) fail(`usage: ${name} --check <file>`, 2);
    let html;
    try {
      html = readFileSync(args[1], "utf8");
    } catch (error) {
      fail(error instanceof Error ? error.message : String(error), 2);
    }
    const verdict = validateRenderedPage(html);
    if (!verdict.ok) fail(verdict.failures.join(","), 1);
    return;
  }
  if (args.length > 0) fail(`usage: ${name} [< model.json] | --check <file>`, 2);
  let model;
  try {
    model = JSON.parse(readFileSync(0, "utf8"));
  } catch (error) {
    fail(`invalid JSON (${error instanceof Error ? error.message : String(error)})`, 2);
  }
  if (!model || typeof model !== "object" || Array.isArray(model)) {
    fail("JSON root must be an object", 2);
  }
  const page = build(model);
  const verdict = validateRenderedPage(page);
  if (!verdict.ok) fail(`refused to emit (${verdict.failures.join(",")})`, 1);
  process.stdout.write(page);
}
