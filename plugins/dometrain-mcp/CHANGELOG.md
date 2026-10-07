# Changelog

All notable changes to the `dometrain-mcp` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.4] - 2026-10-07

### Changed

- **Docs links ([#6498](https://github.com/melodic-software/claude-code-plugins/issues/6498)).** Citations of the retired `plugins-reference` and `discover-plugins` pages now point at the live pages that took over each section (`plugins/manifest-reference`, `plugins/components`, `plugins/cli-reference`, `plugins/loading`, `plugins/install`, and `settings-reference#pluginconfigs`). Quotes that moved with them are updated, and each re-verified pointer carries an as-of date of 2026-10-07.

## [0.1.3] - 2026-10-04

### Changed

- **Upstream plugin doc links repointed to the split `plugins/` pages ([#5962](https://github.com/melodic-software/claude-code-plugins/issues/5962)).** The README options block now links `plugins/cli-reference#plugin-install` for the `--config` flag, since the old `plugins-reference` page no longer carries that section, and `plugins/manifest-reference#user-configuration` for the `userConfig` schema.

## [0.1.2] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.
- `plugin.json` no longer sets `defaultEnabled`, which claude.ai's marketplace sync does not recognize. The marketplace entry's `defaultEnabled: false` still applies, and it takes precedence over `plugin.json`, so the plugin still installs disabled.

## [0.1.1] - 2026-10-02

### Changed

- The `dometrain_api_key` option title reads "API key", dropping the service name the `/config`
  row already shows, per the plugin option naming convention
  (`docs/conventions/plugin-option-naming/`).

## [0.1.0]

### Added

- **Bundled Dometrain MCP server.** An `http` server at `https://mcp.dometrain.com/mcp` with a
  Bearer header from the optional, sensitive `dometrain_api_key` option. It moved here from the
  `dometrain` plugin so a user who runs their own user-scope `dometrain` server can install the
  grounding skills alone, with no duplicate-server warning in `/plugin`
  ([#5209](https://github.com/melodic-software/claude-code-plugins/issues/5209)).
