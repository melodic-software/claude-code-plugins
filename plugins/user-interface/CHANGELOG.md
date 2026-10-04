# Changelog

All notable changes to the `user-interface` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0] - 2026-10-04

### Added

- `design` skill: detects the project's design system and installed design tools, then routes each
  interface concern to the best present source, project first.
- `reference/routing.json` and its schema, `scripts/detect.mjs`, and their tests.
- `account_tools_enabled` option, "Account-bound tools", default on.
