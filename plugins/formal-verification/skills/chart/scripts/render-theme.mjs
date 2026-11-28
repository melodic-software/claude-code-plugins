#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { OptionsError, managedSettingsFiles, readOperatorOptions, resolveInstall } from "../../../lib/plugin-options.mjs";
import { findRoot, resolveBranding } from "../../../lib/view-settings.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = resolve(HERE, "../../..");
const TOKENS_PATH = join(PLUGIN_ROOT, "reference/html-tokens.css");
const THEME_PATH = join(HERE, "../reference/render-theme.css");

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

export function stripTokenComment(tokensCss) {
  return tokensCss.replace(/\r\n?/g, "\n").replace(/^(?:\/\*[\s\S]*?\*\/\s*)+/, "").trim();
}

const PELE_ROLE_MAP = [
  ["bg", "--pele-bg", "var(--bg)"],
  ["fg", "--pele-fg", "var(--fg)"],
  ["muted", "--pele-muted", "var(--muted)"],
  ["panel", "--pele-surface", "var(--panel)"],
];

export function peleOverrideCss(branding) {
  const sources = branding?.sources ?? {};
  const light = [];
  for (const [role, peleProp, tokenRef] of PELE_ROLE_MAP) {
    if (sources[`palette.light.${role}`] && sources[`palette.light.${role}`] !== "default") {
      light.push(`${peleProp}: ${tokenRef};`);
    }
  }
  if (sources["type.sans"] && sources["type.sans"] !== "default") {
    light.push("--pele-font: var(--sans);", "font-family: var(--pele-font);");
  }
  const dark = [];
  for (const [role, peleProp, tokenRef] of PELE_ROLE_MAP) {
    if (sources[`palette.dark.${role}`] && sources[`palette.dark.${role}`] !== "default") {
      dark.push(`${peleProp}: ${tokenRef};`);
    }
  }
  const blocks = [];
  if (light.length) blocks.push(`.pele { ${light.join(" ")} }`);
  if (dark.length) {
    const body = dark.join(" ");
    blocks.push(
      `@media (prefers-color-scheme: dark) { :is(:root.pele:not([data-theme=light]), :root:not([data-theme=light]) .pele) { ${body} } }`,
      `:is(:root.pele[data-theme=dark], :root[data-theme=dark] .pele) { ${body} }`,
    );
  }
  return blocks.join("\n");
}

export function buildChartStyle({ userConfig = null, projectRoot = findRoot(), teamRef = null } = {}, options = {}) {
  const tokens = stripTokenComment(readFileSync(TOKENS_PATH, "utf8"));
  const theme = readFileSync(THEME_PATH, "utf8").replace(/\r\n?/g, "\n").trim();
  const branding = resolveBranding({ userConfig, projectRoot, teamRef }, options);
  const parts = [tokens];
  if (branding.css) parts.push(branding.css);
  parts.push(theme);
  const peleOverrides = peleOverrideCss(branding);
  if (peleOverrides) parts.push(peleOverrides);
  return { css: `${parts.join("\n")}\n`, branding };
}

export function main(argv) {
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
  const { css, branding } = buildChartStyle({ userConfig, projectRoot: projectRoot ?? findRoot(), teamRef });
  for (const notice of [...configNotices, ...branding.notices]) {
    process.stderr.write(`notice: ${notice.text}\n`);
  }
  process.stdout.write(css);
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
