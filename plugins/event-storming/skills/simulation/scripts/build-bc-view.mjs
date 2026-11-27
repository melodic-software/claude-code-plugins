#!/usr/bin/env node

import { readFileSync, realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

import {
  escapeHtml,
  stampPage,
  validateRenderedPage,
} from "../../../lib/html-escape.mjs";
import { managedSettingsFiles, OptionsError, readOperatorOptions, resolveInstall } from "../../../lib/plugin-options.mjs";
import { findRoot, resolveBranding } from "../../../lib/view-settings.mjs";

const PLUGIN_ROOT = fileURLToPath(new URL("../../..", import.meta.url));
const TOKENS_URL = new URL("../../../reference/html-tokens.css", import.meta.url);
const REPORT_BRAND_CSS = [
  ".rv-bar { display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem; margin-bottom: 1rem; }",
  ".rv-brand-mark { margin: 0; display: inline-block; width: 1.5rem; height: 1.5rem; background-size: contain; background-repeat: no-repeat; background-position: center; }",
  ".rv-brand-label { margin: 0; font-family: var(--sans); font-weight: 600; font-size: 0.95rem; color: var(--fg); }",
].join("\n");

function readBrandingOption(explicitOption) {
  if (typeof explicitOption === "string" && explicitOption !== "" && !/^\$\{user_config\./.test(explicitOption)) {
    return explicitOption;
  }
  if (process.env.CLAUDE_PLUGIN_OPTION_BRANDING) {
    return process.env.CLAUDE_PLUGIN_OPTION_BRANDING;
  }
  try {
    return readOperatorOptions(resolveInstall(PLUGIN_ROOT), managedSettingsFiles(), ["branding"]).branding?.value ?? null;
  } catch (err) {
    if (err instanceof OptionsError) {
      process.stderr.write(`notice: branding userConfig: ${err.message}\n`);
      return null;
    }
    throw err;
  }
}

function reportBranding({ brandingOption = null } = {}) {
  const tokens = readFileSync(TOKENS_URL, "utf8").replace(/\r\n?/g, "\n").replace(/^(?:\s*\/\*[\s\S]*?\*\/\s*)+/, "").trim();
  const branding = resolveBranding({ userConfig: readBrandingOption(brandingOption), projectRoot: findRoot() });
  for (const notice of branding.notices) {
    process.stderr.write(`notice: ${notice.text}\n`);
  }
  const logo = branding?.logo;
  const parts = [];
  if (logo?.kind === "image") {
    parts.push(`<p class="rv-brand-mark rv-logo" title="${escapeHtml(logo.label || "Brand logo")}"></p>`);
  } else if (logo?.kind === "svg") {
    process.stderr.write("notice: branding logo: static report pages embed PNG or JPEG logos only; SVG logo omitted\n");
  }
  if (logo?.label) {
    parts.push(`<p class="rv-brand-label">${escapeHtml(logo.label)}</p>`);
  }
  const barHtml = parts.length ? `<section class="rv-bar">${parts.join("")}</section>\n` : "";
  const extraCss = [barHtml ? REPORT_BRAND_CSS : "", branding?.css ?? ""].filter(Boolean).join("\n");
  return { styleBlock: [tokens, CSS, extraCss].filter(Boolean).join("\n"), barHtml };
}

const CSS = `
@media (prefers-reduced-motion: reduce) {
  * { animation: none !important; transition: none !important; }
}
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
summary:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; border-radius: 2px; }
`.trim();

function asText(value) {
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return "";
}

function asList(value) {
  return Array.isArray(value) ? value : [];
}

function isRecord(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function e(value) {
  return escapeHtml(asText(value));
}

function joined(value) {
  return asList(value).map(e).filter(Boolean).join(", ");
}

function contextRows(rows) {
  const items = asList(rows).filter(isRecord);
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
export function buildBoundedContextPage(model, { brandingOption = null } = {}) {
  const source = model && typeof model === "object" ? model : {};
  const title = asText(source.title) || "Bounded-context analysis";
  const { styleBlock, barHtml } = reportBranding({ brandingOption });
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${e(title)}</title>
<style>
${styleBlock}
</style>
</head>
<body>
${barHtml}<p class="muted">Bounded-context analysis</p>
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

function errorText(error) {
  return error instanceof Error ? error.message : String(error);
}

function runCheck(path) {
  let html;
  try {
    html = readFileSync(path, "utf8");
  } catch (error) {
    fail(errorText(error), 2);
  }
  const verdict = validateRenderedPage(html);
  if (!verdict.ok) fail(verdict.failures.join(","), 1);
}

function runBuild(brandingOption = null) {
  let model;
  try {
    model = JSON.parse(readFileSync(0, "utf8"));
  } catch (error) {
    fail(`invalid JSON (${errorText(error)})`, 2);
  }
  if (!isRecord(model)) fail("JSON root must be an object", 2);
  const page = buildBoundedContextPage(model, { brandingOption });
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
  let brandingOption = null;
  if (args.length === 2 && args[0] === "--branding-option") {
    brandingOption = args[1];
  } else if (args.length > 0) {
    fail("usage: build-bc-view.mjs [--branding-option <value>] [< model.json] | --check <file>", 2);
  }
  runBuild(brandingOption);
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
