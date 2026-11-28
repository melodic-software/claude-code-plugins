#!/usr/bin/env node
import { chmodSync, lstatSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { escapeHtml } from "../lib/html-escape.mjs";
import { managedSettingsFiles, OptionsError, readOperatorOptions, resolveInstall } from "../lib/plugin-options.mjs";
import { buildView, ViewBuildError } from "../lib/view-builder.mjs";
import { findRoot, resolveBranding } from "../lib/view-settings.mjs";

const PLUGIN_ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const TEMPLATE = "../skills/debug/templates/post-mortem-view.html";
const TOKENS = "../reference/html-tokens.css";
const BRAND_CSS = [
  ".rv-brand { display: inline-flex; align-items: center; gap: 0.5rem; margin-right: auto; }",
  ".rv-brand svg { height: 1.5rem; width: auto; display: block; }",
  ".rv-brand-mark { display: inline-block; width: 1.5rem; height: 1.5rem; background-size: contain; background-repeat: no-repeat; background-position: center; }",
  ".rv-brand-label { font-family: var(--sans); font-weight: 600; font-size: 0.95rem; color: var(--fg); }",
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

function applyBranding(template, tokensCss, branding) {
  const tokens = tokensCss.replace(/\r\n?/g, "\n").replace(/^(?:\s*\/\*[\s\S]*?\*\/\s*)+/, "").trim();
  const logo = branding?.logo;
  const parts = [];
  if (logo?.kind === "svg" && logo.svg) {
    parts.push(logo.svg);
  } else if (logo?.kind === "image") {
    parts.push(`<span class="rv-brand-mark rv-logo" role="img" aria-label="${escapeHtml(logo.label || "Brand logo")}"></span>`);
  }
  if (logo?.label) {
    parts.push(`<span class="rv-brand-label">${escapeHtml(logo.label)}</span>`);
  }
  const slot = parts.length ? `<div class="rv-brand">${parts.join("")}</div>` : "";
  const extraCss = [slot ? BRAND_CSS : "", branding?.css ?? ""].filter(Boolean).join("\n");
  let out = template.replace(/<style>\s*/i, (open) => `${open}${tokens}\n`);
  if (extraCss) out = out.replace(/<\/style>/i, (close) => `\n${extraCss}\n${close}`);
  if (slot) out = out.replace(/<div class="rv-bar">/i, (bar) => `${bar}${slot}`);
  return out;
}

const TEXT = ["title", "loop", "cause", "fix", "seam", "prevention"];
const LIST = "hypotheses";
const ROW = ["verdict", "claim", "prediction", "evidence"];

const isText = (value) => typeof value === "string";
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

const shapeFailures = (data) => {
  if (!isObject(data)) return ["data is not an object"];
  const failures = TEXT.filter((key) => !isText(data[key])).map((key) => `${key} must be text`);
  if (!Array.isArray(data[LIST])) return [...failures, `${LIST} must be a list`];
  for (const [index, row] of data[LIST].entries()) {
    if (!isObject(row)) {
      failures.push(`${LIST}[${index}] must be an object`);
      continue;
    }
    for (const key of ROW) if (!isText(row[key])) failures.push(`${LIST}[${index}].${key} must be text`);
  }
  return failures;
};

const argv = process.argv.slice(2);
let brandingOption = null;
if (argv.length === 2 && argv[0] === "--branding-option") {
  brandingOption = argv[1];
} else if (argv.length > 0) {
  console.error("usage: build-view.mjs [--branding-option <value>] < data.json");
  process.exit(2);
}

try {
  const data = JSON.parse(readFileSync(0, "utf8"));
  const failures = shapeFailures(data);
  if (failures.length > 0) throw new ViewBuildError(failures);
  const tokensCss = readFileSync(fileURLToPath(new URL(TOKENS, import.meta.url)), "utf8");
  const branding = resolveBranding({ userConfig: readBrandingOption(brandingOption), projectRoot: findRoot() });
  for (const notice of branding.notices) {
    process.stderr.write(`notice: ${notice.text}\n`);
  }
  const rawTemplate = readFileSync(fileURLToPath(new URL(TEMPLATE, import.meta.url)), "utf8");
  const page = buildView({
    profile: "interactive",
    template: applyBranding(rawTemplate, tokensCss, branding),
    data,
  });
  const dir = join(tmpdir(), "debugging-views");
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  if (!lstatSync(dir).isDirectory())
    throw new Error("build-view: refusing a symlinked or non-directory output path");
  chmodSync(dir, 0o700);
  const out = join(dir, "post-mortem.html");
  rmSync(out, { force: true });
  writeFileSync(out, page, { mode: 0o600 });
  console.log(out);
} catch (err) {
  console.error(err instanceof SyntaxError ? "build-view: stdin is not JSON" : err.message);
  process.exit(err instanceof ViewBuildError ? 1 : 2);
}
