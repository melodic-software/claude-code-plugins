# Changelog

All notable changes to the `dometrain-mcp` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0]

### Added

- **Bundled Dometrain MCP server.** An `http` server at `https://mcp.dometrain.com/mcp` with a
  Bearer header from the optional, sensitive `dometrain_api_key` option. It moved here from the
  `dometrain` plugin so a user who runs their own user-scope `dometrain` server can install the
  grounding skills alone, with no duplicate-server warning in `/plugin`
  ([#5209](https://github.com/melodic-software/claude-code-plugins/issues/5209)).
