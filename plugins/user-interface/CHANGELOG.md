# Changelog

All notable changes to the `user-interface` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.0] - 2026-10-11

### Added

- `/user-interface:write-css`: writes and reviews CSS with modern, self-adapting techniques, after
  reading the project's own design system, stack, browser targets and lint config. Its 47
  techniques, grouped by topic, come from vojtaholik/good-css at `b645ab15b9fc`; review mode runs
  that project's `check-css.mjs`, vendored unmodified under `skills/write-css/vendor/`. Credits per
  technique are in `docs/upstream/good-css.md`.
- `scripts/check-good-css-drift.sh --check`: weekly drift check of the upstream files the skill
  absorbed or vendors (`scripts/check-css.mjs`, `LICENSE`, `PRACTICES.md`) and of the vendored
  copies. Exit 0 no drift, 1 drift, 2 unverifiable.
- **Notice.** The technique text in `skills/write-css/reference/` and the vendored linter carry
  material from vojtaholik/good-css (MIT). This paragraph travels with them, is the copy that ships
  with the installed plugin, and must survive any future trim of this changelog:

  ```text
  Copyright (c) 2026 Vojta Holik

  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
  associated documentation files (the "Software"), to deal in the Software without restriction,
  including without limitation the rights to use, copy, modify, merge, publish, distribute,
  sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all copies or
  substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
  NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
  DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  ```

## [0.4.0] - 2026-10-11

### Added

- Five-layer settings: plugin defaults, the `css_browser_target`, `css_important`, `css_layer` and `css_token_fallback` options, `~/docs/conventions/user-interface.yaml`, the team file `<home>/user-interface.yaml` and the personal `<home>/user-interface.local.yaml`, read through one shared resolver. Every value reports the layer it came from.
- `scripts/detect.mjs --config` prints the resolved settings, and its project report gains the browserslist query, Stylelint and `@eslint/css` config, and the kinds of style files present.
- `/user-interface:setup`: `check` shows each value with its source layer, invalid keys, keys set twice in personal layers, legacy files, whether the personal file is gitignored, and a personal file the main checkout has but this worktree lacks; `apply` writes one key in one layer.

## [0.3.0] - 2026-10-10

### Added

- Web guidance gains a design-time "Motion and interaction" block: interruptible motion, expanding to content height, appearance changes that keep the layout box, layout changes that keep element identity, briefing motion in named terms and numbers, snapping free-drag controls, and shaping corners without clipping focus.

## [0.2.1] - 2026-10-09

### Changed

- Detect's installed-plugin logic moves to `scripts/lib/installed.mjs`, a generated copy shared with
  user-experience; output unchanged.

## [0.2.0] - 2026-10-09

### Changed

- Skill route ids are slash invocations (`/plugin:skill`), and `design` drops the leading slash
  before calling the Skill tool.
- Bare sibling plugin detects resolve to `<name>@<own marketplace>`.
- The own-row pointers are removed from the routing data, which moves to schema `version` 2 (see
  docs/conventions/routing-as-data).

### Added

- Detect resolves its own marketplace. When it cannot, it matches siblings by name and sets `reason`
  (`own marketplace unresolved (<origin>); matched by name`) beside the `installed` list.
- `uncertain`: a per-row map of ids that a same-named third-party plugin may hold. `design` treats
  them as not installed and names them to the user.
- `axe-accessibility` must be qualified with its marketplace before it is confirmed.

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
