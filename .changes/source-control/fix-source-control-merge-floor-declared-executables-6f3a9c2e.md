---
bump: minor
---

### Added

- `babysit_risk.RiskInput` gains `declarations`: a plugin's `.claude-plugin/plugin.json`, `.mcp.json`, `.lsp.json`, `hooks/hooks.json` and `monitors/monitors.json` text at the base SHA (`babysit_risk.DECLARATION_FILES`), plus each config file a plugin.json `hooks`, `mcpServers`, `lspServers` or `monitors` string points at (`babysit_risk.declaration_pointers`). While the HIGH floor applies, every path they declare as run joins it: each `${CLAUDE_PLUGIN_ROOT}` reference and each `./` or `../` path, resolved against the plugin root, as the directory holding it (or the path itself at the plugin root, or the whole plugin for a bare root); in plugin.json only under those keys and `experimental.monitors`. A declaration or pointed file that cannot be read, an unrecognized declaration file, a plugin-root reference the reader cannot resolve (a `${CLAUDE_PLUGIN_ROOT:-...}` default, a trim, `$env:` or `%...%`), or a declared path outside its plugin scores HIGH as `high-path:**`.
- Both lanes read the declarations at the base SHA (`babysit_merge_policy.declarations_at`, from a clone holding it, else the contents API) whenever the floor applies, so a pull request cannot drop its own declaration. Only the plugins the pull request's changed files sit in are read; a change outside every plugin reads none. A base tree that cannot be listed holds the floor as HIGH.
