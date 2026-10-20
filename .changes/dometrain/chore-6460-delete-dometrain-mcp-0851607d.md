---
bump: minor
---

### Removed

- **Breaking:** the companion `dometrain-mcp` plugin is deleted from the marketplace, so the README, the setup skill and the grounding skill no longer name it as a way to get the tools. Register a user-scope `dometrain` server with `claude mcp add-json` per the README's "Getting the MCP server" section, then uninstall `dometrain-mcp`. Permission rules written against `mcp__plugin_dometrain-mcp_dometrain__*` need the user-scope tool names.

### Changed

- `/dometrain:setup` checks for the user-scope server alone: its disabled and failed states point to the README and `claude mcp list`, its headless path installs and enables `dometrain` only, and its evals drop the expectations for the deleted plugin.
