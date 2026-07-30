// Port Claude .mcp.json → Cursor mcp.json + plugin.json variables.
//
// Separate files per host (no dual-read):
//   Claude:  plugins/<name>/.mcp.json     + userConfig / ${user_config.KEY}
//   Cursor:  plugins/<name>/mcp.json      + variables / ${VAR}
//
// Docs:
//   https://code.claude.com/docs/en/plugins-reference  (.mcp.json, userConfig, CLAUDE_PLUGIN_ROOT)
//   https://cursor.com/docs/reference/plugins         (mcp.json, variables, ${VAR})

import { existsSync, readFileSync } from "node:fs";
import { basename, dirname } from "node:path";
import { claudeMcpPath } from "./paths.mjs";

export function mcpNeedsCursorPort(raw) {
  return raw.includes("${user_config.") || raw.includes("${CLAUDE_PLUGIN_ROOT}");
}

/**
 * @returns {null | { mcpFile: object, variables: object }}
 */
export function buildCursorMcpBundle(pluginDir, claudePlugin) {
  const path = claudeMcpPath(pluginDir);
  if (!existsSync(path)) return null;
  const raw = readFileSync(path, "utf8");
  if (!mcpNeedsCursorPort(raw)) return null;

  const mcp = JSON.parse(raw);
  const userConfig = claudePlugin.userConfig ?? {};
  const properties = {};
  const required = [];
  const label = `${basename(dirname(path))}/.mcp.json`;

  let serialized = JSON.stringify(mcp.mcpServers ?? {});
  // Cursor examples use relative paths for plugin-local files
  // (https://cursor.com/docs/hooks — ./hooks/...; MCP args follow the same idea).
  serialized = serialized.replaceAll("${CLAUDE_PLUGIN_ROOT}/", "./");
  serialized = serialized.replaceAll("${CLAUDE_PLUGIN_ROOT}", ".");
  serialized = serialized.replace(
    /\$\{user_config\.([A-Za-z0-9_]+)\}/g,
    (_match, key) => {
      const varName = key.toUpperCase();
      const uc = userConfig[key];
      if (!properties[varName]) {
        let description = uc?.description ?? `Value for ${varName}`;
        description = description
          .replace(
            /Stored by Claude Code in secure credential storage(?:,\s*never settings\.json)?\.?/gi,
            "Set in Cursor under Plugins -> Configure.",
          )
          .replace(/Claude Code/gi, "Cursor")
          .trim();
        properties[varName] = {
          type: uc?.type ?? "string",
          ...(uc?.title ? { title: uc.title } : {}),
          description,
        };
        if (!required.includes(varName)) required.push(varName);
      }
      return `\${${varName}}`;
    },
  );

  if (/\$\{user_config\.|\$\{CLAUDE_PLUGIN_ROOT/.test(serialized)) {
    throw new Error(
      `${label}: unresolved Claude placeholders after Cursor MCP port`,
    );
  }

  return {
    mcpFile: { mcpServers: JSON.parse(serialized) },
    variables: {
      type: "object",
      properties,
      ...(required.length ? { required } : {}),
    },
  };
}
