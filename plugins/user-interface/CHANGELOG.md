# Changelog

All notable changes to the `user-interface` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.15.1] - 2026-11-01

### Changed

- The config cascade skips the setup writer's top-level `written_against` and `provenance` keys, so
  neither reaches `values`, a layer's errors or a userConfig name.

### Fixed

- The `animation-audit-readonly` eval case no longer lists Edit and Write in `allowed_tools`, which
  a case cannot grant itself. Its `no-write` and `no-edit` graders now read the trace for any write
  or edit call, or a Skill call with `--fix`, the same shape as `audit-launch-command-palette`, so
  they can still fail when those tools are absent.
- The `--fix` arm of the `no-write` grader in `animation-audit-readonly` and
  `audit-launch-command-palette` now matches only inside the Skill call's input, so a reply that
  offers `--fix` in text beside a bare audit call no longer fails it.
- The `motion-dropdown` and `motion-toast-stack` eval samples that used the drawer curve for an
  entrance now use the configured `out` curve, `cubic-bezier(0.23, 1, 0.32, 1)`. The graders are
  unchanged.

- The `motion-dialog` eval samples that used the drawer curve for a centered dialog's entrance now
  use the configured `out` curve, `cubic-bezier(0.23, 1, 0.32, 1)`. The graders and each sample's
  pass or fail expectation are unchanged.

## [0.15.0] - 2026-10-31

### Added

- Touch and mobile web guidance for `/user-interface:design` and `/user-interface:audit`: a symptom table, hover gated by pointer capability, tap highlight and instant taps, 44px targets, long press, 16px inputs, the on-screen keyboard, no zoom lock, dynamic viewport units, safe areas, anchors under sticky headers, scroll chaining, gesture axes and nothing scrolling sideways, plus a document head for web pages and `/user-interface:write-css` recipes for full-height layouts, gesture surfaces, sideways overflow, small scrollbars and edge fades, a card that links from its own call to action, and scroll fades that clear when nothing is left to scroll.

- `/user-interface:audit`'s motion lane reviews an animation from its captured frame state: slow it down, record and scrub it, annotate the frame that feels wrong, and read a pasted export as data (its frame, recorded speed, per-element values and the timing between an input and a change). With nothing pasted it offers a capture through `/app-control:drive capture --kind animation` and runs it only after a yes. An ungated `:hover` rule is left to the `touch` lane, and the motion catalog now grades an ease-in on an exit that is not permanent as Important.

- `/user-interface:audit` reviews a diff the way a design engineer would, leading with a verdict and a Before, After, Why table and naming what needs a real device, applies the plain-language copy rules at every scope, and its `launch` scope adds a pre-launch sweep: recon, a leftovers pass (dev tools, scaffolding routes, debug output, secrets, stale markers), a Ship or Not yet verdict, and the keyboard, screen reader, form, theme and phone checks a person still has to run.

- `/user-interface:design` and `/user-interface:audit` principles gain plain-language copy rules (buttons that name their outcome, errors that say how to fix them, sentence case, no "please") with audit severities, a stop-the-prompt-loop step that proposes `/prototype:build-generator` for the person to run after one missed round of variants, a delegate-or-build rule, restraint and habits-versus-conventions lines, a system font stack kept as the app UI default, a fuller reduced-motion list, and style-imposing tools offered only on a marketing page or for a requested redesign.

- `/user-interface:design` gains an "Order of work": which skill or concern to run for a screen and in what order (decide, start with layout, type and color, build the pieces, refine, check, then the launch sweep), the overlaps that get confused, a complaint-to-skill table and what to say when no skill fits, in its own reference file; it now sits in the design stage of the workflow, offers a style-imposing tool only where the principles' "Project first" allows, and names the glossary, the audit, `/planning:design` and `/prototype:build-generator` as next steps.

- Trigger probe files `probes/audit.json`, `probes/design.json` and `probes/write-css.json`. The audit probes cover the motion lane, the launch sweep and a non-motion lane; the design probes cover the component API, the design-system note and the order of work; the write-css probes include requests for a style whose value has no matching token.

- `reference/component-libraries.md` gains a table of React primitives libraries by how each lets a part render another element, with a configurable default for a project that has none.

### Changed

- `/user-interface:write-css`'s text-and-media recipes name the concern rules they implement.

- Motion guidance for `/user-interface:write-animation`, `/user-interface:audit` and `/user-interface:write-css` grows: graded findings for frequency, purpose, easing, duration, origin, paired timing, interruption, missing exits, page-load entrances, stagger, reduced motion, hover motion and frame cost; permanent exits accelerate away on their own curve and run shorter than their entrance; element-scale motion stays under 300ms with a separate page duration; a named easing library; component recipes for section entrances, exits, icon swaps and tooltip groups; and write-css recipes for a popover that scales from its trigger, a popover inside a modal, a reduced-motion swap and a hover that keeps its hit area.

- The `/user-interface:write-css` recipe `concentric-nested-radius` now takes the outer radius as input and subtracts the parent's border width and padding, floored at zero.

- The write-css layout recipes link to the web layout spoke.

- The animation glossary moved from `reference/animation/glossary.md` to the glossary skill's `reference/motion.md`; the animation catalog now points at `/user-interface:glossary` for effect names.

### Fixed

- `/user-interface:write-css` now fires on a request to add a variant whose color or value has no matching token, and asks before inventing one.

## [0.14.0] - 2026-10-31

### Removed

- The `design.concern_spoke_cap` setting. `/user-interface:design` now reads every concern spoke whose `read_when` holds in one pass instead of stopping at two and listing the rest as next steps. No observed failure backed the cap. A team or local file that still sets it gets an unknown-key error for `design`, and the rest of the file still loads.

## [0.13.0] - 2026-10-31

### Added

- A layout-stability concern for `/user-interface:design` and `/user-interface:audit`: reserved space for async content and media, equal-width digits on changing numbers, labels that swap without changing width, constant font weight on interaction, persisted state right on first paint, late banners that overlay rather than push, and long user text that cannot break the layout, with audit severities.

- `/user-interface:design` and `/user-interface:audit` gain web performance guidance: preloading the hero image and lazy-loading the rest, images sized to how they're shown, virtualized long lists, pausing work out of view, inline autoplaying video, static content routes, debounced search requests, splitting out heavy rarely-seen UI, and no state update per frame.

- Web accessibility guidance for `/user-interface:design` and `/user-interface:audit`: keyboard reach, visible focus, names for icon buttons and images, modal focus, hidden panels kept out of the tab order, errors not told by color alone, focus that is never lost, DOM order that matches the screen, landmarks and skip links, announced async changes, timers that pause in a hidden tab and per-platform shortcut hints, plus a `scripts/focus-path.mjs` check that flags where a page's tab order jumps backward.

## [0.12.0] - 2026-10-31

### Added

- `/user-interface:design` and `/user-interface:audit` gain forms and inputs guidance for the web (associated labels, the right input type and `autocomplete`, decorations over the input, autofocus gated on a coarse pointer, a wrapping `<form>` with Enter and Cmd or Ctrl+Enter submit, real buttons that disable while submitting, failed submits that keep what was typed, late validation with errors beside their field, dead-zone-free checkbox rows, confirmed destructive actions, prefilled fields and drafts that survive a refresh), each audit-checked rule with its severity.

- `/user-interface:design` and `/user-interface:audit` gain icon and illustration guidance for the web (an icon size ladder with stroke weights per size, thinner strokes at small sizes and filled variants below 12px, one icon library per surface, round caps, single-path icons, one meaning per icon, labels for ambiguous metaphors, icon-to-label gaps, and illustrations matched to the icon stroke, the color tokens, a small palette and the interface's light direction), each audit-checked rule with its severity.

- `/user-interface:design` and `/user-interface:audit` gain interface state guidance for web screens: empty states that teach and create the first item, failed requests with a specific recovery, delayed wait indicators, skeletons that hold the page's shape, optimistic updates that revert on failure, copy confirmations, feedback while the user acts, toast durations from word count, and badges versus tags.

- `/user-interface:design` and `/user-interface:audit` gain component API guidance for shared web components (composition over configuration, compound parts, finite variants typed as unions, platform prop names, controlled and uncontrolled state, refs and prop spreading, safe defaults) with React implementation patterns.

- `/user-interface:design` and `/user-interface:audit` gain marketing page guidance for landing pages, pricing, docs sites, blogs and changelogs: motion that follows the visitor, page titles, descriptions and link previews, crawler files and icons, header submenus kept in the DOM, auth-aware calls to action, a working conversion path, copyable docs, feeds, and code-built illustrations, each rule with its audit severity.

- Theming and dark mode guidance for web interfaces in `reference/types/web/theming.md`: declaring only the color schemes that were designed, finishing or turning off a half-built dark mode, flipping one variable scale at the theme root instead of per-component `dark:` overrides, hardcoded colors, images and third-party widgets that miss the second theme, `theme-color` and autofill in both themes, and theme switches that do not animate every color, each with the severity `/user-interface:audit` reports.

- Generic-defaults guidance for `/user-interface:design` and `/user-interface:audit`: a pass that deletes what nothing needs, then replaces the tells that make a web screen look generated (unchosen indigo, stacked gradients, gradient headlines, glass over nothing, template heroes and feature grids, emoji as icons), flags placeholder content and invented social proof as blocking, and gives marketing and brand surfaces a point of view while application UI keeps the system font stack.

- A design-system note procedure behind `/user-interface:design` filling gaps: inventory the real tokens, components and variant unions first, size the note to the system, document each component with when to use it and its alternative, a closed variant set, the default, a correct and an incorrect example and a flowchart for three or more options, write rules as numbers with their why, then test the note by prompting for a real screen and fix the note, not the output, with a worked example `DESIGN.md`.

## [0.11.0] - 2026-10-31

### Added

- A shape-and-depth concern for `/user-interface:design` and `/user-interface:audit`: nested radii, shadows over borders, hairlines, eased gradients and mask fades, and image outlines, with audit severities, plus `scripts/nested-radius.mjs`, which works out a nested element's radius and says when the gap is too wide for the rule to apply.

- `/user-interface:design` and `/user-interface:audit` gain web layout guidance: settle hierarchy, spacing and alignment first, one primary action per view, spacing from a scale with `gap` on the parent, optical alignment, capped content containers and content-driven breakpoints, sticky headers capped against the viewport, text beside rather than over full-bleed images, `z-index` from a token scale or a local stacking context, and decorative layers that never take clicks.

- `/user-interface:design` and `/user-interface:audit` gain web color guidance: oklch for new colors, contrast repaired by moving lightness only against the WCAG 2.2 AA bar with APCA as an advisory second check, every text pair checked in both themes, tonal scales with one fixed hue and per-hue chroma, dark-mode colors from a remap of the scale's roles, value-for-value conversion from hex, `rgb()` and `hsl()` with `none` as the hue of grays, gamut clamping with a Display P3 layer, a `--focus-ring` token held to 3:1 in both themes, and Tailwind `@theme` color tokens read only in Tailwind projects.

- `/user-interface:design` and `/user-interface:audit` gain web typography guidance (font files and synthesized styles, variable axes and OpenType features, type scale, leading and tracking, line length, wrap modes, truncation, the right typographic characters, underlines, selection, smoothing and size floors), with a Tailwind map read only when the project uses Tailwind.

## [0.10.0] - 2026-10-31

### Added

- `reference/concerns.json`, the interface concern table, with `reference/concerns.schema.json` and `scripts/lib/concerns-validate.mjs`. Each row names the reference files (spokes) a concern reads, its routing concerns and its audit order; the first row is `motion`.
- `design.concern_spoke_cap` (default 2, an integer of at least 1) bounds how many concern spokes one `/user-interface:design` pass loads.

- `/user-interface:glossary`, a model-invoked reverse term lookup: given an effect, visual detail or behavior someone can describe but not name, it answers with the term, separates near-synonyms, turns a vague feel request into named terms, and asks for a reference image when no term fits. Its term files cover typography, color, icons, layout, interaction, motion, easing and springs, rendering performance, accessibility, information architecture, copywriting, design tools, analytics, components and front-end engineering; each entry gives the term, a definition and the line against its nearest near-synonym.

### Changed

- The animation audit skill is now `/user-interface:audit`. It takes a scope, `diff` (the default), `tree`, or `launch`, which walks every lane in the concern table's audit order, one pass each, and reviews one concern lane per pass. The motion lane keeps the `opportunities` and `performance` sub-modes, now in its procedure file `skills/audit/reference/motion.md`. `--fix` still applies one finding at a time after a yes, at every scope.
- `/user-interface:design` Step 3 loads spokes for the concerns the project's own system does not cover from the concern table, up to the cap, and names the rest as next steps.

### Fixed

- `/user-interface:design` now applies the routing-as-data 2.0.0 team-row limits. A team `routing.rows` entry is dropped when its id matches neither a bundled row nor its own installed plugin or skill, when it adds a `kind: tool` row, or when it reuses a bundled id but changes that row's `kind`, `detect` or `account`. When the installed list cannot be read, a row whose id matches no bundled row is also dropped. `scripts/detect.mjs --config` names each dropped row and the rule it broke in `routing_notes`. `reference/team.schema.json` states the three rules.

## [0.9.6] - 2026-10-31

### Fixed

- The convention-home resolver refuses a pointer that names `.git` or a path inside it, and a
  working-tree home reached through a symlink: both exit 3.

## [0.9.5] - 2026-10-30

### Changed

- `/user-interface:setup`: changing a `css_*` option no longer only points at the README. The skill prints the reconfiguration routes itself: `claude plugin configure user-interface@<marketplace> --values-stdin` as the preferred headless route, the `claude plugin install --config` rerun as its fallback for a Claude Code release before 2.1.285, and the four caveats the plugin-reconfiguration convention requires.

## [0.9.4] - 2026-10-30

### Changed

- The generated plugin-options block in this plugin's docs now links `docs/contracts/<name>/` instead of the old `docs/conventions/<name>/` stub.

- Shared copies synced: links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

- Shared copies synced: links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.9.3] - 2026-10-30

### Changed

- `yaml-subset.mjs` gains a `source` option that keeps each scalar as its source text. Default parsing is unchanged (#10131).

## [0.9.2] - 2026-10-30

### Changed

- Links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.9.1] - 2026-10-29

### Changed

- The generated README "How to set these" block names `claude plugin configure <plugin>@<marketplace> --values-stdin` as the preferred headless route, per the plugin-reconfiguration convention, and keeps the `claude plugin install --config` rerun only as its fallback.

## [0.9.0] - 2026-10-29

### Added

- `/user-interface:design` offers to install a better route for a concern: the highest-ranked row
  that is not installed, not `deferred`, and fits this platform and the account rules. It offers a
  `paid` row only when no free row covers the concern. It gives the row's `pointer` URL as the
  source of the install and sign-in steps, says when the team file supplied the row, and installs
  at local scope only after the user says yes to the exact command; otherwise it continues with the
  best route already present. Three eval cases cover the offer, a decline and an accept.

## [0.8.10] - 2026-10-29

### Changed

- The config reader now refuses a plain YAML value holding a colon and a space (such as `label: needs: triage`) and a plain key holding whitespace, `$` or `.` (such as `$schema: x` or `a.b: c`), naming the line. One such line now makes the whole file invalid, where the value used to be read as text or the key reported on its own. Quote the value or key to keep it.

## [0.8.9] - 2026-10-29

### Fixed

- `/user-interface:design`: web mockups now have one route. The Claude Design gotcha no longer sends every mockup to the `Artifact` tool: it covers the design-system route, and mockups follow the `mockups-variants` rows, `/prototype:explore-directions` first and the `Artifact` tool only when no higher row passes routing, for example when that skill is not installed. The handoff to `/prototype:explore-directions` passes on the tokens, components and screens Step 2 found, so detection runs once.

## [0.8.8] - 2026-10-28

### Fixed

- `/user-interface:design` reads an `account_tools_enabled` value that arrives as its unexpanded `${user_config.account_tools_enabled}` token as the key's default `true`, so account-bound tools stay enabled instead of being read as off.

## [0.8.7] - 2026-10-28

### Fixed

- The shared config resolver now tags each layer error with the key it names (`error_keys`, null for a
  file-level error), so a reader can tell a key-level error from a whole-file one.
- `detect.mjs --config` counts team routing problems from those tags instead of message prefixes, so a
  convention home outside the project or a refused team `.md` file is disclosed in `routing_notes`.
- `/user-interface:design` Step 1 is one list, and its `config` bullet says the routing comes from
  `routes`, not `config`; a new eval case checks that a team `deny` skip names the team file.

## [0.8.6] - 2026-10-27

### Changed

- The README's generated "How to set these" block no longer restates Claude Code CLI and settings behavior as fact. Each upstream specific is now a link to the docs section that owns it (`/plugin` in a session, what an uninstall deletes and keeps, `pluginConfigs`), and what this repository measured stays in the plugin-reconfiguration convention.

## [0.8.5] - 2026-10-27

### Security

- Shared `prerequisites.mjs` synced: each dependency probe runs from the library's own directory, so a probed tool never starts with the user's repository as its working directory.

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
