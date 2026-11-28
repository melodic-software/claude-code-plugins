import { readFileSync } from "node:fs";
import { escapeHtml } from "../lib/html-escape.mjs";
import { findRoot, resolveBranding, validateSvgLogo } from "../lib/view-settings.mjs";

const ESCAPED_TEXT = /^(?:[^&<>"']|&(?:amp|lt|gt|quot|#x27);)*$/;

/** The token layer's rules: this plugin's copy of lib/html-tokens.css without its comments. */
export const TOKEN_CSS = readFileSync(new URL("../reference/html-tokens.css", import.meta.url), "utf8")
  .replace(/\r\n?/g, "\n")
  .replace(/\/\*[\s\S]*?\*\/\n?/g, "")
  .trim();

const BRAND_CSS = [
  ".rv-brand { display: inline-flex; align-items: center; gap: 0.5rem; margin-right: auto; font-weight: 600; }",
  ".rv-brand .rv-logo { display: inline-block; width: 7rem; height: 1.75rem; background-repeat: no-repeat; background-position: left center; background-size: contain; }",
  ".rv-brand .rv-logo-svg { width: auto; }",
  ".rv-brand svg { display: block; width: auto; height: 1.75rem; max-width: 7rem; }",
].join("\n");

/** A branding resolution that sets nothing: the page keeps the shipped look. */
export const NO_BRANDING = Object.freeze({ css: "", logo: { kind: null, svg: null, dataUrl: null, label: null } });

/** Resolves `branding` for a build: the project's team file and personal override, then the given userConfig value. */
export function resolvePageBranding(userConfig = null) {
  return resolveBranding({ userConfig, projectRoot: findRoot() });
}

/**
 * The parts a page takes from a resolved `branding`: the rules to append after the page's own,
 * and the brand markup for the chrome bar's first slot. Both are empty when nothing is set.
 */
export function pageBranding(resolution = NO_BRANDING) {
  const { logo } = resolution;
  const named = logo.label ? ' aria-hidden="true"' : ' role="img" aria-label="Logo"';
  const graphic =
    logo.kind === "image" ? `<span class="rv-logo"${named}></span>`
    : logo.kind === "svg" ? `<span class="rv-logo rv-logo-svg"${named}>${logo.svg}</span>`
    : "";
  const label = logo.label ? `<span class="rv-brand-label">${escapeHtml(logo.label)}</span>` : "";
  const brand = graphic || label ? `<span class="rv-brand">${graphic}${label}</span>` : "";
  return { css: [brand ? BRAND_CSS : "", resolution.css].filter(Boolean).join("\n"), brand };
}

const BAR_OPEN = '<div class="rv-bar">';

/** The bar markup with the brand in its first slot. */
export const withBrand = (bar, brand) => bar.replace(BAR_OPEN, () => `${BAR_OPEN}${brand}`);

const BRAND_SLOT = new RegExp(
  `${BAR_OPEN}<span class="rv-brand">` +
    '(?:<span class="rv-logo"(?: aria-hidden="true"| role="img" aria-label="Logo")></span>' +
    '|<span class="rv-logo rv-logo-svg"(?: aria-hidden="true"| role="img" aria-label="Logo")>(<svg\\b[\\s\\S]*?</svg>)</span>)?' +
    '(?:<span class="rv-brand-label">([^<]*)</span>)?</span>(?=<div class="rv-theme")',
);

/**
 * Takes the one brand slot, the chrome bar's first child, out of a page for a validator that does
 * not admit SVG, checking its logo against the SVG allowlist and its label as escaped text.
 * @returns {{ rest: string, failures: string[] }}
 */
export function takeBrandSlot(html) {
  const slots = html.split('<span class="rv-brand">').length - 1;
  if (slots === 0) return { rest: html, failures: [] };
  const match = BRAND_SLOT.exec(html);
  if (slots !== 1 || !match) return { rest: html, failures: ["brand"] };
  const failures = [];
  if (match[1] !== undefined && !validateSvgLogo(match[1]).ok) failures.push("brand-svg");
  if (match[2] !== undefined && !ESCAPED_TEXT.test(match[2])) failures.push("unescaped");
  return { rest: html.replace(match[0], () => BAR_OPEN), failures };
}
