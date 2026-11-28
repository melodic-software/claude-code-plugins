#!/usr/bin/env node
// GENERATED from lib/html-branding.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { brandingReportLines, findRoot, resolveBranding } from "./view-settings.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const STYLE_OPEN = /<style\b[^>]*>/i;
const STYLE_CLOSE = /<\/style>/i;
const RV_BAR_OPEN = /<div\b[^>]*\bclass="[^"]*\brv-bar\b[^"]*"[^>]*>/i;

const escapeHtml = (value) =>
  String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#x27;");

const lf = (text) => String(text).replace(/\r\n?/g, "\n");
const flat = (text) => lf(text).replace(/^[ \t]+/gm, "").trim();

/** Strips leading block comments (generated header and provenance header) from `html-tokens.css`. */
export function stripTokenComment(tokensCss) {
  let body = lf(tokensCss);
  while (/^\s*\/\*[\s\S]*?\*\//.test(body)) {
    body = body.replace(/^\s*\/\*[\s\S]*?\*\/\s*/, "");
  }
  return body.trim();
}

/** Fixed-slot brand markup inserted into `.rv-bar` when a logo graphic or label is resolved. */
export function logoSlotHtml(logo) {
  if (!logo || (!logo.kind && !logo.label)) return "";
  const parts = [];
  if (logo.kind === "svg" && logo.svg) {
    parts.push(logo.svg);
  } else if (logo.kind === "image" && logo.dataUrl) {
    parts.push(`<span class="rv-brand-mark rv-logo" role="img" aria-label="${escapeHtml(logo.label || "Brand logo")}"></span>`);
  }
  if (logo.label) {
    parts.push(`<span class="rv-brand-label">${escapeHtml(logo.label)}</span>`);
  }
  return `<div class="rv-brand">${parts.join("")}</div>`;
}

/** Fixed-slot layout CSS paired with `logoSlotHtml`; `.rv-logo` itself keeps only its `background-image` rule. */
export function logoSlotCss(logo) {
  if (!logo || (!logo.kind && !logo.label)) return "";
  return [
    ".rv-brand { display: inline-flex; align-items: center; gap: 0.5rem; margin-right: auto; }",
    ".rv-brand svg { height: 1.5rem; width: auto; display: block; }",
    ".rv-brand-mark { display: inline-block; width: 1.5rem; height: 1.5rem; background-size: contain; background-repeat: no-repeat; background-position: center; }",
    ".rv-brand-label { font-family: var(--sans); font-weight: 600; font-size: 0.95rem; color: var(--fg); }",
  ].join("\n");
}

/**
 * Inlines `tokensCss` (unless already present at the start of `<style>`) and any resolved
 * `branding` CSS overrides into the page's one `<style>` element, and places `branding.logo` in
 * the chrome bar's `.rv-bar` slot when set. Leaves pages unchanged when no branding is configured
 * and the token layer is already present.
 */
export function applyBranding(html, { tokensCss = "", branding = null } = {}) {
  let page = lf(html);
  const open = STYLE_OPEN.exec(page);
  const close = STYLE_CLOSE.exec(page);
  if (!open || !close || close.index < open.index) {
    throw new Error("html-branding: page has no <style>...</style> element");
  }
  const styleStart = open.index + open[0].length;
  const existing = page.slice(styleStart, close.index);
  const tokens = stripTokenComment(tokensCss);
  const prefix = tokens && !flat(existing).startsWith(flat(tokens)) ? `\n${tokens}\n` : "";
  const extra = [logoSlotCss(branding?.logo), branding?.css ?? ""].filter(Boolean).join("\n");
  const suffix = extra ? `\n${extra}\n` : "";
  if (prefix || suffix) {
    page = page.slice(0, styleStart) + prefix + existing + suffix + page.slice(close.index);
  }
  const slot = logoSlotHtml(branding?.logo);
  if (slot) {
    const bar = RV_BAR_OPEN.exec(page);
    if (bar) {
      const at = bar.index + bar[0].length;
      page = page.slice(0, at) + slot + page.slice(at);
    }
  }
  return page;
}

const USAGE = "usage: html-branding.mjs --in <page.html> --out <page.html> [--tokens <html-tokens.css>] [--option <user_config.branding>] [--team-ref <ref>]\n";

const defaultTokensPath = () => {
  const pluginPath = join(HERE, "..", "reference", "html-tokens.css");
  return existsSync(pluginPath) ? pluginPath : join(HERE, "html-tokens.css");
};

export function main(argv) {
  const args = { in: null, out: null, tokens: defaultTokensPath(), option: null, teamRef: null };
  const flags = { "--in": "in", "--out": "out", "--tokens": "tokens", "--option": "option", "--team-ref": "teamRef" };
  for (let i = 0; i < argv.length; i += 2) {
    const key = flags[argv[i]];
    if (!key || argv[i + 1] === undefined) {
      process.stderr.write(USAGE);
      return 2;
    }
    args[key] = argv[i + 1];
  }
  if (!args.in || !args.out) {
    process.stderr.write(USAGE);
    return 2;
  }
  const html = readFileSync(args.in, "utf8");
  const tokensCss = readFileSync(args.tokens, "utf8");
  const branding = resolveBranding({ userConfig: args.option, projectRoot: findRoot(), teamRef: args.teamRef });
  writeFileSync(args.out, applyBranding(html, { tokensCss, branding }));
  process.stdout.write(`${brandingReportLines(branding).join("\n")}\n`);
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
