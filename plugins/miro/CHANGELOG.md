# Changelog

All notable changes to the `miro` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.2]

### Added

- Setup skill documents the headless `claude plugin install --config miro_api_token=<token>`
  seeding path, its fresh-install-only caveat, and the shell-history/process-table exposure
  caveat (`docs/PLUGIN-PHILOSOPHY.md` userConfig conformance).

### Changed

- MCP server version kept aligned with the plugin: `package.json`, the
  server's MCP `Implementation` version, the lockfile, and the committed
  bundle all report `0.2.2`.

## [0.2.1]

### Added

- **README section "Rotating or clearing the token"** naming
  `/plugin configure miro` as the rotation/clear path for the stored
  `miro_api_token`, per the repo's sensitive-`userConfig` README convention.

### Changed

- MCP server version kept aligned with the plugin: `package.json`, the
  server's MCP `Implementation` version, the lockfile, and the committed
  bundle all report `0.2.1`.

## [0.2.0]

### Changed

- **Setup adopts the uniform contract's check-only carve-out** (fleet
  conformance wave, dim 8). The plugin's entire configuration is the native
  sensitive `miro_api_token` userConfig, so `check` is the sole action; the
  optional read-only credential probe is now the explicit `check verify-api`
  argument instead of an in-flow question — setup stays non-interactive and
  never touches the token or `pluginConfigs`.
- MCP server version kept aligned with the plugin: `package.json`, the
  server's MCP `Implementation` version, the lockfile, and the committed
  bundle all report `0.2.0`.

## [0.1.2]

### Added

- This changelog (fleet conformance wave: every versioned plugin ships a
  Keep-a-Changelog file).

### Changed

- MCP server version aligned with the plugin: `package.json`, the server's
  MCP `Implementation` version, and the committed bundle now all report
  `0.1.2` (they had drifted to `0.1.0` while `plugin.json` was `0.1.1`).

## [0.1.1]

First versioned release covered by this changelog; see the git history of
`plugins/miro/` for earlier changes.
