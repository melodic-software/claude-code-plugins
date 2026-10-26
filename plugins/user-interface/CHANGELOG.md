# Changelog

All notable changes to the `user-interface` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.4] - 2026-10-26

### Fixed

- `scripts/lib/yaml-subset.mjs` reads an empty sequence item (`-` alone) as `null` when the next line is another item at the same indent, instead of nesting the following items under it.
- A quoted key may hold a doubled `''` in single quotes or a `\"` escape in double quotes; such a key no longer fails with `expected a mapping entry`.

## [0.8.3] - 2026-10-26

### Changed

- The bundled config cascade (`scripts/lib/config-cascade.mjs`) now enforces a schema `maximum`, as it already did `minimum`.

## [0.8.2] - 2026-10-25

### Changed

- Shared `prerequisites.mjs` synced where this plugin carries it (#9684): `detect.version` accepts an exclusive `below` bound; no other change to this plugin.

## [0.8.1] - 2026-10-25

### Changed

- An explicit request for an exit that accelerates away now wins over the `ease-in` rule in `write-css`: the exit uses `ease-in` and the reply warns that its slow start can read as lag. The review script and `audit-animation` still report that `ease-in`, and `write-css` says the finding is expected. The default is unchanged.
- The `css-rule-ease-in` eval passes an honored explicit request with the trade-off named, and counts `write-animation` firing as well as `write-css`.
- The `css-rule-logical` eval no longer fails a reply whose prose names a physical property in inline code, such as a right-to-left note offering `text-align: left` or quoting a whole rule; physical declarations in the CSS still fail it.

## [0.8.0] - 2026-10-22

### Added

- `/user-interface:design` now applies the team file's `routing`. `scripts/detect.mjs --config` prints `routes` (the bundled rows with a team row overriding or adding a route, and `disable` and `deny` applied), `skipped` (each removed route, with the team file as its source) and `routing_notes` (a disclosure when the team file or a row could not be applied), and `installed` and `reachable` follow those routes. A team `routing.deny: [figma]` now takes effect.

## [0.7.0] - 2026-10-20

### Added

- An eval case, `css-rule-corner-shape`, checking that smoothed or squircle button corners use `border-radius` (optionally with `corner-shape`) and keep a visible focus indicator, never a `clip-path` on the button.

- An eval case, `web-interruptible-motion`, checking that `/user-interface:write-animation` keeps the current value and velocity when a toggle reverses mid-animation instead of restarting a keyframe from zero.

- Shared `resolve-convention-home.sh` synced: `--ref` (a 40-hex commit id or `origin/<name>`) reads the pointer and the home as committed, `-` reads the region from stdin, a `declined` line in the region exits 4 so the caller does not ask again, and a root that is `$HOME`, an ancestor of it or outside a git work tree exits 5 (not applicable).
- Shared `config-cascade.mjs` synced: `resolve()` takes a `floors` option (key path to `Floor direction`), and a personal `.local.yaml` value that loosens a floor key the team set is dropped with an error naming the layer, file and key. A `.local.md` H2 section replaces the team `.md` section with the same heading, returned as `sections`.

### Changed

- `/user-interface:write-css` layout reference: the content grid with breakouts is now the container of every page, and a pass over existing CSS replaces each centered `max-width` wrapper with it, per the re-audited upstream pin.

- The config cascade has four layers (default, `userConfig`, team, personal): a file under `~/docs/conventions/` is no longer read. An invalid team or `userConfig` value falls to the default, never to a lower layer's value; an invalid personal value leaves the team value standing.
- With no `--root`, `resolve-convention-home.sh` reads the git toplevel of `CLAUDE_PROJECT_DIR` (else of the current directory): one home per git root.
- `detect.mjs --config` reads no team or overlay file when the repository declined a convention home or none applies (the project is `$HOME`, an ancestor of it, or outside git): the bundled defaults apply, and `home_skipped` says why.

### Fixed

- Shared `prerequisites.mjs` synced: a `node-pkg` or `python-pkg` entry reads `CLAUDE_PLUGIN_DATA` only when its last path segment is this plugin's name or starts with `<plugin>-`, and treats a literal `${...}` value as unset, so another plugin's data directory reports `unverified` instead of `missing`.

- A `CLAUDE.md` symlinked to `AGENTS.md`, or the reverse, no longer prints a `duplicate:` notice.
- A convention home whose name starts with `..` (such as `..conf`) is no longer refused as outside the project.

## [0.6.3] - 2026-10-18

### Changed

- The README links ADR 0075, which supersedes ADR 0061's layers and paths for plugin settings.

## [0.6.2] - 2026-10-18

### Fixed

- The generated plugin options section of the README no longer claims which setup route most people prefer.

## [0.6.1] - 2026-10-16

### Changed

- Shared `prerequisites.mjs` synced: the SessionStart probe now also reports a drifted git-hook entry for a plugin that ships `git-hooks/entries.json`. This plugin ships none, so its behavior is unchanged.

## [0.6.0] - 2026-10-13

### Added

- A `LICENSE` carrying the MIT notice for content reauthored from emilkowalski/skills (pinned in `docs/upstream/emilkowalski-skills.md`) beside the Melodic Software derivative line.
- `scripts/check-emilkowalski-drift.sh`, run weekly by the upstream drift workflow: it reads the emilkowalski/skills tree once, compares each pinned file with its pin and reports new upstream skill files.
- `reference/animation/`: a shared animation catalog (whether to animate, purpose, cheapest tool, properties, easing and duration roles, reduced motion, feel check), stack-neutral component behaviors, gestures and springs, web animation performance, and a glossary of effect names.
- An `animation:` settings block (easing curves as four control points, `press`/`small`/`medium`/`large` role durations, a swipe velocity threshold), settable in the user, team and personal config files.
- `/user-interface:write-animation`: decides whether an element should animate and why, names the stack from the project's files, looks up its current animation guidance (a vendor skill, then docs lookup, research, official docs, repo patterns), and writes one animation from the project's motion tokens with reduced motion included; CSS is written through `/user-interface:write-css`.
- `/user-interface:audit-animation [tree|opportunities|performance] [--fix] [<target>]`: a read-only animation review of the diff, the whole tree, the opportunities (and where not to animate) or the frame cost, each finding with severity and "verified from code" or "needs a device recording"; CSS goes through write-css review mode first, and `--fix` applies one finding at a time after a yes.
- `scripts/detect.mjs --config` warns about a team routing row or `disable` entry that names a concern no bundled row has, so a renamed concern no longer goes quiet.
- `reference/types/touch-web.md`: capability-based guidance for web interfaces used by touch (hover and press, target sizes, viewport and safe areas, on-screen keyboards, scroll and gestures, hardware verification), read from `web.md` when people use the interface on a phone.
- `reference/component-libraries.md`: framework-neutral criteria for choosing a component library (headless or styled, accessibility, stack fit, maintenance, license, weight), preferring one the project already uses; `/user-interface:design` answers the `component-libraries` concern from it when no tool is routed.

### Changed

- **Shared `prerequisites.mjs` synced: its per-probe timeout is now 20 seconds, up from 5.** A version or `system-lib` probe that resolves a secret or calls a network API, such as `firecrawl --status` behind a key-injecting wrapper, no longer false-fails on a slow run. A fast probe is unaffected; a hung one now costs at most 20 seconds per entry. No change to this plugin's own entries.

- `/user-interface:write-css` takes its easing curves and its `duration` rule from the resolved `animation:` block instead of fixed values; at the defaults a dropdown or menu now stays within 250ms (was 300ms), and review mode judges the linter's `duration` findings against the configured role.
- Routing: the `motion` concern is now `animation-authoring` (first routes `/pixel-art:animate`, `/user-interface:write-animation`), joined by `animation-audit` (`/user-interface:audit-animation`); the external emilkowalski/skills rows are removed now that their content ships here, and `expo@expo-plugins` is added. A team config whose `routing` rows or `disable` entries name `concern: motion` should rename it to `animation-authoring`; detect now warns until it does.
- The accessibility floor's "Motion is optional" now says what a reduced-motion setting removes (movement) and what may stay (a short opacity or color change), with a pointer to WCAG 2.2 success criterion 2.3.3.

### Fixed

- Shared library comments that restated Claude Code hook, plugin and managed-settings behavior now point at the live docs sections, and the prerequisites probe no longer gives a wrong reason for always exiting 0.

- **The shared prerequisites checker now finds a `python-pkg` in the plugin's own installed Python
  set.** A module that the interpreter cannot import on its own is looked up in the set a plugin
  with a committed `requirements.txt` installs into its data directory
  (`<data>/python/<lock hash>-<interpreter tag>/`), imported the way that plugin's launcher runs
  it. Before, such a package was reported missing. When the data directory is unknown (no
  `--data-dir`, no `CLAUDE_PLUGIN_DATA`), the entry reports `unverified` instead of failing.
  Refs #6112.

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
