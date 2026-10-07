# Changelog

All notable changes to the `user-interface` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.4] - 2026-10-07

### Changed

- **Upstream records ([#6498](https://github.com/melodic-software/claude-code-plugins/issues/6498)).** The plugin-options README text names user and managed settings as the `pluginConfigs` sources, matching the settings reference as of 2026-10-07; it no longer lists `--settings`.

## [0.1.3] - 2026-10-07

### Changed

- **Docs links ([#6498](https://github.com/melodic-software/claude-code-plugins/issues/6498)).** Citations of the retired `plugins-reference` and `discover-plugins` pages now point at the live pages that took over each section (`plugins/manifest-reference`, `plugins/components`, `plugins/cli-reference`, `plugins/loading`, `plugins/install`, and `settings-reference#pluginconfigs`). Quotes that moved with them are updated, and each re-verified pointer carries an as-of date of 2026-10-07.

## [0.1.2] - 2026-10-04

### Changed

- The terminal and mods references now say the developer-experience guidance decides what a hook
  notice must contain and the hook-observability convention governs how each channel phrases it,
  while this plugin owns its look.

## [0.1.1] - 2026-10-04

### Fixed

- `design` routes to an installed account-bound tool when account-bound tools are on and detect
  reports its reachability as unknown, telling the user they may need to sign in. Before, a `null`
  from detect, which is all it can report for an account, made every such row unroutable.
- The Claude Design rows named a `/design` command that does not exist; they now route to the
  `Artifact` tool's Design and Design System types, confirmed in an interactive session with a
  claude.ai login. Headless sessions do not load that tool, so the rows are skipped there.

### Changed

- `chrome-devtools-mcp` and `playwright` from the official marketplace are confirmed: installed on
  Windows, detected, routed, then uninstalled.
- New deferred routes: Subframe, Google Stitch's MCP server, Pencil (pen.dev), Paper and Brilliant.
- The `account_tools_enabled` description names Claude Design as the one account-bound route tested.

## [0.1.0] - 2026-10-04

### Added

- `design` skill: detects the project's design system and installed design tools, then routes each
  interface concern to the best present source, project first. It keeps to the project's system
  when a request conflicts with it, names the target platform with a fallback when the request
  leaves it open, applies theme-safe color and display-width rules, and hands a user-only skill
  over as its slash command.
- `reference/routing.json` and its schema: 13 interface concerns, this repository's skills ranked
  first, Mac-only and account-bound routes deferred. Rows tested by install and a routed prompt
  are marked `confirmed`. No route follows instructions fetched from a mutable branch.
- `scripts/detect.mjs`: the project's design signals, the installed routes (local-scope installs
  for this project included), and which are reachable.
- Guidance: `reference/principles.md` (working order, heuristics, accessibility floor) and
  `reference/types/` for terminal, mods, web and app. `types/web.md` reads the Web Interface
  Guidelines checklist at a pinned commit, as data.
- `account_tools_enabled` option, "Account-bound tools", default on.
- Evals: 10 cases covering terminal rules, project-first routing, and platform targeting.
