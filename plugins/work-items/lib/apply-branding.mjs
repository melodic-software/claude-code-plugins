import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { escapeHtml } from "./html-escape.mjs";
import { managedSettingsFiles, OptionsError, readOperatorOptions, resolveInstall } from "./plugin-options.mjs";
import { findRoot, resolveBranding } from "./view-settings.mjs";

const PLUGIN_ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
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

export function applyPluginBranding(template, { brandingOption = null } = {}) {
  const tokensCss = readFileSync(new URL("../reference/html-tokens.css", import.meta.url), "utf8");
  const branding = resolveBranding({ userConfig: readBrandingOption(brandingOption), projectRoot: findRoot() });
  for (const notice of branding.notices) {
    process.stderr.write(`notice: ${notice.text}\n`);
  }
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
