// Build Cursor .cursor-plugin/plugin.json from a Claude plugin.json + disk layout.
//
// Docs: https://cursor.com/docs/reference/plugins
//   required: name
//   optional: description, version, author, license, keywords, logo, hooks, mcpServers, variables
//
// Hooks: Cursor plugin discovery defaults to hooks/hooks.json (Claude format here).
// Specifying hooks replaces discovery — we point at an empty Cursor-native stub under
// .cursor-plugin/ so Cursor never parses Claude hooks/hooks.json as a plugin hook file.
// Claude scripts stay Claude-payload-specific; no compatibility wrapper
// (PLUGIN-PHILOSOPHY: no dual-read / silent shims; standards shareable-artifact-design:
// declare host boundary explicitly).

import { cursorDescription } from "./description.mjs";
import { pick } from "./json.mjs";
import { buildCursorMcpBundle } from "./mcp.mjs";
import { hasClaudePluginHooks } from "./paths.mjs";

const PLUGIN_FIELDS = [
  "name",
  "version",
  "description",
  "author",
  "homepage",
  "repository",
  "license",
  "keywords",
  "logo",
];

/** Empty Cursor-native hooks file — https://cursor.com/docs/hooks (`version` + `hooks`). */
export const EMPTY_CURSOR_HOOKS = {
  version: 1,
  hooks: {},
};

/**
 * @returns {{
 *   plugin: object,
 *   mcpBundle: null | { mcpFile: object, variables: object },
 *   hooksStub: null | object
 * }}
 */
export function buildCursorPlugin(claudePlugin, pluginDir) {
  const cursor = pick(claudePlugin, PLUGIN_FIELDS);
  if (!cursor.name) throw new Error("plugin.json missing required name");
  if (!cursor.description) {
    throw new Error(`${cursor.name}: plugin.json has no description`);
  }

  const mcpBundle = buildCursorMcpBundle(pluginDir, claudePlugin);
  const claudeHooks = hasClaudePluginHooks(pluginDir);

  cursor.description = cursorDescription(claudePlugin.description, {
    hasClaudePluginHooks: claudeHooks,
    hasCursorMcp: Boolean(mcpBundle),
  });

  let hooksStub = null;
  if (claudeHooks) {
    // Relative to plugin root; replaces hooks/ discovery.
    cursor.hooks = "./.cursor-plugin/hooks.json";
    hooksStub = EMPTY_CURSOR_HOOKS;
  }

  if (mcpBundle) {
    // Default Cursor discovery is mcp.json at plugin root — no mcpServers override.
    cursor.variables = mcpBundle.variables;
  }

  return { plugin: cursor, mcpBundle, hooksStub };
}
