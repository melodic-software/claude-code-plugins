// Build Cursor .cursor-plugin/marketplace.json from Claude marketplace + plugin map.
// Docs: https://cursor.com/docs/reference/plugins#multi-plugin-repositories
//
// Marketplace-level description is Cursor-facing (honest about dual host; does not
// claim Claude plugin hooks as Cursor plugin hooks). Per-plugin descriptions come
// from the already-rewritten Cursor plugin.json (reference-dont-duplicate: one
// generated description SSOT for Cursor plugin + marketplace entry).

import { pick } from "./json.mjs";
import { pluginDirFromSource } from "./paths.mjs";

const ENTRY_FIELDS = ["name", "displayName", "source", "category", "tags", "logo"];

const CURSOR_MARKETPLACE_DESCRIPTION =
  "Reusable, repo-agnostic plugins for Claude Code and Cursor — skills, agents, and MCP servers.";

export function buildCursorMarketplace(repoRoot, claudeMarketplace, pluginByName) {
  if (!claudeMarketplace.name) throw new Error("marketplace.json missing name");
  if (!claudeMarketplace.owner?.name) {
    throw new Error("marketplace.json missing owner.name");
  }
  if (!Array.isArray(claudeMarketplace.plugins)) {
    throw new Error("marketplace.json missing plugins array");
  }

  return {
    name: claudeMarketplace.name,
    owner: {
      name: claudeMarketplace.owner.name,
      ...(claudeMarketplace.owner.email
        ? { email: claudeMarketplace.owner.email }
        : {}),
    },
    metadata: {
      description: CURSOR_MARKETPLACE_DESCRIPTION,
      ...(claudeMarketplace.version ? { version: claudeMarketplace.version } : {}),
      ...(claudeMarketplace.pluginRoot
        ? { pluginRoot: claudeMarketplace.pluginRoot }
        : {}),
    },
    plugins: claudeMarketplace.plugins.map((entry) => {
      if (!entry.name) throw new Error("marketplace entry missing name");
      if (!entry.source) throw new Error(`${entry.name}: missing source`);
      pluginDirFromSource(repoRoot, entry.source);
      const plugin = pluginByName.get(entry.name);
      if (!plugin) {
        throw new Error(
          `${entry.name}: no Cursor plugin.json built for marketplace entry`,
        );
      }
      const cursorEntry = pick(entry, ENTRY_FIELDS);
      cursorEntry.description = plugin.description;
      return cursorEntry;
    }),
  };
}
