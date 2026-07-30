// Path ownership for the Cursor companion-host export.
// Claude SSOTs are read-only; Cursor outputs are write targets only.
//
// Docs:
//   https://code.claude.com/docs/en/plugins-reference  (.claude-plugin/, .mcp.json)
//   https://cursor.com/docs/reference/plugins         (.cursor-plugin/, mcp.json)

import { existsSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { readJson } from "./json.mjs";

const here = dirname(fileURLToPath(import.meta.url));

/** Repository root when this package lives at scripts/cursor-export/. */
export const defaultRepoRoot = join(here, "..", "..");

export function rel(repoRoot, path) {
  return relative(repoRoot, path).split(sep).join("/");
}

/** Resolve marketplace source under plugins/; reject traversal. Returns absolute path. */
export function pluginDirFromSource(repoRoot, source) {
  const dir = source.replace(/^\.\//, "").replace(/\/$/, "");
  if (dir.includes("..") || dir.startsWith("/") || /^[A-Za-z]:/.test(dir)) {
    throw new Error(`marketplace source must be a relative plugins/ path: ${source}`);
  }
  const abs = resolve(repoRoot, dir);
  const pluginsAbs = resolve(repoRoot, "plugins");
  if (abs !== pluginsAbs && !abs.startsWith(pluginsAbs + sep)) {
    throw new Error(`marketplace source escapes plugins/: ${source}`);
  }
  return abs;
}

export function claudeMarketplacePath(repoRoot) {
  return join(repoRoot, ".claude-plugin", "marketplace.json");
}

export function cursorMarketplacePath(repoRoot) {
  return join(repoRoot, ".cursor-plugin", "marketplace.json");
}

export function claudePluginJsonPath(pluginDir) {
  return join(pluginDir, ".claude-plugin", "plugin.json");
}

export function cursorPluginJsonPath(pluginDir) {
  return join(pluginDir, ".cursor-plugin", "plugin.json");
}

/** Empty Cursor-native hooks stub — replaces discovery of Claude hooks/hooks.json. */
export function cursorHooksPath(pluginDir) {
  return join(pluginDir, ".cursor-plugin", "hooks.json");
}

export function claudeMcpPath(pluginDir) {
  return join(pluginDir, ".mcp.json");
}

/** Cursor default MCP discovery — https://cursor.com/docs/reference/plugins */
export function cursorMcpPath(pluginDir) {
  return join(pluginDir, "mcp.json");
}

export function hasClaudePluginHooks(pluginDir) {
  return existsSync(join(pluginDir, "hooks", "hooks.json"));
}

export function readClaudeMarketplace(repoRoot) {
  return readJson(claudeMarketplacePath(repoRoot));
}

export function readClaudePlugin(pluginDir) {
  const path = claudePluginJsonPath(pluginDir);
  if (!existsSync(path)) {
    throw new Error(`missing Claude plugin.json: ${path}`);
  }
  return readJson(path);
}
