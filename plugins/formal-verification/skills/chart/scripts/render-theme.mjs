#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { findRoot, resolveBranding } from "../../../lib/view-settings.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const TOKENS_PATH = join(HERE, "../../../reference/html-tokens.css");
const THEME_PATH = join(HERE, "../reference/render-theme.css");

export function stripTokenComment(tokensCss) {
  return tokensCss.replace(/\r\n?/g, "\n").replace(/^(?:\/\*[\s\S]*?\*\/\s*)+/, "").trim();
}

export function buildChartStyle({ userConfig = null, projectRoot = findRoot(), teamRef = null } = {}, options = {}) {
  const tokens = stripTokenComment(readFileSync(TOKENS_PATH, "utf8"));
  const theme = readFileSync(THEME_PATH, "utf8").replace(/\r\n?/g, "\n").trim();
  const branding = resolveBranding({ userConfig, projectRoot, teamRef }, options);
  const parts = [tokens];
  if (branding.css) parts.push(branding.css);
  parts.push(theme);
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
    if (flag === "--option") userConfig = value;
    else if (flag === "--project-root") projectRoot = value;
    else if (flag === "--team-ref") teamRef = value;
    else return 2;
  }
  const { css, branding } = buildChartStyle({ userConfig, projectRoot: projectRoot ?? findRoot(), teamRef });
  for (const notice of branding.notices) {
    process.stderr.write(`notice: ${notice.text}\n`);
  }
  process.stdout.write(css);
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
