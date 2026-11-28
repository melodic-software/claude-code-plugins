#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { OptionsError, managedSettingsFiles, readOperatorOptions, resolveInstall } from "../../../lib/plugin-options.mjs";
import { findRoot, resolveBranding } from "../../../lib/view-settings.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = resolve(HERE, "../../..");
const TOKENS_PATH = join(PLUGIN_ROOT, "reference/html-tokens.css");

const isConfiguredOption = (value) => typeof value === "string" && value.trim() !== "" && !/^\$\{user_config\.[^}]+\}$/.test(value.trim());

export function readConfiguredBranding({ pluginRoot = PLUGIN_ROOT, env = process.env, managedFiles = managedSettingsFiles() } = {}) {
  if (isConfiguredOption(env.CLAUDE_PLUGIN_OPTION_BRANDING)) {
    return { value: env.CLAUDE_PLUGIN_OPTION_BRANDING, notices: [] };
  }
  const install = resolveInstall(resolve(pluginRoot));
  const effectiveInstall =
    install.userSettings === null && env.CLAUDE_CONFIG_DIR
      ? { ...install, userSettings: join(env.CLAUDE_CONFIG_DIR, "settings.json") }
      : install;
  try {
    const opts = readOperatorOptions(effectiveInstall, managedFiles, ["branding"]);
    return { value: isConfiguredOption(opts.branding?.value) ? opts.branding.value : null, notices: [] };
  } catch (error) {
    if (error instanceof OptionsError) return { value: null, notices: [{ text: error.message }] };
    throw error;
  }
}

const BRAND_SLOT_CSS = [
  ".rv-brand { display: inline-flex; align-items: center; gap: 0.5rem; margin-right: auto; }",
  ".rv-brand svg { height: 1.5rem; width: auto; display: block; }",
  ".rv-brand-mark { display: inline-block; width: 1.5rem; height: 1.5rem; background-size: contain; background-repeat: no-repeat; background-position: center; }",
  ".rv-brand-label { font-family: var(--sans); font-weight: 600; font-size: 0.95rem; color: var(--fg); }",
].join("\n");

const ESC = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
const escHtml = (text) => String(text).replace(/[&<>"']/g, (ch) => ESC[ch]);

export function stripTokenComment(tokensCss) {
  return tokensCss.replace(/\r\n?/g, "\n").replace(/^(?:\/\*[\s\S]*?\*\/\s*)+/, "").trim();
}

export function logoSlotHtml(logo) {
  if (!logo || (!logo.kind && !logo.label)) return "";
  const parts = [];
  if (logo.kind === "svg" && logo.svg) {
    parts.push(logo.svg);
  } else if (logo.kind === "image" && logo.dataUrl) {
    parts.push(`<span class="rv-brand-mark rv-logo" role="img" aria-label="${escHtml(logo.label || "Brand logo")}"></span>`);
  }
  if (logo.label) {
    parts.push(`<span class="rv-brand-label">${escHtml(logo.label)}</span>`);
  }
  return parts.length ? `<div class="rv-brand">${parts.join("")}</div>` : "";
}

export function applyBrandingToHtml(html, { tokensCss, branding }) {
  const styleOpen = html.indexOf("<style>");
  const styleClose = styleOpen >= 0 ? html.indexOf("</style>", styleOpen) : -1;
  if (styleOpen < 0 || styleClose < 0) return html;

  const strippedTokens = stripTokenComment(tokensCss);
  const bodyStart = styleOpen + "<style>".length;
  const existingCss = html.slice(bodyStart, styleClose);
  const parts = [];
  if (strippedTokens && !existingCss.includes("--ivory:")) {
    parts.push(`\n${strippedTokens}\n`);
  }
  parts.push(existingCss);

  const slot = logoSlotHtml(branding?.logo);
  if (slot) parts.push(`\n${BRAND_SLOT_CSS}\n`);
  if (branding?.css) parts.push(`\n${branding.css}\n`);

  let out = `${html.slice(0, bodyStart)}${parts.join("")}${html.slice(styleClose)}`;
  if (slot) {
    const barMarker = '<div class="rv-bar">';
    const at = out.indexOf(barMarker);
    if (at >= 0) {
      out = `${out.slice(0, at + barMarker.length)}${slot}${out.slice(at + barMarker.length)}`;
    }
  }
  return out;
}

export function main(argv, stdin = process.stdin) {
  let userConfig = null;
  let projectRoot = null;
  let teamRef = null;
  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i];
    const value = argv[i + 1];
    if (value === undefined) return 2;
    if (flag === "--option" || flag === "--branding-option") {
      if (isConfiguredOption(value)) userConfig = value;
    } else if (flag === "--project-root") projectRoot = value;
    else if (flag === "--team-ref") teamRef = value;
    else return 2;
  }
  const configNotices = [];
  if (userConfig === null) {
    const configured = readConfiguredBranding();
    userConfig = configured.value;
    configNotices.push(...configured.notices);
  }
  const html = readFileSync(stdin.fd, "utf8");
  const tokensCss = readFileSync(TOKENS_PATH, "utf8");
  const branding = resolveBranding({ userConfig, projectRoot: projectRoot ?? findRoot(), teamRef });
  for (const notice of [...configNotices, ...branding.notices]) {
    process.stderr.write(`notice: ${notice.text}\n`);
  }
  process.stdout.write(applyBrandingToHtml(html, { tokensCss, branding }));
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
