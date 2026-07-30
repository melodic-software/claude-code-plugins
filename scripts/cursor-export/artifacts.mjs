// Plan Cursor export artifacts from Claude SSOTs — pure planning + read I/O.
// Claude paths are never listed as write targets
// (standards: code-organization — Claude SSOT vs Cursor generated contract).

import {
  buildCursorMarketplace,
} from "./marketplace.mjs";
import {
  cursorHooksPath,
  cursorMarketplacePath,
  cursorMcpPath,
  cursorPluginJsonPath,
  pluginDirFromSource,
  readClaudeMarketplace,
  readClaudePlugin,
} from "./paths.mjs";
import { buildCursorPlugin } from "./plugin.mjs";

/**
 * @returns {{
 *   writes: Map<string, object>,
 *   counts: { plugins: number, hooksStubs: number, mcpFiles: number }
 * }}
 */
export function planCursorExport(repoRoot) {
  const claudeMarketplace = readClaudeMarketplace(repoRoot);
  const pluginByName = new Map();
  const writes = new Map();
  let hooksStubs = 0;
  let mcpFiles = 0;

  for (const entry of claudeMarketplace.plugins) {
    const pluginDir = pluginDirFromSource(repoRoot, entry.source);
    const claudePlugin = readClaudePlugin(pluginDir);
    if (claudePlugin.name !== entry.name) {
      throw new Error(
        `${entry.name}: Claude plugin.json name "${claudePlugin.name}" does not match marketplace entry`,
      );
    }

    const { plugin, mcpBundle, hooksStub } = buildCursorPlugin(
      claudePlugin,
      pluginDir,
    );
    pluginByName.set(entry.name, plugin);
    writes.set(cursorPluginJsonPath(pluginDir), plugin);

    if (hooksStub) {
      writes.set(cursorHooksPath(pluginDir), hooksStub);
      hooksStubs += 1;
    }

    if (mcpBundle) {
      writes.set(cursorMcpPath(pluginDir), mcpBundle.mcpFile);
      mcpFiles += 1;
    }
  }

  const marketplace = buildCursorMarketplace(
    repoRoot,
    claudeMarketplace,
    pluginByName,
  );
  writes.set(cursorMarketplacePath(repoRoot), marketplace);

  return {
    writes,
    counts: {
      plugins: pluginByName.size,
      hooksStubs,
      mcpFiles,
    },
  };
}
