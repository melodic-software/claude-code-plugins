
import { readFileSync, realpathSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { escapeHtml, stampPage, validateRenderedPage } from "./html-escape.mjs";
import { managedSettingsFiles, OptionsError, readOperatorOptions, resolveInstall } from "./plugin-options.mjs";
import { findRoot, resolveBranding } from "./view-settings.mjs";

export { stampPage };

const PLUGIN_ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const TOKENS_URL = new URL("../reference/html-tokens.css", import.meta.url);
const REPORT_BRAND_CSS = [
  ".rv-bar { display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem; margin-bottom: 1rem; }",
  ".rv-brand-mark { margin: 0; display: inline-block; width: 1.5rem; height: 1.5rem; background-size: contain; background-repeat: no-repeat; background-position: center; }",
  ".rv-brand-label { margin: 0; font-family: var(--sans); font-weight: 600; font-size: 0.95rem; color: var(--fg); }",
].join("\n");

export function readBrandingOption(explicitOption) {
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

export function readTokensCss() {
  return readFileSync(TOKENS_URL, "utf8").replace(/\r\n?/g, "\n").replace(/^(?:\s*\/\*[\s\S]*?\*\/\s*)+/, "").trim();
}

export function reportBranding({ brandingOption = null } = {}) {
  const tokens = readTokensCss();
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
  return { tokens, extraCss, barHtml };
}

export const CSS = `
@media (prefers-reduced-motion: reduce) {
  * { animation: none !important; transition: none !important; }
}
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
code.block { display: block; white-space: pre; overflow-x: auto; border: var(--border); border-radius: 6px; padding: 0.6rem 0.75rem; margin: 0.75rem 0; }
.muted { color: color-mix(in srgb, var(--fg) 75%, var(--bg)); }
table.flow { width: 100%; table-layout: fixed; border-collapse: separate; border-spacing: 0.25rem; margin: 1rem 0 0.5rem; }
table.flow td { border: 2px solid var(--gray-300); border-radius: 6px; padding: 0.6rem 0.5rem; text-align: center; overflow-wrap: anywhere; }
table.flow td.arrow { border: 0; width: 2rem; padding: 0; color: var(--muted); font-size: 1.5rem; }
table.stack td { border: 2px solid var(--gray-300); border-radius: 6px; padding: 0.6rem 0.75rem; }
.caption { font-weight: 600; margin-top: 0; }
ol.choices { list-style: upper-alpha; }
summary:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; border-radius: 2px; }
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
export function pageShell(title, body, head = "", { brandingOption = null } = {}) {
  const { tokens, extraCss, barHtml } = reportBranding({ brandingOption });
  const style = [tokens, CSS, extraCss].filter(Boolean).join("\n");
  return stampPage(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
${head}
<title>${e(title)}</title>
<style>
${style}
</style>
</head>
<body>
${barHtml}${body}
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
  let brandingOption = null;
  if (args.length === 2 && args[0] === "--branding-option") {
    brandingOption = args[1];
  } else if (args.length > 0) {
    fail(`usage: ${name} [--branding-option <value>] [< model.json] | --check <file>`, 2);
  }
  let model;
  try {
    model = JSON.parse(readFileSync(0, "utf8"));
  } catch (error) {
    fail(`invalid JSON (${error instanceof Error ? error.message : String(error)})`, 2);
  }
  if (!model || typeof model !== "object" || Array.isArray(model)) {
    fail("JSON root must be an object", 2);
  }
  const page = build(model, { brandingOption });
  const verdict = validateRenderedPage(page);
  if (!verdict.ok) fail(`refused to emit (${verdict.failures.join(",")})`, 1);
  process.stdout.write(page);
}
