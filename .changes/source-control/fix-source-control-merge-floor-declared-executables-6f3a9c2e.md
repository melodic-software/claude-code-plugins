---
bump: minor
---

### Added

- `babysit_risk.RiskInput` gains `declarations`: each plugin's `.claude-plugin/plugin.json`, `.mcp.json` and `hooks/hooks.json` text at the base SHA (`babysit_risk.DECLARATION_FILES`). While the HIGH floor applies, every path they declare as run joins it: each `${CLAUDE_PLUGIN_ROOT}` reference, as the directory holding it (or the path itself at the plugin root, or the whole plugin for a bare root), and in plugin.json each `./` path under `hooks`, `mcpServers`, `lspServers` or `monitors`. A declaration that cannot be read, an unrecognized declaration file, or a declared path outside its plugin scores HIGH as `high-path:**`. Both lanes read the declarations at the base SHA (`babysit_merge_policy.declarations_at`, from a clone holding it, else the contents API) whenever the floor applies, so a pull request cannot drop its own declaration; a base tree that cannot be listed holds the floor as HIGH.
